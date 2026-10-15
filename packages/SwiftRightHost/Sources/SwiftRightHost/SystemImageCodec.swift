import Foundation
import SwiftRightRuntime

/// The platform codec under `ImagePolicy`: WIC on Windows, ImageIO on Apple platforms. One frame in, straight-alpha RGBA8 sRGB out (embedded ICC profiles converted, untagged = sRGB).
enum SystemImageCodec {
    /// `applyProfile: false` returns the 8-bit pixels in the file's own colour space plus the embedded non-sRGB ICC profile (Windows only; policy converts it with `ICCMatrixTRC` when it can);
    /// `true` converts with the codec (WIC's colour transform). The Mac codec always converts (CoreGraphics) and reports no profile.
    static func decode(_ data: Data, frameIndex: Int, applyProfile: Bool = true) throws -> (image: RGBAImage, profile: [UInt8]?) {
        #if os(Windows)
        let d = try ImageCodecWIC.decode(data, frameIndex: frameIndex, applyProfile: applyProfile)
        return (d.image, d.profile)
        #elseif canImport(ImageIO)
        return (try ImageCodecImageIO.decode(data, frameIndex: frameIndex), nil)
        #else
        throw ImageDecodeError.unsupported("no system image codec on this platform")
        #endif
    }

    /// Pixel sizes of every frame in codec order (used to find an ICO entry).
    static func frameSizes(_ data: Data) throws -> [(Int, Int)] {
        #if os(Windows)
        return try ImageCodecWIC.frameSizes(data)
        #elseif canImport(ImageIO)
        return try ImageCodecImageIO.frameSizes(data)
        #else
        throw ImageDecodeError.unsupported("no system image codec on this platform")
        #endif
    }
}
