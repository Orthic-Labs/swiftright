/// An angular gradient, often referred to as a conic gradient.
///
/// Currently unsupported on WinUIBackend and GtkBackend.
public struct AngularGradient: ElementaryView {
    /// The gradient represented as an array of color stops, each having a parametric location value.
    public let gradient: Gradient
    /// The normalized center point of the gradient in its coordinate space.
    public let center: UnitPoint
    /// The angle at which the gradient starts drawing. 0° is trailing center.
    public let startAngle: Angle
    /// The angle at which the gradient stops drawing. Everything after is filled with the last used color.
    ///
    /// Ends 360° from ``AngularGradient/startAngle`` when `nil`.
    public let endAngle: Angle?

    private static let idealSize = ViewSize(10, 10)

    /// Creates an angular gradient that completes a full turn.
    public init(
        gradient: Gradient,
        center: UnitPoint,
        angle: Angle = .zero
    ) {
        self.gradient = gradient
        self.center = center
        self.startAngle = angle
        self.endAngle = nil
    }

    /// Creates an angular gradient that completes a partial rotation.
    ///
    /// For each ``Gradient.Stop``, a location of 0 corresponds to 0°, and a location of 1 corresponds to 360°.
    public init(
        gradient: Gradient,
        center: UnitPoint,
        startAngle: Angle,
        endAngle: Angle
    ) {
        self.gradient = gradient
        self.center = center
        self.startAngle = startAngle
        self.endAngle = endAngle
    }

    public func asWidget<Backend: BaseAppBackend>(
        backend: Backend
    ) -> Backend.Widget {
        func __castBackend1<NewBackend: BaseAppBackend & BackendFeatures.AngularGradients>(_ backend: NewBackend) -> NewBackend.Widget {
        backend.createAngularGradientWidget()
    
        }
        guard let __castedBackend1 = backend as? any BaseAppBackend & BackendFeatures.AngularGradients else {
            fatalError("backend does not implement BackendFeatures.AngularGradients")
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
        func __castBackend2<NewBackend: BaseAppBackend & BackendFeatures.AngularGradients>(_ backend: NewBackend) {
            let widget = widget as! NewBackend.Widget
        backend.setSize(of: widget, to: layout.size.vector)
        backend.updateAngularGradientWidget(
            widget,
            gradient: self,
            withSize: layout.size.vector,
            in: environment
        )
    
        }
        guard let __castedBackend2 = backend as? any BaseAppBackend & BackendFeatures.AngularGradients else {
            fatalError("backend does not implement BackendFeatures.AngularGradients")
        }
        return __castBackend2(__castedBackend2)
    }
}

extension AngularGradient {
    /// Creates an angular gradient from a collection of colors that completes a full turn.
    public init(
        colors: [Color],
        center: UnitPoint,
        angle: Angle = .zero
    ) {
        self.init(
            gradient: Gradient(colors: colors),
            center: center,
            angle: angle
        )
    }

    /// Creates an angular gradient from a collection of color stops that completes a full turn.
    public init(
        stops: [Gradient.Stop],
        center: UnitPoint,
        angle: Angle = .zero
    ) {
        self.init(
            gradient: Gradient(stops: stops),
            center: center,
            angle: angle
        )
    }

    /// Creates an angular gradient from a collection of colors that completes a partial rotation.
    public init(
        colors: [Color],
        center: UnitPoint,
        startAngle: Angle,
        endAngle: Angle
    ) {
        self.init(
            gradient: Gradient(colors: colors),
            center: center,
            startAngle: startAngle,
            endAngle: endAngle
        )
    }

    /// Creates an angular gradient from a collection of color stops that completes a partial rotation.
    ///
    /// Stops are expected to be in 360° unit space.
    public init(
        stops: [Gradient.Stop],
        center: UnitPoint,
        startAngle: Angle,
        endAngle: Angle
    ) {
        self.init(
            gradient: Gradient(stops: stops),
            center: center,
            startAngle: startAngle,
            endAngle: endAngle
        )
    }

    /// Stops adjusted to accomodate endAngle on backends without native support.
    @_spi(Backends) public var adjustedStops: [Gradient.Stop] {
        guard let endAngle else { return gradient.stops }

        var stops = gradient.stops

        let range = (endAngle - startAngle).degrees

        if range < 0 {
            stops = stops.map {
                Gradient.Stop(color: $0.color, location: 1 - $0.location)
            }
        }

        let absoluteRange = abs(range)

        let dividableRange = absoluteRange / 360

        stops = stops.map {
            Gradient.Stop(color: $0.color, location: $0.location * dividableRange)
        }

        return stops.sorted(by: { $0.location < $1.location })
    }
}
