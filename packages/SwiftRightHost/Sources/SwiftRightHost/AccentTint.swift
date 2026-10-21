import Foundation
import SwiftRightRuntime

/// Issue #54: `.tint(_:)` on controls. The measured control artwork is drawn in the accent colour (and, in the disabled states, accent mixed with white); a tint
/// replaces that accent. The mixing is kept: a measured state colour that is the accent mixed toward white or toward black by some fraction is the tint mixed by
/// the same fraction. A colour that is not on either line (a grey knob, a track) is not accent and stays. The label colours are not touched (a prominent
/// Button's label stays white).
///
/// UNMEASURED: the artwork was measured with the accent only. A Mac pair of a tinted prominent Button, Toggle and Slider (factory case `tint-controls-v1`) is
/// what confirms the rule; the mix tolerance below is the only fitted number.
public enum AccentTint {
    /// Channel difference (0...1 of the mix fraction) the channels may disagree by and still be one mix.
    static let tolerance = 0.03

    /// 0xRRGGBB of the tint a node carries, nil when it has none (or its colour is not a plain RGB).
    public static func rgb(of node: ResolvedNode) -> UInt32? {
        guard let tint = node.tint, let rgba = try? HostPaint.rgba(tint, opacity: 1, scheme: node.style.colorScheme) else { return nil }
        return rgba >> 8
    }

    /// `colour` (0xRRGGBB) with `accent` replaced by `tint`: see the type's comment. `colour` itself when it is not accent mixed with white or black.
    public static func remap(_ colour: UInt32, accent: UInt32, to tint: UInt32) -> UInt32 {
        let p = channels(colour), a = channels(accent), t = channels(tint)
        if let w = fraction(p, from: a, toward: 255) { return pack(zip(t, [255, 255, 255]).map { $0 + ($1 - $0) * w }) }
        if let k = fraction(p, from: a, toward: 0) { return pack(t.map { $0 * (1 - k) }) }
        return colour
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
