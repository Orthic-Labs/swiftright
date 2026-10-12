import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Maps resolved shape paint to ABI 0.6 rect fill/border fields for observation.
/// Continuous geometry is logged as an ABI rect approximation; no parity claim is made.
func factoryShapePrimitive(_ node: ResolvedNode, bounds: Rect, scale: Float) throws -> Primitive {
    guard let shape = node.shape, let paint = shape.paint else {
        throw NSError(domain: "FactoryShapeMetadataRequired", code: 1)
    }
    let radius: Float
    var requestedStyle = "none"
    switch shape.geometry {
    case .rectangle:
        radius = 0
    case .circle:
        radius = min(bounds.w, bounds.h) / 2
    case .roundedRectangle(let cornerRadius, let style):
        switch style {
        case .circular: requestedStyle = "circular"
        case .continuous: requestedStyle = "continuous"
        }
        radius = min(Float(cornerRadius) * scale, min(bounds.w, bounds.h) / 2)
        print("FACTORY_SHAPE_APPROXIMATION requestedStyle=\(requestedStyle) abiGeometry=rect-radius-border radiusPX=\(radius) scale=\(scale)")
    }
    switch paint.kind {
    case .fill:
        return .rect(bounds, color: try factoryResolvedFill(paint.color, opacity: node.opacity), radius: radius)
    case .stroke:
        guard let logicalWidth = paint.lineWidth, logicalWidth.isFinite, logicalWidth >= 0 else {
            throw NSError(domain: "FactoryShapeStrokeWidthRequired", code: 1)
        }
        print("FACTORY_STROKE_APPROXIMATION requestedStyle=\(requestedStyle) abiGeometry=rect-radius-border lineWidthPX=\(Float(logicalWidth) * scale)")
        return .rect(bounds, color: 0, radius: radius,
                     borderColor: try factoryResolvedFill(paint.color, opacity: node.opacity),
                     borderWidth: Float(logicalWidth) * scale)
    }
}
