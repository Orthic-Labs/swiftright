import Foundation

/// Geometry metadata for a headless SwiftRight shape.
public enum ShapeGeometry: Equatable, Sendable {
    case rectangle
    case roundedRectangle(cornerRadius: CGFloat, style: RoundedCornerStyle)
    case circle
}

/// Corner treatment used by `RoundedRectangle`.
public enum RoundedCornerStyle: Hashable, Sendable {
    case circular
    case continuous
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

    init(kind: Kind, color: ResolvedColor, lineWidth: CGFloat?) {
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }
}

/// Shape facts attached to a resolved node. Bounds are provided by `ResolvedNode.frame`.
public struct ResolvedShape: Equatable, Sendable {
    public let geometry: ShapeGeometry
    public let paint: ShapePaint?
}

/// Shared shape API for rectangle, rounded rectangle & circle.
public protocol Shape: View {
    var shapeGeometry: ShapeGeometry { get }
}

extension Shape {
    public func fill<S: ShapeStyle>(_ style: S) -> some View {
        ShapePaintView(shape: self, paint: ShapePaint(kind: .fill, color: style.resolvedColor, lineWidth: nil))
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat = 1) -> some View {
        ShapePaintView(shape: self, paint: ShapePaint(kind: .stroke, color: style.resolvedColor, lineWidth: max(0, lineWidth)))
    }
}

private struct ShapePaintView<Content: Shape>: View, PrimitiveView {
    let shape: Content
    let paint: ShapePaint

    @MainActor var body: Never { return fatalError("primitive shape paint has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shape.shapeGeometry, paint: paint)) }
    var nodeContent: (any View)? { nil }
}

/// Rectangular path that fills its proposed bounds.
public struct Rectangle: Shape, PrimitiveView {
    public init() {}
    public var shapeGeometry: ShapeGeometry { .rectangle }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}


/// Rounded rectangular path that fills its proposed bounds.
public struct RoundedRectangle: Shape, PrimitiveView {
    public let cornerRadius: CGFloat
    public let style: RoundedCornerStyle

    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {
        self.cornerRadius = max(0, cornerRadius)
        self.style = style
    }

    public var shapeGeometry: ShapeGeometry { .roundedRectangle(cornerRadius: cornerRadius, style: style) }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}


/// Circular path that fits its proposed bounds.
public struct Circle: Shape, PrimitiveView {
    public init() {}
    public var shapeGeometry: ShapeGeometry { .circle }
    @MainActor public var body: Never { return fatalError("primitive shape has no body") }
    var nodeKind: NodeKind { .shape(ResolvedShape(geometry: shapeGeometry, paint: nil)) }
    var nodeContent: (any View)? { nil }
}
