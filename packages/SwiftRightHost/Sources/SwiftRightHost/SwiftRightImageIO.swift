import Foundation
import SwiftRightRuntime
#if canImport(ImageIO)
import CoreGraphics
#endif

/// Wave 0 block I1 (docs/foundations-images-fonts.md 1.1): the ONE decode entry shared source calls on both platforms.
/// Windows: WIC (`ImageCodecWIC`), returning the runtime's CGImage-shaped `CGImage`. Mac: ImageIO, returning CoreGraphics' `CGImage` (8-bit sRGB, non-premultiplied alpha).
/// Policy (completeness, ICO entry, EXIF orientation, maxPixel) is `ImagePolicy`, shared. Throws `ImageDecodeError`; never returns a blank image.
public enum SwiftRightImageIO {
    /// An image whose longer side is over `maxPixel` is box-filtered down so the longer side equals `maxPixel` (never upscaled); `maxPixel <= 0` means no limit.
    /// An ICO yields the entry that is the smallest one at least `maxPixel`, else the largest.
    public static func makeImage(data: Data, maxPixel: Int) throws -> CGImage {
        let pixels = try ImagePolicy.decode(data, maxPixel: maxPixel)
        let hasAlpha = stride(from: 3, to: pixels.rgba.count, by: 4).contains { pixels.rgba[$0] != 255 }
        #if os(Windows)
        return CGImage(pixels: pixels, alphaInfo: hasAlpha ? .last : .noneSkipLast)
        #else
        let info: CGImageAlphaInfo = hasAlpha ? .last : .noneSkipLast
        guard let provider = CGDataProvider(data: Data(pixels.rgba) as CFData),
              let image = CGImage(width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: info.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw ImageDecodeError.corrupt("could not build a CGImage") }
        return image
        #endif
    }

    /// The straight-alpha buffer behind an image made by `makeImage` (both platforms; used by the gates).
    public static func decodePixels(data: Data, maxPixel: Int) throws -> RGBAImage { try ImagePolicy.decode(data, maxPixel: maxPixel) }

    /// Diagnostic only (the I1 gate records it for the negative controls): what the OS codec alone does with these bytes, WITHOUT the policy's completeness check.
    /// Returns "ok WxH" when the codec produced an image, else the error. Shows why `ImagePolicy.checkComplete` exists: a codec may deliver a partly grey picture for a cut file.
    public static func codecOnlyProbe(data: Data) -> String {
        do {
            let r = try SystemImageCodec.decode(data, frameIndex: 0, applyProfile: true)
            return "ok \(r.image.width)x\(r.image.height)"
        } catch { return "threw \(error)" }
    }
}
