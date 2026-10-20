import Foundation

#if !canImport(CoreGraphics)
/// CoreGraphics' affine transform, for platforms without CoreGraphics (Windows: swift-corelibs-foundation has CGPoint, CGSize,
/// CGRect and CGFloat but no CGAffineTransform). Same fields and semantics as Apple's: a point maps to
/// (a*x + c*y + tx, b*x + d*y + ty); `t1.concatenating(t2)` applies t1 then t2.
/// Apple: https://developer.apple.com/documentation/corefoundation/cgaffinetransform
public struct CGAffineTransform: Equatable, Hashable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init() { self.init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
    public static let identity = CGAffineTransform()
    public init(translationX tx: CGFloat, y ty: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty) }
    public init(scaleX sx: CGFloat, y sy: CGFloat) { self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0) }
    public init(rotationAngle angle: CGFloat) {
        let cs = CGFloat(cos(Double(angle))), sn = CGFloat(sin(Double(angle)))
        self.init(a: cs, b: sn, c: -sn, d: cs, tx: 0, ty: 0)
    }
    public var isIdentity: Bool { self == .identity }

    /// `self` then `t2`.
    public func concatenating(_ t2: CGAffineTransform) -> CGAffineTransform {
        let na = a * t2.a + b * t2.c, nb = a * t2.b + b * t2.d
        let nc = c * t2.a + d * t2.c, nd = c * t2.b + d * t2.d
        let ntx = tx * t2.a + ty * t2.c + t2.tx, nty = tx * t2.b + ty * t2.d + t2.ty
        return CGAffineTransform(a: na, b: nb, c: nc, d: nd, tx: ntx, ty: nty)
    }
    /// Apple order: the new transform applies `translation` first, then `self`.
    public func translatedBy(x: CGFloat, y: CGFloat) -> CGAffineTransform { CGAffineTransform(translationX: x, y: y).concatenating(self) }
    public func scaledBy(x: CGFloat, y: CGFloat) -> CGAffineTransform { CGAffineTransform(scaleX: x, y: y).concatenating(self) }
    public func rotated(by angle: CGFloat) -> CGAffineTransform { CGAffineTransform(rotationAngle: angle).concatenating(self) }
    public func inverted() -> CGAffineTransform {
        let det = a * d - b * c
        guard det != 0 else { return self }   // Apple returns the matrix unchanged when it is not invertible
        let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
        return CGAffineTransform(a: ia, b: ib, c: ic, d: id, tx: -(tx * ia + ty * ic), ty: -(tx * ib + ty * id))
    }
}

extension CGPoint {
    public func applying(_ t: CGAffineTransform) -> CGPoint {
        let nx = t.a * x + t.c * y + t.tx
        let ny = t.b * x + t.d * y + t.ty
        return CGPoint(x: nx, y: ny)
    }
}

extension CGSize {
    public func applying(_ t: CGAffineTransform) -> CGSize {
        let w = t.a * width + t.c * height
        let h = t.b * width + t.d * height
        return CGSize(width: w, height: h)
    }
}
#endif
