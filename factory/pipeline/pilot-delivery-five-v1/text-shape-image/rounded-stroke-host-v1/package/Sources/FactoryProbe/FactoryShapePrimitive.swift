import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Maps resolved shape paint to ABI 0.6 rect fill/border fields.
/// Continuous rounded geometry stays explicit hold: ABI rect radius is not proof of
/// SwiftUI continuous corner construction or centered-stroke semantics.
func factoryShapePrimitive(_ node: ResolvedNode, bounds: Rect, scale: Float) throws -> Primitive {
    guard let shape = node.shape, let paint = shape.paint else {
        throw NSError(domain: "FactoryShapeMetadataRequired", code: 1)
    }
    let radius: Float
    switch shape.geometry {
    case .rectangle:
        radius = 0
    case .circle:
        radius = min(bounds.w, bounds.h) / 2
    case .roundedRectangle(let cornerRadius, let style):
        guard style == .circular else {
            throw NSError(domain: "FactoryContinuousRoundedStrokeProviderHold", code: 78)
        }
        radius = min(Float(cornerRadius) * scale, min(bounds.w, bounds.h) / 2)
    }
    switch paint.kind {
    case .fill:
        return .rect(bounds, color: try factoryResolvedFill(paint.color, opacity: node.opacity), radius: radius)
    case .stroke:
        guard let logicalWidth = paint.lineWidth, logicalWidth.isFinite, logicalWidth >= 0 else {
            throw NSError(domain: "FactoryShapeStrokeWidthRequired", code: 1)
        }
        return .rect(bounds, color: 0, radius: radius,
                     borderColor: try factoryResolvedFill(paint.color, opacity: node.opacity),
                     borderWidth: Float(logicalWidth) * scale)
    }
}
