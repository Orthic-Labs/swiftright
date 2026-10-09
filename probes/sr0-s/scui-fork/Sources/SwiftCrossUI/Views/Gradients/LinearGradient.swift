/// A linear gradient.
public struct LinearGradient: ElementaryView {
    /// The gradient represented as an array of color stops, each having a parametric location value.
    public let gradient: Gradient
    /// The normalized point where the gradient begins, defined in the view's coordinate space.
    ///
    /// Use values like `.top`, `.leading`, or custom `UnitPoint(x:y:)` offsets.
    public let startPoint: UnitPoint
    /// The normalized point where the gradient ends, defined in the views coordinate space.
    ///
    /// The color interpolation moves linearly from the start point to this point.
    public let endPoint: UnitPoint

    private static let idealSize = ViewSize(10, 10)

    /// Creates a linear gradient from a base gradient.
    public init(
        gradient: Gradient,
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public func asWidget<Backend: BaseAppBackend>(
        backend: Backend
    ) -> Backend.Widget {
        func __castBackend1<NewBackend: BaseAppBackend & BackendFeatures.LinearGradients>(_ backend: NewBackend) -> NewBackend.Widget {
        backend.createLinearGradientWidget()
    
        }
        guard let __castedBackend1 = backend as? any BaseAppBackend & BackendFeatures.LinearGradients else {
            fatalError("backend does not implement BackendFeatures.LinearGradients")
        }
        return __castBackend1(__castedBackend1) as! Backend.Widget
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        ViewLayoutResult.leafView(
            size: proposedSize.replacingUnspecifiedDimensions(by: Self.idealSize)
        )
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        func __castBackend2<NewBackend: BaseAppBackend & BackendFeatures.LinearGradients>(_ backend: NewBackend) {
            let widget = widget as! NewBackend.Widget
        backend.setSize(of: widget, to: layout.size.vector)
        backend.updateLinearGradientWidget(
            widget,
            gradient: self,
            withSize: layout.size.vector,
            in: environment
        )
    
        }
        guard let __castedBackend2 = backend as? any BaseAppBackend & BackendFeatures.LinearGradients else {
            fatalError("backend does not implement BackendFeatures.LinearGradients")
        }
        return __castBackend2(__castedBackend2)
    }
}

extension LinearGradient {
    /// Creates a linear gradient from a collection of colors.
    public init(
        stops: [Gradient.Stop],
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) {
        self.init(
            gradient: Gradient(stops: stops),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    /// Creates a linear gradient from a collection of color stops.
    public init(
        colors: [Color],
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) {
        self.init(
            gradient: Gradient(colors: colors),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}
