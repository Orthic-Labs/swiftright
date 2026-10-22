import Foundation

// Issue #84 (SR2 S5): UnevenRoundedRectangle and RectangleCornerRadii. The continuous style (the default) uses the same three-cubic corner family as
// RoundedRectangle (ContinuousRoundedGeometry, measured on macOS 27) with each corner's own radius; the circular style uses quarter arcs. A radius is clamped to half of the
// shorter side, and when two corners' extents (1.5287 r along an edge) together exceed that edge, all radii shrink by one factor so they fit. Radii beyond the measured
// large-radius family of RoundedRectangle (a radius near half the side) are not separately measured for uneven corners.

/// Apple: https://developer.apple.com/documentation/swiftui/rectanglecornerradii
public struct RectangleCornerRadii: Equatable, Sendable {
    public var topLeading: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat, topTrailing: CGFloat
    public init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
        self.topLeading = topLeading; self.bottomLeading = bottomLeading; self.bottomTrailing = bottomTrailing; self.topTrailing = topTrailing
    }
}

/// Apple: https://developer.apple.com/documentation/swiftui/unevenroundedrectangle
public struct UnevenRoundedRectangle: Shape {
    public var cornerRadii: RectangleCornerRadii
    public var style: RoundedCornerStyle

    public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) { self.cornerRadii = cornerRadii; self.style = style }
    public init(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0, topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) {
        self.init(cornerRadii: RectangleCornerRadii(topLeading: topLeadingRadius, bottomLeading: bottomLeadingRadius, bottomTrailing: bottomTrailingRadius, topTrailing: topTrailingRadius), style: style)
    }

    public func path(in rect: CGRect) -> Path {
        let w = Double(rect.width), h = Double(rect.height)
        guard w > 0, h > 0 else { return Path() }
        let extent = 1.528664946556
        var tl = max(0, Double(cornerRadii.topLeading)), bl = max(0, Double(cornerRadii.bottomLeading))
        var br = max(0, Double(cornerRadii.bottomTrailing)), tr = max(0, Double(cornerRadii.topTrailing))
        let cap = min(w, h) / 2
        (tl, bl, br, tr) = (min(tl, cap), min(bl, cap), min(br, cap), min(tr, cap))
        let k = style == .continuous ? extent : 1
        var shrink = 1.0
        for (sum, length) in [((tl + tr) * k, w), ((bl + br) * k, w), ((tl + bl) * k, h), ((tr + br) * k, h)] where sum > length { shrink = min(shrink, length / sum) }
        (tl, bl, br, tr) = (tl * shrink, bl * shrink, br * shrink, tr * shrink)

        let left = Double(rect.minX), right = left + w, top = Double(rect.minY), bottom = top + h
        var path = Path()
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

        // One corner as segments from its vertical-edge end to its horizontal-edge end, in corner-local (u along the horizontal edge, v along the vertical edge).
        typealias Seg = (to: (Double, Double), c1: (Double, Double), c2: (Double, Double))
        func local(_ r: Double) -> (start: (Double, Double), segs: [Seg]) {
            if style == .continuous {
                let a = r * 0.074911400676, b = r * 0.631493985653, e = r * extent
                let outer = r * 1.088490009308, inner = r * 0.868407011032, mn = r * 0.169060006738, mf = r * 0.372824013233
                return ((0, e), [((a, b), (0, outer), (0, inner)), ((b, a), (mn, mf), (mf, mn)), ((e, 0), (inner, 0), (outer, 0))])
            }
            // circular quarter arc as one cubic (kappa)
            let c = 0.5522847498307936 * r
            return ((0, r), [((r, 0), (0, r - c), (r - c, 0))])
        }
        // global point of corner-local (u, v) for each corner
        enum Corner { case tl, tr, br, bl }
        func place(_ corner: Corner, _ p: (Double, Double)) -> CGPoint {
            switch corner {
            case .tl: return pt(left + p.0, top + p.1)
            case .tr: return pt(right - p.0, top + p.1)
            case .br: return pt(right - p.0, bottom - p.1)
            case .bl: return pt(left + p.0, bottom - p.1)
            }
        }
        // draws one corner, leaving the pen at the end; `vertical` is true when the traversal arrives along the vertical edge (BR, TL)
        func corner(_ c: Corner, _ r: Double, verticalFirst: Bool) {
            guard r > 0 else {
                let vertex: CGPoint = { switch c { case .tl: return pt(left, top); case .tr: return pt(right, top); case .br: return pt(right, bottom); case .bl: return pt(left, bottom) } }()
                path.addLine(to: vertex); return
            }
            let (start, segs) = local(r)
            if verticalFirst {
                path.addLine(to: place(c, start))
                for s in segs { path.addCurve(to: place(c, s.to), control1: place(c, s.c1), control2: place(c, s.c2)) }
            } else {
                var points = [start] + segs.map(\.to)
                path.addLine(to: place(c, points.removeLast()))
                for s in segs.reversed() {
                    let target = points.removeLast()
                    path.addCurve(to: place(c, target), control1: place(c, s.c2), control2: place(c, s.c1))
                }
            }
        }
        // Start on the right edge, going down: BR, BL, TL, TR, as RoundedRectangle's path.
        path.move(to: pt(right, top + h / 2))
        corner(.br, br, verticalFirst: true)
        corner(.bl, bl, verticalFirst: false)
        corner(.tl, tl, verticalFirst: true)
        corner(.tr, tr, verticalFirst: false)
        path.closeSubpath()
        return path
    }
}
