import Foundation

/// One public-path-compatible element for SwiftUI continuous rounded corners.
public enum ContinuousPathElement: Equatable, Sendable {
    case move(to: LayoutPoint)
    case line(to: LayoutPoint)
    case cubic(to: LayoutPoint, control1: LayoutPoint, control2: LayoutPoint)
    case close
}

/// Explicit rejection prevents unsupported large-radius requests from being
/// silently replaced by circular or fixture-specific geometry.
public enum ContinuousRoundedGeometryError: Error, Equatable, Sendable {
    case invalidBounds
    case unsupportedRadiusExtent
}

/// Generic continuous-corner geometry derived from public SwiftUI
/// `RoundedRectangle.path(in:)` output. Coefficients are scale-free, so no
/// witness dimensions or pixel fixture are embedded.
public enum ContinuousRoundedGeometry {
    // Four path probes produced same normalized coefficients across aspect
    // ratios 2:1, 105:55, 1:1, & 3:1. Constants describe Apple's three-cubic
    // smooth corner family rather than circular or superellipse substitution.
    private static let extent = 1.528664946556
    private static let endpointNear = 0.074911400676
    private static let endpointFar = 0.631493985653
    private static let controlOuter = 1.088490009308
    private static let controlInner = 0.868407011032
    private static let controlMiddleNear = 0.169060006738
    private static let controlMiddleFar = 0.372824013233

    public static func path(in rect: LayoutRect, cornerRadius: CGFloat) throws -> [ContinuousPathElement] {
        let x0 = Double(rect.minX), y0 = Double(rect.minY)
        let width = max(0, Double(rect.width)), height = max(0, Double(rect.height))
        guard x0.isFinite, y0.isFinite,
              width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw ContinuousRoundedGeometryError.invalidBounds
        }
        guard cornerRadius.isFinite, cornerRadius >= 0 else {
            throw ContinuousRoundedGeometryError.invalidBounds
        }
        // Round 5 block 30 (hub gaps R7/R8): the large-radius family, measured from `RoundedRectangle(style: .continuous).path(in:)` on macOS 27 (100x40, 100x24,
        // 200x60, 30x30 and 40x40 at radii from the extent limit to 99, scale-free). A radius is clamped to min(w, h) / 2 (r = 20 and r = 99 give the same path on 100x40).
        // Up to r0 = half / extent along an edge the ordinary coefficients hold. Past r0 the edge's extent clamps to its half length (the first cubic then starts at the
        // edge's mid-point) and the two control distances from the corner move linearly in r: outer 1.0885 r0 -> 0.96 half, inner 0.8684 r0 -> 0.82 half (at r = half), with the
        // end point (a, b) still 0.0749 r and 0.6315 r. The slopes fit every measured radius to 5 decimals.
        let requested = min(Double(cornerRadius), min(width, height) / 2)
        let x1 = x0 + width, y1 = y0 + height
        guard x1.isFinite, y1.isFinite else {
            throw ContinuousRoundedGeometryError.invalidBounds
        }
        if requested == 0 {
            func p(_ x: Double, _ y: Double) -> LayoutPoint {
                LayoutPoint(x: CGFloat(x), y: CGFloat(y))
            }
            return [.move(to: p(x0, y0)), .line(to: p(x1, y0)),
                    .line(to: p(x1, y1)), .line(to: p(x0, y1)), .close]
        }
        let radius = requested
        let a = radius * endpointNear
        let b = radius * endpointFar
        /// (extent along the edge, outer control distance, inner control distance) for an edge whose half length is `half`.
        func edge(_ half: Double) -> (e: Double, outer: Double, inner: Double) {
            let e = radius * extent
            if e <= half + 0.000001 { return (e, radius * controlOuter, radius * controlInner) }
            let r0 = half / extent
            let t = half > r0 ? min(1, max(0, (radius - r0) / (half - r0))) : 1
            return (half, (controlOuter * r0) + t * (0.96 * half - controlOuter * r0), (controlInner * r0) + t * (0.82 * half - controlInner * r0))
        }
        let vertical = edge(height / 2), horizontal = edge(width / 2)
        let eV = vertical.e, outerV = vertical.outer, innerV = vertical.inner
        let eH = horizontal.e, outerH = horizontal.outer, innerH = horizontal.inner
        let middleNear = radius * controlMiddleNear
        let middleFar = radius * controlMiddleFar
        let xm = (x0 + x1) / 2, ym = (y0 + y1) / 2
        guard xm.isFinite, ym.isFinite,
              eV.isFinite, eH.isFinite, a.isFinite, b.isFinite,
              outerV.isFinite, innerV.isFinite, outerH.isFinite, innerH.isFinite,
              middleNear.isFinite, middleFar.isFinite else {
            throw ContinuousRoundedGeometryError.invalidBounds
        }
        let right = x1, left = x0, top = y0, bottom = y1
        var result: [ContinuousPathElement] = []
        result.reserveCapacity(18)
        func p(_ x: Double, _ y: Double) -> LayoutPoint { LayoutPoint(x: CGFloat(x), y: CGFloat(y)) }
        func cubic(_ to: (Double, Double), _ c1: (Double, Double), _ c2: (Double, Double)) {
            result.append(.cubic(to: p(to.0, to.1), control1: p(c1.0, c1.1), control2: p(c2.0, c2.1)))
        }

        result.append(.move(to: p(right, ym)))
        result.append(.line(to: p(right, bottom - eV)))
        cubic((right - a, bottom - b), (right, bottom - outerV), (right, bottom - innerV))
        cubic((right - b, bottom - a), (right - middleNear, bottom - middleFar), (right - middleFar, bottom - middleNear))
        cubic((right - eH, bottom), (right - innerH, bottom), (right - outerH, bottom))
        result.append(.line(to: p(left + eH, bottom)))
        cubic((left + b, bottom - a), (left + outerH, bottom), (left + innerH, bottom))
        cubic((left + a, bottom - b), (left + middleFar, bottom - middleNear), (left + middleNear, bottom - middleFar))
        cubic((left, bottom - eV), (left, bottom - innerV), (left, bottom - outerV))
        result.append(.line(to: p(left, top + eV)))
        cubic((left + a, top + b), (left, top + outerV), (left, top + innerV))
        cubic((left + b, top + a), (left + middleNear, top + middleFar), (left + middleFar, top + middleNear))
        cubic((left + eH, top), (left + innerH, top), (left + outerH, top))
        result.append(.line(to: p(right - eH, top)))
        cubic((right - b, top + a), (right - outerH, top), (right - innerH, top))
        cubic((right - a, top + b), (right - middleFar, top + middleNear), (right - middleNear, top + middleFar))
        cubic((right, top + eV), (right, top + innerV), (right, top + outerV))
        result.append(.close)
        return result
    }
}
