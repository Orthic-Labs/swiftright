import SwiftRightRuntime
import SwiftRightBridge

/// The coverage of a `.clipShape` in window pixels (SR2 R6, #41): 255 inside, 0 outside, anti-aliased at the edge. Rendered with the same path rasteriser
/// as the shapes it clips, so a clip and a shape of the same outline agree to the pixel.
public struct ClipMask: Equatable, Sendable {
    public let x0: Int, y0: Int, width: Int, height: Int
    public let alpha: [UInt8]

    /// The mask of `geometry` laid out in `bounds` (window pixels) at `scale`; an empty mask (clips everything) when the shape has no area.
    public static func render(geometry: ShapeGeometry, fillStyle: FillStyle, bounds: Rect, scale: Float) throws -> ClipMask {
        let request = PathShapeRequest(bounds: bounds, scale: scale, geometry: geometry, fillRGBA: 0xffffffff, strokeRGBA: nil, fillStyle: fillStyle)
        guard let result = try PathShapeRaster.render(request) else { return ClipMask(x0: 0, y0: 0, width: 0, height: 0, alpha: []) }
        let w = result.image.width, h = result.image.height
        var a = [UInt8](repeating: 0, count: w * h)
        result.image.rgba.withUnsafeBufferPointer { p in for i in 0..<(w * h) { a[i] = p[i * 4 + 3] } }
        return ClipMask(x0: Int((result.placement.x - imageGuardBand).rounded()), y0: Int((result.placement.y - imageGuardBand).rounded()), width: w, height: h, alpha: a)
    }

    @inline(__always) func coverage(_ x: Int, _ y: Int) -> UInt8 {
        let lx = x - x0, ly = y - y0
        guard lx >= 0, ly >= 0, lx < width, ly < height else { return 0 }
        return alpha[ly * width + lx]
    }

    /// True when every pixel `rect` touches is fully inside the clip.
    func covers(_ rect: Rect) -> Bool {
        let xa = Int(rect.x.rounded(.down)), xb = Int((rect.x + rect.w).rounded(.up))
        let ya = Int(rect.y.rounded(.down)), yb = Int((rect.y + rect.h).rounded(.up))
        guard xb > xa, yb > ya else { return true }
        for y in ya..<yb { for x in xa..<xb where coverage(x, y) != 255 { return false } }
        return true
    }

    /// `image` (straight alpha) placed with its top-left pixel at (`originX`, `originY`), its alpha multiplied by every mask's coverage.
    static func apply(_ masks: [ClipMask], to image: ContinuousRGBAImage, originX: Int, originY: Int) -> ContinuousRGBAImage {
        var rgba = image.rgba
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4 + 3
                guard rgba[i] != 0 else { continue }
                var a = UInt32(rgba[i])
                for m in masks { a = (a * UInt32(m.coverage(originX + x, originY + y)) + 127) / 255 }
                rgba[i] = UInt8(a)
            }
        }
        return ContinuousRGBAImage(width: image.width, height: image.height, rgba: rgba)
    }
}
