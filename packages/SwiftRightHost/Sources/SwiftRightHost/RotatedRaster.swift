import Foundation
import SwiftRightBridge
import SwiftRightRuntime

/// A bitmap under `.rotationEffect` (#69): the renderer transform is translation only, so the host resamples the bitmap through the rotation into a new upright bitmap that covers the
/// rotated rectangle, and the renderer paints that 1:1. Each destination pixel centre is mapped back through the inverse transform into the source and sampled bilinearly in premultiplied,
/// gamma-encoded values (as Core Animation samples a rotated layer); outside the source is transparent, so the rotated edges come out anti-aliased by the same filter.
enum RotatedRaster {
    /// `rgba` is straight-alpha RGBA8, `width` x `height`, drawn to fill `placement` (window pixels). `transform` maps window pixels to window pixels (`ShapeRotation.combined`).
    /// Returns the rotated bitmap and the integer-aligned rectangle it is drawn into 1:1, or nil when the result covers no pixel.
    static func rotate(rgba: [UInt8], width: Int, height: Int, placement: Rect, transform: CGAffineTransform) -> (image: ContinuousRGBAImage, placement: Rect)? {
        guard width > 0, height > 0, placement.w > 0, placement.h > 0, rgba.count >= width * height * 4 else { return nil }
        let x0 = Double(placement.x), y0 = Double(placement.y), x1 = x0 + Double(placement.w), y1 = y0 + Double(placement.h)
        let corners = [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x0, y: y1), CGPoint(x: x1, y: y1)].map { $0.applying(transform) }
            .map { CGPoint(x: (Double($0.x) * 1e6).rounded() / 1e6, y: (Double($0.y) * 1e6).rounded() / 1e6) }   // cos(pi/2) is not exactly 0
        let left = Int(floor(corners.map(\.x).min()!)), right = Int(ceil(corners.map(\.x).max()!))
        let top = Int(floor(corners.map(\.y).min()!)), bottom = Int(ceil(corners.map(\.y).max()!))
        let ow = right - left, oh = bottom - top
        guard ow > 0, oh > 0, ow <= 8192, oh <= 8192 else { return nil }
        let inverse = transform.inverted()
        // window pixel -> source pixel space (pixel centres at i + 0.5)
        let sx = Double(width) / Double(placement.w), sy = Double(height) / Double(placement.h)

        func texel(_ i: Int, _ j: Int) -> (Double, Double, Double, Double) {
            guard i >= 0, j >= 0, i < width, j < height else { return (0, 0, 0, 0) }
            let k = (j * width + i) * 4
            let a = Double(rgba[k + 3]) / 255
            return (Double(rgba[k]) / 255 * a, Double(rgba[k + 1]) / 255 * a, Double(rgba[k + 2]) / 255 * a, a)
        }

        var out = [UInt8](repeating: 0, count: ow * oh * 4)
        var any = false
        for y in 0..<oh {
            for x in 0..<ow {
                let p = CGPoint(x: Double(left + x) + 0.5, y: Double(top + y) + 0.5).applying(inverse)
                let u = (Double(p.x) - x0) * sx - 0.5, v = (Double(p.y) - y0) * sy - 0.5
                let iu = Int(floor(u)), iv = Int(floor(v))
                guard iu >= -1, iv >= -1, iu < width, iv < height else { continue }
                let fu = u - Double(iu), fv = v - Double(iv)
                let a = texel(iu, iv), b = texel(iu + 1, iv), c = texel(iu, iv + 1), d = texel(iu + 1, iv + 1)
                func mix(_ p: Double, _ q: Double, _ r: Double, _ s: Double) -> Double { (p * (1 - fu) + q * fu) * (1 - fv) + (r * (1 - fu) + s * fu) * fv }
                let alpha = mix(a.3, b.3, c.3, d.3)
                guard alpha > 0.5 / 255 else { continue }
                let k = (y * ow + x) * 4
                out[k] = UInt8(min(255, (mix(a.0, b.0, c.0, d.0) / alpha * 255).rounded()))
                out[k + 1] = UInt8(min(255, (mix(a.1, b.1, c.1, d.1) / alpha * 255).rounded()))
                out[k + 2] = UInt8(min(255, (mix(a.2, b.2, c.2, d.2) / alpha * 255).rounded()))
                out[k + 3] = UInt8(min(255, (alpha * 255).rounded()))
                any = true
            }
        }
        guard any else { return nil }
        return (ContinuousRGBAImage(width: ow, height: oh, rgba: out), Rect(x: Float(left), y: Float(top), w: Float(ow), h: Float(oh)))
    }
}
