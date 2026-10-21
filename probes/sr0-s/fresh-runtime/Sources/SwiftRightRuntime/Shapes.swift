import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry metadata for a headless SwiftRight shape. Parametric: the host resolves it against the node's bounds
/// (`makePath(in:)`), because a shape's path depends on the rectangle it is given, which is known only after layout.
public indirect enum ShapeGeometry: Equatable, Sendable {
    case rectangle
    case roundedRectangle(cornerRadius: CGFloat, style: RoundedCornerStyle)
    case circle
    case capsule(style: RoundedCornerStyle)
    /// A fixed path in the node's local coordinates (a `Path` used as a shape).
    case path(Path)
    /// `Shape.trim(from:to:)` of another geometry.
    case trimmed(ShapeGeometry, from: CGFloat, to: CGFloat)
    /// `InsettableShape.inset(by:)` of a Circle, Rectangle, RoundedRectangle or Capsule (nested insets are summed).
    case inset(ShapeGeometry, by: CGFloat)
    /// A user shape that overrides `path(in:)`.
    case custom(CustomShapeGeometry)

    /// The node kind name: the plain shape's own name, `Path` for fixed and custom paths. Trim and inset keep their base's name.
    public var kindName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .roundedRectangle: return "RoundedRectangle"
        case .circle: return "Circle"
        case .capsule: return "Capsule"
        case .trimmed(let base, _, _), .inset(let base, _): return base.kindName
        case .path, .custom: return "Path"
        }
    }

    /// Inset of a geometry; an inset of an inset is one inset by the sum.
    static func insetting(_ geometry: ShapeGeometry, by amount: CGFloat) -> ShapeGeometry {
        if case .inset(let base, let existing) = geometry { return .inset(base, by: existing + amount) }
        return .inset(geometry, by: amount)
    }

    /// The outline of this geometry in `rect` (points, y down), as the matching SwiftUI shape's `path(in:)`.
    public func makePath(in rect: CGRect) -> Path {
        switch self {
        case .rectangle:
            return Path(rect)
        case .circle:
            let side = min(rect.width, rect.height)
            return Path(ellipseIn: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        case .roundedRectangle(let radius, let style):
            return ShapeGeometry.roundedPath(rect, radius: radius, style: style)
        case .capsule(let style):
            return ShapeGeometry.roundedPath(rect, radius: min(rect.width, rect.height) / 2, style: style)
        case .path(let path):
            return path
        case .custom(let custom):
            return custom.path(in: rect)
        case .trimmed(let base, let from, let to):
            return base.makePath(in: rect).trimmedPath(from: from, to: to)
        case .inset(let base, let amount):
            let inner = rect.insetBy(dx: amount, dy: amount)
            guard inner.width > 0, inner.height > 0 else { return Path() }
            switch base {
            case .roundedRectangle(let radius, let style): return ShapeGeometry.roundedPath(inner, radius: max(0, radius - amount), style: style)
            case .rectangle, .circle, .capsule: return base.makePath(in: inner)
            default: return base.makePath(in: rect)
            }
        }
    }

    /// The path a stroke of this geometry follows in `rect`. As `makePath(in:)`, except that a rectangle inset past its own width (`Rectangle().strokeBorder` of a
    /// one-point-wide rect, an inset of half the line width) collapses to the vertical line down its middle instead of nothing: the Mac draws MarkdownUI's inside
    /// column dividers that way (#74, markdown-basic-v1 capture, a one-point column rect). A rectangle collapsed in height still draws nothing, as in that capture, where
    /// the inside row line is absent.
    public func strokePath(in rect: CGRect) -> Path {
        if case .inset(.rectangle, let amount) = self {
            // Computed by hand: `CGRect.insetBy` returns the null rect (size 0 in both axes) once either side goes negative, which hid the height.
            let innerWidth = rect.width - 2 * amount, innerHeight = rect.height - 2 * amount
            if innerWidth <= 0, innerHeight > 0, rect.width > 0 {
                var line = Path()
                line.move(to: CGPoint(x: rect.midX, y: rect.minY + amount))
                line.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - amount))
                return line
            }
        }
        return makePath(in: rect)
    }

    private static func roundedPath(_ rect: CGRect, radius: CGFloat, style: RoundedCornerStyle) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        switch style {
        case .circular:
            var path = Path()
            path.addRoundedRectFromRightMiddle(rect, cornerRadius: radius)
            return path
        case .continuous:
            guard let elements = try? ContinuousRoundedGeometry.path(in: LayoutRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height), cornerRadius: radius) else { return Path() }
            var path = Path()
            for element in elements {
                switch element {
                case .move(let p): path.move(to: p.cgPoint)
                case .line(let p): path.addLine(to: p.cgPoint)
                case .cubic(let p, let c1, let c2): path.addCurve(to: p.cgPoint, control1: c1.cgPoint, control2: c2.cgPoint)
                case .close: path.closeSubpath()
                }
            }
            return path
        }
    }
}

/// Type-erased `path(in:)` of a user shape. Equality compares the shape's type and printed value (a closure cannot be compared).
public struct CustomShapeGeometry: Equatable, @unchecked Sendable {
    let identity: String
    private let make: (CGRect) -> Path
    /// The shape value, for `interpolated(from:amount:)`.
    private let value: Any
    /// This shape (the target) with its `animatableData` taken `t` of the way from another value of the same type; nil when the type differs or has no animatable data.
    private let interpolateFrom: (Any, Double) -> CustomShapeGeometry?

    public init<S: Shape>(_ shape: S) {
        identity = "\(type(of: shape))|\(String(describing: shape))"
        // The shape value is only read on the thread that resolves the view tree (same contract as @unchecked Sendable above).
        nonisolated(unsafe) let captured = shape
        make = { captured.path(in: $0) }
        value = captured
        interpolateFrom = { other, t in
            guard S.AnimatableData.self != EmptyAnimatableData.self, let typed = other as? S else { return nil }
            nonisolated(unsafe) let from = typed
            // Called by the graph's motion layers, on the main actor.
            return MainActor.assumeIsolated {
                var presented = captured
                presented.animatableData = from.animatableData.interpolated(towards: captured.animatableData, amount: t)
                return CustomShapeGeometry(presented)
            }
        }
    }

    public func path(in rect: CGRect) -> Path { make(rect) }
    /// This geometry presented `t` of the way from `from` (SwiftUI: the new shape value with its animatable data interpolated).
    func interpolated(from: CustomShapeGeometry, amount t: Double) -> CustomShapeGeometry? { interpolateFrom(from.value, t) }
    public static func == (lhs: CustomShapeGeometry, rhs: CustomShapeGeometry) -> Bool { lhs.identity == rhs.identity }
}

/// Corner treatment used by `RoundedRectangle`.
public enum RoundedCornerStyle: Hashable, Sendable {
    case circular
    case continuous
}

/// How a stroke ends. Apple: CGLineCap.
public enum LineCap: Hashable, Sendable {
    case butt, round, square
}

/// How a stroke turns a corner. Apple: CGLineJoin.
public enum LineJoin: Hashable, Sendable {
    case miter, round, bevel
}

/// Stroke parameters. Apple: https://developer.apple.com/documentation/swiftui/strokestyle
public struct StrokeStyle: Equatable, Sendable {
    public var lineWidth: CGFloat
    public var lineCap: LineCap
    public var lineJoin: LineJoin
    public var miterLimit: CGFloat
    public var dash: [CGFloat]
    public var dashPhase: CGFloat

    public init(lineWidth: CGFloat = 1, lineCap: LineCap = .butt, lineJoin: LineJoin = .miter, miterLimit: CGFloat = 10,
                dash: [CGFloat] = [], dashPhase: CGFloat = 0) {
        self.lineWidth = lineWidth; self.lineCap = lineCap; self.lineJoin = lineJoin
        self.miterLimit = miterLimit; self.dash = dash; self.dashPhase = dashPhase
    }
}

/// Fill parameters. Apple: https://developer.apple.com/documentation/swiftui/fillstyle
public struct FillStyle: Equatable, Sendable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        isEOFilled = eoFill; isAntialiased = antialiased
    }
}

/// A resolved fill or centered stroke recorded for a shape node.
public struct ShapePaint: Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case fill
        case stroke
    }

    public let kind: Kind
    public let color: ResolvedColor
    /// Nil for fills; stroke width is measured in logical points.
    public let lineWidth: CGFloat?
    /// Set by `stroke(_:style:)`; a plain `stroke(_:lineWidth:)` leaves it nil (butt cap, miter join, no dash).
    public let strokeStyle: StrokeStyle?
    /// Set by `fill(_:style:)` when the style is not the default.
    public let fillStyle: FillStyle?

    init(kind: Kind, color: ResolvedColor, lineWidth: CGFloat?, strokeStyle: StrokeStyle? = nil, fillStyle: FillStyle? = nil) {
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
        self.strokeStyle = strokeStyle
        self.fillStyle = fillStyle
    }

    /// This paint in another colour.
    func withColor(_ color: ResolvedColor) -> ShapePaint {
        ShapePaint(kind: kind, color: color, lineWidth: lineWidth, strokeStyle: strokeStyle, fillStyle: fillStyle)
    }

    /// This paint with another stroke width (the stroke style's too), for an animated line width (#54).
    func withLineWidth(_ width: CGFloat) -> ShapePaint {
        var style = strokeStyle
        style?.lineWidth = width
        return ShapePaint(kind: kind, color: color, lineWidth: width, strokeStyle: style, fillStyle: fillStyle)
    }

    /// The paint SwiftUI gives a shape with no `.fill` / `.stroke`: a non-zero fill in the inherited foreground style (`.foregroundStyle`), else `.primary`.
    public static func implicitFill(foreground: ResolvedColor?) -> ShapePaint {
        ShapePaint(kind: .fill, color: foreground ?? .semantic("label"), lineWidth: nil)
    }
}

/// Shape facts attached to a resolved node. Bounds are provided by `ResolvedNode.frame`.
public struct ResolvedShape: Equatable, Sendable {
    public let geometry: ShapeGeometry
    public let paint: ShapePaint?
}

/// Shared shape API for rectangle, rounded rectangle, circle, capsule, paths and custom shapes.
public protocol Shape: View, Animatable {
    var shapeGeometry: ShapeGeometry { get }
    /// The outline in `rect`. The default derives it from `shapeGeometry`; a custom shape overrides this (and then needs no `shapeGeometry`).
    /// A conformer must provide at least one of the two: the defaults call each other.
    func path(in rect: CGRect) -> Path
}

extension Shape {
    public var shapeGeometry: ShapeGeometry { .custom(CustomShapeGeometry(self)) }
    public func path(in rect: CGRect) -> Path { shapeGeometry.makePath(in: rect) }

    public func fill<S: ShapeStyle>(_ style: S) -> some View {
        ShapePaintView(shape: self, paint: ShapePaint(kind: .fill, color: style.resolvedColor, lineWidth: nil))
    }

    public func fill<S: ShapeStyle>(_ content: S, style fillStyle: FillStyle) -> some View {
        ShapePaintView(shape: self, paint: ShapePaint(kind: .fill, color: content.resolvedColor, lineWidth: nil,
                                                      fillStyle: fillStyle == FillStyle() ? nil : fillStyle))
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat = 1) -> some View {
        ShapePaintView(shape: self, paint: ShapePaint(kind: .stroke, color: style.resolvedColor, lineWidth: max(0, lineWidth)))
    }

    public func stroke<S: ShapeStyle>(_ content: S, style strokeStyle: StrokeStyle) -> some View {
        var style = strokeStyle
        style.lineWidth = max(0, style.lineWidth)
        return ShapePaintView(shape: self, paint: ShapePaint(kind: .stroke, color: content.resolvedColor, lineWidth: style.lineWidth, strokeStyle: style))
    }

    /// The part of the outline between two fractions of its arc length (see `Path.trimmedPath`).
    public func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> TrimmedShape<Self> {
        TrimmedShape(base: self, from: startFraction, to: endFraction)
    }
}

extension Shape {
    /// A user shape used as a view: SwiftUI fills it with the foreground style (the host's implicit fill, `ShapePaint.implicitFill`).
    /// Built-in shapes are primitives and declare their own `body`.
    @MainActor public var body: _ShapeView<Self> { _ShapeView(shape: self) }
}

/// The view a user shape is drawn as when no `.fill` / `.stroke` is applied. Apple: https://developer.apple.com/documentation/swiftui/_shapeview
public struct _ShapeView<Content: Shape>: View, PrimitiveView {
    let shape: Content

    @MainActor public var body: Never { return fatalError("primitive shape view has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shape.shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}

private struct ShapePaintView<Content: Shape>: View, PrimitiveView {
    let shape: Content
    let paint: ShapePaint

    @MainActor var body: Never { return fatalError("primitive shape paint has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shape.shapeGeometry, paint: paint)) }
    var nodeContent: (any View)? { nil }
}

/// A shape that can be inset by a distance. Apple: https://developer.apple.com/documentation/swiftui/insettableshape
public protocol InsettableShape: Shape {
    associatedtype InsetShape: InsettableShape
    func inset(by amount: CGFloat) -> InsetShape
}

extension InsettableShape {
    /// Strokes inside the shape's edge: inset by half the line width, then stroke.
    public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
        inset(by: lineWidth / 2).stroke(content, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle) -> some View {
        inset(by: style.lineWidth / 2).stroke(content, style: style)
    }
}

/// `Shape.trim(from:to:)`.
public struct TrimmedShape<Base: Shape>: Shape, PrimitiveView {
    public let base: Base
    public var startFraction: CGFloat
    public var endFraction: CGFloat

    public init(base: Base, from startFraction: CGFloat, to endFraction: CGFloat) {
        self.base = base; self.startFraction = startFraction; self.endFraction = endFraction
    }

    public var shapeGeometry: ShapeGeometry { .trimmed(base.shapeGeometry, from: startFraction, to: endFraction) }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}

/// `InsettableShape.inset(by:)` of one of the built-in shapes.
public struct _InsetShape<Base: Shape>: InsettableShape, PrimitiveView {
    public let base: Base
    public let amount: CGFloat

    public init(base: Base, amount: CGFloat) { self.base = base; self.amount = amount }

    public func inset(by more: CGFloat) -> _InsetShape<Base> { _InsetShape(base: base, amount: amount + more) }
    public var shapeGeometry: ShapeGeometry { ShapeGeometry.insetting(base.shapeGeometry, by: amount) }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}

extension Path: Shape, PrimitiveView {
    public var shapeGeometry: ShapeGeometry { .path(self) }
    /// A path used as a shape is drawn as given, in the node's local coordinates.
    public func path(in rect: CGRect) -> Path { self }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}

/// Rectangular path that fills its proposed bounds.
public struct Rectangle: InsettableShape, PrimitiveView {
    public init() {}
    public var shapeGeometry: ShapeGeometry { .rectangle }
    public func inset(by amount: CGFloat) -> _InsetShape<Rectangle> { _InsetShape(base: self, amount: amount) }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}


/// Rounded rectangular path that fills its proposed bounds.
public struct RoundedRectangle: InsettableShape, PrimitiveView {
    public let cornerRadius: CGFloat
    public let style: RoundedCornerStyle

    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.cornerRadius = max(0, cornerRadius)
        self.style = style
    }

    public var shapeGeometry: ShapeGeometry { .roundedRectangle(cornerRadius: cornerRadius, style: style) }
    public func inset(by amount: CGFloat) -> _InsetShape<RoundedRectangle> { _InsetShape(base: self, amount: amount) }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}


/// Circular path that fits its proposed bounds.
public struct Circle: InsettableShape, PrimitiveView {
    public init() {}
    public var shapeGeometry: ShapeGeometry { .circle }
    public func inset(by amount: CGFloat) -> _InsetShape<Circle> { _InsetShape(base: self, amount: amount) }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}

/// A rounded rectangle whose corner radius is half its short side. Defaults to the continuous corner style, as SwiftUI's does.
public struct Capsule: InsettableShape, PrimitiveView {
    public let style: RoundedCornerStyle

    public init(style: RoundedCornerStyle = .continuous) { self.style = style }

    public var shapeGeometry: ShapeGeometry { .capsule(style: style) }
    public func inset(by amount: CGFloat) -> _InsetShape<Capsule> { _InsetShape(base: self, amount: amount) }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}
