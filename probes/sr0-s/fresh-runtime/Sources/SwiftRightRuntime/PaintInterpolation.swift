import Foundation

// Issue #54 (SR2): paint interpolation. A node's paint is a presented channel like its frame: an animated change of a shape's fill or stroke colour, a
// `Color` view's colour, a foreground style (Text, symbols, implicit shape fills) or a stroke's line width interpolates with the layer's progress.
//
// Semantics (and what is measured, what is not):
// - SwiftUI animates a colour as its resolved components and an opacity (all four are interpolated, straight alpha, no premultiplication). A spring that
//   overshoots (progress above 1 or below 0) is clamped to 0...1 per component where it is drawn, so the components are clamped here.
// - MEASURED (CI 39579395357, macOS 27, paint-colour-v1): the components are interpolated in Oklab (the space SwiftUI's Gradient also uses on macOS 26+), not
//   gamma-encoded and not in linear light. Red 255/51/51 to blue 51/102/255 at progress 0.25 / 0.5 / 0.75 reads 212/90/119, 167/106/167, 118/109/212 on the Mac;
//   Oklab reproduces all nine channel values exactly (gamma gives 204/64/102 ... 153/77/153, linear light 226/68/143 ... 190/81/190). Alpha stays straight and linear.
//   `ColorInterpolation.space` is the single switch.
// - Two `.rgba` colours interpolate per component. Two semantic colours of the same name interpolate their alpha. Any other pair (a different semantic colour,
//   or a semantic against an `rgba`) cannot be blended here (semantic names resolve in the host), so it takes the new colour as soon as the layer is past
//   progress 0. A spring settles on a colour change like an opacity-like value (`distance`).

/// The animatable paint of one node: its primary colour (a shape's explicit fill or stroke colour, a `Color` view's colour, else its foreground style) and the
/// line width of a stroke.
struct PaintValues: Equatable, Sendable {
    var color: ResolvedColor?
    var lineWidth: Double?
    /// A Text under `.contentTransition(.numericText())`: the number of text changes it has seen. An animated change moves this by one, so its presented value
    /// between the two counts is the progress of the digit roll (`NumericTextRoll.swift`). Nil on every other node.
    var roll: Double?

    init(color: ResolvedColor?, lineWidth: Double?, roll: Double? = nil) { self.color = color; self.lineWidth = lineWidth; self.roll = roll }

    static func mix(_ a: PaintValues?, _ b: PaintValues?, _ t: Double) -> PaintValues? {
        guard let a, let b else { return b }
        var out = b
        if let ra = a.roll, let rb = b.roll { out.roll = ra + (rb - ra) * t }
        if let ca = a.color, let cb = b.color { out.color = ResolvedColor.interpolated(ca, cb, t) }
        if let wa = a.lineWidth, let wb = b.lineWidth { out.lineWidth = max(0, wa + (wb - wa) * t) }   // an overshooting spring never draws a negative width
        return out
    }

    /// How far a change of paint moves, for a spring's removal rule: the largest colour component change (0...1) or, for line width, points.
    static func distance(_ a: PaintValues?, _ b: PaintValues?) -> (color: Double, lineWidth: Double) {
        guard let a, let b else { return (0, 0) }
        var color = 0.0, width = 0.0
        if let ra = a.roll, let rb = b.roll { color = abs(rb - ra) }   // a roll settles like a unit change of an opacity-like value
        if let ca = a.color, let cb = b.color { color = max(color, ResolvedColor.distance(ca, cb)) }
        if let wa = a.lineWidth, let wb = b.lineWidth { width = abs(wb - wa) }
        return (color, width)
    }
}

enum ColorInterpolation {
    enum Space { case sRGB, linear, oklab }
    /// The space colour components are interpolated in (see the header: Oklab, measured against a macOS 27 capture).
    static let space: Space = .oklab

    static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    static func decode(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func encode(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    /// One component of `a` -> `b` at `t` in `space`, clamped to 0...1.
    static func mix(_ a: Double, _ b: Double, _ t: Double, in space: Space = ColorInterpolation.space) -> Double {
        let p = clamp(a), q = clamp(b)
        switch space {
        case .sRGB, .oklab: return clamp(p + (q - p) * t)   // Oklab mixes three channels together: `mixRGB`
        case .linear:
            let lp = decode(p), lq = decode(q)
            return clamp(encode(clamp(lp + (lq - lp) * t)))
        }
    }
}

extension ColorInterpolation {
    /// (r, g, b) of `a` -> `b` at `t` in `space`, each 0...1. Oklab (Ottosson, 2020) is a joint transform, so its three channels are mixed together; the others per channel.
    static func mixRGB(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double, in space: Space) -> (Double, Double, Double) {
        guard space == .oklab else {
            return (mix(a.0, b.0, t, in: space), mix(a.1, b.1, t, in: space), mix(a.2, b.2, t, in: space))
        }
        let la = oklab(a), lb = oklab(b)
        return fromOklab((la.0 + (lb.0 - la.0) * t, la.1 + (lb.1 - la.1) * t, la.2 + (lb.2 - la.2) * t))
    }

    static func oklab(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        let r = decode(clamp(c.0)), g = decode(clamp(c.1)), b = decode(clamp(c.2))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// Back to gamma-encoded sRGB, each channel clamped to 0...1 (a mix can leave the gamut, and an overshooting spring leaves it further).
    static func fromOklab(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        let l = c.0 + 0.3963377774 * c.1 + 0.2158037573 * c.2
        let m = c.0 - 0.1055613458 * c.1 - 0.0638541728 * c.2
        let s = c.0 - 0.0894841775 * c.1 - 1.2914855480 * c.2
        let l3 = l * l * l, m3 = m * m * m, s3 = s * s * s
        return (encode(clamp(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3)),
                encode(clamp(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3)),
                encode(clamp(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)))
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
            let rgb = ColorInterpolation.mixRGB((r1, g1, b1), (r2, g2, b2), t, in: space)
            return .rgba(rgb.0, rgb.1, rgb.2, ColorInterpolation.clamp(a1 + (a2 - a1) * t))
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
