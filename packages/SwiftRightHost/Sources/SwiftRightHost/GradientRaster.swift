import Foundation
import SwiftRightRuntime

/// Rasterises a resolved gradient (issue #60) into a straight-alpha RGBA8 bitmap of a node's snapped pixel frame.
///
/// Interpolation (measured, issue #60 pass 3, macOS 27 capture of linear-gradient-v1): per channel in Oklab (perceptual, the space SwiftUI's Gradient uses on macOS 26+), with straight
/// (non-premultiplied) alpha; the result is converted back to gamma-encoded sRGB, clipped to 0...255, and quantised once, rounding to the nearest level. Gamma-sRGB and linear-light mixes
/// differ from the Mac capture by up to 48 and 54 levels; Oklab brings it to at most 29 (mean ~7 on the gate's band). The remaining residual (the Mac path is slightly darker in the
/// mid-gradient and bends further near saturated orange/blue) is not explained by Oklab, CIELAB, ICtCp, IPT, wide-gamut or power-law variants and is carried by the pair gate.
/// A stop with alpha 0 has no hue of its own, so the other stop's colour is used (`blue -> clear` fades blue's alpha and stays blue).
/// Sampling: the colour of a pixel is the gradient's value at its centre; beyond the first and last stop the colour is clamped (extended), as SwiftUI draws it.
/// Linear: the colour is constant along lines perpendicular to the start-to-end line, in the bitmap's pixel space (unit points are scaled by the frame's width and height
/// first, so a diagonal gradient across a wide frame runs along the pixel diagonal, as Core Graphics draws an axial gradient between two device points).
public enum GradientRaster {
    /// One stop with its colour already resolved to 0xRRGGBBAA.
    public struct Stop: Equatable {
        public var location: Double
        public var rgba: UInt32
        public init(location: Double, rgba: UInt32) { self.location = location; self.rgba = rgba }
    }

    /// The most pixels one gradient bitmap may have (16 MB of RGBA).
    public static let maxPixels = 4 * 1024 * 1024

    /// The colour at `t` (0 at the first stop's location or before, clamped at both ends) as straight-alpha 0...255 components. `stops` must be sorted by location and non-empty.
    public static func color(at t: Double, stops: [Stop]) -> (r: Double, g: Double, b: Double, a: Double) {
        func parts(_ c: UInt32) -> (Double, Double, Double, Double) {
            (Double(c >> 24 & 255), Double(c >> 16 & 255), Double(c >> 8 & 255), Double(c & 255))
        }
        guard let first = stops.first, let last = stops.last else { return (0, 0, 0, 0) }
        if !(t > first.location) { return parts(first.rgba) }
        if t >= last.location { return parts(last.rgba) }
        // the first stop strictly after t; the one before it is at or before t
        var hi = 1
        while hi < stops.count - 1, stops[hi].location <= t { hi += 1 }
        let lo = stops[hi - 1], up = stops[hi]
        let span = up.location - lo.location
        guard span > 0 else { return parts(up.rgba) }
        let f = (t - lo.location) / span
        var a = parts(lo.rgba), b = parts(up.rgba)
        if a.3 == 0 { a = (b.0, b.1, b.2, 0) }
        if b.3 == 0 { b = (a.0, a.1, a.2, 0) }
        let la = oklab(a.0, a.1, a.2), lb = oklab(b.0, b.1, b.2)
        let rgb = fromOklab(la.0 + (lb.0 - la.0) * f, la.1 + (lb.1 - la.1) * f, la.2 + (lb.2 - la.2) * f)
        return (rgb.0, rgb.1, rgb.2, a.3 + (b.3 - a.3) * f)
    }

    // Oklab (Ottosson, 2020): linear sRGB -> LMS -> cube root -> Lab; components in, 0...255 gamma sRGB.
    private static func toLinear(_ v: Double) -> Double {
        let c = min(max(v / 255, 0), 1)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func fromLinear(_ l: Double) -> Double {
        let c = min(max(l, 0), 1)
        return 255 * (c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055)
    }

    static func oklab(_ r8: Double, _ g8: Double, _ b8: Double) -> (Double, Double, Double) {
        let r = toLinear(r8), g = toLinear(g8), b = toLinear(b8)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func fromOklab(_ L: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
        let l = L + 0.3963377774 * a + 0.2158037573 * b
        let m = L - 0.1055613458 * a - 0.0638541728 * b
        let s = L - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l * l * l, m3 = m * m * m, s3 = s * s * s
        return (fromLinear(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
                fromLinear(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
                fromLinear(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3))
    }

    private static func level(_ v: Double) -> UInt8 { UInt8(min(max(v.rounded(), 0), 255)) }

    /// The bitmap of `widthPX` x `heightPX` pixels. `scale` is device pixels per point (it converts a radial gradient's radii). Nil when the frame has no area or is over `maxPixels`.
    public static func render(geometry: ResolvedGradient.Geometry, stops: [Stop], widthPX: Int, heightPX: Int, scale: Double) -> ContinuousRGBAImage? {
        guard widthPX > 0, heightPX > 0, widthPX <= maxPixels / heightPX, scale.isFinite, scale > 0, !stops.isEmpty else { return nil }
        let key = CacheKey(widthPX: widthPX, heightPX: heightPX, scale: scale, geometry: geometry, stops: stops)
        if let hit = cache.get(key) { return hit }
        let w = Double(widthPX), h = Double(heightPX)
        var bytes = [UInt8](repeating: 0, count: widthPX * heightPX * 4)
        // t along the row y: linear is affine in (x, y); radial is a distance.
        bytes.withUnsafeMutableBufferPointer { out in
            // Oklab per pixel is costly: the colour along t is tabulated once (nearest of `lutSize` entries across the stop range, at most ~0.1 level off) and clamped outside it.
            let t0 = stops[0].location, t1 = stops[stops.count - 1].location
            let lutSize = 4096
            var lut: [UInt8] = []
            if t1 > t0 {
                lut.reserveCapacity(lutSize * 4)
                for k in 0..<lutSize {
                    let c = color(at: t0 + (t1 - t0) * Double(k) / Double(lutSize - 1), stops: stops)
                    lut.append(level(c.r)); lut.append(level(c.g)); lut.append(level(c.b)); lut.append(level(c.a))
                }
            }
            let single = color(at: t0, stops: stops)
            func put(_ x: Int, _ y: Int, _ t: Double) {
                let i = (y * widthPX + x) * 4
                if lut.isEmpty {
                    out[i] = level(single.r); out[i + 1] = level(single.g); out[i + 2] = level(single.b); out[i + 3] = level(single.a)
                    return
                }
                let u = (t - t0) / (t1 - t0)
                let k = u.isFinite ? min(max(Int((u * Double(lutSize - 1)).rounded()), 0), lutSize - 1) : 0
                out[i] = lut[k * 4]; out[i + 1] = lut[k * 4 + 1]; out[i + 2] = lut[k * 4 + 2]; out[i + 3] = lut[k * 4 + 3]
            }
            switch geometry {
            case .linear(let start, let end):
                let sx = Double(start.x) * w, sy = Double(start.y) * h
                let dx = Double(end.x) * w - sx, dy = Double(end.y) * h - sy
                let len2 = dx * dx + dy * dy
                for y in 0..<heightPX {
                    for x in 0..<widthPX {
                        let t = len2 > 0 ? ((Double(x) + 0.5 - sx) * dx + (Double(y) + 0.5 - sy) * dy) / len2 : 0
                        put(x, y, t)
                    }
                }
            case .radial(let center, let startRadius, let endRadius):
                let cx = Double(center.x) * w, cy = Double(center.y) * h
                let r0 = max(startRadius, 0) * scale, r1 = max(endRadius, 0) * scale
                for y in 0..<heightPX {
                    for x in 0..<widthPX {
                        let r = (pow(Double(x) + 0.5 - cx, 2) + pow(Double(y) + 0.5 - cy, 2)).squareRoot()
                        let t = r1 > r0 ? (r - r0) / (r1 - r0) : (r < r0 ? 0 : 1)
                        put(x, y, t)
                    }
                }
            }
        }
        let image = ContinuousRGBAImage(width: widthPX, height: heightPX, rgba: bytes)
        cache.set(key, image)
        return image
    }

    // MARK: cache

    /// A gradient re-rendered on every commit (an animation elsewhere in the tree) is served from a few recent bitmaps.
    struct CacheKey: Hashable {
        let widthPX: Int, heightPX: Int, scale: Double
        let kind: Int
        let numbers: [Double]
        let stopLocations: [Double]
        let stopColours: [UInt32]
        init(widthPX: Int, heightPX: Int, scale: Double, geometry: ResolvedGradient.Geometry, stops: [Stop]) {
            self.widthPX = widthPX; self.heightPX = heightPX; self.scale = scale
            switch geometry {
            case .linear(let s, let e): kind = 0; numbers = [Double(s.x), Double(s.y), Double(e.x), Double(e.y)]
            case .radial(let c, let r0, let r1): kind = 1; numbers = [Double(c.x), Double(c.y), r0, r1]
            }
            stopLocations = stops.map(\.location); stopColours = stops.map(\.rgba)
        }
    }

    final class Cache: @unchecked Sendable {
        let capacity = 8
        private let lock = NSLock()
        private var entries: [CacheKey: ContinuousRGBAImage] = [:]
        private var order: [CacheKey] = []
        func get(_ key: CacheKey) -> ContinuousRGBAImage? {
            lock.lock(); defer { lock.unlock() }
            guard let v = entries[key] else { return nil }
            if let i = order.lastIndex(of: key) { order.remove(at: i); order.append(key) }
            return v
        }
        func set(_ key: CacheKey, _ image: ContinuousRGBAImage) {
            lock.lock(); defer { lock.unlock() }
            entries[key] = image
            order.removeAll { $0 == key }
            order.append(key)
            while order.count > capacity { entries[order.removeFirst()] = nil }
        }
    }

    static let cache = Cache()
}
