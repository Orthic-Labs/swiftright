import Foundation
import SwiftRightRuntime

/// Our own vector model of SwiftUI's macOS switch (`Toggle` with `.toggleStyle(.switch)`), light appearance. Windows has no SF switch
/// artwork and Apple's is not redistributable, so the switch is drawn from geometry and colours we measured from SwiftUI renders
/// (`factory/tools/switch-artwork/derive_switch_profile.py` produces `SwitchArtworkData`; decision 4 of docs/sr1-decisions.md).
///
/// Anatomy, in points (the control is 54 x 24, `ToggleArtwork.switchControl`):
///   - a track filling the control, ends are the measured continuous-corner caps (rounder than a circle near the tip, flat tail);
///   - a white 32 x 20 knob inset 2 pt, at the trailing end when on and the leading end when off;
///   - a soft shadow the knob casts on the track: the track colour darkened by `shadowStrength` at the knob's edge, falling off cubically
///     over `shadowReach` points, with the knob's shadow lifted `shadowLift` points above the knob.
/// A disabled switch uses lighter track colours and covers the track edge a little less (`disabledEdgeCoverage`).
public enum SwitchArtwork {
    public static let controlWidth = 54.0, controlHeight = 24.0
    static let knobWidth = 32.0, knobHeight = 20.0, knobInset = 2.0
    static let shadowStrength = 0.0562, shadowReach = 4.5, shadowLift = 0.75
    static let samplesPerAxis = 8

    private struct Key: Hashable { let width: Int, height: Int, isOn: Bool, isEnabled: Bool, dark: Bool, tint: UInt32? }
    nonisolated(unsafe) private static var cache: [Key: ContinuousRGBAImage] = [:]
    private static let cacheLock = NSLock()

    /// Straight-alpha RGBA of the switch at `widthPX` x `heightPX` device pixels (the control's frame in pixels). Memoised per state and size.
    /// `tint` (0xRRGGBB, #54) replaces the accent of the on track (`AccentTint`).
    public static func render(widthPX: Int, heightPX: Int, isOn: Bool, isEnabled: Bool, scheme: ColorScheme = .light, tint: UInt32? = nil) -> ContinuousRGBAImage {
        let tint = isOn ? tint : nil
        let key = Key(width: widthPX, height: heightPX, isOn: isOn, isEnabled: isEnabled, dark: scheme == .dark, tint: tint)
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[key] { return hit }
        let image = rasterize(widthPX: widthPX, heightPX: heightPX, isOn: isOn, isEnabled: isEnabled, dark: scheme == .dark, tint: tint)
        cache[key] = image
        return image
    }

    /// The track colour for a state (0xRRGGBB).
    public static func trackColor(isOn: Bool, isEnabled: Bool, scheme: ColorScheme = .light) -> UInt32 {
        if scheme == .dark {
            switch (isOn, isEnabled) {
            case (true, true): return ToggleDarkData.trackOn
            case (false, true): return ToggleDarkData.trackOff
            case (true, false): return ToggleDarkData.trackOnDisabled
            case (false, false): return ToggleDarkData.trackOffDisabled
            }
        }
        switch (isOn, isEnabled) {
        case (true, true): return SwitchArtworkData.trackOn
        case (false, true): return SwitchArtworkData.trackOff
        case (true, false): return SwitchArtworkData.trackOnDisabled
        case (false, false): return SwitchArtworkData.trackOffDisabled
        }
    }

    /// Where the knob's left end sits in the control, in points.
    public static func knobOriginX(isOn: Bool) -> Double { isOn ? controlWidth - knobInset - knobWidth : knobInset }

    // MARK: Rasteriser

    /// Height of the cap above a column at distance `x` points from the end of the shape (0 once the cap has merged into the straight edge).
    static func capTop(_ cap: [(x: Double, y: Double)], _ x: Double) -> Double {
        guard let first = cap.first, let last = cap.last else { return 0 }
        if x >= last.x { return 0 }
        if x <= first.x { return first.y }
        var lo = 0, hi = cap.count - 1
        while hi - lo > 1 { let mid = (lo + hi) / 2; if cap[mid].x <= x { lo = mid } else { hi = mid } }
        let a = cap[lo], b = cap[hi]
        return b.x > a.x ? a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x) : a.y
    }

    static func inside(_ cap: [(x: Double, y: Double)], x: Double, y: Double, width: Double, height: Double) -> Bool {
        guard x >= 0, x <= width, y >= 0, y <= height else { return false }
        let top = capTop(cap, min(x, width - x))
        return y >= top && y <= height - top
    }

    /// Signed distance from (x, y) to a pill (stadium) with its top-left corner at (x0, y0).
    static func pillDistance(x: Double, y: Double, x0: Double, y0: Double, width: Double, height: Double) -> Double {
        let r = height / 2
        let cx = min(max(x, x0 + r), x0 + width - r)
        return hypot(x - cx, y - (y0 + r)) - r
    }

    static func disabledCoverage(_ coverage: Double) -> Double {
        let curve = SwitchArtworkData.disabledEdgeCoverage
        for i in 1..<curve.count where coverage <= curve[i].enabled {
            let a = curve[i - 1], b = curve[i]
            return a.disabled + (b.disabled - a.disabled) * (coverage - a.enabled) / (b.enabled - a.enabled)
        }
        return coverage
    }

    private static func rasterize(widthPX: Int, heightPX: Int, isOn: Bool, isEnabled: Bool, dark: Bool = false, tint: UInt32? = nil) -> ContinuousRGBAImage {
        let n = samplesPerAxis, total = Double(n * n)
        let pxPerPointX = Double(widthPX) / controlWidth, pxPerPointY = Double(heightPX) / controlHeight
        let knobX = knobOriginX(isOn: isOn)
        var base = trackColor(isOn: isOn, isEnabled: isEnabled, scheme: dark ? .dark : .light)
        if let tint { let accent = trackColor(isOn: true, isEnabled: true, scheme: dark ? .dark : .light)
            base = AccentTint.remap(base, accent: accent, to: AccentTint.shaded(tint: tint, artworkAccent: accent, dark: dark)) }
        // dark: the knob is white at `knobAlpha` over the track, so it is a blend INSIDE the track; light: an opaque white knob over the track
        let knobAlpha = dark ? ToggleDarkData.knobAlpha : 1.0
        let strength = dark ? ToggleDarkData.shadowStrength : shadowStrength
        let knobCap = dark ? ToggleDarkData.knobCap : SwitchArtworkData.knobCap
        let baseRGB = [Double(base >> 16 & 255), Double(base >> 8 & 255), Double(base & 255)]
        var rgba = [UInt8](repeating: 0, count: widthPX * heightPX * 4)
        for py in 0..<heightPX {
            for px in 0..<widthPX {
                var trackSamples = 0, knobSamples = 0
                var colour = [0.0, 0.0, 0.0]
                for sy in 0..<n {
                    let y = (Double(py) + (Double(sy) + 0.5) / Double(n)) / pxPerPointY
                    for sx in 0..<n {
                        let x = (Double(px) + (Double(sx) + 0.5) / Double(n)) / pxPerPointX
                        guard inside(SwitchArtworkData.trackCap, x: x, y: y, width: controlWidth, height: controlHeight) else { continue }
                        if inside(knobCap, x: x - knobX, y: y - knobInset, width: knobWidth, height: knobHeight) {
                            if knobAlpha < 1 {
                                trackSamples += 1
                                for c in 0..<3 { colour[c] += 255 * knobAlpha + baseRGB[c] * (1 - knobAlpha) }
                            } else {
                                knobSamples += 1
                            }
                            continue
                        }
                        trackSamples += 1
                        let d = max(0, pillDistance(x: x, y: y + shadowLift, x0: knobX, y0: knobInset, width: knobWidth, height: knobHeight))
                        let falloff = 1 - min(1, d / shadowReach)
                        let shade = 1 - strength * falloff * falloff * falloff
                        for c in 0..<3 { colour[c] += baseRGB[c] * shade }
                    }
                }
                guard trackSamples + knobSamples > 0 else { continue }
                var trackCoverage = Double(trackSamples + knobSamples) / total
                if !isEnabled { trackCoverage = disabledCoverage(trackCoverage) }
                let knobCoverage = Double(knobSamples) / total
                let trackColour = trackSamples > 0 ? colour.map { $0 / Double(trackSamples) } : baseRGB
                // knob (white) over track, as premultiplied sums, then un-premultiplied
                let alpha = knobCoverage + trackCoverage * (1 - knobCoverage)
                guard alpha > 0 else { continue }
                let o = (py * widthPX + px) * 4
                for c in 0..<3 {
                    let premultiplied = 255 * knobCoverage + trackColour[c] * trackCoverage * (1 - knobCoverage)
                    rgba[o + c] = UInt8(max(0, min(255, (premultiplied / alpha).rounded())))
                }
                rgba[o + 3] = UInt8(max(0, min(255, (alpha * 255).rounded())))
            }
        }
        return ContinuousRGBAImage(width: widthPX, height: heightPX, rgba: rgba)
    }
}
