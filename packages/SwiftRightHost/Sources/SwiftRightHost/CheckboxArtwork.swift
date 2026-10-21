import Foundation
import SwiftRightRuntime

/// Our own vector model of SwiftUI's macOS default Toggle, a checkbox (`.toggleStyle(.automatic)` / `.checkbox`), light appearance: a 16 x 16 pt
/// rounded square (measured continuous-corner outline) in a flat state colour, and for the on state a white check mark of two tapered round-capped strokes
/// made of two round-capped strokes. Disabled controls use lighter colours and a grey check. Numbers come from `CheckboxArtworkData`
/// (`factory/tools/switch-artwork/derive_checkbox_profile.py`); nothing of Apple's artwork is embedded.
public enum CheckboxArtwork {
    public static let side = 16.0
    static let samplesPerAxis = 8

    private struct Key: Hashable { let width: Int, height: Int, isOn: Bool, isEnabled: Bool, dark: Bool, tint: UInt32? }
    nonisolated(unsafe) private static var cache: [Key: ContinuousRGBAImage] = [:]
    private static let cacheLock = NSLock()

    /// Straight-alpha RGBA of the checkbox at `widthPX` x `heightPX` device pixels (the control's frame in pixels). Memoised per state and size.
    /// `tint` (0xRRGGBB, #54) replaces the accent of the checked box (`AccentTint`).
    public static func render(widthPX: Int, heightPX: Int, isOn: Bool, isEnabled: Bool, scheme: ColorScheme = .light, tint: UInt32? = nil) -> ContinuousRGBAImage {
        let tint = isOn ? tint : nil
        let key = Key(width: widthPX, height: heightPX, isOn: isOn, isEnabled: isEnabled, dark: scheme == .dark, tint: tint)
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[key] { return hit }
        let image = rasterize(widthPX: widthPX, heightPX: heightPX, isOn: isOn, isEnabled: isEnabled, dark: scheme == .dark, tint: tint)
        cache[key] = image
        return image
    }

    /// The box colour for a state (0xRRGGBB).
    public static func boxColor(isOn: Bool, isEnabled: Bool, scheme: ColorScheme = .light) -> UInt32 {
        if scheme == .dark {
            switch (isOn, isEnabled) {
            case (true, true): return ToggleDarkData.boxOn
            case (false, true): return ToggleDarkData.boxOff
            case (true, false): return ToggleDarkData.boxOnDisabled
            case (false, false): return ToggleDarkData.boxOffDisabled
            }
        }
        switch (isOn, isEnabled) {
        case (true, true): return CheckboxArtworkData.boxOn
        case (false, true): return CheckboxArtworkData.boxOff
        case (true, false): return CheckboxArtworkData.boxOnDisabled
        case (false, false): return CheckboxArtworkData.boxOffDisabled
        }
    }

    /// Signed distance from (x, y) to a tapered round-capped stroke from (ax, ay) with radius ra to (bx, by) with radius rb.
    private static func strokeDistance(_ x: Double, _ y: Double, _ s: [Double]) -> Double {
        let dx = s[2] - s[0], dy = s[3] - s[1]
        let l = dx * dx + dy * dy
        let t = l > 0 ? max(0, min(1, ((x - s[0]) * dx + (y - s[1]) * dy) / l)) : 0
        return hypot(x - (s[0] + t * dx), y - (s[1] + t * dy)) - (s[4] + (s[5] - s[4]) * t)
    }

    private static func rasterize(widthPX: Int, heightPX: Int, isOn: Bool, isEnabled: Bool, dark: Bool = false, tint: UInt32? = nil) -> ContinuousRGBAImage {
        let n = samplesPerAxis, total = Double(n * n)
        let pxPerPointX = Double(widthPX) / side, pxPerPointY = Double(heightPX) / side
        var box = boxColor(isOn: isOn, isEnabled: isEnabled, scheme: dark ? .dark : .light)
        if let tint { let accent = boxColor(isOn: true, isEnabled: true, scheme: dark ? .dark : .light)
            box = AccentTint.remap(box, accent: accent, to: AccentTint.shaded(tint: tint, artworkAccent: accent, dark: dark)) }
        let checkColour = dark ? (isEnabled ? ToggleDarkData.checkOn : ToggleDarkData.checkOnDisabled) : (isEnabled ? CheckboxArtworkData.checkOn : CheckboxArtworkData.checkOnDisabled)
        let boxRGB = [Double(box >> 16 & 255), Double(box >> 8 & 255), Double(box & 255)]
        let checkRGB = [Double(checkColour >> 16 & 255), Double(checkColour >> 8 & 255), Double(checkColour & 255)]
        let strokes = CheckboxArtworkData.checkStrokes
        var rgba = [UInt8](repeating: 0, count: widthPX * heightPX * 4)
        for py in 0..<heightPX {
            for px in 0..<widthPX {
                var inside = 0, checked = 0
                for sy in 0..<n {
                    let y = (Double(py) + (Double(sy) + 0.5) / Double(n)) / pxPerPointY
                    for sx in 0..<n {
                        let x = (Double(px) + (Double(sx) + 0.5) / Double(n)) / pxPerPointX
                        guard SwitchArtwork.inside(CheckboxArtworkData.corner, x: x, y: y, width: side, height: side) else { continue }
                        inside += 1
                        if isOn {
                            if strokes.contains(where: { strokeDistance(x, y, $0) <= 0 }) { checked += 1 }
                        }
                    }
                }
                guard inside > 0 else { continue }
                let o = (py * widthPX + px) * 4
                for k in 0..<3 { rgba[o + k] = UInt8(max(0, min(255, ((boxRGB[k] * Double(inside - checked) + checkRGB[k] * Double(checked)) / Double(inside)).rounded()))) }
                rgba[o + 3] = UInt8(max(0, min(255, (Double(inside) / total * 255).rounded())))
            }
        }
        return ContinuousRGBAImage(width: widthPX, height: heightPX, rgba: rgba)
    }
}
