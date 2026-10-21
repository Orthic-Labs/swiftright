import Foundation

// Issue #54 (SR2): paint interpolation. A node's paint is a presented channel like its frame: an animated change of a shape's fill or stroke colour, a
// `Color` view's colour, a foreground style (Text, symbols, implicit shape fills) or a stroke's line width interpolates with the layer's progress.
//
// Semantics (and what is measured, what is not):
// - SwiftUI animates a colour as its resolved components and an opacity (all four are interpolated, straight alpha, no premultiplication). A spring that
//   overshoots (progress above 1 or below 0) is clamped to 0...1 per component where it is drawn, so the components are clamped here.
// - UNMEASURED: whether the components are interpolated gamma-encoded or in linear light. `ColorInterpolation.space` is the single switch; the factory case
//   `paint-animated-v1` (factory/pipeline/sr2-effects) has a mid-frame whose two spaces differ by 55 levels per channel, so the first CI pair decides it.
// - Two `.rgba` colours interpolate per component. Two semantic colours of the same name interpolate their alpha. Any other pair (a different semantic colour,
//   or a semantic against an `rgba`) cannot be blended here (semantic names resolve in the host), so it takes the new colour as soon as the layer is past
//   progress 0. A spring settles on a colour change like an opacity-like value (`distance`).

/// The animatable paint of one node: its primary colour (a shape's explicit fill or stroke colour, a `Color` view's colour, else its foreground style) and the
/// line width of a stroke.
struct PaintValues: Equatable, Sendable {
    var color: ResolvedColor?
    var lineWidth: Double?

    static func mix(_ a: PaintValues?, _ b: PaintValues?, _ t: Double) -> PaintValues? {
        guard let a, let b else { return b }
        var out = b
        if let ca = a.color, let cb = b.color { out.color = ResolvedColor.interpolated(ca, cb, t) }
        if let wa = a.lineWidth, let wb = b.lineWidth { out.lineWidth = max(0, wa + (wb - wa) * t) }   // an overshooting spring never draws a negative width
        return out
    }

    /// How far a change of paint moves, for a spring's removal rule: the largest colour component change (0...1) or, for line width, points.
    static func distance(_ a: PaintValues?, _ b: PaintValues?) -> (color: Double, lineWidth: Double) {
        guard let a, let b else { return (0, 0) }
        var color = 0.0, width = 0.0
        if let ca = a.color, let cb = b.color { color = ResolvedColor.distance(ca, cb) }
        if let wa = a.lineWidth, let wb = b.lineWidth { width = abs(wb - wa) }
        return (color, width)
    }
}

enum ColorInterpolation {
    enum Space { case sRGB, linear }
    /// The space colour components are interpolated in (see the header: unmeasured, gamma-encoded until a CI pair says otherwise).
    static let space: Space = .sRGB

    static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    static func decode(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func encode(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    /// One component of `a` -> `b` at `t` in `space`, clamped to 0...1.
    static func mix(_ a: Double, _ b: Double, _ t: Double, in space: Space = ColorInterpolation.space) -> Double {
        let p = clamp(a), q = clamp(b)
        switch space {
        case .sRGB: return clamp(p + (q - p) * t)
        case .linear:
            let lp = decode(p), lq = decode(q)
            return clamp(encode(clamp(lp + (lq - lp) * t)))
        }
    }
}

extension ResolvedColor {
    /// (name, alpha) of a semantic colour, nil for an `rgba`.
    fileprivate var semanticParts: (name: String, alpha: Double)? {
        switch self {
        case .semantic(let name): return (name, 1)
        case .semanticAlpha(let name, let alpha): return (name, alpha)
        case .rgba: return nil
        }
    }

    /// `a` at `t` = 0 and `b` at `t` = 1 (beyond that a spring's overshoot, clamped); see the file header for the rules.
    static func interpolated(_ a: ResolvedColor, _ b: ResolvedColor, _ t: Double, in space: ColorInterpolation.Space = ColorInterpolation.space) -> ResolvedColor {
        if a == b { return b }
        if case .rgba(let r1, let g1, let b1, let a1) = a, case .rgba(let r2, let g2, let b2, let a2) = b {
            return .rgba(ColorInterpolation.mix(r1, r2, t, in: space), ColorInterpolation.mix(g1, g2, t, in: space), ColorInterpolation.mix(b1, b2, t, in: space),
                         ColorInterpolation.clamp(a1 + (a2 - a1) * t))
        }
        if let pa = a.semanticParts, let pb = b.semanticParts, pa.name == pb.name {
            let alpha = ColorInterpolation.clamp(pa.alpha + (pb.alpha - pa.alpha) * t)
            return alpha >= 1 ? .semantic(pa.name) : .semanticAlpha(pa.name, alpha)
        }
        return b
    }

    /// The largest component change from `a` to `b` (0...1) when the pair interpolates; 0 when it switches at once.
    static func distance(_ a: ResolvedColor, _ b: ResolvedColor) -> Double {
        if a == b { return 0 }
        if case .rgba(let r1, let g1, let b1, let a1) = a, case .rgba(let r2, let g2, let b2, let a2) = b {
            return max(abs(r2 - r1), abs(g2 - g1), abs(b2 - b1), abs(a2 - a1))
        }
        if let pa = a.semanticParts, let pb = b.semanticParts, pa.name == pb.name { return abs(pb.alpha - pa.alpha) }
        return 0
    }
}
