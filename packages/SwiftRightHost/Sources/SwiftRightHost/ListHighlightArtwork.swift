import Foundation
import SwiftRightRuntime

/// Our own vector model of the selection highlight of SwiftUI's macOS List (inset style): a flat rounded rectangle whose corners follow a measured outline
/// (`ListHighlightData`, factory/tools/switch-artwork/derive_list_golden.py), in one flat colour. Nothing of Apple's artwork is embedded.
public enum ListHighlightArtwork {
    static let samplesPerAxis = 8

    private struct Key: Hashable { let width: Int, height: Int, scale: Float, rgb: UInt32 }
    nonisolated(unsafe) private static var cache: [Key: ContinuousRGBAImage] = [:]
    private static let cacheLock = NSLock()

    /// Straight-alpha RGBA of the highlight at `widthPX` x `heightPX` device pixels at `scale` pixels per point, filled with `rgb` (0xRRGGBB).
    public static func render(widthPX: Int, heightPX: Int, scale: Float, rgb: UInt32) -> ContinuousRGBAImage {
        let key = Key(width: widthPX, height: heightPX, scale: scale, rgb: rgb)
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[key] { return hit }
        let image = rasterize(widthPX: widthPX, heightPX: heightPX, scale: scale, rgb: rgb)
        cache[key] = image
        return image
    }

    private static func rasterize(widthPX: Int, heightPX: Int, scale: Float, rgb: UInt32) -> ContinuousRGBAImage {
        let n = samplesPerAxis, total = Double(n * n)
        let pxPerPoint = Double(scale)
        let widthPt = Double(widthPX) / pxPerPoint, heightPt = Double(heightPX) / pxPerPoint
        let colour = [UInt8(rgb >> 16 & 255), UInt8(rgb >> 8 & 255), UInt8(rgb & 255)]
        var rgba = [UInt8](repeating: 0, count: max(0, widthPX * heightPX * 4))
        for py in 0..<heightPX {
            for px in 0..<widthPX {
                var inside = 0
                for sy in 0..<n {
                    let y = (Double(py) + (Double(sy) + 0.5) / Double(n)) / pxPerPoint
                    for sx in 0..<n {
                        let x = (Double(px) + (Double(sx) + 0.5) / Double(n)) / pxPerPoint
                        if SwitchArtwork.inside(ListHighlightData.corner, x: x, y: y, width: widthPt, height: heightPt) { inside += 1 }
                    }
                }
                guard inside > 0 else { continue }
                let o = (py * widthPX + px) * 4
                rgba[o] = colour[0]; rgba[o + 1] = colour[1]; rgba[o + 2] = colour[2]
                rgba[o + 3] = UInt8(max(0, min(255, (Double(inside) / total * 255).rounded())))
            }
        }
        return ContinuousRGBAImage(width: widthPX, height: heightPX, rgba: rgba)
    }
}
