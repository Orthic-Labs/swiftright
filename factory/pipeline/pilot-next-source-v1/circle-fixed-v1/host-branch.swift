import Foundation
import SwiftRightRuntime

// Paste into reviewed FactoryProbe commit handler; no runtime/ABI edits.
// FactoryFill.swift supplies geometry/color conversion, while existing host
// lifecycle measures physical client metrics & keeps no activation.
func factoryRequireCircleFixedViewport(_ client: FactoryClientSize, scale: Float) throws {
    guard scale.isFinite, scale > 0,
          abs(Float(client.width) / scale - 320) <= 0.001,
          abs(Float(client.height) / scale - 240) <= 0.001 else {
        throw NSError(domain: "FactoryCircleFixedViewportMismatch", code: 1)
    }
}

func factoryCircleFixedPrimitive(_ node: ResolvedNode, bounds: Rect, scale: Float) throws -> Primitive {
    guard node.kind == "Circle", let shape = node.shape,
          shape.geometry == .circle,
          let paint = shape.paint, paint.kind == .fill,
          node.opacity.isFinite, node.opacity >= 0, node.opacity <= 1 else {
        throw NSError(domain: "FactoryCircleFixedMetadataRequired", code: 1)
    }
    guard scale.isFinite, scale > 0 else {
        throw NSError(domain: "FactoryCircleFixedScaleMismatch", code: 1)
    }
    let fill = try factoryFillRect(.circle, x: bounds.x, y: bounds.y,
                                   width: 40 * scale, height: 40 * scale)
    guard abs(fill.width - 40 * scale) <= 0.001,
          abs(fill.height - 40 * scale) <= 0.001,
          abs(fill.radius - 20 * scale) <= 0.001 else {
        throw NSError(domain: "FactoryCircleFixedFrameMismatch", code: 1)
    }
    return .rect(Rect(x: fill.x, y: fill.y, w: fill.width, h: fill.height),
                 color: try factoryResolvedFill(paint.color, opacity: node.opacity),
                 radius: fill.radius)
}

// Host branch contract:
// case "Circle": primitives = [try factoryCircleFixedPrimitive(n, bounds: bounds, scale: measuredScale)]
// Existing FactoryViewport must report actual client metrics; admission then
// requires measured physical pixels whose finite scale resolves to 320x240 DIP, & one owned HWND.
