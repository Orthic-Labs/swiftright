/// The children of a view graph node. This is implemented by a few different
/// types for various purposes. E.g. variable length with same-typed elements
/// (``ForEach``), and fixed length with distinctly-typed elements (``TupleView1``,
/// ``TupleView2``, etc).
@MainActor
public protocol ViewGraphNodeChildren {
    /// The widget of the children. Type-erased to avoid the type of the currently
    /// selected backend leaking into the ``View`` protocol, requiring users to
    /// engage with annoying complexity and reducing ease of backend switching.
    var widgets: [AnyWidget] { get }
    /// Erased representations of all contained child nodes.
    var erasedNodes: [ErasedViewGraphNode] { get }
    #if !SCUI_STOCK_TEARDOWN
    /// SR0-OVERRIDE O4: called once, before this node's children are unmounted, when the node
    /// leaves the view graph. `onDisappear` actions run here instead of from `deinit`.
    func willUnmount()
    #endif
}

#if !SCUI_STOCK_TEARDOWN
extension ViewGraphNodeChildren {
    public func willUnmount() {}
}
#endif

extension ViewGraphNodeChildren {
    /// Gets the node's type-erased widgets for a specific backend (crashing if the
    /// widgets were created by a different backend).
    public func widgets<Backend: BaseAppBackend>(for backend: Backend) -> [Backend.Widget] {
        return widgets.map { $0.into() }
    }
}
