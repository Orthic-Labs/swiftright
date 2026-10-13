import Foundation

/// Bounded CPU raster output for a continuous rounded shape. Bytes are RGBA8,
/// straight alpha. Coverage uses fixed 4x4 sampling; this is deterministic
/// geometry transport for `SWR_PRIM_IMAGE`, not renderer antialias parity.
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
    private static let subdivisions = 8

    public static func rasterize(width: Int, height: Int, cornerRadius: CGFloat,
                                 fillRGBA: UInt32? = nil,
                                 strokeRGBA: UInt32? = nil,
                                 strokeWidth: CGFloat = 0) throws -> ContinuousRGBAImage {
        guard width > 0, height > 0 else { throw ContinuousRoundedRasterError.invalidSize }
        guard width <= maxPixels / max(1, height) else { throw ContinuousRoundedRasterError.pixelLimitExceeded }
        let stroke = Double(strokeWidth)
        guard stroke.isFinite, stroke >= 0 else { throw ContinuousRoundedRasterError.invalidStroke }
        guard stroke < Double(min(width, height)) else { throw ContinuousRoundedRasterError.invalidStroke }
        let halfStroke = stroke / 2
        // Render centered stroke inside output extent. This supplies required
        // outer padding instead of clipping half stroke at bitmap edges.
        let rect = LayoutRect(x: CGFloat(halfStroke), y: CGFloat(halfStroke),
                              width: CGFloat(Double(width) - stroke),
                              height: CGFloat(Double(height) - stroke))
        let path: [ContinuousPathElement]
        do {
            path = try ContinuousRoundedGeometry.path(in: rect, cornerRadius: cornerRadius)
        } catch ContinuousRoundedGeometryError.invalidBounds {
            throw ContinuousRoundedRasterError.invalidSize
        } catch ContinuousRoundedGeometryError.unsupportedRadiusExtent {
            throw ContinuousRoundedRasterError.unsupportedGeometry
        }
        let segments = flatten(path)
        let sampleCount = width * height * 16
        guard segments.count == 0 || sampleCount <= maxSampleSegmentEvaluations / segments.count else {
            throw ContinuousRoundedRasterError.workLimitExceeded
        }
        let bytes = width * height * 4
        var output = [UInt8](repeating: 0, count: bytes)
        let samples: [(Double, Double)] = [(0.125, 0.125), (0.375, 0.125), (0.625, 0.125), (0.875, 0.125),
                                            (0.125, 0.375), (0.375, 0.375), (0.625, 0.375), (0.875, 0.375),
                                            (0.125, 0.625), (0.375, 0.625), (0.625, 0.625), (0.875, 0.625),
                                            (0.125, 0.875), (0.375, 0.875), (0.625, 0.875), (0.875, 0.875)]
        for y in 0..<height {
            for x in 0..<width {
                var fillHits = 0, strokeHits = 0
                for (sx, sy) in samples {
                    let point = (Double(x) + sx, Double(y) + sy)
                    if fillRGBA != nil && inside(point, segments: segments) { fillHits += 1 }
                    if strokeRGBA != nil && stroke > 0 && distanceSquared(point, segments: segments) <= halfStroke * halfStroke { strokeHits += 1 }
                }
                let fillCoverage = Double(fillHits) / 16
                let strokeCoverage = Double(strokeHits) / 16
                let fill = fillRGBA.map { unpack($0, coverage: fillCoverage) }
                let strokeColor = strokeRGBA.map { unpack($0, coverage: strokeCoverage) }
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

    private static func flatten(_ path: [ContinuousPathElement]) -> [Segment] {
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
                for step in 1...subdivisions {
                    let t = Double(step) / Double(subdivisions), u = 1 - t
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
