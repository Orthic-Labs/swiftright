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
    // SwiftUI `.stroke` centers its line on the original path, so half the line
    // width extends outside the requested bounds. Apple anti-aliases at the true
    // fractional position, while GPUI floors an image origin to whole pixels. So
    // the bitmap is placed at the integer origin at or before the stroked outer
    // edge, and the fractional remainder is baked into the raster itself.
    let halfStroke = request.strokeWidthPX / 2
    let outerX = request.bounds.x - halfStroke, outerY = request.bounds.y - halfStroke
    let originX = outerX.rounded(.down), originY = outerY.rounded(.down)
    let fracX = Double(outerX) - Double(originX), fracY = Double(outerY) - Double(originY)
    let width = max(1, Int((fracX + Double(request.bounds.w) + Double(request.strokeWidthPX)).rounded(.up)))
    let height = max(1, Int((fracY + Double(request.bounds.h) + Double(request.strokeWidthPX)).rounded(.up)))
    let image = try ContinuousRoundedRasterizer.rasterize(
        width: width, height: height,
        cornerRadius: CGFloat(request.cornerRadiusPX),
        fillRGBA: request.fillRGBA,
        strokeRGBA: request.strokeRGBA,
        strokeWidth: CGFloat(request.strokeWidthPX),
        shapeWidth: CGFloat(request.bounds.w), shapeHeight: CGFloat(request.bounds.h),
        offsetX: CGFloat(fracX), offsetY: CGFloat(fracY))
    let handle = try bridge.registerImage(width: UInt32(width), height: UInt32(height), rgba: image.rgba)
    let placement = Rect(x: originX, y: originY, w: Float(width), h: Float(height))
    return (.image(handle, placement), handle)
}
