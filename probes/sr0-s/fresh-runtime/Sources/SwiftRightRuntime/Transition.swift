import Foundation

// SwiftUI `AnyTransition` (SR1 round 3 block 19, measured on macOS SwiftUI under a manual clock).
//
// A view inserted under an animated transaction starts from its transition's initial state and animates to its place with the transaction's
// animation: `.opacity` (the default transition, also what a view without a `.transition` gets) from opacity 0; `.move(edge:)` from a position
// shifted by the view's own size towards that edge (measured: leading shifts by -width, opacity unchanged); `.offset(x:y:)` from that offset;
// `.identity` does not animate. The transition belongs to the inserted view: the nearest `.transition` modifier at the top of the inserted
// subtree, and every node of that subtree takes the same initial state. A view removed under an animated transaction stays in the resolved tree (a ghost, frozen at its last frame) while it fades or moves out, then goes.

public struct AnyTransition: Sendable {
    struct Effect: Sendable, Equatable {
        /// Opacity the view has when it is not inserted (nil: unchanged).
        var offOpacity: Double?
        /// Edge the view moves from, by its own size.
        var edge: Edge?
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        static let none = Effect()
    }

    let insertion: Effect
    let removal: Effect

    init(insertion: Effect, removal: Effect) {
        self.insertion = insertion
        self.removal = removal
    }

    init(both effect: Effect) { self.init(insertion: effect, removal: effect) }

    /// The default transition: fade.
    public static let opacity = AnyTransition(both: Effect(offOpacity: 0))
    /// No transition: the view appears and disappears at once.
    public static let identity = AnyTransition(both: .none)
    public static func move(edge: Edge) -> AnyTransition { AnyTransition(both: Effect(edge: edge)) }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { AnyTransition(both: Effect(dx: x, dy: y)) }
    public static func offset(_ size: CGSize) -> AnyTransition { offset(x: size.width, y: size.height) }
    /// Inserts from the leading edge and removes towards the trailing edge.
    public static var slide: AnyTransition { asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)) }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(insertion: insertion.insertion, removal: removal.removal)
    }

    /// Applies this transition and `other` together.
    public func combined(with other: AnyTransition) -> AnyTransition {
        func merge(_ a: Effect, _ b: Effect) -> Effect {
            Effect(offOpacity: a.offOpacity ?? b.offOpacity, edge: a.edge ?? b.edge, dx: a.dx + b.dx, dy: a.dy + b.dy)
        }
        return AnyTransition(insertion: merge(insertion, other.insertion), removal: merge(removal, other.removal))
    }
}

extension View {
    /// Associates a transition with this view: how it appears when inserted under an animated transaction.
    public func transition(_ t: AnyTransition) -> some View {
        Modified(content: self, spec: .transition(t))
    }
}

extension Graph {
    /// The presentation a freshly inserted node starts from: its target, moved and faded by the transition of the inserted subtree it belongs to.
    /// `fresh` holds the nodes presented for the first time in this commit.
    func insertionStart(_ node: Node, fresh: Set<ObjectIdentifier>) -> Presentation {
        let target = Presentation(frame: node.frame, opacity: node.targetOpacity)
        var top = node
        while let parent = top.parent, fresh.contains(ObjectIdentifier(parent)) { top = parent }
        var transition = AnyTransition.opacity
        var cursor: Node? = top
        while let current = cursor {
            if case .modifier(.transition(let t)) = current.kind { transition = t; break }
            guard case .modifier = current.kind, current.childNodes.count == 1 else { break }
            cursor = current.childNodes[0]
        }
        let effect = transition.insertion
        var start = target
        if let off = effect.offOpacity { start.opacity = target.opacity * off }
        var dx = effect.dx, dy = effect.dy
        if let edge = effect.edge {
            let rtl = top.environment.layoutDirection == .rightToLeft
            switch edge {
            case .leading: dx += rtl ? top.frame.width : -top.frame.width
            case .trailing: dx += rtl ? -top.frame.width : top.frame.width
            case .top: dy -= top.frame.height
            case .bottom: dy += top.frame.height
            }
        }
        if dx != 0 || dy != 0 {
            start.frame = LayoutRect(x: target.frame.minX + dx, y: target.frame.minY + dy, width: target.frame.width, height: target.frame.height)
        }
        return start
    }
}

// MARK: - Removal

/// A removed subtree that stays in the resolved tree while its removal transition runs. Its frames are frozen at the last presented frames; only the
/// transition's offset and opacity change.
@MainActor
final class Ghost {
    let parentID: String
    let index: Int
    let root: ResolvedNode
    let chain: MotionChain
    var current: Presentation

    init(parentID: String, index: Int, root: ResolvedNode, chain: MotionChain) {
        self.parentID = parentID
        self.index = index
        self.root = root
        self.chain = chain
        current = chain.base
    }
}

extension Graph {
    /// The animation a removal under `parent` runs with: a changed `.animation(_:value:)` above it, else the last explicit transaction; nil = none.
    private func removalTransaction(under parent: Node) -> AnimationTransaction? {
        let queued = TransactionContext.queuedTransactions
        let explicit = queued.last { $0.scope == nil }
        let disables = explicit?.disablesAnimations ?? false
        if !disables {
            var cursor: Node? = parent
            while let current = cursor {
                if let scoped = queued.last(where: { $0.scope === current }) { return scoped }
                cursor = current.parent
            }
        }
        return explicit
    }

    /// Called before `old` (a child of `parent`) is torn down: when an animated transaction is pending, keeps a ghost of it.
    func captureGhost(parent: Node, old: Node) {
        guard old.committed, self.sequence > 0, let transaction = removalTransaction(under: parent), let animation = transaction.animation,
              animation.duration > 0, !parent.environment.accessibilityReduceMotion else { return }
        var transition = AnyTransition.opacity
        var cursor: Node? = old
        while let current = cursor {
            if case .modifier(.transition(let t)) = current.kind { transition = t; break }
            guard case .modifier = current.kind, current.childNodes.count == 1 else { break }
            cursor = current.childNodes[0]
        }
        let effect = transition.removal
        guard effect != .none else { return }
        let snapshot = resolve(old)
        let start = Presentation(frame: snapshot.frame, opacity: snapshot.opacity)
        var end = start
        if let off = effect.offOpacity { end.opacity = start.opacity * off }
        var dx = effect.dx, dy = effect.dy
        if let edge = effect.edge {
            let rtl = old.environment.layoutDirection == .rightToLeft
            switch edge {
            case .leading: dx += rtl ? snapshot.frame.width : -snapshot.frame.width
            case .trailing: dx += rtl ? -snapshot.frame.width : snapshot.frame.width
            case .top: dy -= snapshot.frame.height
            case .bottom: dy += snapshot.frame.height
            }
        }
        end.frame = LayoutRect(x: start.frame.minX + dx, y: start.frame.minY + dy, width: start.frame.width, height: start.frame.height)
        let chain = MotionChain(base: start)
        chain.layers.append(MotionLayer(to: end, animation: animation, transaction: transaction))
        let index = parent.childNodes.firstIndex { $0 === old } ?? parent.childNodes.count
        ghosts.append(Ghost(parentID: parent.idString, index: index, root: snapshot, chain: chain))
    }

    /// Moves the running removal transitions to `now`; a finished ghost leaves the resolved tree.
    func advanceGhosts(now: Double, anchoring: Bool) {
        guard !ghosts.isEmpty else { return }
        for ghost in ghosts {
            let value = advanceChain(ghost.chain, now: now, anchoring: anchoring)
            ghost.current = ghost.chain.layers.isEmpty ? ghost.chain.base : value
        }
        ghosts.removeAll { $0.chain.layers.isEmpty }
    }

    /// The ghost's subtree as resolved now: every node shifted by the transition's offset and faded by its opacity ratio.
    func resolvedGhost(_ ghost: Ghost) -> ResolvedNode {
        let dx = ghost.current.frame.minX - ghost.root.frame.minX
        let dy = ghost.current.frame.minY - ghost.root.frame.minY
        let factor = ghost.root.opacity > 0 ? ghost.current.opacity / ghost.root.opacity : 0
        return ghostNode(ghost.root, dx: dx, dy: dy, factor: factor)
    }

    private func ghostNode(_ n: ResolvedNode, dx: CGFloat, dy: CGFloat, factor: Double) -> ResolvedNode {
        let frame = LayoutRect(x: n.frame.minX + dx, y: n.frame.minY + dy, width: n.frame.width, height: n.frame.height)
        return n.replacing(frame: frame, pixelFrame: pixelRect(frame, scale: scale), opacity: n.opacity * factor,
                           children: n.children.map { ghostNode($0, dx: dx, dy: dy, factor: factor) })
    }
}
