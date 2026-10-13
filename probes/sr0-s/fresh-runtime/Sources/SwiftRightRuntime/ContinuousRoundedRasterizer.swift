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
    private static let maxSampleSegmentEvaluations = 100_000_000
    /// Flattening tolerance in device pixels. Fills follow the exact curve; Apple's
    /// stroker flattens each cubic to ~0.2 px (measured against SwiftUI at 2.5x: the
    /// fill matches the exact curve, the stroke matches a 0.2 px Wang flattening).
    private static let fillTolerance = 0.02
    private static let strokeTolerance = 0.2
    private static let grid = 16
    private static let edgeBand = 0.75

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
        guard fillSegments.count == 0 || width * height <= maxSampleSegmentEvaluations / (fillSegments.count + segments.count) else {
            throw ContinuousRoundedRasterError.workLimitExceeded
        }
        let bytes = width * height * 4
        var output = [UInt8](repeating: 0, count: bytes)
        let hasFill = fillRGBA != nil, hasStroke = strokeRGBA != nil && stroke > 0
        let step = 1.0 / Double(grid)
        for y in 0..<height {
            for x in 0..<width {
                let center = (Double(x) + 0.5, Double(y) + 0.5)
                let dist = hasStroke ? distance(center, segments: segments) : 0
                let fillDist = hasFill ? distance(center, segments: fillSegments) : 0
                let isInside = hasFill && inside(center, segments: fillSegments)
                let fillNear = hasFill && fillDist <= edgeBand
                let strokeNear = hasStroke && abs(dist - halfStroke) <= edgeBand
                var fillCoverage = (hasFill && isInside) ? 1.0 : 0.0
                var strokeCoverage = (hasStroke && dist <= halfStroke) ? 1.0 : 0.0
                if fillNear || strokeNear {
                    var fillHits = 0, strokeHits = 0
                    for j in 0..<grid {
                        for i in 0..<grid {
                            let point = (Double(x) + (Double(i) + 0.5) * step, Double(y) + (Double(j) + 0.5) * step)
                            if fillNear && inside(point, segments: fillSegments) { fillHits += 1 }
                            if strokeNear && distanceSquared(point, segments: segments) <= halfStroke * halfStroke { strokeHits += 1 }
                        }
                    }
                    let n = Double(grid * grid)
                    if fillNear { fillCoverage = Double(fillHits) / n }
                    if strokeNear { strokeCoverage = Double(strokeHits) / n }
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

    private static func inside(_ p: (Double, Double), segments: [Segment]) -> Bool {
        var hit = false
        for segment in segments {
            let (x0, y0) = segment.a, (x1, y1) = segment.b
            if (y0 > p.1) != (y1 > p.1) {
                let x = (x1 - x0) * (p.1 - y0) / (y1 - y0) + x0
                if p.0 < x { hit.toggle() }
            }
        }
        return hit
    }

    private static func distance(_ p: (Double, Double), segments: [Segment]) -> Double {
        distanceSquared(p, segments: segments).squareRoot()
    }

    private static func distanceSquared(_ p: (Double, Double), segments: [Segment]) -> Double {
        segments.reduce(Double.greatestFiniteMagnitude) { best, segment in
            let vx = segment.b.0 - segment.a.0, vy = segment.b.1 - segment.a.1
            let wx = p.0 - segment.a.0, wy = p.1 - segment.a.1
            let lengthSquared = vx * vx + vy * vy
            let t = lengthSquared > 0 ? max(0, min(1, (wx * vx + wy * vy) / lengthSquared)) : 0
            let dx = p.0 - (segment.a.0 + t * vx), dy = p.1 - (segment.a.1 + t * vy)
            return min(best, dx * dx + dy * dy)
        }
    }
}
