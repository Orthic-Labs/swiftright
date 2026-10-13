import Foundation

// SwiftUI `AnyTransition` (SR1 round 3 block 19, measured on macOS SwiftUI under a manual clock).
//
// A view inserted under an animated transaction starts from its transition's initial state and animates to its place with the transaction's
// animation: `.opacity` (the default transition, also what a view without a `.transition` gets) from opacity 0; `.move(edge:)` from a position
// shifted by the view's own size towards that edge (measured: leading shifts by -width, opacity unchanged); `.offset(x:y:)` from that offset;
// `.identity` does not animate. The transition belongs to the inserted view: the nearest `.transition` modifier at the top of the inserted
// subtree, and every node of that subtree takes the same initial state. Removal transitions are not implemented (a removed node leaves at once).

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
