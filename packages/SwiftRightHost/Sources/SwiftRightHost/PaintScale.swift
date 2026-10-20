import SwiftRightRuntime
import SwiftRightBridge

/// The accumulated `.scaleEffect` transform of a subtree in window pixels (SR2 R4, #39): p -> (p.x * sx + tx, p.y * sy + ty).
public struct PaintScale: Equatable, Sendable {
    public var sx: Float = 1, sy: Float = 1, tx: Float = 0, ty: Float = 0
    public static let identity = PaintScale()

    public var isIdentity: Bool { sx == 1 && sy == 1 && tx == 0 && ty == 0 }
    /// The factor radii, stroke widths and raster sizes take: the geometric mean of the axes (exact for a uniform scale, which is what S1 uses).
    public var uniform: Float { (abs(sx) * abs(sy)).squareRoot() }

    public func map(_ r: Rect) -> Rect {
        let x0 = r.x * sx + tx, x1 = (r.x + r.w) * sx + tx
        let y0 = r.y * sy + ty, y1 = (r.y + r.h) * sy + ty
        return Rect(x: min(x0, x1), y: min(y0, y1), w: abs(x1 - x0), h: abs(y1 - y0))
    }

    /// `r` at its own size, centred where the scale puts its centre.
    public func mapCentre(_ r: Rect) -> Rect {
        let cx = (r.x + r.w / 2) * sx + tx, cy = (r.y + r.h / 2) * sy + ty
        return Rect(x: cx - r.w / 2, y: cy - r.h / 2, w: r.w, h: r.h)
    }

    /// This transform applied after `scale` about its anchor in `frame` (the scale node's own laid-out pixel frame): T(S(p)).
    public func scaled(by scale: ResolvedScale, about frame: Rect) -> PaintScale {
        let ax = frame.x + frame.w * Float(scale.anchor.x), ay = frame.y + frame.h * Float(scale.anchor.y)
        let kx = Float(scale.x), ky = Float(scale.y)
        return PaintScale(sx: sx * kx, sy: sy * ky, tx: sx * (ax - ax * kx) + tx, ty: sy * (ay - ay * ky) + ty)
    }
}
