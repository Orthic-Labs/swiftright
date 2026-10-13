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
    // SwiftUI draws a frame on whole device pixels (both edges rounded; DevicePixelSnap), so the path
    // rectangle is the snapped one, never the fractional layout rectangle.
    let snapX = DevicePixelSnap.edges(origin: Double(request.bounds.x), length: Double(request.bounds.w))
    let snapY = DevicePixelSnap.edges(origin: Double(request.bounds.y), length: Double(request.bounds.h))
    let boundsX = Float(snapX.origin), boundsY = Float(snapY.origin)
    let boundsW = Float(snapX.length), boundsH = Float(snapY.length)
    guard boundsW > 0, boundsH > 0 else { throw NSError(domain: "FactoryContinuousShapeRasterInput", code: 2) }
    // `.stroke` centers its line on the path, so half the line width extends outside the snapped
    // bounds. Apple anti-aliases at the true fractional position, while GPUI floors an image origin
    // to whole pixels. So the bitmap is placed at the integer origin at or before the stroked outer
    // edge, and the fractional remainder is baked into the raster itself.
    let halfStroke = request.strokeWidthPX / 2
    let outerX = boundsX - halfStroke, outerY = boundsY - halfStroke
    let originX = outerX.rounded(.down), originY = outerY.rounded(.down)
    let fracX = Double(outerX) - Double(originX), fracY = Double(outerY) - Double(originY)
    let width = max(1, Int((fracX + Double(boundsW) + Double(request.strokeWidthPX)).rounded(.up)))
    let height = max(1, Int((fracY + Double(boundsH) + Double(request.strokeWidthPX)).rounded(.up)))
    let image = try ContinuousRoundedRasterizer.rasterize(
        width: width, height: height,
        cornerRadius: CGFloat(request.cornerRadiusPX),
        fillRGBA: request.fillRGBA,
        strokeRGBA: request.strokeRGBA,
        strokeWidth: CGFloat(request.strokeWidthPX),
        shapeWidth: CGFloat(boundsW), shapeHeight: CGFloat(boundsH),
        offsetX: CGFloat(fracX), offsetY: CGFloat(fracY))
    let handle = try bridge.registerImage(width: UInt32(width), height: UInt32(height), rgba: image.rgba)
    // GPUI scales logical bounds by the display scale in f32 and then floors the origin and
    // ceils the size, so an exactly integral device-pixel rect can land a whole pixel off
    // (104 px x 0.4 x 2.5 ceils to 105). Nudge the rect strictly inside its pixel cell so
    // floor(origin) and ceil(size) both reproduce the intended integers.
    let guardBand: Float = 1.0 / 64
    let placement = Rect(x: originX + guardBand, y: originY + guardBand,
                         w: Float(width) - 2 * guardBand, h: Float(height) - 2 * guardBand)
    return (.image(handle, placement), handle)
}
