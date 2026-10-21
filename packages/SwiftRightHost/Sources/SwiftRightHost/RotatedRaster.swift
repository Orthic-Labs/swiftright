import Foundation
import SwiftRightBridge
import SwiftRightRuntime

/// A bitmap under `.rotationEffect` (#69): the renderer transform is translation only, so the host resamples the bitmap through the rotation into a new upright bitmap that covers the
/// rotated rectangle, and the renderer paints that 1:1. Fitted to the Mac (CI 39617668587, rotation-image-v1 at 30 degrees): the colour is a bilinear sample (premultiplied, clamped to
/// the edge texels) at the destination pixel centre, mapped back through the inverse transform, which matches the interior to 1 level; the alpha is that sample's alpha times the
/// pixel's AREA coverage by the source rectangle inset by `edgeInset` texels (8 x 8 supersampled on edge pixels only), which brings the rotated edges from 55 levels to 10.
enum RotatedRaster {
    /// How far inside the source rectangle the coverage edge lies, in source texels (fitted: 0.2 against 0.17 and 0.23 on CI 39617668587).
    static let edgeInset = 0.2

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
            let i = min(max(i, 0), width - 1), j = min(max(j, 0), height - 1)
            let k = (j * width + i) * 4
            let a = Double(rgba[k + 3]) / 255
            return (Double(rgba[k]) / 255 * a, Double(rgba[k + 1]) / 255 * a, Double(rgba[k + 2]) / 255 * a, a)
        }
        // destination window pixel -> source texel space
        func source(_ px: Double, _ py: Double) -> (Double, Double) {
            let p = CGPoint(x: px, y: py).applying(inverse)
            return ((Double(p.x) - x0) * sx, (Double(p.y) - y0) * sy)
        }
        // a quarter turn maps pixels onto pixels (no edge to anti-alias, so no inset); the inset is fitted on a 30 degree turn
        let axisAligned = (abs(Double(transform.b)) < 1e-9 && abs(Double(transform.c)) < 1e-9) || (abs(Double(transform.a)) < 1e-9 && abs(Double(transform.d)) < 1e-9)
        let inset = axisAligned ? 0 : edgeInset
        let lo = inset, hiU = Double(width) - inset, hiV = Double(height) - inset
        func inside(_ uv: (Double, Double)) -> Bool { uv.0 >= lo && uv.0 < hiU && uv.1 >= lo && uv.1 < hiV }
        func coverage(_ x: Double, _ y: Double) -> Double {
            let corners = [source(x, y), source(x + 1, y), source(x, y + 1), source(x + 1, y + 1)]
            let n = corners.filter(inside).count
            if n == 4 { return 1 }
            if n == 0 {
                // a pixel can still be cut by a corner of the rectangle with none of its own corners inside
                let us = corners.map(\.0), vs = corners.map(\.1)
                if us.max()! < lo || us.min()! >= hiU || vs.max()! < lo || vs.min()! >= hiV { return 0 }
            }
            var hit = 0
            for b in 0..<8 { for a in 0..<8 where inside(source(x + (Double(a) + 0.5) / 8, y + (Double(b) + 0.5) / 8)) { hit += 1 } }
            return Double(hit) / 64
        }

        var out = [UInt8](repeating: 0, count: ow * oh * 4)
        var any = false
        for y in 0..<oh {
            for x in 0..<ow {
                let cover = coverage(Double(left + x), Double(top + y))
                guard cover > 0 else { continue }
                let (su, sv) = source(Double(left + x) + 0.5, Double(top + y) + 0.5)
                let u = su - 0.5, v = sv - 0.5
                let iu = Int(floor(u)), iv = Int(floor(v))
                let fu = u - Double(iu), fv = v - Double(iv)
                let a = texel(iu, iv), b = texel(iu + 1, iv), c = texel(iu, iv + 1), d = texel(iu + 1, iv + 1)
                func mix(_ p: Double, _ q: Double, _ r: Double, _ s: Double) -> Double { (p * (1 - fu) + q * fu) * (1 - fv) + (r * (1 - fu) + s * fu) * fv }
                let alpha = mix(a.3, b.3, c.3, d.3)
                guard alpha > 0.5 / 255 else { continue }
                let k = (y * ow + x) * 4
                out[k] = UInt8(min(255, (mix(a.0, b.0, c.0, d.0) / alpha * 255).rounded()))
                out[k + 1] = UInt8(min(255, (mix(a.1, b.1, c.1, d.1) / alpha * 255).rounded()))
                out[k + 2] = UInt8(min(255, (mix(a.2, b.2, c.2, d.2) / alpha * 255).rounded()))
                let a8 = UInt8(min(255, (alpha * cover * 255).rounded()))
                guard a8 > 0 else { continue }
                out[k + 3] = a8
                any = true
            }
        }
        guard any else { return nil }
        return (ContinuousRGBAImage(width: ow, height: oh, rgba: out), Rect(x: Float(left), y: Float(top), w: Float(ow), h: Float(oh)))
    }
}
