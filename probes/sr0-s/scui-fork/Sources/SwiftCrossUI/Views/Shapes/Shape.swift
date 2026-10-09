/// A 2D shape that can be drawn as a view.
///
/// If no stroke color or fill color is specified, the default is no stroke and
/// a fill of the current foreground color.
public protocol Shape: View, Sendable, _RemoveGlobalActorIsolation where Content == EmptyView {
    /// Draw the path for this shape.
    ///
    /// The bounds passed to a shape that is immediately drawn as a view will
    /// always have an origin of (0, 0). However, you may pass a different
    /// bounding box to subpaths. For example, this code draws a rectangle in
    /// the left half of the bounds and an ellipse in the right half:
    /// ```swift
    /// func path(in bounds: Path.Rect) -> Path {
    ///     Path()
    ///         .addSubpath(
    ///             Rectangle().path(
    ///                 in: Path.Rect(
    ///                     x: bounds.x,
    ///                     y: bounds.y,
    ///                     width: bounds.width / 2.0,
    ///                     height: bounds.height
    ///                 )
    ///             )
    ///         )
    ///         .addSubpath(
    ///             Ellipse().path(
    ///                 in: Path.Rect(
    ///                     x: bounds.center.x,
    ///                     y: bounds.y,
    ///                     width: bounds.width / 2.0,
    ///                     height: bounds.height
    ///                 )
    ///             )
    ///         )
    /// }
    /// ```
    ///
    /// - Parameter bounds: The bounds of this shape.
    func path(in bounds: Path.Rect) -> Path

    /// Determine the ideal size of this shape given the proposed bounds.
    ///
    /// The default implementation accepts the proposal, replacing unspecified
    /// dimensions with 10.
    ///
    /// - Parameter proposal: The proposed bounds of this shape.
    /// - Returns: The shape's size for the given proposal.
    func size(fitting proposal: ProposedViewSize) -> ViewSize
}

extension Shape {
    public var body: EmptyView { return EmptyView() }

    public func size(fitting proposal: ProposedViewSize) -> ViewSize {
        proposal.replacingUnspecifiedDimensions(by: ViewSize(10, 10))
    }

    @MainActor
    public func children<Backend: BaseAppBackend>(
        backend _: Backend,
        snapshots _: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment _: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        ShapeStorage()
    }

    @MainActor
    public func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        func __castBackend1<NewBackend: BaseAppBackend & BackendFeatures.Paths>(_ backend: NewBackend) -> NewBackend.Widget {
        let container = backend.createPathWidget()
        let storage = children as! ShapeStorage
        storage.backendPath = backend.createPath()
        storage.oldPath = nil
        return container
    
        }
        guard let __castedBackend1 = backend as? any BaseAppBackend & BackendFeatures.Paths else {
            fatalError("backend does not implement BackendFeatures.Paths")
        }
        return __castBackend1(__castedBackend1) as! Backend.Widget
    }

    @MainActor
    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let size = size(fitting: proposedSize)
        return ViewLayoutResult.leafView(size: size)
    }

    @MainActor
    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        func __castBackend2<NewBackend: BaseAppBackend & BackendFeatures.Paths>(_ backend: NewBackend) {
            let widget = widget as! NewBackend.Widget
        let bounds = Path.Rect(
            x: 0.0,
            y: 0.0,
            width: layout.size.width,
            height: layout.size.height
        )
        let path = path(in: bounds)

        let storage = children as! ShapeStorage
        let pointsChanged = storage.oldPath?.actions != path.actions
        storage.oldPath = path

        let backendPath = storage.backendPath as! NewBackend.Path
        backend.updatePath(
            backendPath,
            path,
            bounds: bounds,
            pointsChanged: pointsChanged,
            environment: environment
        )

        backend.setSize(of: widget, to: layout.size.vector)
        backend.renderPath(
            backendPath,
            container: widget,
            strokeColor: Color.clear.resolve(in: environment),
            fillColor: environment.suggestedForegroundColor.resolve(in: environment),
            overrideStrokeStyle: nil
        )
    
        }
        guard let __castedBackend2 = backend as? any BaseAppBackend & BackendFeatures.Paths else {
            fatalError("backend does not implement BackendFeatures.Paths")
        }
        return __castBackend2(__castedBackend2)
    }
}

final class ShapeStorage: ViewGraphNodeChildren {
    let widgets: [AnyWidget] = []
    let erasedNodes: [ErasedViewGraphNode] = []
    var backendPath: Any!
    var oldPath: Path?
}
