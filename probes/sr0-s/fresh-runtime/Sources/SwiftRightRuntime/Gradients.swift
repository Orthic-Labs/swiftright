import Foundation

// Issue #60 (SR1 backlog), pass 2: `Gradient`, `Gradient.Stop`, `LinearGradient` and `RadialGradient`.
//
// A gradient used where a view is expected (`LinearGradient(...)`, `.overlay(gradient)`, `.background(gradient)`, `Shape.fill(gradient)`) is ONE resolved node of kind
// "Gradient" carrying a `ResolvedGradient` (stops, start/end points or centre/radii). The host rasterises it into a bitmap of the node's snapped pixel frame
// (`GradientRaster` in SwiftRightHost), so it is smooth, at any angle. `Shape.fill(gradient)` is the gradient view under `.clipShape(shape)`: the host masks the bitmap
// with the shape's anti-aliased coverage, the same mask path every `.clipShape` uses.
//
// Colour interpolation (decision, UNVERIFIED against a macOS 27 capture until the linear-gradient-v1 pair runs): stops are interpolated per channel, linearly, in
// gamma-encoded sRGB (the device RGB space SwiftUI and Core Graphics default to) with straight (non-premultiplied) alpha; the host quantises each pixel once, rounding
// to the nearest 8-bit level. A stop with alpha 0 (`Color.clear`) has no hue of its own: the other stop's colour is used, so `blue -> clear` fades blue's alpha only.
// Semantic colours are resolved by the host before interpolation (light/dark scheme of the node).
// Sampling: the colour at a pixel is that of its centre; beyond the first and last stop the gradient is clamped (extended), as SwiftUI draws it.
//
// APPROXIMATIONS (each stated where it applies):
// - As a plain `ShapeStyle` (`foregroundStyle(gradient)`, `AnyShapeStyle(gradient)`, `stroke(gradient)`) a gradient resolves to its colour at the midpoint, because a
//   `ShapeStyle` here resolves to one colour. `Shape.fill(_:)` and `View.background(_:)` have gradient overloads that draw the real gradient.
// - A gradient view's ideal size is a shape's (10 x 10 when nothing is proposed), as SwiftUI's `LinearGradient` body is a `Rectangle` filled with the style.
// AngularGradient and EllipticalGradient are not provided.

/// Apple: https://developer.apple.com/documentation/swiftui/gradient
public struct Gradient: Equatable, Sendable {
    /// Apple: https://developer.apple.com/documentation/swiftui/gradient/stop
    public struct Stop: Equatable, Sendable {
        public var color: Color
        public var location: CGFloat

        /// Apple: https://developer.apple.com/documentation/swiftui/gradient/stop/init(color:location:)
        public init(color: Color, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    public var stops: [Stop]

    /// Apple: https://developer.apple.com/documentation/swiftui/gradient/init(stops:)
    public init(stops: [Stop]) {
        self.stops = stops
    }

    /// Evenly spaced stops: location `i / (count - 1)` (a single colour sits at 0).
    /// Apple: https://developer.apple.com/documentation/swiftui/gradient/init(colors:)
    public init(colors: [Color]) {
        let last = max(colors.count - 1, 1)
        stops = colors.enumerated().map { Stop(color: $0.element, location: CGFloat($0.offset) / CGFloat(last)) }
    }

    /// The colour at `t` (0 at the start point, 1 at the end point): the first stop's colour before the first location, the last stop's after the last,
    /// else the blend of the two stops around `t` (see the file header for how colours blend).
    func resolvedColor(at t: Double) -> ResolvedColor {
        let ordered = stops.enumerated().sorted { a, b in
            a.element.location == b.element.location ? a.offset < b.offset : a.element.location < b.element.location
        }.map(\.element)
        guard let first = ordered.first, let last = ordered.last else { return .semantic("clear") }
        if t <= Double(first.location) { return first.color.resolvedColor }
        if t >= Double(last.location) { return last.color.resolvedColor }
        for index in 1..<ordered.count {
            let lower = ordered[index - 1], upper = ordered[index]
            if t <= Double(upper.location) {
                let span = Double(upper.location - lower.location)
                guard span > 0 else { return upper.color.resolvedColor }
                return ResolvedColor.blended(lower.color.resolvedColor, upper.color.resolvedColor, (t - Double(lower.location)) / span)
            }
        }
        return last.color.resolvedColor
    }
}

extension ResolvedColor {
    /// The colour without its alpha, and the alpha. `clear` is a transparent colour with no hue of its own.
    fileprivate var baseAndAlpha: (base: ResolvedColor, alpha: Double) {
        switch self {
        case .rgba(let r, let g, let b, let a): return (.rgba(r, g, b, 1), a)
        case .semantic(let name): return name == "clear" ? (self, 0) : (self, 1)
        case .semanticAlpha(let name, let a): return name == "clear" ? (.semantic("clear"), 0) : (.semantic(name), a)
        }
    }

    private static func withAlpha(_ base: ResolvedColor, _ alpha: Double) -> ResolvedColor {
        let a = min(max(alpha, 0), 1)
        switch base {
        case .rgba(let r, let g, let b, _): return .rgba(r, g, b, a)
        case .semantic(let name):
            if name == "clear" { return base }
            return a >= 1 ? base : .semanticAlpha(name, a)
        case .semanticAlpha(let name, _): return a >= 1 ? .semantic(name) : .semanticAlpha(name, a)
        }
    }

    /// `a` at `t` = 0, `b` at `t` = 1; see the file header for the rules.
    static func blended(_ a: ResolvedColor, _ b: ResolvedColor, _ t: Double) -> ResolvedColor {
        let t = min(max(t, 0), 1)
        let (baseA, alphaA) = a.baseAndAlpha
        let (baseB, alphaB) = b.baseAndAlpha
        let alpha = alphaA + (alphaB - alphaA) * t
        if alphaA == 0 { return withAlpha(baseB, alpha) }
        if alphaB == 0 { return withAlpha(baseA, alpha) }
        if case .rgba(let r1, let g1, let b1, _) = baseA, case .rgba(let r2, let g2, let b2, _) = baseB {
            return .rgba(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t, alpha)
        }
        if baseA == baseB { return withAlpha(baseA, alpha) }
        return withAlpha(t < 0.5 ? baseA : baseB, alpha)
    }
}

/// What a gradient node resolves to for the host: ordered stops and the geometry in unit points of the node's frame.
public struct ResolvedGradient: Equatable, Sendable {
    public struct Stop: Equatable, Sendable {
        public var location: Double
        public var color: ResolvedColor
        public init(location: Double, color: ResolvedColor) { self.location = location; self.color = color }
    }

    public enum Geometry: Equatable, Sendable {
        /// Along the line from `start` to `end` (unit points of the frame); the colour is constant on lines perpendicular to it, in the frame's pixel space.
        case linear(start: UnitPoint, end: UnitPoint)
        /// Rings about `center` (unit point of the frame): radii in points, `startRadius` at location 0 and `endRadius` at location 1.
        case radial(center: UnitPoint, startRadius: Double, endRadius: Double)
    }

    public var geometry: Geometry
    /// Sorted by location (stable), locations clamped to 0...1. Never empty (an empty gradient resolves to one clear stop).
    public var stops: [Stop]

    public init(geometry: Geometry, stops: [Stop]) {
        self.geometry = geometry
        self.stops = stops.isEmpty ? [Stop(location: 0, color: .semantic("clear"))] : stops
    }

    init(geometry: Geometry, gradient: Gradient) {
        let ordered = gradient.stops.enumerated().sorted { a, b in
            a.element.location == b.element.location ? a.offset < b.offset : a.element.location < b.element.location
        }.map { Stop(location: min(max(Double($0.element.location), 0), 1), color: $0.element.color.resolvedColor) }
        self.init(geometry: geometry, stops: ordered)
    }

    /// Stops with a `.tint` colour replaced by the environment's tint.
    func resolvingTint(_ environment: EnvironmentValues) -> ResolvedGradient {
        ResolvedGradient(geometry: geometry, stops: stops.map { Stop(location: $0.location, color: $0.color.resolvingTint(environment)) })
    }
}

/// A colour gradient along a line from `startPoint` to `endPoint` (unit points of the view). Used as a view it fills the space it is offered, drawn by the host as one
/// smooth bitmap (see the file header); used as a `ShapeStyle` it resolves to its midpoint colour, except in `Shape.fill(_:)` and `View.background(_:)`, which draw it.
/// Apple: https://developer.apple.com/documentation/swiftui/lineargradient
public struct LinearGradient: ShapeStyle, Equatable, Sendable {
    public let gradient: Gradient
    public let startPoint: UnitPoint
    public let endPoint: UnitPoint

    /// Apple: https://developer.apple.com/documentation/swiftui/lineargradient/init(gradient:startpoint:endpoint:)
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/lineargradient/init(colors:startpoint:endpoint:)
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/lineargradient/init(stops:startpoint:endpoint:)
    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }

    /// The colour at the middle of the gradient: what a single-colour `ShapeStyle` use gets.
    public var resolvedColor: ResolvedColor { gradient.resolvedColor(at: 0.5) }

    var resolved: ResolvedGradient { ResolvedGradient(geometry: .linear(start: startPoint, end: endPoint), gradient: gradient) }
}

extension LinearGradient: View, PrimitiveView {
    @MainActor public var body: Never { return fatalError("LinearGradient has no body") }
    var nodeKind: NodeKind { .gradient(resolved) }
    var nodeContent: (any View)? { nil }
}

/// A colour gradient in rings about `center`, from `startRadius` (location 0) to `endRadius` (location 1), in points.
/// Apple: https://developer.apple.com/documentation/swiftui/radialgradient
public struct RadialGradient: ShapeStyle, Equatable, Sendable {
    public let gradient: Gradient
    public let center: UnitPoint
    public let startRadius: CGFloat
    public let endRadius: CGFloat

    /// Apple: https://developer.apple.com/documentation/swiftui/radialgradient/init(gradient:center:startradius:endradius:)
    public init(gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.gradient = gradient
        self.center = center
        self.startRadius = startRadius
        self.endRadius = endRadius
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/radialgradient/init(colors:center:startradius:endradius:)
    public init(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.init(gradient: Gradient(colors: colors), center: center, startRadius: startRadius, endRadius: endRadius)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/radialgradient/init(stops:center:startradius:endradius:)
    public init(stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.init(gradient: Gradient(stops: stops), center: center, startRadius: startRadius, endRadius: endRadius)
    }

    /// The colour at the middle of the gradient: what a single-colour `ShapeStyle` use gets.
    public var resolvedColor: ResolvedColor { gradient.resolvedColor(at: 0.5) }

    var resolved: ResolvedGradient {
        ResolvedGradient(geometry: .radial(center: center, startRadius: Double(startRadius), endRadius: Double(endRadius)), gradient: gradient)
    }
}

extension RadialGradient: View, PrimitiveView {
    @MainActor public var body: Never { return fatalError("RadialGradient has no body") }
    var nodeKind: NodeKind { .gradient(resolved) }
    var nodeContent: (any View)? { nil }
}

extension Shape {
    /// Fills the shape with a gradient: the gradient view clipped to the shape (the host masks its bitmap with the shape's anti-aliased coverage).
    /// Apple: https://developer.apple.com/documentation/swiftui/shape/fill(_:style:)
    public func fill(_ gradient: LinearGradient) -> some View {
        gradient.clipShape(self)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/shape/fill(_:style:)
    public func fill(_ gradient: RadialGradient) -> some View {
        gradient.clipShape(self)
    }
}

extension View {
    /// Draws a gradient behind this view, offered the view's size.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/background(_:ignoressafeareaedges:)
    public func background(_ gradient: LinearGradient) -> some View {
        BackgroundStack(base: self, background: gradient, alignment: .center)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/background(_:ignoressafeareaedges:)
    public func background(_ gradient: RadialGradient) -> some View {
        BackgroundStack(base: self, background: gradient, alignment: .center)
    }

    /// Draws a gradient clipped to `shape` behind this view.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/background(_:in:fillstyle:)
    public func background<T: Shape>(_ gradient: LinearGradient, in shape: T) -> some View {
        BackgroundStack(base: self, background: gradient.clipShape(shape), alignment: .center)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/view/background(_:in:fillstyle:)
    public func background<T: Shape>(_ gradient: RadialGradient, in shape: T) -> some View {
        BackgroundStack(base: self, background: gradient.clipShape(shape), alignment: .center)
    }
}
