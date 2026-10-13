import Foundation
import SwiftRightRuntime

/// Our own vector model of the bezel of a SwiftUI `TextField` on macOS (`.automatic`, `.roundedBorder` and `.squareBorder` draw the same
/// pixels), light appearance, measured from an offscreen `NSHostingView` at scale 2.5 (`factory/pipeline/blocks-6-10/swiftui.textfield/FACTS.md`).
/// The field frame is a 6 pt corner-radius rounded rectangle filled white at 98% opacity; a 1 pt border of black at 15% opacity is drawn
/// OUTSIDE the frame (outer corner radius 7 pt). A least-squares fit of those numbers to the measured corner reproduces it to 0.5 grey levels.
/// Nothing of Apple's artwork is embedded; coverage is computed here.
public enum TextFieldArtwork {
    public static let cornerRadius = 6.0
    public static let borderWidth = 1.0
    public static let borderAlpha = 0.15
    public static let fillAlpha = 0.98

    /// The bezel as straight-alpha RGBA: `image` covers the frame plus `pad` device pixels on every side (the border lies outside the frame).
    public struct Bezel: Equatable, Sendable {
        public let image: ContinuousRGBAImage
        public let pad: Int
    }

    private struct Key: Hashable { let width: Int, height: Int, scale: Double, dark: Bool }
    nonisolated(unsafe) private static var cache: [Key: Bezel] = [:]
    private static let cacheLock = NSLock()

    public static func render(widthPX: Int, heightPX: Int, scale: Double, scheme: ColorScheme = .light) -> Bezel {
        let key = Key(width: widthPX, height: heightPX, scale: scale, dark: scheme == .dark)
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[key] { return hit }
        let bezel = rasterize(widthPX: widthPX, heightPX: heightPX, scale: scale, dark: scheme == .dark)
        if cache.count > 64 { cache.removeAll() }
        cache[key] = bezel
        return bezel
    }

    /// Signed distance (px, negative inside) from (x, y) to the rounded rectangle [x0, x1] x [y0, y1] with corner radius `r`.
    static func signedDistance(_ x: Double, _ y: Double, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ r: Double) -> Double {
        let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
        let hx = (x1 - x0) / 2 - r, hy = (y1 - y0) / 2 - r
        let qx = abs(x - cx) - hx, qy = abs(y - cy) - hy
        return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    }

    private static func rasterize(widthPX: Int, heightPX: Int, scale: Double, dark: Bool) -> Bezel {
        let border = borderWidth * scale, rInner = cornerRadius * scale, rOuter = rInner + border
        let pad = Int(border.rounded(.up))
        let width = widthPX + 2 * pad, height = heightPX + 2 * pad
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        // Light: white fill and black border. (Dark appearance is not measured; it is painted as light, a known gap.)
        let samples = 4
        func coverage(_ px: Int, _ py: Int, _ inside: (Double, Double) -> Double) -> Double {
            // Exact enough: signed-distance coverage at the pixel centre, refined by a 4 x 4 grid only on the boundary.
            let d = inside(Double(px) + 0.5, Double(py) + 0.5)
            if d < -1 { return 1 }
            if d > 1 { return 0 }
            var hit = 0
            for sy in 0..<samples { for sx in 0..<samples {
                if inside(Double(px) + (Double(sx) + 0.5) / Double(samples), Double(py) + (Double(sy) + 0.5) / Double(samples)) <= 0 { hit += 1 }
            } }
            return Double(hit) / Double(samples * samples)
        }
        let px0 = Double(pad), py0 = Double(pad), px1 = px0 + Double(widthPX), py1 = py0 + Double(heightPX)
        let outer = { (x: Double, y: Double) in signedDistance(x, y, px0 - border, py0 - border, px1 + border, py1 + border, rOuter) }
        let inner = { (x: Double, y: Double) in signedDistance(x, y, px0, py0, px1, py1, rInner) }
        for y in 0..<height {
            for x in 0..<width {
                let covOuter = coverage(x, y, outer), covInner = coverage(x, y, inner)
                guard covOuter > 0 else { continue }
                let ring = max(0, covOuter - covInner)
                // Composite: border (black at borderAlpha) over nothing, fill (white at fillAlpha) inside. Straight alpha.
                let ringA = ring * borderAlpha, fillA = covInner * fillAlpha
                let a = ringA + fillA
                guard a > 0 else { continue }
                let grey = (fillA * 255) / a   // white fill, black ring
                let o = (y * width + x) * 4
                rgba[o] = UInt8(max(0, min(255, grey.rounded()))); rgba[o + 1] = rgba[o]; rgba[o + 2] = rgba[o]
                rgba[o + 3] = UInt8(max(0, min(255, (a * 255).rounded())))
            }
        }
        _ = dark
        return Bezel(image: ContinuousRGBAImage(width: width, height: height, rgba: rgba), pad: pad)
    }
}
