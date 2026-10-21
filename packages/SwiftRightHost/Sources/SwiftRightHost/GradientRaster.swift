import Foundation
import SwiftRightRuntime

/// Rasterises a resolved gradient (issue #60) into a straight-alpha RGBA8 bitmap of a node's snapped pixel frame.
///
/// Interpolation (decision, unverified against a macOS 27 capture until the linear-gradient-v1 pair runs): per channel, linear, in gamma-encoded sRGB (the device RGB
/// space SwiftUI and Core Graphics default to), with straight (non-premultiplied) alpha; each pixel is quantised once, rounding to the nearest level. A stop with alpha 0
/// has no hue of its own, so the other stop's colour is used (`blue -> clear` fades blue's alpha and stays blue).
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
        return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f, a.3 + (b.3 - a.3) * f)
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
            func put(_ x: Int, _ y: Int, _ t: Double) {
                let c = color(at: t, stops: stops)
                let i = (y * widthPX + x) * 4
                out[i] = level(c.r); out[i + 1] = level(c.g); out[i + 2] = level(c.b); out[i + 3] = level(c.a)
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
