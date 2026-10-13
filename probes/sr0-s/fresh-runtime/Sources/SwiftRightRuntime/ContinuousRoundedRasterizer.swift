import Foundation

/// Bounded CPU raster output for a continuous rounded shape. Bytes are RGBA8,
/// straight alpha. Coverage is 16x16 supersampled (256 samples) on pixels
/// within 0.75 px of a boundary and exact (0 or 1) elsewhere; this is deterministic
/// geometry transport for `SWR_PRIM_IMAGE`.
public struct ContinuousRGBAImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width; self.height = height; self.rgba = rgba
    }
}

public enum ContinuousRoundedRasterError: Error, Equatable {
    case invalidSize
    case invalidStroke
    case pixelLimitExceeded
    case workLimitExceeded
    case unsupportedGeometry
}

public enum ContinuousRoundedRasterizer {
    private static let maxRGBABytes = 16 * 1024 * 1024
    private static let maxPixels = maxRGBABytes / 4
    /// Upper bound on raster area. Per-pixel cost is bounded by the segments near that pixel (spatial
    /// grid), so cost is linear in area; 2M px covers any full-screen shape at 1080p-class sizes.
    private static let maxWorkPixels = 2_000_000
    private static let cellSize = 16
    /// Flattening tolerance in device pixels. Fills follow the exact curve. Apple's stroker
    /// subdivides each cubic uniformly into n = ceil(sqrt(0.75 * M / tolerance)) segments (Wang's
    /// bound, M = max second difference of the control polygon) with tolerance 0.2 DEVICE pixels:
    /// the rule is in device px, so n grows as sqrt(radius_px). Verified against SwiftUI
    /// ImageRenderer for corner radii 2.5-100 px, stroke 1.25-20 px at scales 1, 2, 2.5, 3 and 4
    /// (every config passes at 0.2; a 0.3 or 0.1 tolerance fails the large and small radii).
    private static let fillTolerance = 0.02
    private static let strokeTolerance = 0.2
    private static let grid = 16
    private static let edgeBand = 0.75

    /// Apple's stroke anti-aliasing is not linear in covered area: measured straight-edge strokes at
    /// 0.25 / 0.5 / 0.75 true coverage render as 0.157 / 0.498 / 0.843, which is smoothstep(c) =
    /// c*c*(3-2c) (0.156 / 0.5 / 0.844). Applying it cuts the stroke edge error against SwiftUI from
    /// about 30/255 to about 15/255 across radii, widths and scales. Fill edges are linear.
    @inline(__always) public static func strokeEdgeCoverage(_ linear: Double) -> Double {
        linear * linear * (3 - 2 * linear)
    }

    public static func rasterize(width: Int, height: Int, cornerRadius: CGFloat,
                                 fillRGBA: UInt32? = nil,
                                 strokeRGBA: UInt32? = nil,
                                 strokeWidth: CGFloat = 0,
                                 shapeWidth: CGFloat? = nil, shapeHeight: CGFloat? = nil,
                                 offsetX: CGFloat = 0, offsetY: CGFloat = 0) throws -> ContinuousRGBAImage {
        guard width > 0, height > 0 else { throw ContinuousRoundedRasterError.invalidSize }
        guard width <= maxPixels / max(1, height) else { throw ContinuousRoundedRasterError.pixelLimitExceeded }
        let stroke = Double(strokeWidth)
        guard stroke.isFinite, stroke >= 0 else { throw ContinuousRoundedRasterError.invalidStroke }
        guard stroke < Double(min(width, height)) else { throw ContinuousRoundedRasterError.invalidStroke }
        let halfStroke = stroke / 2
        // Render centered stroke inside output extent. This supplies required
        // outer padding instead of clipping half stroke at bitmap edges.
        // `offsetX/Y` is the fractional sub-pixel position of the stroked outer
        // edge inside the bitmap (so the bitmap itself can be placed on an
        // integer origin); `shapeWidth/Height` is the path rect size.
        let ox = Double(offsetX), oy = Double(offsetY)
        guard ox.isFinite, oy.isFinite, ox >= 0, oy >= 0, ox < 1, oy < 1 else { throw ContinuousRoundedRasterError.invalidSize }
        let rect = LayoutRect(x: CGFloat(halfStroke + ox), y: CGFloat(halfStroke + oy),
                              width: shapeWidth ?? CGFloat(Double(width) - stroke),
                              height: shapeHeight ?? CGFloat(Double(height) - stroke))
        let path: [ContinuousPathElement]
        do {
            path = try ContinuousRoundedGeometry.path(in: rect, cornerRadius: cornerRadius)
        } catch ContinuousRoundedGeometryError.invalidBounds {
            throw ContinuousRoundedRasterError.invalidSize
        } catch ContinuousRoundedGeometryError.unsupportedRadiusExtent {
            throw ContinuousRoundedRasterError.unsupportedGeometry
        }
        let fillSegments = flatten(path, tolerance: fillTolerance)
        let segments = stroke > 0 && strokeRGBA != nil ? flatten(path, tolerance: strokeTolerance) : fillSegments
        guard width * height <= maxWorkPixels else { throw ContinuousRoundedRasterError.workLimitExceeded }
        let bytes = width * height * 4
        var output = [UInt8](repeating: 0, count: bytes)
        let hasFill = fillRGBA != nil, hasStroke = strokeRGBA != nil && stroke > 0
        let step = 1.0 / Double(grid)
        // Spatial indexes: a pixel only needs segments within the reach that can still matter
        // (stroke: half width + edge band; fill: edge band), plus a pixel diagonal for sample points.
        let strokeIndex = hasStroke ? SegmentIndex(segments, width: width, height: height, cell: cellSize, reach: halfStroke + edgeBand + 1.5) : nil
        let fillIndex = hasFill ? SegmentIndex(fillSegments, width: width, height: height, cell: cellSize, reach: edgeBand + 1.5) : nil
        var centerCrossings: [Double] = [], subCrossings = [[Double]](repeating: [], count: grid)
        for y in 0..<height {
            if hasFill { centerCrossings = crossings(fillSegments, y: Double(y) + 0.5) }
            var subRowsReady = false
            for x in 0..<width {
                let center = (Double(x) + 0.5, Double(y) + 0.5)
                let cell = (y / cellSize) * (strokeIndex?.cellsX ?? fillIndex!.cellsX) + x / cellSize
                let dist = hasStroke ? strokeIndex!.distanceSquared(center, cell: cell).squareRoot() : 0
                let fillDist = hasFill ? fillIndex!.distanceSquared(center, cell: cell).squareRoot() : 0
                let isInside = hasFill && isInsideCrossings(centerCrossings, center.0)
                let fillNear = hasFill && fillDist <= edgeBand
                let strokeNear = hasStroke && abs(dist - halfStroke) <= edgeBand
                var fillCoverage = (hasFill && isInside) ? 1.0 : 0.0
                var strokeCoverage = (hasStroke && dist <= halfStroke) ? 1.0 : 0.0
                if fillNear || strokeNear {
                    if fillNear && !subRowsReady {
                        for j in 0..<grid { subCrossings[j] = crossings(fillSegments, y: Double(y) + (Double(j) + 0.5) * step) }
                        subRowsReady = true
                    }
                    var fillHits = 0, strokeHits = 0
                    for j in 0..<grid {
                        for i in 0..<grid {
                            let px = Double(x) + (Double(i) + 0.5) * step
                            if fillNear && isInsideCrossings(subCrossings[j], px) { fillHits += 1 }
                            if strokeNear {
                                let py = Double(y) + (Double(j) + 0.5) * step
                                if strokeIndex!.distanceSquared((px, py), cell: cell) <= halfStroke * halfStroke { strokeHits += 1 }
                            }
                        }
                    }
                    let n = Double(grid * grid)
                    if fillNear { fillCoverage = Double(fillHits) / n }
                    if strokeNear { strokeCoverage = strokeEdgeCoverage(Double(strokeHits) / n) }
                }
                let fill = fillRGBA.map { unpack($0, coverage: fillCoverage) }
                let strokeColor = hasStroke ? strokeRGBA.map { unpack($0, coverage: strokeCoverage) } : nil
                let composited = over(strokeColor, fill)
                guard let composited, composited.alpha > 0 else { continue }
                let index = (y * width + x) * 4
                output[index] = UInt8(max(0, min(255, Int((composited.red * 255).rounded()))))
                output[index + 1] = UInt8(max(0, min(255, Int((composited.green * 255).rounded()))))
                output[index + 2] = UInt8(max(0, min(255, Int((composited.blue * 255).rounded()))))
                output[index + 3] = UInt8(max(0, min(255, Int((composited.alpha * 255).rounded()))))
            }
        }
        return ContinuousRGBAImage(width: width, height: height, rgba: output)
    }

    private struct Segment { let a: (Double, Double); let b: (Double, Double) }
    private struct SampleColor {
        let red: Double, green: Double, blue: Double, alpha: Double
    }

    private static func unpack(_ color: UInt32, coverage: Double) -> SampleColor {
        SampleColor(red: Double(UInt8(color >> 24)) / 255,
                    green: Double(UInt8((color >> 16) & 0xff)) / 255,
                    blue: Double(UInt8((color >> 8) & 0xff)) / 255,
                    alpha: Double(UInt8(color & 0xff)) / 255 * coverage)
    }

    private static func over(_ source: SampleColor?, _ destination: SampleColor?) -> SampleColor? {
        guard let source else { return destination }
        guard let destination else { return source }
        let outAlpha = source.alpha + destination.alpha * (1 - source.alpha)
        guard outAlpha > 0 else { return nil }
        return SampleColor(
            red: (source.red * source.alpha + destination.red * destination.alpha * (1 - source.alpha)) / outAlpha,
            green: (source.green * source.alpha + destination.green * destination.alpha * (1 - source.alpha)) / outAlpha,
            blue: (source.blue * source.alpha + destination.blue * destination.alpha * (1 - source.alpha)) / outAlpha,
            alpha: outAlpha)
    }

    private static func flatten(_ path: [ContinuousPathElement], tolerance: Double) -> [Segment] {
        var result: [Segment] = []; result.reserveCapacity(64)
        var current = (0.0, 0.0), start = current
        func point(_ p: LayoutPoint) -> (Double, Double) { (Double(p.x), Double(p.y)) }
        func append(_ next: (Double, Double)) { result.append(Segment(a: current, b: next)); current = next }
        for element in path {
            switch element {
            case .move(let to): current = point(to); start = current
            case .line(let to): append(point(to))
            case .cubic(let to, let c1, let c2):
                let p0 = current, p1 = point(c1), p2 = point(c2), p3 = point(to)
                // Wang's bound on uniform-t subdivisions for a cubic.
                let d0 = (p0.0 - 2 * p1.0 + p2.0, p0.1 - 2 * p1.1 + p2.1)
                let d1 = (p1.0 - 2 * p2.0 + p3.0, p1.1 - 2 * p2.1 + p3.1)
                let m = max((d0.0 * d0.0 + d0.1 * d0.1).squareRoot(), (d1.0 * d1.0 + d1.1 * d1.1).squareRoot())
                let n = max(1, min(256, Int((0.75 * m / tolerance).squareRoot().rounded(.up))))
                for step in 1...n {
                    let t = Double(step) / Double(n), u = 1 - t
                    append((u*u*u*p0.0 + 3*u*u*t*p1.0 + 3*u*t*t*p2.0 + t*t*t*p3.0,
                            u*u*u*p0.1 + 3*u*u*t*p1.1 + 3*u*t*t*p2.1 + t*t*t*p3.1))
                }
            case .close: append(start)
            }
        }
        return result
    }

    /// Sorted x positions where the horizontal line at `y` crosses the closed outline (even-odd rule).
    private static func crossings(_ segments: [Segment], y: Double) -> [Double] {
        var xs: [Double] = []
        for segment in segments {
            let (x0, y0) = segment.a, (x1, y1) = segment.b
            if (y0 > y) != (y1 > y) { xs.append((x1 - x0) * (y - y0) / (y1 - y0) + x0) }
        }
        xs.sort()
        return xs
    }

    /// Even-odd containment: odd number of crossings strictly to the right of `x`.
    private static func isInsideCrossings(_ xs: [Double], _ x: Double) -> Bool {
        var lo = 0, hi = xs.count
        while lo < hi { let mid = (lo + hi) / 2; if xs[mid] > x { hi = mid } else { lo = mid + 1 } }
        return (xs.count - lo) % 2 == 1
    }

    /// Uniform grid over the raster: each cell lists the segments that can lie within `reach` of any
    /// point in it, so nearest-segment queries cost the local segment count, not the whole outline.
    private struct SegmentIndex {
        let segments: [Segment]
        let cellsX: Int
        let offsets: [Int32]
        let items: [Int32]

        init(_ segments: [Segment], width: Int, height: Int, cell: Int, reach: Double) {
            self.segments = segments
            let cx = (width + cell - 1) / cell, cy = (height + cell - 1) / cell
            cellsX = cx
            var counts = [Int32](repeating: 0, count: cx * cy + 1)
            func cells(_ s: Segment) -> (Int, Int, Int, Int)? {
                let x0 = min(s.a.0, s.b.0) - reach, x1 = max(s.a.0, s.b.0) + reach
                let y0 = min(s.a.1, s.b.1) - reach, y1 = max(s.a.1, s.b.1) + reach
                let c0 = max(0, Int((x0 / Double(cell)).rounded(.down))), c1 = min(cx - 1, Int((x1 / Double(cell)).rounded(.down)))
                let r0 = max(0, Int((y0 / Double(cell)).rounded(.down))), r1 = min(cy - 1, Int((y1 / Double(cell)).rounded(.down)))
                return c0 <= c1 && r0 <= r1 ? (c0, c1, r0, r1) : nil
            }
            for s in segments { if let (c0, c1, r0, r1) = cells(s) { for r in r0...r1 { for c in c0...c1 { counts[r * cx + c + 1] += 1 } } } }
            for i in 1..<counts.count { counts[i] += counts[i - 1] }
            offsets = counts
            var fill = counts, items = [Int32](repeating: 0, count: Int(counts[counts.count - 1]))
            for (k, s) in segments.enumerated() {
                if let (c0, c1, r0, r1) = cells(s) {
                    for r in r0...r1 { for c in c0...c1 { let slot = r * cx + c; items[Int(fill[slot])] = Int32(k); fill[slot] += 1 } }
                }
            }
            self.items = items
        }

        /// Squared distance to the nearest indexed segment, or +infinity when none is within reach.
        func distanceSquared(_ p: (Double, Double), cell: Int) -> Double {
            var best = Double.infinity
            for n in Int(offsets[cell])..<Int(offsets[cell + 1]) {
                let segment = segments[Int(items[n])]
                let vx = segment.b.0 - segment.a.0, vy = segment.b.1 - segment.a.1
                let wx = p.0 - segment.a.0, wy = p.1 - segment.a.1
                let lengthSquared = vx * vx + vy * vy
                let t = lengthSquared > 0 ? max(0, min(1, (wx * vx + wy * vy) / lengthSquared)) : 0
                let dx = p.0 - (segment.a.0 + t * vx), dy = p.1 - (segment.a.1 + t * vy)
                best = min(best, dx * dx + dy * dy)
            }
            return best
        }
    }
}
