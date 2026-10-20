import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// An angle, SwiftUI-shaped. Apple: https://developer.apple.com/documentation/swiftui/angle
public struct Angle: Hashable, Comparable, Sendable {
    public var radians: Double
    public var degrees: Double {
        get { radians * 180 / Double.pi }
        set { radians = newValue * Double.pi / 180 }
    }

    public init() { radians = 0 }
    public init(radians: Double) { self.radians = radians }
    public init(degrees: Double) { radians = degrees * Double.pi / 180 }

    public static let zero = Angle()
    public static func radians(_ radians: Double) -> Angle { Angle(radians: radians) }
    public static func degrees(_ degrees: Double) -> Angle { Angle(degrees: degrees) }
    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }
}

/// A 2D outline of lines and curves, SwiftUI-shaped. Coordinates are in a y-down space (SwiftUI's), in points.
///
/// Arc rule (`addArc`): a point at angle `a` is `center + radius * (cos a, sin a)` in that y-down space, so increasing
/// angle turns visually CLOCKWISE on screen (0 = 3 o'clock, 90 degrees = 6 o'clock). SwiftUI's `clockwise` flag is the
/// CoreGraphics one, which is defined for a y-up space; so `clockwise: false` sweeps in the direction of increasing angle
/// (visually clockwise) and `clockwise: true` sweeps toward decreasing angle (visually COUNTER-clockwise). Equal start and
/// end angles draw a zero sweep; a sweep of two pi or more is a full circle.
public struct Path: Equatable, Sendable {
    /// One path element. Apple: https://developer.apple.com/documentation/swiftui/path/element
    public enum Element: Equatable, @unchecked Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case closeSubpath

        public static func == (lhs: Element, rhs: Element) -> Bool {
            func same(_ a: CGPoint, _ b: CGPoint) -> Bool { a.x == b.x && a.y == b.y }
            switch (lhs, rhs) {
            case (.move(let a), .move(let b)), (.line(let a), .line(let b)): return same(a, b)
            case (.quadCurve(let a, let ac), .quadCurve(let b, let bc)): return same(a, b) && same(ac, bc)
            case (.curve(let a, let a1, let a2), .curve(let b, let b1, let b2)): return same(a, b) && same(a1, b1) && same(a2, b2)
            case (.closeSubpath, .closeSubpath): return true
            default: return false
            }
        }
    }

    public private(set) var elements: [Element] = []
    private var current: PathPoint?
    private var subpathStart: PathPoint?
    /// True right after `closeSubpath`: the next drawing element starts a new subpath at the closed one's start.
    private var needsMove = false

    public init() {}

    public init(_ callback: (inout Path) -> Void) {
        var path = Path()
        callback(&path)
        self = path
    }

    public init(_ rect: CGRect) {
        self.init()
        addRect(rect)
    }

    public init(ellipseIn rect: CGRect) {
        self.init()
        addEllipse(in: rect)
    }

    /// A circular-cornered rounded rectangle. The radius is clamped to half the short side.
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
        self.init()
        addRoundedRect(rect, cornerRadius: cornerRadius)
    }

    public static func == (lhs: Path, rhs: Path) -> Bool { lhs.elements == rhs.elements }

    public var isEmpty: Bool { elements.isEmpty }
    public var currentPoint: CGPoint? { (needsMove ? subpathStart : current)?.cg }

    public func forEach(_ body: (Element) -> Void) { elements.forEach(body) }

    // MARK: Builders

    private mutating func beginDrawing() {
        if needsMove, let start = subpathStart {
            elements.append(.move(to: start.cg)); current = start; needsMove = false
        }
    }

    public mutating func move(to point: CGPoint) {
        elements.append(.move(to: point))
        current = PathPoint(point); subpathStart = PathPoint(point); needsMove = false
    }

    public mutating func addLine(to point: CGPoint) {
        guard current != nil else { move(to: point); return }
        beginDrawing()
        elements.append(.line(to: point)); current = PathPoint(point)
    }

    public mutating func addLines(_ points: [CGPoint]) {
        for (index, point) in points.enumerated() {
            if index == 0 { move(to: point) } else { addLine(to: point) }
        }
    }

    public mutating func addQuadCurve(to point: CGPoint, control: CGPoint) {
        if current == nil { move(to: control) }
        beginDrawing()
        elements.append(.quadCurve(to: point, control: control)); current = PathPoint(point)
    }

    public mutating func addCurve(to point: CGPoint, control1: CGPoint, control2: CGPoint) {
        if current == nil { move(to: control1) }
        beginDrawing()
        elements.append(.curve(to: point, control1: control1, control2: control2)); current = PathPoint(point)
    }

    public mutating func closeSubpath() {
        guard current != nil, !needsMove else { return }
        elements.append(.closeSubpath)
        current = subpathStart
        needsMove = true
    }

    /// Adds an arc of a circle (see the arc rule on `Path`). The arc is joined to the current point with a line when there is one.
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool) {
        let start = startAngle.radians
        var sweep: Double
        let full = 2 * Double.pi
        if clockwise {
            // decreasing angle (visually counter-clockwise)
            let delta = start - endAngle.radians
            sweep = delta >= full ? -full : -Path.positiveRemainder(delta, full)
        } else {
            let delta = endAngle.radians - start
            sweep = delta >= full ? full : Path.positiveRemainder(delta, full)
        }
        if abs(endAngle.radians - start) >= full { sweep = sweep < 0 ? -full : full }
        appendEllipticalArc(center: center, rx: Double(radius), ry: Double(radius), start: start, sweep: sweep, joinWithLine: true)
    }

    public mutating func addEllipse(in rect: CGRect) {
        let rx = Double(rect.width) / 2, ry = Double(rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        move(to: CGPoint(x: Double(center.x) + rx, y: Double(center.y)))
        appendEllipticalArc(center: center, rx: rx, ry: ry, start: 0, sweep: 2 * Double.pi, joinWithLine: false)
        closeSubpath()
    }

    public mutating func addRect(_ rect: CGRect) {
        move(to: CGPoint(x: rect.minX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        closeSubpath()
    }

    public mutating func addRoundedRect(_ rect: CGRect, cornerRadius: CGFloat) {
        let r = Double(max(0, min(cornerRadius, min(rect.width, rect.height) / 2)))
        guard r > 0 else { addRect(rect); return }
        let x0 = Double(rect.minX), y0 = Double(rect.minY), x1 = Double(rect.maxX), y1 = Double(rect.maxY)
        let h = Double.pi / 2
        move(to: CGPoint(x: x0 + r, y: y0))
        lineIfMoved(to: CGPoint(x: x1 - r, y: y0))
        appendEllipticalArc(center: CGPoint(x: x1 - r, y: y0 + r), rx: r, ry: r, start: -h, sweep: h, joinWithLine: true)
        lineIfMoved(to: CGPoint(x: x1, y: y1 - r))
        appendEllipticalArc(center: CGPoint(x: x1 - r, y: y1 - r), rx: r, ry: r, start: 0, sweep: h, joinWithLine: true)
        lineIfMoved(to: CGPoint(x: x0 + r, y: y1))
        appendEllipticalArc(center: CGPoint(x: x0 + r, y: y1 - r), rx: r, ry: r, start: h, sweep: h, joinWithLine: true)
        lineIfMoved(to: CGPoint(x: x0, y: y0 + r))
        appendEllipticalArc(center: CGPoint(x: x0 + r, y: y0 + r), rx: r, ry: r, start: 2 * h, sweep: h, joinWithLine: true)
        closeSubpath()
    }

    /// Appends another path's elements.
    public mutating func addPath(_ other: Path) {
        for element in other.elements {
            switch element {
            case .move(let p): move(to: p)
            case .line(let p): addLine(to: p)
            case .quadCurve(let p, let c): addQuadCurve(to: p, control: c)
            case .curve(let p, let c1, let c2): addCurve(to: p, control1: c1, control2: c2)
            case .closeSubpath: closeSubpath()
            }
        }
    }

    private mutating func lineIfMoved(to point: CGPoint) {
        guard let c = current, abs(c.x - Double(point.x)) > 1e-12 || abs(c.y - Double(point.y)) > 1e-12 else { return }
        addLine(to: point)
    }

    private static func positiveRemainder(_ value: Double, _ modulus: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: modulus)
        return r < 0 ? r + modulus : r
    }

    /// Cubic approximation of an elliptical arc, split into pieces of at most a quarter turn (k = 4/3 tan(sweep/4) per piece).
    private mutating func appendEllipticalArc(center: CGPoint, rx: Double, ry: Double, start: Double, sweep: Double, joinWithLine: Bool) {
        let cx = Double(center.x), cy = Double(center.y)
        func point(_ a: Double) -> CGPoint { CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a)) }
        if joinWithLine { lineIfMovedOrMove(to: point(start)) }
        guard sweep != 0 else { return }
        let pieces = max(1, Int((abs(sweep) / (Double.pi / 2) - 1e-9).rounded(.up)))
        let step = sweep / Double(pieces)
        let k = 4.0 / 3.0 * tan(step / 4)
        for i in 0..<pieces {
            let a0 = start + step * Double(i), a1 = a0 + step
            let c1 = CGPoint(x: cx + rx * (cos(a0) - k * sin(a0)), y: cy + ry * (sin(a0) + k * cos(a0)))
            let c2 = CGPoint(x: cx + rx * (cos(a1) + k * sin(a1)), y: cy + ry * (sin(a1) - k * cos(a1)))
            addCurve(to: point(a1), control1: c1, control2: c2)
        }
    }

    private mutating func lineIfMovedOrMove(to point: CGPoint) {
        if currentPoint == nil { move(to: point) } else { lineIfMoved(to: point) }
    }

    // MARK: Transforms

    public func applying(_ transform: CGAffineTransform) -> Path {
        func map(_ p: CGPoint) -> CGPoint {
            // Split so the Windows type checker stays within its time limit.
            let x: CGFloat = transform.a * p.x + transform.c * p.y + transform.tx
            let y: CGFloat = transform.b * p.x + transform.d * p.y + transform.ty
            return CGPoint(x: x, y: y)
        }
        var result = Path()
        for element in elements {
            switch element {
            case .move(let p): result.move(to: map(p))
            case .line(let p): result.addLine(to: map(p))
            case .quadCurve(let p, let c): result.addQuadCurve(to: map(p), control: map(c))
            case .curve(let p, let c1, let c2): result.addCurve(to: map(p), control1: map(c1), control2: map(c2))
            case .closeSubpath: result.closeSubpath()
            }
        }
        return result
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        applying(CGAffineTransform(translationX: dx, y: dy))
    }

    // MARK: Bounds

    /// The tight bounding box of the path (curve extrema included, not the control polygon). Zero rect for an empty path.
    public var boundingRect: CGRect {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        func add(_ x: Double, _ y: Double) { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        for segment in PathSegments.subpaths(of: self).flatMap(\.segments) {
            for p in segment.extremePoints() { add(p.x, p.y) }
        }
        guard minX.isFinite else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Trimming and measuring

    /// Total arc length of the path in points, closing segments included (Gauss-Legendre on each curve).
    public var arcLength: CGFloat {
        CGFloat(PathSegments.subpaths(of: self).reduce(0.0) { $0 + $1.segments.reduce(0.0) { $0 + $1.length() } })
    }

    /// The part of the path between fractions `from` and `to` (each clamped to 0...1) of its total ARC LENGTH.
    ///
    /// Assumptions (SwiftUI documents none; the Mac spike checks them): the length is measured over every subpath in order,
    /// a closed subpath includes its closing segment, and a fraction maps to the point at that arc length (not to a
    /// Bezier parameter). `to <= from` gives an empty path; `0...1` returns the path itself. Curves are cut exactly (de Casteljau), not flattened.
    /// Each emitted piece is an open subpath.
    public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
        let f = min(1, max(0, Double(from))), t = min(1, max(0, Double(to)))
        guard t > f else { return Path() }
        if f <= 0 && t >= 1 { return self }
        let subpaths = PathSegments.subpaths(of: self)
        let lengths = subpaths.map { $0.segments.map { $0.length() } }
        let total = lengths.reduce(0.0) { $0 + $1.reduce(0, +) }
        guard total > 0 else { return Path() }
        let a = f * total, b = t * total
        var result = Path()
        var offset = 0.0
        for (si, subpath) in subpaths.enumerated() {
            var open = false
            for (gi, segment) in subpath.segments.enumerated() {
                let length = lengths[si][gi]
                defer { offset += length }
                let lo = max(a, offset), hi = min(b, offset + length)
                guard length > 0, hi > lo else { open = false; continue }
                let t0 = lo - offset <= 1e-12 ? 0 : segment.parameter(atLength: lo - offset, length: length)
                let t1 = hi - offset >= length - 1e-12 ? 1 : segment.parameter(atLength: hi - offset, length: length)
                let piece = segment.sub(t0, t1)
                if !open { result.move(to: piece.start.cg) }
                piece.append(to: &result)
                open = t1 >= 1
            }
        }
        return result
    }
}

// MARK: - Segment model shared by measuring, trimming and the rasteriser

struct PathPoint: Sendable {
    var x: Double, y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
    var cg: CGPoint { CGPoint(x: x, y: y) }
    static func + (a: PathPoint, b: PathPoint) -> PathPoint { PathPoint(a.x + b.x, a.y + b.y) }
    static func - (a: PathPoint, b: PathPoint) -> PathPoint { PathPoint(a.x - b.x, a.y - b.y) }
    static func * (a: PathPoint, s: Double) -> PathPoint { PathPoint(a.x * s, a.y * s) }
    func lerp(_ b: PathPoint, _ t: Double) -> PathPoint { PathPoint(x + (b.x - x) * t, y + (b.y - y) * t) }
}

/// One drawn segment of a path: a line, a quadratic or a cubic.
enum PathSegment {
    case line(PathPoint, PathPoint)
    case quad(PathPoint, PathPoint, PathPoint)
    case cubic(PathPoint, PathPoint, PathPoint, PathPoint)

    var start: PathPoint {
        switch self {
        case .line(let a, _), .quad(let a, _, _), .cubic(let a, _, _, _): return a
        }
    }
    var end: PathPoint {
        switch self {
        case .line(_, let b), .quad(_, _, let b), .cubic(_, _, _, let b): return b
        }
    }

    func point(_ t: Double) -> PathPoint {
        let u = 1 - t
        switch self {
        case .line(let a, let b): return a.lerp(b, t)
        case .quad(let a, let c, let b): return a * (u * u) + c * (2 * u * t) + b * (t * t)
        case .cubic(let a, let c1, let c2, let b): return a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t)
        }
    }

    func speed(_ t: Double) -> Double {
        let u = 1 - t
        let d: PathPoint
        switch self {
        case .line(let a, let b): d = b - a
        case .quad(let a, let c, let b): d = (c - a) * (2 * u) + (b - c) * (2 * t)
        case .cubic(let a, let c1, let c2, let b): d = (c1 - a) * (3 * u * u) + (c2 - c1) * (6 * u * t) + (b - c2) * (3 * t * t)
        }
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    private static let nodes: [Double] = [0, 0.5384693101056831, -0.5384693101056831, 0.9061798459386640, -0.9061798459386640]
    private static let weights: [Double] = [0.5688888888888889, 0.4786286704993665, 0.4786286704993665, 0.2369268850561891, 0.2369268850561891]
    private static let panelsPerUnit = 12.0

    /// Arc length over parameter range t0...t1 (composite 5-point Gauss-Legendre; line is exact).
    func length(from t0: Double = 0, to t1: Double = 1) -> Double {
        if case .line(let a, let b) = self {
            let d = b - a
            return (d.x * d.x + d.y * d.y).squareRoot() * (t1 - t0)
        }
        guard t1 > t0 else { return 0 }
        let panels = max(1, Int(((t1 - t0) * PathSegment.panelsPerUnit).rounded(.up)))
        let h = (t1 - t0) / Double(panels)
        var sum = 0.0
        for p in 0..<panels {
            let mid = t0 + h * (Double(p) + 0.5)
            for k in 0..<5 { sum += PathSegment.weights[k] * speed(mid + PathSegment.nodes[k] * h / 2) }
        }
        return sum * h / 2
    }

    /// Parameter t whose arc length from the start is `s` (0...length), by bisection on the exact integral.
    func parameter(atLength s: Double, length total: Double) -> Double {
        if case .line = self { return total > 0 ? min(1, max(0, s / total)) : 0 }
        var lo = 0.0, hi = 1.0
        for _ in 0..<48 {
            let mid = (lo + hi) / 2
            if length(from: 0, to: mid) < s { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// The segment restricted to parameter range t0...t1 (de Casteljau).
    func sub(_ t0: Double, _ t1: Double) -> PathSegment {
        func lerp(_ a: PathPoint, _ b: PathPoint, _ t: Double) -> PathPoint { a.lerp(b, t) }
        func splitCubic(_ p: (PathPoint, PathPoint, PathPoint, PathPoint), _ t: Double) -> ((PathPoint, PathPoint, PathPoint, PathPoint), (PathPoint, PathPoint, PathPoint, PathPoint)) {
            let a = lerp(p.0, p.1, t), b = lerp(p.1, p.2, t), c = lerp(p.2, p.3, t)
            let d = lerp(a, b, t), e = lerp(b, c, t), f = lerp(d, e, t)
            return ((p.0, a, d, f), (f, e, c, p.3))
        }
        func splitQuad(_ p: (PathPoint, PathPoint, PathPoint), _ t: Double) -> ((PathPoint, PathPoint, PathPoint), (PathPoint, PathPoint, PathPoint)) {
            let a = lerp(p.0, p.1, t), b = lerp(p.1, p.2, t), c = lerp(a, b, t)
            return ((p.0, a, c), (c, b, p.2))
        }
        switch self {
        case .line(let a, let b): return .line(a.lerp(b, t0), a.lerp(b, t1))
        case .quad(let a, let c, let b):
            var q = (a, c, b)
            if t0 > 0 { q = splitQuad(q, t0).1 }
            if t1 < 1 { q = splitQuad(q, t0 >= 1 ? 1 : (t1 - t0) / (1 - t0)).0 }
            return .quad(q.0, q.1, q.2)
        case .cubic(let a, let c1, let c2, let b):
            var q = (a, c1, c2, b)
            if t0 > 0 { q = splitCubic(q, t0).1 }
            if t1 < 1 { q = splitCubic(q, t0 >= 1 ? 1 : (t1 - t0) / (1 - t0)).0 }
            return .cubic(q.0, q.1, q.2, q.3)
        }
    }

    func append(to path: inout Path) {
        switch self {
        case .line(_, let b): path.addLine(to: b.cg)
        case .quad(_, let c, let b): path.addQuadCurve(to: b.cg, control: c.cg)
        case .cubic(_, let c1, let c2, let b): path.addCurve(to: b.cg, control1: c1.cg, control2: c2.cg)
        }
    }

    /// Endpoints plus the points where the curve's x or y derivative is zero.
    func extremePoints() -> [PathPoint] {
        var points = [start, end]
        func roots(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> [Double] {
            let a = p1 - p0, b = p2 - p1, c = p3 - p2
            let qa = a - 2 * b + c, qb = 2 * (b - a), qc = a
            if abs(qa) < 1e-12 { return abs(qb) < 1e-12 ? [] : [-qc / qb] }
            let disc = qb * qb - 4 * qa * qc
            guard disc >= 0 else { return [] }
            let s = disc.squareRoot()
            return [(-qb + s) / (2 * qa), (-qb - s) / (2 * qa)]
        }
        switch self {
        case .line: break
        case .quad(let a, let c, let b):
            for t in roots(a.x, a.x + (c.x - a.x) * 2 / 3, b.x + (c.x - b.x) * 2 / 3, b.x) + roots(a.y, a.y + (c.y - a.y) * 2 / 3, b.y + (c.y - b.y) * 2 / 3, b.y) where t > 0 && t < 1 { points.append(point(t)) }
        case .cubic(let a, let c1, let c2, let b):
            for t in roots(a.x, c1.x, c2.x, b.x) + roots(a.y, c1.y, c2.y, b.y) where t > 0 && t < 1 { points.append(point(t)) }
        }
        return points
    }
}

/// A path split into subpaths of segments. A `closeSubpath` contributes its closing line (when the end is not already the start).
struct PathSubpath {
    var segments: [PathSegment]
    var closed: Bool
}

enum PathSegments {
    static func subpaths(of path: Path) -> [PathSubpath] {
        var result: [PathSubpath] = []
        var segments: [PathSegment] = []
        var start = PathPoint(0, 0), current = start
        var hasStart = false
        func flush(closed: Bool) {
            if !segments.isEmpty || closed { result.append(PathSubpath(segments: segments, closed: closed)) }
            segments = []
        }
        for element in path.elements {
            switch element {
            case .move(let p):
                if hasStart && !segments.isEmpty { flush(closed: false) }
                start = PathPoint(p); current = start; hasStart = true
            case .line(let p):
                let next = PathPoint(p); segments.append(.line(current, next)); current = next
            case .quadCurve(let p, let c):
                let next = PathPoint(p); segments.append(.quad(current, PathPoint(c), next)); current = next
            case .curve(let p, let c1, let c2):
                let next = PathPoint(p); segments.append(.cubic(current, PathPoint(c1), PathPoint(c2), next)); current = next
            case .closeSubpath:
                if abs(current.x - start.x) > 1e-12 || abs(current.y - start.y) > 1e-12 { segments.append(.line(current, start)) }
                flush(closed: true)
                current = start
            }
        }
        if !segments.isEmpty { flush(closed: false) }
        return result.filter { !$0.segments.isEmpty }
    }
}
