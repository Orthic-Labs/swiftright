import SwiftRightRuntime
import SwiftRightBridge
import Foundation

/// The coverage of a `.clipShape` in window pixels (SR2 R6, #41): 255 inside, 0 outside, anti-aliased at the edge. Rendered with the same path rasteriser
/// as the shapes it clips, so a clip and a shape of the same outline agree to the pixel.
public struct ClipMask: Equatable, Sendable {
    public let x0: Int, y0: Int, width: Int, height: Int
    public let alpha: [UInt8]
    /// The same outline as a renderer path (ABI rev 0.12), in window pixels: set by `render` when the renderer can draw it (`PathShapeRaster.rendererPath`). Used to
    /// send a text run or bitmap under this clip as `Primitive.clipPath` instead of a host-computed set of rect bands (the renderer cuts the same row bands).
    public var path: PathSpec?
    /// A hash of the raster (origin, size, alpha): equal masks have equal digests, so the band cache survives a mask being rendered again.
    public let digest: UInt64

    public init(x0: Int, y0: Int, width: Int, height: Int, alpha: [UInt8], path: PathSpec? = nil) {
        self.x0 = x0; self.y0 = y0; self.width = width; self.height = height; self.alpha = alpha; self.path = path
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        mix(UInt64(bitPattern: Int64(x0))); mix(UInt64(bitPattern: Int64(y0))); mix(UInt64(width)); mix(UInt64(height))
        for b in alpha { mix(UInt64(b)) }
        self.digest = h
    }

    /// The mask of `geometry` laid out in `bounds` (window pixels) at `scale`; an empty mask (clips everything) when the shape has no area.
    public static func render(geometry: ShapeGeometry, fillStyle: FillStyle, bounds: Rect, scale: Float) throws -> ClipMask {
        let request = PathShapeRequest(bounds: bounds, scale: scale, geometry: geometry, fillRGBA: 0xffffffff, strokeRGBA: nil, fillStyle: fillStyle)
        guard let result = try PathShapeRaster.render(request) else { return ClipMask(x0: 0, y0: 0, width: 0, height: 0, alpha: []) }
        let spec = try PathShapeRaster.rendererPath(request)?.spec
        let w = result.image.width, h = result.image.height
        var a = [UInt8](repeating: 0, count: w * h)
        result.image.rgba.withUnsafeBufferPointer { p in for i in 0..<(w * h) { a[i] = p[i * 4 + 3] } }
        return ClipMask(x0: Int((result.placement.x - imageGuardBand).rounded()), y0: Int((result.placement.y - imageGuardBand).rounded()), width: w, height: h, alpha: a, path: spec)
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

    /// How a renderer-drawn primitive (a text run, a bitmap) over `region` is clipped by `masks` (#43): the renderer clips by rectangles only, so the region is cut
    /// into bands of rows whose inside spans are the same, each span a rect clip. A pixel is inside when every mask covers it at least half; the curved edge is then a
    /// one-pixel staircase where SwiftUI anti-aliases it.
    public enum RectCover: Equatable { case all, none, rects([Rect]) }

    /// Glyph ink reaches past a text node's frame (italic overhang, descenders, swash): the host knows no ink box (the measurer exposes advance and line metrics only), so the
    /// region a text run is clipped over is its frame grown by this many em on every side (#53). The mask, not the frame, then cuts the overhang.
    public static let inkExpansionEm: Float = 0.25

    /// `bounds` grown by the ink allowance of a font `fontPx` pixels tall.
    static func inkRegion(_ bounds: Rect, fontPx: Float) -> Rect {
        let e = inkExpansionEm * fontPx
        return Rect(x: bounds.x - e, y: bounds.y - e, w: bounds.w + 2 * e, h: bounds.h + 2 * e)
    }

    /// Bands cached by (mask digests, device region, bands wanted), least recently used out at `capacity` entries. A mask's digest is its content, so a mask re-rendered
    /// on the next commit (same shape, same place) hits.
    final class BandCache: @unchecked Sendable {
        struct Key: Hashable { let digests: [UInt64]; let xa: Int, xb: Int, ya: Int, yb: Int; let bands: Bool }
        let capacity: Int
        private let lock = NSLock()
        private var entries: [Key: RectCover] = [:]
        private var order: [Key] = []
        private(set) var hits = 0, misses = 0
        init(capacity: Int = 64) { self.capacity = capacity }
        func get(_ key: Key) -> RectCover? {
            lock.lock(); defer { lock.unlock() }
            guard let v = entries[key] else { misses += 1; return nil }
            hits += 1
            if let i = order.lastIndex(of: key) { order.remove(at: i); order.append(key) }
            return v
        }
        func put(_ key: Key, _ value: RectCover) {
            lock.lock(); defer { lock.unlock() }
            if entries.updateValue(value, forKey: key) != nil, let i = order.lastIndex(of: key) { order.remove(at: i) }
            order.append(key)
            while order.count > capacity { entries.removeValue(forKey: order.removeFirst()) }
        }
        var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
        func reset() { lock.lock(); entries = [:]; order = []; hits = 0; misses = 0; lock.unlock() }
    }
    static let bandCache = BandCache()

    /// `needBands` false (a renderer that cuts the bands itself from the mask's path) classifies only: `.all`, `.none`, or `.rects([])` for a partial cover.
    static func rectCover(_ masks: [ClipMask], region: Rect, needBands: Bool = true) -> RectCover {
        let xa = Int(region.x.rounded(.down)), xb = Int((region.x + region.w).rounded(.up))
        let ya = Int(region.y.rounded(.down)), yb = Int((region.y + region.h).rounded(.up))
        guard xb > xa, yb > ya else { return .all }
        // Early exits: no mask at all is everything; a region apart from any mask's pixels (its coverage is 0 off its raster) is nothing; a region every pixel of which is fully covered is
        // everything (stops at the first pixel that is not).
        if masks.isEmpty { return .all }
        for m in masks where m.width == 0 || m.height == 0 || xb <= m.x0 || xa >= m.x0 + m.width || yb <= m.y0 || ya >= m.y0 + m.height { return .none }
        if masks.allSatisfy({ $0.covers(region) }) { return .all }
        let key = BandCache.Key(digests: masks.map(\.digest), xa: xa, xb: xb, ya: ya, yb: yb, bands: needBands)
        if let hit = bandCache.get(key) { return hit }
        let result = computeCover(masks, xa: xa, xb: xb, ya: ya, yb: yb, needBands: needBands)
        bandCache.put(key, result)
        return result
    }

    /// The inside spans of row `y` over xa..<xb: pixels every mask covers at least half. Rows outside a mask's raster are empty without a scan.
    private static func spans(_ masks: [ClipMask], y: Int, xa: Int, xb: Int) -> [Range<Int>] {
        var lo = xa, hi = xb
        for m in masks {
            guard y >= m.y0, y < m.y0 + m.height else { return [] }
            lo = max(lo, m.x0); hi = min(hi, m.x0 + m.width)
        }
        guard hi > lo else { return [] }
        var out: [Range<Int>] = []
        var start: Int?
        let first = masks[0]
        let multi = masks.count > 1
        first.alpha.withUnsafeBufferPointer { p in
            let row = (y - first.y0) * first.width - first.x0
            for x in lo..<hi {
                var inside = p[row + x] >= 128
                if inside, multi { for m in masks.dropFirst() where m.coverage(x, y) < 128 { inside = false; break } }
                if inside, start == nil { start = x }
                if !inside, let s = start { out.append(s..<x); start = nil }
            }
        }
        if let s = start { out.append(s..<hi) }
        return out
    }

    private static func computeCover(_ masks: [ClipMask], xa: Int, xb: Int, ya: Int, yb: Int, needBands: Bool) -> RectCover {
        var rects: [Rect] = []
        var full = true, empty = true
        var bandStart = ya
        var bandSpans = spans(masks, y: ya, xa: xa, xb: xb)
        func flush(_ end: Int) {
            guard needBands else { return }
            for s in bandSpans { rects.append(Rect(x: Float(s.lowerBound), y: Float(bandStart), w: Float(s.count), h: Float(end - bandStart))) }
        }
        for y in ya..<yb {
            let s = y == ya ? bandSpans : spans(masks, y: y, xa: xa, xb: xb)
            if !(s.count == 1 && s[0] == xa..<xb) { full = false }
            if !s.isEmpty { empty = false }
            if !full, !empty, !needBands { break }
            // Adjacent rows with identical spans are one band.
            if y > ya && s != bandSpans { flush(y); bandStart = y; bandSpans = s }
        }
        flush(yb)
        if full { return .all }
        if empty { return .none }
        return .rects(rects)
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
