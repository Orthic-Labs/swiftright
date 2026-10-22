import Foundation

// Issue #84 (SR2 S5): ScrollViewReader and ScrollViewProxy.scrollTo. `scrollTo(id, anchor:)` finds the view marked `.id(id)` beneath the reader, takes its nearest enclosing
// ScrollView or List and moves that container's vertical offset: with an anchor, the point `anchor` of the target meets the same point of the viewport; without one, the
// smallest move that shows the target. The offset is clamped to the content. Not modelled: horizontal scrolling, `scrollTo` inside an animation (the move is immediate), ids
// of ForEach rows (only `.id(_:)` marks a target).

/// Apple: https://developer.apple.com/documentation/swiftui/scrollviewproxy
@MainActor
public struct ScrollViewProxy {
    let node: Node?

    /// Apple: https://developer.apple.com/documentation/swiftui/scrollviewproxy/scrollto(_:anchor:)
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        guard let node, let graph = node.owner else { return }
        graph.scrollTo(AnyHashable(id), within: node, anchor: anchor)
    }
}

/// A member the graph binds to the reader's node (it looks for members that are dynamic properties).
@MainActor
struct ScrollReaderBinder: DynamicPropertyStorage {
    final class Box { var node: Node? }
    let box = Box()
    func bindDynamicProperty(to node: Node, key: String) { box.node = node }
}

/// Apple: https://developer.apple.com/documentation/swiftui/scrollviewreader
public struct ScrollViewReader<Content: View>: View {
    let content: (ScrollViewProxy) -> Content
    let binder = ScrollReaderBinder()

    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) { self.content = content }

    @MainActor public var body: some View { content(ScrollViewProxy(node: binder.box.node)) }
}

extension Graph {
    func scrollTo(_ id: AnyHashable, within reader: Node, anchor: UnitPoint?) {
        func find(_ n: Node) -> Node? {
            // the node a `.id` marks is the first one down the tree whose key among its siblings includes the identity
            if n.relative.contains(where: { if case .identified(let value) = $0 { return value == id } else { return false } }) { return n }
            for child in n.childNodes { if let hit = find(child) { return hit } }
            return nil
        }
        guard let target = find(reader) else { return }
        var container: Node? = target.parent
        while let c = container, c.scrollState == nil { container = c.parent }
        guard let container, let state = container.scrollState, let offset = verticalOffset(container) else { return }
        let viewport = CGFloat(state.viewportHeight)
        // frames are in content coordinates (the offset is applied when painting), so the target's place in the content is its distance below the container's top
        let top = target.frame.minY - container.frame.minY
        let height = target.frame.height
        let proposed: CGFloat
        if let anchor {
            proposed = top + anchor.y * height - anchor.y * viewport
        } else if top < offset {
            proposed = top
        } else if top + height > offset + viewport {
            proposed = top + height - viewport
        } else {
            proposed = offset
        }
        if moveScroll(container, to: proposed) { flush() }
    }
}
