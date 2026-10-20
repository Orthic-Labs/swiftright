import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A rasterised path: where its bitmap goes (integer device pixels, the coordinate space `transform` maps into) and the
/// bitmap. Bytes are RGBA8 STRAIGHT alpha, the same convention as `ContinuousRoundedRasterizer` (the host registers both
/// through the same `SWR_PRIM_IMAGE` route); not premultiplied.
public struct PathRasterImage: Equatable, Sendable {
    public let image: ContinuousRGBAImage
    public let originX: Int
    public let originY: Int
}

public enum PathRasterError: Error, Equatable {
    case invalidInput
    case pixelLimitExceeded
    case workLimitExceeded
}

/// CPU rasteriser for `Path` fills and strokes: plain Swift, no platform API.
///
/// Method (generalises `ContinuousRoundedRasterizer`):
/// - Curves are flattened in device space. Strokes use Apple's observed rule (uniform subdivision, n = ceil(sqrt(0.75 M / 0.2)),
///   Wang's bound, 0.2 device px); fills use 0.02 px (fills follow the exact curve).
/// - Fill: winding crossings (non-zero or even-odd) along scanlines; pixels farther than 0.8 px from any edge are exact (0 or 1),
///   edge pixels are 16x16 supersampled (256 samples).
/// - Stroke: the stroke is built as an exact UNION OF CONVEX PIECES: one rectangle per segment, a disc for every round join
///   and round cap (and for the interior vertices of flattened curves, whose true join is smooth), a wedge polygon for a miter
///   or bevel join, and a rectangle for a square cap. Coverage is the union, so overlaps never double-count and round caps and joins
///   are exact circles (the distance-to-polyline method gives only round shapes; pieces give all cap/join styles). A pixel wholly
///   inside one piece is 1, a pixel clear of every piece is 0, others are 16x16 supersampled and then mapped by the smoothstep
///   fitted for Apple's stroke edge (`ContinuousRoundedRasterizer.strokeEdgeCoverage`).
/// - Dashes are expanded on the flattened polyline by arc length (pattern restarts on every subpath, `dashPhase` offsets into
///   the pattern, an odd-length pattern repeats so on and off swap), each dash being an open stroke with its own caps.
///
/// Units: `path` is in points; the device point of `p` is `transform(p * scale)`, so `scale` is points-to-pixels and `transform`
/// works in pixels (use it for the placement translation or a folded-in rotation). Line width, dash and phase are points and
/// scale by `scale * sqrt(|det transform|)`; a non-uniform `transform` therefore widens the stroke by its geometric-mean scale only.
public enum PathRasterizer {
    /// The most pixels one `rasterize` call will work (same limit as the continuous rasteriser).
    public static let workPixelLimit = 2_000_000
    private static let grid = 16
    private static let cellSize = 16
    private static let edgeBand = 0.8
    private static let strokeTolerance = 0.2
    private static let fillTolerance = 0.02
    private static let maxDashPieces = 100_000

    public static func rasterize(path: Path, transform: CGAffineTransform = .identity, scale: CGFloat = 1,
                                 fillRGBA: UInt32? = nil, fillStyle: FillStyle = FillStyle(),
                                 strokeRGBA: UInt32? = nil, strokeStyle: StrokeStyle = StrokeStyle()) throws -> PathRasterImage? {
        let s = Double(scale)
        guard s.isFinite, s > 0 else { throw PathRasterError.invalidInput }
        let matrix = Matrix(transform: transform, scale: s)
        guard matrix.isFinite else { throw PathRasterError.invalidInput }
        let lineWidth = Double(strokeStyle.lineWidth)
        guard lineWidth.isFinite, lineWidth >= 0 else { throw PathRasterError.invalidInput }
        let hasFill = fillRGBA != nil
        let hasStroke = strokeRGBA != nil && lineWidth > 0
        guard hasFill || hasStroke else { return nil }
        let subpaths = PathSegments.subpaths(of: path)
        guard !subpaths.isEmpty else { return nil }

        let lengthScale = abs(matrix.determinant).squareRoot()
        var fillPolys: [Poly] = []
        var pieces: [Piece] = []
        if hasFill { fillPolys = subpaths.map { flatten($0, matrix, tolerance: fillTolerance) } }
        if hasStroke {
            let polys = subpaths.map { flatten($0, matrix, tolerance: strokeTolerance) }
            // Dashes are laid out by TRUE arc length (CoreGraphics measures the curve, not its flattening): each subpath's
            // pattern is rescaled by flattened length / true length, so dash ends land where they would on the exact curve.
            let trueLengths = subpaths.map { $0.segments.reduce(0.0) { $0 + $1.length() } * lengthScale }
            pieces = try strokePieces(polys, style: strokeStyle, lengthScale: lengthScale, trueLengths: trueLengths)
        }

        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for poly in fillPolys { for p in poly.points { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) } }
        for piece in pieces { minX = min(minX, piece.minX); maxX = max(maxX, piece.maxX); minY = min(minY, piece.minY); maxY = max(maxY, piece.maxY) }
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
        guard abs(minX) < 1e9, abs(maxX) < 1e9, abs(minY) < 1e9, abs(maxY) < 1e9 else { throw PathRasterError.invalidInput }
        let ox = Int(minX.rounded(.down)), oy = Int(minY.rounded(.down))
        let width = max(1, Int(maxX.rounded(.up)) - ox), height = max(1, Int(maxY.rounded(.up)) - oy)
        guard width <= 16 * 1024 * 1024 / 4 / max(1, height) else { throw PathRasterError.pixelLimitExceeded }
        guard width * height <= workPixelLimit else { throw PathRasterError.workLimitExceeded }

        // Move everything into the bitmap's own coordinates.
        let dx = Double(ox), dy = Double(oy)
        for i in fillPolys.indices { for j in fillPolys[i].points.indices { fillPolys[i].points[j].x -= dx; fillPolys[i].points[j].y -= dy } }
        for i in pieces.indices { pieces[i].translate(-dx, -dy) }

        var fillCoverage = [Float](repeating: 0, count: hasFill ? width * height : 0)
        if hasFill { fillCoverage = fillCoverageMap(fillPolys, width: width, height: height, evenOdd: fillStyle.isEOFilled, antialiased: fillStyle.isAntialiased) }
        var strokeCoverage = [Float](repeating: 0, count: hasStroke ? width * height : 0)
        if hasStroke { strokeCoverage = strokeCoverageMap(pieces, width: width, height: height) }

        var output = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let f = hasFill ? unpack(fillRGBA!, coverage: Double(fillCoverage[i])) : nil
            let k = hasStroke ? unpack(strokeRGBA!, coverage: Double(strokeCoverage[i])) : nil
            guard let c = over(k, f), c.alpha > 0 else { continue }
            output[i * 4] = byte(c.red); output[i * 4 + 1] = byte(c.green); output[i * 4 + 2] = byte(c.blue); output[i * 4 + 3] = byte(c.alpha)
        }
        return PathRasterImage(image: ContinuousRGBAImage(width: width, height: height, rgba: output), originX: ox, originY: oy)
    }

    // MARK: Geometry types

    struct Matrix {
        var a, b, c, d, tx, ty: Double
        init(transform t: CGAffineTransform, scale s: Double) {
            // device = T(p * s): the scale folds into the linear part, the translation is not scaled.
            a = Double(t.a) * s; b = Double(t.b) * s; c = Double(t.c) * s; d = Double(t.d) * s
            tx = Double(t.tx); ty = Double(t.ty)
        }
        var isFinite: Bool { a.isFinite && b.isFinite && c.isFinite && d.isFinite && tx.isFinite && ty.isFinite }
        var determinant: Double { a * d - b * c }
        func map(_ p: PathPoint) -> PathPoint { PathPoint(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty) }
    }

    struct Poly {
        var points: [PathPoint]
        var smooth: [Bool]
        var closed: Bool
        /// Direction used for caps of a zero-length piece (a dash of length 0).
        var hint: PathPoint?
        /// Exact unit tangent of the source curve at each point (nil when unknown). Open ends use it for butt/square caps:
        /// CoreGraphics cuts a stroke end square to the curve tangent, not to the last flattening chord.
        var tangents: [PathPoint]? = nil
        /// Polyline length, including the closing segment of a closed polyline.
        var length: Double {
            guard points.count > 1 else { return 0 }
            var total = 0.0
            for i in 1..<points.count { let a = points[i - 1], b = points[i]; total += ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() }
            if closed, let a = points.last, let b = points.first { total += ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() }
            return total
        }
    }

    /// Flattens one subpath in device space. Interior points of a curve are flagged smooth.
    static func flatten(_ subpath: PathSubpath, _ m: Matrix, tolerance: Double) -> Poly {
        var points: [PathPoint] = [], smooth: [Bool] = [], tangents: [PathPoint] = []
        points.reserveCapacity(subpath.segments.count * 4)
        func cubicOf(_ segment: PathSegment) -> (PathPoint, PathPoint, PathPoint, PathPoint) {
            switch segment {
            case .line(let a, let b): return (m.map(a), m.map(a + (b - a) * (1.0 / 3.0)), m.map(a + (b - a) * (2.0 / 3.0)), m.map(b))
            case .quad(let a, let c, let b): return (m.map(a), m.map(a + (c - a) * (2.0 / 3.0)), m.map(b + (c - b) * (2.0 / 3.0)), m.map(b))
            case .cubic(let a, let c1, let c2, let b): return (m.map(a), m.map(c1), m.map(c2), m.map(b))
            }
        }
        if let first = subpath.segments.first {
            let c = cubicOf(first)
            points.append(c.0); smooth.append(false); tangents.append(cubicTangent(c.0, c.1, c.2, c.3, 0))
        }
        for segment in subpath.segments {
            let c = cubicOf(segment)
            if case .line = segment {
                points.append(c.3); smooth.append(false); tangents.append(cubicTangent(c.0, c.1, c.2, c.3, 1))
            } else {
                flattenCubic(c.0, c.1, c.2, c.3, tolerance, &points, &smooth, &tangents)
            }
        }
        let closed = subpath.closed
        if closed, points.count > 1, let first = points.first, let last = points.last,
           (first.x - last.x) * (first.x - last.x) + (first.y - last.y) * (first.y - last.y) < 1e-18 {
            points.removeLast(); smooth.removeLast(); tangents.removeLast()
        }
        return Poly(points: points, smooth: smooth, closed: closed, hint: nil, tangents: tangents)
    }

    /// Uniform-t subdivision with Wang's bound for the count (Apple's stroker rule, device px tolerance).
    private static func flattenCubic(_ p0: PathPoint, _ p1: PathPoint, _ p2: PathPoint, _ p3: PathPoint, _ tolerance: Double,
                                     _ points: inout [PathPoint], _ smooth: inout [Bool], _ tangents: inout [PathPoint]) {
        let d0x = p0.x - 2 * p1.x + p2.x, d0y = p0.y - 2 * p1.y + p2.y
        let d1x = p1.x - 2 * p2.x + p3.x, d1y = p1.y - 2 * p2.y + p3.y
        let m = max((d0x * d0x + d0y * d0y).squareRoot(), (d1x * d1x + d1y * d1y).squareRoot())
        let n = max(1, min(256, Int((0.75 * m / tolerance).squareRoot().rounded(.up))))
        for step in 1...n {
            let t = Double(step) / Double(n), u = 1 - t
            points.append(PathPoint(u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                                    u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y))
            smooth.append(step < n)
            tangents.append(cubicTangent(p0, p1, p2, p3, t))
        }
    }

    /// Unit tangent of a cubic at t (falls back to the chord direction where the derivative vanishes).
    static func cubicTangent(_ p0: PathPoint, _ p1: PathPoint, _ p2: PathPoint, _ p3: PathPoint, _ t: Double) -> PathPoint {
        let u = 1 - t
        var dx = 3 * (u * u * (p1.x - p0.x) + 2 * u * t * (p2.x - p1.x) + t * t * (p3.x - p2.x))
        var dy = 3 * (u * u * (p1.y - p0.y) + 2 * u * t * (p2.y - p1.y) + t * t * (p3.y - p2.y))
        var l = (dx * dx + dy * dy).squareRoot()
        if l < 1e-12 { dx = p3.x - p0.x; dy = p3.y - p0.y; l = (dx * dx + dy * dy).squareRoot() }
        return l < 1e-12 ? PathPoint(1, 0) : PathPoint(dx / l, dy / l)
    }

    // MARK: Dashes

    /// Splits a polyline into dashes by arc length. `pattern` is on/off lengths in the polyline's units (negative or all-zero
    /// patterns mean no dashing); `phase` starts that far into the pattern. A closed polyline walks its closing segment too.
    /// Each dash is an open polyline; a zero-length dash is a single point with `hint` set to the local direction.
    static func dash(_ poly: Poly, pattern: [Double], phase: Double) throws -> [Poly] {
        guard poly.points.count >= 2, pattern.allSatisfy({ $0 >= 0 && $0.isFinite }), pattern.reduce(0, +) > 0 else { return [poly] }
        var pts = poly.points, flags = poly.smooth
        var tans = poly.tangents ?? []
        let hasTangents = tans.count == pts.count
        if poly.closed, let first = pts.first { pts.append(first); flags.append(false); if hasTangents { tans.append(tans[0]) } }
        func tangentAt(_ i: Int, _ s: Double) -> PathPoint? {
            guard hasTangents else { return nil }
            let a = tans[i], b = tans[i + 1]
            let x = a.x + (b.x - a.x) * s, y = a.y + (b.y - a.y) * s, l = (x * x + y * y).squareRoot()
            return l < 1e-12 ? a : PathPoint(x / l, y / l)
        }
        let sum = pattern.reduce(0, +)
        let period = sum * (pattern.count % 2 == 1 ? 2 : 1)
        var ph = phase.truncatingRemainder(dividingBy: period)
        if ph < 0 { ph += period }
        var index = 0
        while ph > 0 && ph >= pattern[index % pattern.count] { ph -= pattern[index % pattern.count]; index += 1 }
        var remaining = pattern[index % pattern.count] - ph
        var on = index % 2 == 0

        var result: [Poly] = []
        var currentPoints: [PathPoint] = on ? [pts[0]] : []
        var currentFlags: [Bool] = on ? [false] : []
        var currentTans: [PathPoint] = on && hasTangents ? [tans[0]] : []
        var hint: PathPoint?
        // Length the open piece has actually run: a dash that only starts at the very end of the path is not drawn (a dash of length 0 in the pattern is, in the loop below).
        var drawn = 0.0
        func finish() throws {
            if currentPoints.count >= 1 {
                result.append(Poly(points: currentPoints, smooth: currentFlags, closed: false, hint: hint,
                                   tangents: hasTangents && currentTans.count == currentPoints.count ? currentTans : nil))
                if result.count > maxDashPieces { throw PathRasterError.workLimitExceeded }
            }
            currentPoints = []; currentFlags = []; currentTans = []
        }
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { continue }
            let ux = dx / length, uy = dy / length
            var position = 0.0
            while true {
                let left = length - position
                if remaining > left + 1e-12 {
                    remaining -= left
                    if on { currentPoints.append(b); currentFlags.append(flags[i + 1]); if hasTangents { currentTans.append(tans[i + 1]) }; drawn += left }
                    break
                }
                let q = PathPoint(a.x + ux * (position + remaining), a.y + uy * (position + remaining))
                let s = (position + remaining) / length
                if on {
                    currentPoints.append(q); currentFlags.append(false)
                    if let tq = tangentAt(i, s) { currentTans.append(tq) }
                    hint = PathPoint(ux, uy)
                    try finish()
                } else {
                    currentPoints = [q]; currentFlags = [false]
                    currentTans = tangentAt(i, s).map { [$0] } ?? []
                }
                drawn = 0
                position += remaining
                index += 1
                on.toggle()
                remaining = pattern[index % pattern.count]
            }
        }
        if on, drawn > 0 { try finish() }
        return result
    }

    // MARK: Stroke pieces

    /// A convex piece of stroke: a disc or a convex polygon.
    struct Piece {
        var isDisc: Bool
        var cx = 0.0, cy = 0.0, r = 0.0
        var vx: [Double] = [], vy: [Double] = []
        var orient = 1.0
        var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0

        static func disc(_ x: Double, _ y: Double, _ r: Double) -> Piece {
            var p = Piece(isDisc: true); p.cx = x; p.cy = y; p.r = r
            p.minX = x - r; p.maxX = x + r; p.minY = y - r; p.maxY = y + r
            return p
        }

        static func polygon(_ pts: [PathPoint]) -> Piece? {
            var area = 0.0
            for i in pts.indices { let j = (i + 1) % pts.count; area += pts[i].x * pts[j].y - pts[j].x * pts[i].y }
            guard abs(area) > 1e-12 else { return nil }
            var p = Piece(isDisc: false)
            p.vx = pts.map(\.x); p.vy = pts.map(\.y)
            p.orient = area > 0 ? 1 : -1
            p.minX = p.vx.min()!; p.maxX = p.vx.max()!; p.minY = p.vy.min()!; p.maxY = p.vy.max()!
            return p
        }

        mutating func translate(_ dx: Double, _ dy: Double) {
            cx += dx; cy += dy
            for i in vx.indices { vx[i] += dx; vy[i] += dy }
            minX += dx; maxX += dx; minY += dy; maxY += dy
        }

        @inline(__always) func contains(_ x: Double, _ y: Double) -> Bool {
            if isDisc { let ex = x - cx, ey = y - cy; return ex * ex + ey * ey <= r * r }
            let n = vx.count
            for i in 0..<n {
                let j = i + 1 == n ? 0 : i + 1
                if ((vx[j] - vx[i]) * (y - vy[i]) - (vy[j] - vy[i]) * (x - vx[i])) * orient < 0 { return false }
            }
            return true
        }

        /// Distance from a point to the piece's boundary.
        func boundaryDistance(_ x: Double, _ y: Double) -> Double {
            if isDisc { let ex = x - cx, ey = y - cy; return abs((ex * ex + ey * ey).squareRoot() - r) }
            var best = Double.infinity
            let n = vx.count
            for i in 0..<n {
                let j = i + 1 == n ? 0 : i + 1
                let ex = vx[j] - vx[i], ey = vy[j] - vy[i]
                let len2 = ex * ex + ey * ey
                let t = len2 > 0 ? max(0, min(1, ((x - vx[i]) * ex + (y - vy[i]) * ey) / len2)) : 0
                let px = vx[i] + t * ex - x, py = vy[i] + t * ey - y
                best = min(best, px * px + py * py)
            }
            return best.squareRoot()
        }
    }

    static func strokePieces(_ polys: [Poly], style: StrokeStyle, lengthScale: Double, trueLengths: [Double]? = nil) throws -> [Piece] {
        let h = Double(style.lineWidth) * lengthScale / 2
        guard h > 0, h.isFinite else { return [] }
        var strokes = polys
        let pattern = style.dash.map { Double($0) * lengthScale }
        if !pattern.isEmpty {
            let phase = Double(style.dashPhase) * lengthScale
            strokes = []
            for (i, poly) in polys.enumerated() {
                var k = 1.0
                if let trueLengths, i < trueLengths.count, trueLengths[i] > 0 {
                    let flat = poly.length
                    if flat > 0 { k = flat / trueLengths[i] }
                }
                strokes += try dash(poly, pattern: pattern.map { $0 * k }, phase: phase * k)
            }
        }
        var pieces: [Piece] = []
        for poly in strokes { addStroke(poly, h: h, style: style, into: &pieces) }
        return pieces
    }

    private static func addStroke(_ poly: Poly, h: Double, style: StrokeStyle, into pieces: inout [Piece]) {
        // Drop repeated points (their flags with them).
        var pts: [PathPoint] = [], smooth: [Bool] = [], tans: [PathPoint] = []
        let srcTans = poly.tangents.flatMap { $0.count == poly.points.count ? $0 : nil }
        for (i, p) in poly.points.enumerated() {
            if let last = pts.last, (p.x - last.x) * (p.x - last.x) + (p.y - last.y) * (p.y - last.y) < 1e-18 {
                if let srcTans, !tans.isEmpty { tans[tans.count - 1] = srcTans[i] }   // keep the tangent of the later duplicate (the end)
                continue
            }
            pts.append(p); smooth.append(poly.smooth[i]); if let srcTans { tans.append(srcTans[i]) }
        }
        var closed = poly.closed
        if closed, pts.count > 1, let first = pts.first, let last = pts.last,
           (first.x - last.x) * (first.x - last.x) + (first.y - last.y) * (first.y - last.y) < 1e-18 { pts.removeLast(); smooth.removeLast() }
        if pts.count < 3 { closed = false }   // two points close onto themselves: draw as an open stroke
        guard let first = pts.first else { return }

        func unit(_ a: PathPoint, _ b: PathPoint) -> PathPoint {
            let dx = b.x - a.x, dy = b.y - a.y, l = (dx * dx + dy * dy).squareRoot()
            return PathPoint(dx / l, dy / l)
        }
        func capAt(_ p: PathPoint, outward d: PathPoint) {
            switch style.lineCap {
            case .butt: break
            case .round: pieces.append(.disc(p.x, p.y, h))
            case .square:
                let nx = -d.y * h, ny = d.x * h
                if let piece = Piece.polygon([PathPoint(p.x + nx, p.y + ny), PathPoint(p.x + nx + d.x * h, p.y + ny + d.y * h),
                                              PathPoint(p.x - nx + d.x * h, p.y - ny + d.y * h), PathPoint(p.x - nx, p.y - ny)]) { pieces.append(piece) }
            }
        }

        if pts.count == 1 {
            // A zero-length stroke is a dot for round and square caps (nothing for butt), oriented by the hint.
            capAt(first, outward: poly.hint ?? PathPoint(1, 0))
            return
        }

        let count = pts.count
        let segmentCount = closed ? count : count - 1
        var directions: [PathPoint] = []
        let endTangents = !closed && tans.count == count
        for i in 0..<segmentCount {
            let a = pts[i], b = pts[(i + 1) % count]
            let d = unit(a, b)
            directions.append(d)
            // Open ends are cut square to the exact curve tangent; everything else square to the chord.
            let da = endTangents && i == 0 ? tans[0] : d
            let db = endTangents && i == segmentCount - 1 ? tans[count - 1] : d
            let nax = -da.y * h, nay = da.x * h, nbx = -db.y * h, nby = db.x * h
            if let piece = Piece.polygon([PathPoint(a.x + nax, a.y + nay), PathPoint(b.x + nbx, b.y + nby),
                                          PathPoint(b.x - nbx, b.y - nby), PathPoint(a.x - nax, a.y - nay)]) { pieces.append(piece) }
        }
        let joinRange = closed ? Array(0..<count) : (count > 2 ? Array(1..<(count - 1)) : [])
        for i in joinRange {
            let d0 = directions[(i + segmentCount - 1) % segmentCount], d1 = directions[i % segmentCount]
            join(at: pts[i], d0, d1, smooth: smooth[i], h: h, style: style, into: &pieces)
        }
        if !closed {
            let t0 = endTangents ? tans[0] : directions[0]
            let t1 = endTangents ? tans[count - 1] : directions[segmentCount - 1]
            capAt(pts[0], outward: PathPoint(-t0.x, -t0.y))
            capAt(pts[count - 1], outward: t1)
        }
    }

    private static func join(at v: PathPoint, _ d0: PathPoint, _ d1: PathPoint, smooth: Bool, h: Double, style: StrokeStyle, into pieces: inout [Piece]) {
        let cross = d0.x * d1.y - d0.y * d1.x, dot = d0.x * d1.x + d0.y * d1.y
        if abs(cross) < 1e-9 && dot > 0 { return }
        // A smooth (curve-interior) vertex turns by a tiny angle: a bevel wedge closes the gap without reaching past the segments,
        // unlike a disc, which bulges beyond a butt-capped dash that ends just after the vertex.
        if style.lineJoin == .round && !smooth { pieces.append(.disc(v.x, v.y, h)); return }
        // The outer side of the turn is opposite the turn direction.
        let side = cross > 0 ? -h : h
        let n0 = PathPoint(-d0.y, d0.x), n1 = PathPoint(-d1.y, d1.x)
        let a = PathPoint(v.x + n0.x * side, v.y + n0.y * side), b = PathPoint(v.x + n1.x * side, v.y + n1.y * side)
        if style.lineJoin == .miter, !smooth, 1 + dot > 1e-12 {
            let ratio = (2 / (1 + dot)).squareRoot()      // miter length / line width = 1 / cos(turn / 2)
            if ratio <= Double(style.miterLimit) {
                let k = side / (1 + dot)
                let m = PathPoint(v.x + (n0.x + n1.x) * k, v.y + (n0.y + n1.y) * k)
                if let piece = Piece.polygon([v, a, m, b]) { pieces.append(piece) }
                return
            }
        }
        if let piece = Piece.polygon([v, a, b]) { pieces.append(piece) }
    }

    // MARK: Coverage

    private static func strokeCoverageMap(_ pieces: [Piece], width: Int, height: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        guard !pieces.isEmpty else { return out }
        let cellsX = (width + cellSize - 1) / cellSize, cellsY = (height + cellSize - 1) / cellSize
        var buckets = [[Int32]](repeating: [], count: cellsX * cellsY)
        let reach = 1.5
        for (k, piece) in pieces.enumerated() {
            let c0 = max(0, Int(((piece.minX - reach) / Double(cellSize)).rounded(.down))), c1 = min(cellsX - 1, Int(((piece.maxX + reach) / Double(cellSize)).rounded(.down)))
            let r0 = max(0, Int(((piece.minY - reach) / Double(cellSize)).rounded(.down))), r1 = min(cellsY - 1, Int(((piece.maxY + reach) / Double(cellSize)).rounded(.down)))
            guard c0 <= c1, r0 <= r1 else { continue }
            for r in r0...r1 { for c in c0...c1 { buckets[r * cellsX + c].append(Int32(k)) } }
        }
        let step = 1.0 / Double(grid), half = 0.7072
        for y in 0..<height {
            for x in 0..<width {
                let candidates = buckets[(y / cellSize) * cellsX + x / cellSize]
                if candidates.isEmpty { continue }
                let fx = Double(x), fy = Double(y), cx = fx + 0.5, cy = fy + 0.5
                var full = false, ambiguous: [Int32] = []
                for k in candidates {
                    let piece = pieces[Int(k)]
                    if piece.maxX < fx || piece.minX > fx + 1 || piece.maxY < fy || piece.minY > fy + 1 { continue }
                    if piece.contains(fx, fy) && piece.contains(fx + 1, fy) && piece.contains(fx, fy + 1) && piece.contains(fx + 1, fy + 1) { full = true; break }
                    if !piece.contains(cx, cy) && piece.boundaryDistance(cx, cy) >= half { continue }
                    ambiguous.append(k)
                }
                if full { out[y * width + x] = 1; continue }
                if ambiguous.isEmpty { continue }
                var hits = 0
                for j in 0..<grid {
                    let py = fy + (Double(j) + 0.5) * step
                    for i in 0..<grid {
                        let px = fx + (Double(i) + 0.5) * step
                        for k in ambiguous where pieces[Int(k)].contains(px, py) { hits += 1; break }
                    }
                }
                out[y * width + x] = Float(ContinuousRoundedRasterizer.strokeEdgeCoverage(Double(hits) / Double(grid * grid)))
            }
        }
        return out
    }

    private struct Crossings {
        var xs: [Double] = []
        var suffix: [Int] = [0]     // suffix[i] = sum of directions of crossings i...; count + 1 entries
        init() {}
        init(_ list: [(x: Double, dir: Int)]) {
            let sorted = list.sorted { $0.x < $1.x }
            xs = sorted.map(\.x)
            suffix = [Int](repeating: 0, count: sorted.count + 1)
            var i = sorted.count - 1
            while i >= 0 { suffix[i] = suffix[i + 1] + sorted[i].dir; i -= 1 }
        }
        /// Crossings strictly right of x (a ray to +x): their count and signed winding sum.
        func rightOf(_ x: Double) -> (count: Int, winding: Int) {
            var lo = 0, hi = xs.count
            while lo < hi { let mid = (lo + hi) / 2; if xs[mid] > x { hi = mid } else { lo = mid + 1 } }
            return (xs.count - lo, suffix[lo])
        }
        func inside(_ x: Double, evenOdd: Bool) -> Bool {
            let r = rightOf(x)
            return evenOdd ? r.count % 2 == 1 : r.winding != 0
        }
    }

    private static func fillCoverageMap(_ polys: [Poly], width: Int, height: Int, evenOdd: Bool, antialiased: Bool) -> [Float] {
        // Closed edge list (an open subpath fills as if closed).
        var edges: [(x0: Double, y0: Double, x1: Double, y1: Double)] = []
        for poly in polys where poly.points.count >= 2 {
            for i in 0..<poly.points.count {
                let a = poly.points[i], b = poly.points[(i + 1) % poly.points.count]
                edges.append((a.x, a.y, b.x, b.y))
            }
        }
        var out = [Float](repeating: 0, count: width * height)
        guard !edges.isEmpty else { return out }

        // Mark pixels whose centre is within `edgeBand` of an edge (conservatively, by a row band per edge).
        var near = [Bool](repeating: false, count: width * height)
        if antialiased {
            let r = edgeBand
            for e in edges {
                let rowLo = max(0, Int((min(e.y0, e.y1) - r).rounded(.down)) - 1), rowHi = min(height - 1, Int((max(e.y0, e.y1) + r).rounded(.up)))
                guard rowLo <= rowHi else { continue }
                for j in rowLo...rowHi {
                    let yc = Double(j) + 0.5
                    let xa: Double, xb: Double
                    let dy = e.y1 - e.y0
                    if abs(dy) < 1e-12 {
                        guard abs(e.y0 - yc) <= r else { continue }
                        xa = min(e.x0, e.x1); xb = max(e.x0, e.x1)
                    } else {
                        var t0 = (yc - r - e.y0) / dy, t1 = (yc + r - e.y0) / dy
                        if t0 > t1 { swap(&t0, &t1) }
                        t0 = max(0, t0); t1 = min(1, t1)
                        guard t0 <= t1 else { continue }
                        let xp = e.x0 + (e.x1 - e.x0) * t0, xq = e.x0 + (e.x1 - e.x0) * t1
                        xa = min(xp, xq); xb = max(xp, xq)
                    }
                    let iLo = max(0, Int((xa - r - 0.5).rounded(.down))), iHi = min(width - 1, Int((xb + r - 0.5).rounded(.up)))
                    guard iLo <= iHi else { continue }
                    for i in iLo...iHi { near[j * width + i] = true }
                }
            }
        }

        let step = 1.0 / Double(grid)
        func crossings(at y: Double) -> Crossings {
            var list: [(x: Double, dir: Int)] = []
            for e in edges where (e.y0 > y) != (e.y1 > y) {
                list.append(((e.x1 - e.x0) * (y - e.y0) / (e.y1 - e.y0) + e.x0, e.y1 > e.y0 ? 1 : -1))
            }
            return Crossings(list)
        }
        for y in 0..<height {
            let center = crossings(at: Double(y) + 0.5)
            var sub: [Crossings] = []
            for x in 0..<width {
                let inside = center.inside(Double(x) + 0.5, evenOdd: evenOdd)
                guard near[y * width + x] else { if inside { out[y * width + x] = 1 }; continue }
                if sub.isEmpty { sub = (0..<grid).map { crossings(at: Double(y) + (Double($0) + 0.5) * step) } }
                var hits = 0
                for j in 0..<grid {
                    for i in 0..<grid where sub[j].inside(Double(x) + (Double(i) + 0.5) * step, evenOdd: evenOdd) { hits += 1 }
                }
                out[y * width + x] = Float(hits) / Float(grid * grid)
            }
        }
        return out
    }

    // MARK: Colour

    private struct SampleColor { let red: Double, green: Double, blue: Double, alpha: Double }

    private static func unpack(_ color: UInt32, coverage: Double) -> SampleColor? {
        guard coverage > 0 else { return nil }
        return SampleColor(red: Double(UInt8(color >> 24)) / 255, green: Double(UInt8((color >> 16) & 0xff)) / 255,
                           blue: Double(UInt8((color >> 8) & 0xff)) / 255, alpha: Double(UInt8(color & 0xff)) / 255 * coverage)
    }

    private static func over(_ source: SampleColor?, _ destination: SampleColor?) -> SampleColor? {
        guard let source else { return destination }
        guard let destination else { return source }
        let outAlpha = source.alpha + destination.alpha * (1 - source.alpha)
        guard outAlpha > 0 else { return nil }
        func mix(_ s: Double, _ d: Double) -> Double { (s * source.alpha + d * destination.alpha * (1 - source.alpha)) / outAlpha }
        return SampleColor(red: mix(source.red, destination.red), green: mix(source.green, destination.green), blue: mix(source.blue, destination.blue), alpha: outAlpha)
    }

    private static func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, Int((value * 255).rounded())))) }
}
