import Foundation

// Issue #60 (SR1 backlog), first pass: `Gradient`, `Gradient.Stop` and `LinearGradient`.
//
// ADAPTATION: the host's shape painter has no gradient fill (a `ShapePaint` carries one `ResolvedColor`), so a linear gradient is COMPOSED from existing
// primitives instead: `bandCount` equal strips of solid `Color`, laid out in a VStack (or HStack) with no spacing, each strip the gradient's colour at the
// strip's centre. A gradient used where a view is expected (`.overlay(gradient)`, `.background(gradient)`, `gradient.frame(...)`, `Shape.fill(gradient)`) is
// therefore stepped, not smooth: with 32 bands a 40 pt gradient steps every 1.25 pt (each step is a distinct colour only where the colours differ enough).
// A host gradient fill (one `SWR` gradient primitive) would replace the bands; until then this is the whole implementation.
//
// APPROXIMATIONS (each stated where it applies):
// - The gradient axis is the dominant axis of `startPoint` -> `endPoint` (vertical when |dy| >= |dx|). A diagonal gradient is drawn along that one axis, not
//   along the diagonal.
// - Colours blend in straight (non-premultiplied) sRGB for two `rgba` colours; two semantic colours with the same name blend their alpha; a semantic colour
//   against `clear` fades the semantic colour's alpha (the usual `Color.blue -> Color.clear` fade keeps its hue); any other pair of semantic colours steps at the
//   midpoint (semantic names resolve in the host, so they cannot be blended here).
// - As a plain `ShapeStyle` (`foregroundStyle(gradient)`, `AnyShapeStyle(gradient)`, `stroke(gradient)`) a gradient resolves to its colour at the midpoint, because a
//   `ShapeStyle` here resolves to one colour. `Shape.fill(_:)` and `View.background(_:)` have `LinearGradient` overloads that draw the bands instead.
// RadialGradient and AngularGradient are not provided (they need a host primitive; concentric bands would not be a faithful angular sweep).

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

/// A colour gradient along a line from `startPoint` to `endPoint` (unit points of the view). Used as a view it fills the space it is offered, as a stack of solid
/// bands (see the file header); used as a `ShapeStyle` it resolves to its midpoint colour, except in `Shape.fill(_:)` and `View.background(_:)`, which draw the bands.
/// Apple: https://developer.apple.com/documentation/swiftui/lineargradient
public struct LinearGradient: ShapeStyle, Equatable, Sendable {
    public let gradient: Gradient
    public let startPoint: UnitPoint
    public let endPoint: UnitPoint

    /// Number of solid strips a gradient view is drawn with.
    static let bandCount = 32

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

    /// True when the gradient runs mainly top to bottom (the band axis). Equal extents count as vertical.
    var isVertical: Bool { abs(endPoint.y - startPoint.y) >= abs(endPoint.x - startPoint.x) }

    /// The colour of band `index` of `count`, sampled at the band's centre along the gradient axis. A degenerate gradient (start == end) is its first colour.
    func bandColor(_ index: Int, of count: Int = LinearGradient.bandCount) -> ResolvedColor {
        let position = (Double(index) + 0.5) / Double(count)
        let from = Double(isVertical ? startPoint.y : startPoint.x)
        let to = Double(isVertical ? endPoint.y : endPoint.x)
        guard to != from else { return gradient.resolvedColor(at: 0) }
        return gradient.resolvedColor(at: (position - from) / (to - from))
    }
}

extension LinearGradient: View {
    @MainActor public var body: some View { LinearGradientBands(gradient: self) }
}

/// The bands of a gradient view. Each band is a plain `Color` node (greedy), so the stack splits the space it is offered evenly.
struct LinearGradientBands: View {
    let gradient: LinearGradient

    @MainActor var body: some View {
        if gradient.isVertical {
            VStack(spacing: 0) {
                ForEach(0..<LinearGradient.bandCount, id: \.self) { index in
                    Color(resolved: gradient.bandColor(index))
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(0..<LinearGradient.bandCount, id: \.self) { index in
                    Color(resolved: gradient.bandColor(index))
                }
            }
        }
    }
}

extension Shape {
    /// Fills the shape with a gradient: the gradient's bands clipped to the shape (the host has no gradient fill; see the file header).
    /// Apple: https://developer.apple.com/documentation/swiftui/shape/fill(_:style:)
    public func fill(_ gradient: LinearGradient) -> some View {
        gradient.clipShape(self)
    }
}

extension View {
    /// Draws a gradient behind this view, offered the view's size (bands; see the file header).
    /// Apple: https://developer.apple.com/documentation/swiftui/view/background(_:ignoressafeareaedges:)
    public func background(_ gradient: LinearGradient) -> some View {
        BackgroundStack(base: self, background: gradient, alignment: .center)
    }

    /// Draws a gradient clipped to `shape` behind this view.
    /// Apple: https://developer.apple.com/documentation/swiftui/view/background(_:in:fillstyle:)
    public func background<T: Shape>(_ gradient: LinearGradient, in shape: T) -> some View {
        BackgroundStack(base: self, background: gradient.clipShape(shape), alignment: .center)
    }
}
