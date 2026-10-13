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
        let requested = Double(cornerRadius)
        // R2 shows Apple clamps path extent independently from requested
        // radius for large requests, then adjusts control points. Reusing
        // ordinary-radius coefficients after clamping radius is incorrect.
        // Reject until independently observed large-radius coefficients exist.
        let maxSupportedRadius = min(width, height) / (2 * extent)
        guard requested <= maxSupportedRadius + 0.000001 else {
            throw ContinuousRoundedGeometryError.unsupportedRadiusExtent
        }
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
        let e = radius * extent
        let a = radius * endpointNear
        let b = radius * endpointFar
        let outer = radius * controlOuter
        let inner = radius * controlInner
        let middleNear = radius * controlMiddleNear
        let middleFar = radius * controlMiddleFar
        let xm = (x0 + x1) / 2, ym = (y0 + y1) / 2
        guard xm.isFinite, ym.isFinite,
              e.isFinite, a.isFinite, b.isFinite,
              outer.isFinite, inner.isFinite,
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
        result.append(.line(to: p(right, bottom - e)))
        cubic((right - a, bottom - b), (right, bottom - outer), (right, bottom - inner))
        cubic((right - b, bottom - a), (right - middleNear, bottom - middleFar), (right - middleFar, bottom - middleNear))
        cubic((right - e, bottom), (right - inner, bottom), (right - outer, bottom))
        result.append(.line(to: p(left + e, bottom)))
        cubic((left + b, bottom - a), (left + outer, bottom), (left + inner, bottom))
        cubic((left + a, bottom - b), (left + middleFar, bottom - middleNear), (left + middleNear, bottom - middleFar))
        cubic((left, bottom - e), (left, bottom - inner), (left, bottom - outer))
        result.append(.line(to: p(left, top + e)))
        cubic((left + a, top + b), (left, top + outer), (left, top + inner))
        cubic((left + b, top + a), (left + middleNear, top + middleFar), (left + middleFar, top + middleNear))
        cubic((left + e, top), (left + inner, top), (left + outer, top))
        result.append(.line(to: p(right - e, top)))
        cubic((right - b, top + a), (right - outer, top), (right - inner, top))
        cubic((right - a, top + b), (right - middleFar, top + middleNear), (right - middleNear, top + middleFar))
        cubic((right, top + e), (right, top + inner), (right, top + outer))
        result.append(.close)
        return result
    }
}
