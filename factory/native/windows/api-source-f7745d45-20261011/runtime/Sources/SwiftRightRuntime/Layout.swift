import Foundation

/// The public `Layout` subset: size and placement with subview size queries and a cache.
@MainActor
public protocol Layout {
    associatedtype Cache = Void
    func makeCache(subviews: Subviews) -> Cache
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> LayoutSize
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
}

extension Layout where Cache == Void {
    public func makeCache(subviews: Subviews) -> Cache { () }
}

extension Layout {
    /// `MyLayout { ... }` builds a layout container from its builder content.
    @MainActor
    public func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> LayoutRoot<Self, Content> {
        LayoutRoot(layout: self, content: content())
    }
}

/// One child of a layout container. Size queries and placement go through the graph's engine.
@MainActor
public struct Subview {
    let graph: Graph
    let node: Node

    public func sizeThatFits(_ proposal: ProposedViewSize) -> LayoutSize {
        graph.measure(node, proposal)
    }

    /// Places the child so that `anchor` lies at `position`, sized under `proposal`.
    public func place(at position: LayoutPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        let size = graph.measure(node, proposal)
        let origin = LayoutPoint(x: position.x - anchor.x * size.width, y: position.y - anchor.y * size.height)
        graph.place(node, in: LayoutRect(origin: origin, size: size), proposal: proposal)
    }
}

public struct Subviews: RandomAccessCollection {
    public typealias Element = Subview
    public typealias Index = Int

    private let items: [Subview]

    init(_ items: [Subview]) { self.items = items }

    public var startIndex: Int { 0 }
    public var endIndex: Int { items.count }
    public subscript(position: Int) -> Subview { items[position] }
}

/// Type-erased layout behavior stored on a graph node. `storage` holds the layout's cache.
struct LayoutSpec {
    let size: @MainActor (ProposedViewSize, Subviews, inout Any?) -> LayoutSize
    let place: @MainActor (LayoutRect, ProposedViewSize, Subviews, inout Any?) -> Void
}

/// A layout container: its content children are the subviews, and its geometry comes from `layout`.
@MainActor
public struct LayoutRoot<L: Layout, Content: View>: View, PrimitiveView {
    let layout: L
    let content: Content

    public init(layout: L, content: Content) {
        self.layout = layout
        self.content = content
    }

    @MainActor public var body: Never { return fatalError("layout container has no body") }

    var nodeKind: NodeKind {
        let layout = layout
        return .layout(LayoutSpec(
            size: { proposal, subviews, storage in
                var cache = (storage as? L.Cache) ?? layout.makeCache(subviews: subviews)
                let size = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
                storage = cache
                return size
            },
            place: { bounds, proposal, subviews, storage in
                var cache = (storage as? L.Cache) ?? layout.makeCache(subviews: subviews)
                layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
                storage = cache
            }
        ))
    }

    var nodeContent: (any View)? { content }
}
