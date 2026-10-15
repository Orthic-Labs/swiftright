import Foundation
import SwiftRightRuntime

/// Our own vector model of SwiftUI's macOS `Button` push button (bordered, or prominent for `.borderedProminent` and the default button), light appearance: a flat
/// rounded rectangle whose corners follow a measured outline, in the enabled or the disabled fill. `.borderless` and `.plain` have no body. The label is the Button's child node and paints itself (grey when disabled, see
/// `ButtonMetrics`). Numbers come from `ButtonArtworkData` (`factory/tools/switch-artwork/derive_button_profile.py`); nothing of Apple's artwork is embedded.
public enum ButtonArtwork {
    static let samplesPerAxis = 8

    private struct Key: Hashable { let width: Int, height: Int, scale: Float, isEnabled: Bool, prominent: Bool, dark: Bool }
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
    public static func render(widthPX: Int, heightPX: Int, scale: Float, isEnabled: Bool, prominent: Bool = false, dark: Bool = false) -> ContinuousRGBAImage {
        let key = Key(width: widthPX, height: heightPX, scale: scale, isEnabled: isEnabled, prominent: prominent, dark: dark)
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[key] { return hit }
        let image = rasterize(widthPX: widthPX, heightPX: heightPX, scale: scale, isEnabled: isEnabled, prominent: prominent, dark: dark)
        cache[key] = image
        return image
    }

    private static func rasterize(widthPX: Int, heightPX: Int, scale: Float, isEnabled: Bool, prominent: Bool, dark: Bool) -> ContinuousRGBAImage {
        let n = samplesPerAxis, total = Double(n * n)
        let pxPerPoint = Double(scale)
        let widthPt = Double(widthPX) / pxPerPoint, heightPt = Double(heightPX) / pxPerPoint
        let fill = fillColor(isEnabled: isEnabled, prominent: prominent, dark: dark)
        let rgb = [UInt8(fill >> 16 & 255), UInt8(fill >> 8 & 255), UInt8(fill & 255)]
        var rgba = [UInt8](repeating: 0, count: max(0, widthPX * heightPX * 4))
        for py in 0..<heightPX {
            for px in 0..<widthPX {
                var inside = 0
                for sy in 0..<n {
                    let y = (Double(py) + (Double(sy) + 0.5) / Double(n)) / pxPerPoint
                    for sx in 0..<n {
                        let x = (Double(px) + (Double(sx) + 0.5) / Double(n)) / pxPerPoint
                        if SwitchArtwork.inside(ButtonArtworkData.corner, x: x, y: y, width: widthPt, height: heightPt) { inside += 1 }
                    }
                }
                guard inside > 0 else { continue }
                let o = (py * widthPX + px) * 4
                rgba[o] = rgb[0]; rgba[o + 1] = rgb[1]; rgba[o + 2] = rgb[2]
                rgba[o + 3] = UInt8(max(0, min(255, (Double(inside) / total * 255).rounded())))
            }
        }
        return ContinuousRGBAImage(width: widthPX, height: heightPX, rgba: rgba)
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
