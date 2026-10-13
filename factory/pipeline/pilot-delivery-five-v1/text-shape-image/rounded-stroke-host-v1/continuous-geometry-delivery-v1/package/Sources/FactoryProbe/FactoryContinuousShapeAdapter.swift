import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Shape-owned bridge adapter: generic continuous geometry becomes retained
/// RGBA8 image data through existing ABI 0.6 registration. Caller owns returned
/// image handle until node removal, then calls `bridge.release(handle)`.
struct FactoryContinuousShapeRasterRequest {
    let bounds: Rect
    let cornerRadiusPX: Float
    let fillRGBA: UInt32?
    let strokeRGBA: UInt32?
    let strokeWidthPX: Float
}

func factoryContinuousShapePrimitive(_ bridge: Bridge,
                                     request: FactoryContinuousShapeRasterRequest) throws -> (primitive: Primitive, image: ImageHandle) {
    guard request.bounds.w.isFinite, request.bounds.h.isFinite,
          request.bounds.w > 0, request.bounds.h > 0,
          request.cornerRadiusPX.isFinite, request.cornerRadiusPX >= 0,
          request.strokeWidthPX.isFinite, request.strokeWidthPX >= 0 else {
        throw NSError(domain: "FactoryContinuousShapeRasterInput", code: 1)
    }
    // SwiftUI `.stroke` centers its line on original path, so half line width
    // extends outside requested bounds. Rasterizer's inset path model becomes
    // correct when image canvas is expanded by full stroke width, then image
    // primitive is translated by half width. This keeps corner radius tied to
    // original path instead of silently converting stroke into strokeBorder.
    let halfStroke = request.strokeWidthPX / 2
    let width = max(1, Int((request.bounds.w + request.strokeWidthPX).rounded(.up)))
    let height = max(1, Int((request.bounds.h + request.strokeWidthPX).rounded(.up)))
    let image = try ContinuousRoundedRasterizer.rasterize(
        width: width, height: height,
        cornerRadius: CGFloat(request.cornerRadiusPX),
        fillRGBA: request.fillRGBA,
        strokeRGBA: request.strokeRGBA,
        strokeWidth: CGFloat(request.strokeWidthPX))
    let handle = try bridge.registerImage(width: UInt32(width), height: UInt32(height), rgba: image.rgba)
    let expandedBounds = Rect(x: request.bounds.x - halfStroke,
                              y: request.bounds.y - halfStroke,
                              w: Float(width), h: Float(height))
    return (.image(handle, expandedBounds), handle)
}
