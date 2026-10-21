import Foundation
import SwiftRightRuntime

/// Issue #54: `.tint(_:)` on controls. The measured control artwork is drawn in the accent colour (and, in the disabled states, accent mixed with white); a tint
/// replaces that accent. The mixing is kept: a measured state colour that is the accent mixed toward white or toward black by some fraction is the tint mixed by
/// the same fraction. A colour that is not on either line (a grey knob, a track) is not accent and stays. The label colours are not touched (a prominent
/// Button's label stays white).
///
/// MEASURED (CI 39579395357, macOS 27, `tint-controls-v1`, `.tint(.red)` = 255/56/60): a prominent Button fill and a ProgressView fill are the tint itself, exactly.
/// A Switch track, a Checkbox box and a Slider fill are the tint darkened by 2.35 %: 249/55/59, the same shade their measured accent artwork has against the accent
/// itself (0x0078f9 against the prominent Button's 0x007bff; dark 0x067eff against 0x007bff: lightened by 2.3 %). `shaded` carries that shade over to the tint.
/// The mix tolerance below is the only fitted number.
public enum AccentTint {
    /// Channel difference (0...1 of the mix fraction) the channels may disagree by and still be one mix.
    static let tolerance = 0.03

    /// 0xRRGGBB of the tint a node carries, nil when it has none (or its colour is not a plain RGB).
    public static func rgb(of node: ResolvedNode) -> UInt32? {
        guard let tint = node.tint, let rgba = try? HostPaint.rgba(tint, opacity: 1, scheme: node.style.colorScheme) else { return nil }
        return rgba >> 8
    }

    /// The accent itself, as the prominent push button's flat fill (light and dark are the same colour): what the other artwork's accent shades are measured against.
    static let accentLight: UInt32 = 0x007bff
    static let accentDark: UInt32 = 0x007bff

    /// `colour` (0xRRGGBB) with `accent` replaced by `tint`: see the type's comment. `colour` itself when it is not accent mixed with white or black.
    public static func remap(_ colour: UInt32, accent: UInt32, to tint: UInt32) -> UInt32 {
        let p = channels(colour), a = channels(accent), t = channels(tint)
        // Both lines can accept a colour that is within a level of the accent (0x0078f9 reads as the accent lightened by nothing, or darkened by 2.4 %): the closer one wins.
        let white = fraction(p, from: a, toward: 255).map { (f: $0, error: error(p, a, toward: 255, $0)) }
        let black = fraction(p, from: a, toward: 0).map { (f: $0, error: error(p, a, toward: 0, $0)) }
        switch (white, black) {
        case (nil, nil): return colour
        case (let w?, let k?) where k.error < w.error: return pack(t.map { $0 * (1 - k.f) })
        case (let w?, _): return pack(zip(t, [255, 255, 255]).map { $0 + ($1 - $0) * w.f })
        case (nil, let k?): return pack(t.map { $0 * (1 - k.f) })
        }
    }

    /// The tint an artwork whose own accent colour is `artworkAccent` (a switch track, a checkbox box, a slider fill) is drawn in: the tint shaded the way `artworkAccent`
    /// is shaded against the accent itself. The tint unchanged when `artworkAccent` is not a mix of the accent.
    public static func shaded(tint: UInt32, artworkAccent: UInt32, dark: Bool) -> UInt32 {
        let shaded = remap(artworkAccent, accent: dark ? accentDark : accentLight, to: tint)
        return shaded == artworkAccent ? tint : shaded
    }

    private static func error(_ p: [Double], _ a: [Double], toward end: Double, _ f: Double) -> Double {
        (0..<3).map { abs(p[$0] - (a[$0] + (end - a[$0]) * f)) }.max() ?? 0
    }

    /// The fraction `f` (0...1) with `p = a + (end - a) f` on every channel that has room to tell (|end - a| >= 16), or nil when the channels disagree.
    private static func fraction(_ p: [Double], from a: [Double], toward end: Double) -> Double? {
        var values: [Double] = []
        for c in 0..<3 where abs(end - a[c]) >= 16 { values.append((p[c] - a[c]) / (end - a[c])) }
        guard let lo = values.min(), let hi = values.max(), hi - lo <= tolerance, lo >= -tolerance, hi <= 1 + tolerance else { return nil }
        // channels with no room must agree with the mix as well (within a level or two)
        let f = min(max((lo + hi) / 2, 0), 1)
        for c in 0..<3 where abs(end - a[c]) < 16 { guard abs(p[c] - (a[c] + (end - a[c]) * f)) <= 4 else { return nil } }
        return f
    }

    private static func channels(_ rgb: UInt32) -> [Double] { [Double(rgb >> 16 & 255), Double(rgb >> 8 & 255), Double(rgb & 255)] }
    private static func pack(_ c: [Double]) -> UInt32 {
        func b(_ v: Double) -> UInt32 { UInt32(min(max(v.rounded(), 0), 255)) }
        return b(c[0]) << 16 | b(c[1]) << 8 | b(c[2])
    }

    /// The accent artwork colour of one state, for tests and the painters: `state` re-tinted.
    public static func apply(_ state: UInt32, accent: UInt32, tint: UInt32?) -> UInt32 {
        guard let tint else { return state }
        return remap(state, accent: accent, to: tint)
    }
}
