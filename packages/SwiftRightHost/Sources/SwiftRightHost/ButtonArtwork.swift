import Foundation
import SwiftRightRuntime

/// Our own vector model of SwiftUI's macOS `Button` push button (bordered, or prominent for `.borderedProminent` and the default button), light appearance: a flat
/// rounded rectangle whose corners follow a measured outline, in the enabled or the disabled fill. `.borderless` and `.plain` have no body. The label is the Button's child node and paints itself (grey when disabled, see
/// `ButtonMetrics`). Numbers come from `ButtonArtworkData` (`factory/tools/switch-artwork/derive_button_profile.py`); nothing of Apple's artwork is embedded.
public enum ButtonArtwork {
    static let samplesPerAxis = 8

    private struct Key: Hashable { let width: Int, height: Int, scale: Float, isEnabled: Bool, prominent: Bool, dark: Bool, tint: UInt32?, pressed: Bool, focused: Bool }
    nonisolated(unsafe) private static var cache: [Key: ContinuousRGBAImage] = [:]
    private static let cacheLock = NSLock()

    /// The fill colour of a state (0xRRGGBB) of the bordered (`.prominent == false`) or the prominent push button.
    public static func fillColor(isEnabled: Bool, prominent: Bool = false, dark: Bool = false) -> UInt32 {
        if dark {
            return prominent ? (isEnabled ? ButtonArtworkDark.prominentFill : ButtonArtworkDark.prominentFillDisabled) : (isEnabled ? ButtonArtworkDark.fill : ButtonArtworkDark.fillDisabled)
        }
        return prominent ? (isEnabled ? ButtonArtworkData.prominentFill : ButtonArtworkData.prominentFillDisabled)
                  : (isEnabled ? ButtonArtworkData.fill : ButtonArtworkData.fillDisabled)
    }

    // PRESSED AND FOCUSED (issue #60 pass 3). NOT MEASURED on macOS 27: a press cannot be held in a static capture, so these are estimates the `button-states` case will
    // measure on its first CI pair. The bordered body darkens (light) or lightens (dark) toward black or white; the prominent body darkens toward black. The focus ring is the
    // 3 pt focus-ring band around the body: the accent at half opacity, following the body's corner outline.
    /// How far a pressed body moves toward black (light bordered, prominent) or white (dark bordered), as a fraction.
    public static let pressedMix: Double = 0.098
    public static let pressedProminentMix: Double = 0.098
    /// The focus ring's width in points and its opacity (the accent, or the tint, at this alpha).
    public static let focusRingWidth: Double = 3
    public static let focusRingAlpha: UInt8 = 0x80

    /// `fill` (0xRRGGBB) as the pressed state draws it: mixed toward black in light mode, toward white in dark mode, for the bordered and the prominent body alike (measured on macOS 27,
    /// CI 39701531679 dark: bordered 48 -> 68, prominent (0,123,255) -> (25,136,255), both 9.8% toward white).
    public static func pressedColor(_ fill: UInt32, prominent: Bool, dark: Bool) -> UInt32 {
        let toward: Double = dark ? 255 : 0
        let f = prominent ? pressedProminentMix : pressedMix
        func channel(_ shift: UInt32) -> UInt32 {
            let c = Double(fill >> shift & 255)
            return UInt32(max(0, min(255, (c + (toward - c) * f).rounded())))
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }

    /// The focus ring's margin around the body, in device pixels (the image of a focused button is this much larger on every side).
    public static func focusRingPixels(scale: Float) -> Int { max(1, Int((focusRingWidth * Double(scale)).rounded())) }

    /// The label colour of a state (0xRRGGBB) of the bordered push button: the colour the Button's text takes.
    public static func labelColor(isEnabled: Bool, dark: Bool = false) -> UInt32 {
        dark ? (isEnabled ? ButtonArtworkDark.label : ButtonArtworkDark.labelDisabled) : (isEnabled ? ButtonArtworkData.label : ButtonArtworkData.labelDisabled)
    }

    /// The label colour a look gives its label, 0xRRGGBB, or nil when the label keeps the colour it gives itself (`.plain`, enabled).
    public static func labelColor(look: ButtonLook, isEnabled: Bool, dark: Bool = false) -> UInt32? {
        if dark {
            switch look {
            case .bordered: return labelColor(isEnabled: isEnabled, dark: true)
            case .prominent: return isEnabled ? ButtonArtworkDark.prominentLabel : ButtonArtworkDark.prominentLabelDisabled
            case .borderless: return isEnabled ? ButtonArtworkDark.borderlessLabel : ButtonArtworkDark.borderlessLabelDisabled
            case .plain: return isEnabled ? nil : ButtonArtworkDark.plainLabelDisabled
            }
        }
        switch look {
        case .bordered: return labelColor(isEnabled: isEnabled)
        case .prominent: return isEnabled ? ButtonArtworkData.prominentLabel : ButtonArtworkData.prominentLabelDisabled
        case .borderless: return isEnabled ? ButtonArtworkData.borderlessLabel : ButtonArtworkData.borderlessLabelDisabled
        case .plain: return isEnabled ? nil : ButtonArtworkData.plainLabelDisabled
        }
    }

    /// Straight-alpha RGBA of the button at `widthPX` x `heightPX` device pixels at `scale` pixels per point. Memoised per state and size.
    /// `tint` (0xRRGGBB, #54) replaces the accent of a prominent button's fill (`AccentTint`); it is ignored for the other looks. `pressed` darkens the body (an enabled button
    /// only); `focused` makes the image larger by `focusRingPixels(scale:)` on every side and draws the focus ring in that margin (the body keeps its place, offset by the margin).
    public static func render(widthPX: Int, heightPX: Int, scale: Float, isEnabled: Bool, prominent: Bool = false, dark: Bool = false, tint: UInt32? = nil,
                              pressed: Bool = false, focused: Bool = false) -> ContinuousRGBAImage {
        let tintForBody = prominent ? tint : nil
        let pressed = pressed && isEnabled
        let focused = focused && isEnabled
        let key = Key(width: widthPX, height: heightPX, scale: scale, isEnabled: isEnabled, prominent: prominent, dark: dark, tint: tint, pressed: pressed, focused: focused)
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[key] { return hit }
        let image = rasterize(widthPX: widthPX, heightPX: heightPX, scale: scale, isEnabled: isEnabled, prominent: prominent, dark: dark, tint: tintForBody, ringTint: tint,
                              pressed: pressed, focused: focused)
        cache[key] = image
        return image
    }

    private static func rasterize(widthPX: Int, heightPX: Int, scale: Float, isEnabled: Bool, prominent: Bool, dark: Bool, tint: UInt32?, ringTint: UInt32?,
                                  pressed: Bool, focused: Bool) -> ContinuousRGBAImage {
        let n = samplesPerAxis, total = Double(n * n)
        let pxPerPoint = Double(scale)
        let widthPt = Double(widthPX) / pxPerPoint, heightPt = Double(heightPX) / pxPerPoint
        let margin = focused ? focusRingPixels(scale: scale) : 0
        let outW = widthPX + 2 * margin, outH = heightPX + 2 * margin
        let marginPt = Double(margin) / pxPerPoint
        var fill = fillColor(isEnabled: isEnabled, prominent: prominent, dark: dark)
        if let tint { fill = AccentTint.remap(fill, accent: fillColor(isEnabled: true, prominent: true, dark: dark), to: tint) }
        if pressed { fill = pressedColor(fill, prominent: prominent, dark: dark) }
        let rgb = [UInt8(fill >> 16 & 255), UInt8(fill >> 8 & 255), UInt8(fill & 255)]
        let ringRGB = ringTint ?? AccentTint.accentLight
        let ring = [Double(ringRGB >> 16 & 255), Double(ringRGB >> 8 & 255), Double(ringRGB & 255)]
        // the ring is the body's outline grown by `marginPt`: a rounded rectangle of the body's corner radius plus the margin
        let radius = (ButtonArtworkData.corner.map { $0.x }.max() ?? 0) + marginPt
        func insideRing(_ x: Double, _ y: Double) -> Bool {
            let w = widthPt + 2 * marginPt, h = heightPt + 2 * marginPt
            guard x >= 0, x <= w, y >= 0, y <= h else { return false }
            let cx = min(max(x, radius), w - radius), cy = min(max(y, radius), h - radius)
            return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius
        }
        var rgba = [UInt8](repeating: 0, count: max(0, outW * outH * 4))
        for py in 0..<outH {
            for px in 0..<outW {
                var inside = 0, ringSamples = 0
                for sy in 0..<n {
                    let y = (Double(py) + (Double(sy) + 0.5) / Double(n)) / pxPerPoint
                    for sx in 0..<n {
                        let x = (Double(px) + (Double(sx) + 0.5) / Double(n)) / pxPerPoint
                        if SwitchArtwork.inside(ButtonArtworkData.corner, x: x - marginPt, y: y - marginPt, width: widthPt, height: heightPt) { inside += 1 }
                        else if focused, insideRing(x, y) { ringSamples += 1 }
                    }
                }
                guard inside > 0 || ringSamples > 0 else { continue }
                let o = (py * outW + px) * 4
                let bodyAlpha = Double(inside) / total
                guard ringSamples > 0 else {
                    rgba[o] = rgb[0]; rgba[o + 1] = rgb[1]; rgba[o + 2] = rgb[2]
                    rgba[o + 3] = UInt8(max(0, min(255, (bodyAlpha * 255).rounded())))
                    continue
                }
                // body and ring cover disjoint parts of the pixel: their alphas add and the colour is the alpha-weighted mix
                let ringAlpha = Double(ringSamples) / total * Double(focusRingAlpha) / 255
                let alpha = bodyAlpha + ringAlpha
                for c in 0..<3 { rgba[o + c] = UInt8(max(0, min(255, ((Double(rgb[c]) * bodyAlpha + ring[c] * ringAlpha) / alpha).rounded()))) }
                rgba[o + 3] = UInt8(max(0, min(255, (alpha * 255).rounded())))
            }
        }
        return ContinuousRGBAImage(width: outW, height: outH, rgba: rgba)
    }
}


/// The dark appearance of the push button (round 5 block 36, decision F13): flat colours measured on macOS 27 in a darkAqua window at scale 2.5
/// (`factory/pipeline/blocks-26-34/swiftui.button-dark`); the corner outline is the light one (the shape does not change). The prominent fill is the same accent.
enum ButtonArtworkDark {
    static let fill: UInt32 = 0x303030
    static let fillDisabled: UInt32 = 0x262626
    static let label: UInt32 = 0xdfdfdf
    static let labelDisabled: UInt32 = 0x5c5c5c
    static let prominentFill: UInt32 = 0x007bff
    static let prominentFillDisabled: UInt32 = 0x095db9
    static let prominentLabel: UInt32 = 0xffffff
    static let prominentLabelDisabled: UInt32 = 0x84aedc
    static let borderlessLabel: UInt32 = 0x9a9a9a
    static let borderlessLabelDisabled: UInt32 = 0x565656
    static let plainLabelDisabled: UInt32 = 0x7d7d7d
}
