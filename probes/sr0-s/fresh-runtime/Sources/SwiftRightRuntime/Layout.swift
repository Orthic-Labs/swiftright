import Foundation

/// The public `Layout` subset: size and placement with subview size queries and a cache.
@MainActor
public protocol Layout {
    associatedtype Cache = Void
    func makeCache(subviews: Subviews) -> Cache
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> LayoutSize
    @_disfavoredOverload
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
    @_disfavoredOverload
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
}

extension Layout where Cache == Void {
    public func makeCache(subviews: Subviews) -> Cache { () }
}

extension Layout {
    /// Adapts a SwiftUI-style size witness to the runtime's portable geometry path.
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> LayoutSize {
        let size: CGSize = sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        return LayoutSize(size)
    }

    /// Existing `LayoutSize` implementations keep their original witness and behavior.
    /// A `Layout` must implement one of the two size witnesses; this terminal default prevents
    /// missing witnesses from silently producing an empty container.
    @_disfavoredOverload
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        preconditionFailure("Layout must implement a LayoutSize or CGSize sizeThatFits witness")
    }

    /// Adapts runtime bounds for a SwiftUI-style CGRect placement witness.
    public func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        placeSubviews(in: bounds.cgRect, proposal: proposal, subviews: subviews, cache: &cache)
    }

    /// A `Layout` must implement one placement witness; this terminal default prevents silent omission.
    @_disfavoredOverload
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        preconditionFailure("Layout must implement a LayoutRect or CGRect placeSubviews witness")
    }
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
    /// Container bounds to mirror within when the container's layout direction is right-to-left.
    let mirrorBounds: LayoutRect?

    init(graph: Graph, node: Node, mirrorBounds: LayoutRect? = nil) {
        self.graph = graph
        self.node = node
        self.mirrorBounds = mirrorBounds
    }

    /// The runtime's portable size; ask for it by type (`let s: LayoutSize = ...`).
    @_disfavoredOverload
    public func sizeThatFits(_ proposal: ProposedViewSize) -> LayoutSize {
        graph.measure(node, proposal)
    }

    /// The subview's `.layoutPriority(_:)` (0 when none is set).
    /// Apple: https://developer.apple.com/documentation/swiftui/layoutsubview/priority
    public var priority: Double { graph.layoutPriority(of: node) }

    /// SwiftUI's `LayoutSubview.sizeThatFits(_:)` returns `CGSize`, so an untyped `var size = subview.sizeThatFits(...)` is a CGSize as in SwiftUI.
    /// Apple: https://developer.apple.com/documentation/swiftui/layoutsubview/sizethatfits(_:)
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        graph.measure(node, proposal).cgSize
    }

    /// Places the child so that `anchor` lies at `position`, sized under `proposal`.
    public func place(at position: LayoutPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        let size = graph.measure(node, proposal)
        let origin = LayoutPoint(x: position.x - anchor.x * size.width, y: position.y - anchor.y * size.height)
        let rect = LayoutRect(origin: origin, size: size)
        graph.place(node, in: mirrorBounds.map { graph.mirroredRect(rect, in: $0, if: true) } ?? rect, proposal: proposal)
    }

    @_disfavoredOverload
    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        place(at: LayoutPoint(position), anchor: anchor, proposal: proposal)
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
                let size: LayoutSize = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
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
