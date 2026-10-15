import Foundation

// SR1 round 6 block 38: `.onHover(perform:)` and `.onTapGesture(count:perform:)` (decisions H6-H8 in docs/sr1-decisions.md).
//
// The host reports where the pointer is (`pointerMoved`) and where a press was released (`tapGesture`), in logical points in the graph's coordinates. A modifier's region
// is the frame of the view it modifies. Hover: a view is hovered while the pointer is inside its frame; when the pointer moves, every view it left is told `false` (in tree
// order), then every view it entered `true` (in tree order), so two adjacent views see the first one's exit before the second one's entry; leaving the window ends every
// hover. Tap: the deepest view whose frame holds the point and that has a tap gesture runs its action (a Button the host already tapped never reaches here). Only a
// single tap (`count: 1`) is delivered; another count never fires.

final class HoverHook {
    let action: (Bool) -> Void
    init(_ action: @escaping (Bool) -> Void) { self.action = action }
}

final class TapHook {
    let count: Int
    let action: () -> Void
    init(count: Int, _ action: @escaping () -> Void) { self.count = count; self.action = action }
}

extension View {
    /// Apple: https://developer.apple.com/documentation/swiftui/view/onhover(perform:)
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        Modified(content: self, spec: .hover(HoverHook(action)))
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/ontapgesture(count:perform:)
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        Modified(content: self, spec: .tap(TapHook(count: count, action)))
    }
}

extension Graph {
    /// The live gesture modifier nodes of one kind, in tree (pre-)order with their depth.
    private func gestureNodes(hover: Bool) -> [(node: Node, depth: Int)] {
        var out: [(Node, Int)] = []
        func walk(_ n: Node, _ depth: Int) {
            guard n.alive else { return }
            switch n.kind {
            case .modifier(.hover) where hover: out.append((n, depth))
            case .modifier(.tap) where !hover: out.append((n, depth))
            default: break
            }
            for c in childNodes(n) { walk(c, depth + 1) }
        }
        if let root { walk(root, 0) }
        return out
    }

    private func contains(_ frame: LayoutRect, _ x: CGFloat, _ y: CGFloat) -> Bool {
        x >= frame.minX && x < frame.maxX && y >= frame.minY && y < frame.maxY
    }

    /// The pointer is at (x, y) logical points, or has left the window (nil). Every `.onHover` view whose state changed is told: exits first, then entries, each in tree order.
    public func pointerMoved(toX x: CGFloat?, y: CGFloat?) {
        let hooks = gestureNodes(hover: true)
        var inside: [Bool] = []
        for (n, _) in hooks { if let x, let y { inside.append(contains(n.frame, x, y)) } else { inside.append(false) } }
        for (i, (n, _)) in hooks.enumerated() where n.hovered && !inside[i] {
            n.hovered = false
            if case .modifier(.hover(let hook)) = n.kind { hook.action(false) }
        }
        for (i, (n, _)) in hooks.enumerated() where !n.hovered && inside[i] {
            n.hovered = true
            if case .modifier(.hover(let hook)) = n.kind { hook.action(true) }
        }
        flush()
    }

    /// The runtime id of the deepest view with a tap gesture whose frame holds the point, nil when there is none.
    public func tapTarget(atX x: CGFloat, y: CGFloat) -> String? {
        var best: (Node, Int)?
        for (n, depth) in gestureNodes(hover: false) where contains(n.frame, x, y) && n.environment.isEnabled {
            if best == nil || depth >= best!.1 { best = (n, depth) }
        }
        return best?.0.idString
    }

    /// A press was released at (x, y): the deepest view with a single-tap gesture whose frame holds the point runs its action. Returns whether one did.
    @discardableResult
    public func tapGesture(atX x: CGFloat, y: CGFloat) -> Bool {
        var best: (Node, Int)?
        for (n, depth) in gestureNodes(hover: false) where contains(n.frame, x, y) && n.environment.isEnabled {
            if best == nil || depth >= best!.1 { best = (n, depth) }
        }
        guard let (node, _) = best, case .modifier(.tap(let hook)) = node.kind, hook.count == 1 else { return false }
        hook.action()
        flush()
        return true
    }

    /// An accessibility invoke on a tap-gesture view (the host maps the node id back): runs its action.
    @discardableResult
    public func invokeTapGesture(_ id: String) -> Bool {
        guard let n = node(id), n.alive, case .modifier(.tap(let hook)) = n.kind, hook.count == 1, n.environment.isEnabled else { return false }
        hook.action()
        flush()
        return true
    }
}
