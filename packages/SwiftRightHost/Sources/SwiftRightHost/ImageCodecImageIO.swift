#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import SwiftRightRuntime

/// The Mac codec: ImageIO (`CGImageSource`), converted to straight-alpha RGBA8 sRGB. Same method as the block I1 oracle (`factory/pipeline/blocks-w0-i1/mac_oracle.swift`):
/// an 8-bit non-premultiplied sRGB image is read as it is; anything else is drawn into an 8-bit premultiplied sRGB context (CoreGraphics converts the colour space) and un-premultiplied.
enum ImageCodecImageIO {
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func source(_ data: Data) throws -> CGImageSource {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { throw ImageDecodeError.notAnImage }
        guard CGImageSourceGetCount(src) > 0 else { throw ImageDecodeError.corrupt("ImageIO found no image") }
        return src
    }

    static func frameSizes(_ data: Data) throws -> [(Int, Int)] {
        let src = try source(data)
        return (0..<CGImageSourceGetCount(src)).map { i in
            let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any] ?? [:]
            return ((p["PixelWidth"] as? Int) ?? 0, (p["PixelHeight"] as? Int) ?? 0)
        }
    }

    static func decode(_ data: Data, frameIndex: Int) throws -> RGBAImage {
        let src = try source(data)
        guard frameIndex < CGImageSourceGetCount(src), let cg = CGImageSourceCreateImageAtIndex(src, frameIndex, nil) else { throw ImageDecodeError.corrupt("ImageIO returned no image") }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, w <= 16384, h <= 16384 else { throw ImageDecodeError.unsupported("image \(w)x\(h) is over the decode limit") }
        let alpha = cg.alphaInfo
        let straight = [.none, .last, .first, .noneSkipLast, .noneSkipFirst].contains(alpha)
        let isSRGB = (cg.colorSpace?.name as String?) == (CGColorSpace.sRGB as String)
        if cg.bitsPerComponent == 8, cg.bitsPerPixel == 32 || cg.bitsPerPixel == 24, straight, isSRGB, cg.bitmapInfo.byteOrder == .orderDefault,
           let cf = cg.dataProvider?.data {
            let bytes = [UInt8](cf as Data), bpp = cg.bitsPerPixel / 8, bpr = cg.bytesPerRow
            guard bytes.count >= bpr * h else { throw ImageDecodeError.corrupt("ImageIO pixel buffer") }
            var out = [UInt8](repeating: 255, count: w * h * 4)
            let first = alpha == .first || alpha == .noneSkipFirst
            let hasAlpha = alpha == .last || alpha == .first
            for y in 0..<h {
                for x in 0..<w {
                    let o = y * bpr + x * bpp, d = (y * w + x) * 4
                    let c = first ? o + 1 : o
                    out[d] = bytes[c]; out[d + 1] = bytes[c + 1]; out[d + 2] = bytes[c + 2]
                    if hasAlpha { out[d + 3] = bytes[first ? o : o + 3] }
                }
            }
            guard let image = RGBAImage(width: w, height: h, rgba: out) else { throw ImageDecodeError.corrupt("pixel buffer") }
            return image
        }
        var drawn = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = drawn.withUnsafeMutableBytes { p in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw ImageDecodeError.unsupported("ImageIO: no sRGB context for this image") }
        for i in stride(from: 0, to: drawn.count, by: 4) {
            let a = Int(drawn[i + 3])
            if a == 0 { drawn[i] = 0; drawn[i + 1] = 0; drawn[i + 2] = 0 }
            else if a < 255 { for c in 0..<3 { drawn[i + c] = UInt8(min(255, (Int(drawn[i + c]) * 255 + a / 2) / a)) } }
        }
        guard let image = RGBAImage(width: w, height: h, rgba: drawn) else { throw ImageDecodeError.corrupt("pixel buffer") }
        return image
    }
}
#endif
