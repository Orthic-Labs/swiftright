#if os(Windows)
import Foundation

// Wave 0 block I1 (docs/foundations-images-fonts.md 1.1): the CGImage-shaped surface on Windows. Shared source that decodes with `SwiftRightImageIO.makeImage(data:maxPixel:)`
// and draws with `Image(decorative:scale:orientation:)` compiles unchanged on the Mac (CoreGraphics' CGImage) and here (this class, backed by `RGBAImage`).
// Pixels are 8-bit sRGB, straight alpha, top-left origin. Any other CoreGraphics API is unsupported on Windows (a compile diagnostic, section 5 categories).

/// CoreGraphics' `CGImageAlphaInfo` raw values. A decoded `CGImage` here is `.last` (straight alpha, R G B A) when it has alpha channel data, else `.noneSkipLast`.
public enum CGImageAlphaInfo: UInt32, Sendable {
    case none = 0, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly
}

public final class CGImage: @unchecked Sendable {
    public let pixels: RGBAImage
    public let alphaInfo: CGImageAlphaInfo
    public var width: Int { pixels.width }
    public var height: Int { pixels.height }
    public var bitsPerComponent: Int { 8 }
    public var bitsPerPixel: Int { 32 }
    public var bytesPerRow: Int { pixels.width * 4 }
    /// The only working space.
    public var colorSpaceName: String { "sRGB" }

    public init(pixels: RGBAImage, alphaInfo: CGImageAlphaInfo = .last) {
        self.pixels = pixels
        self.alphaInfo = alphaInfo
    }
}

extension Image {
    /// Apple: https://developer.apple.com/documentation/swiftui/image/init(decorative:scale:orientation:)
    /// The intrinsic size is the pixel size (after the orientation) divided by `scale`.
    public init(decorative cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation = .up) {
        self.init(decorative: cgImage.pixels.oriented(orientation), scale: scale)
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/image/init(_:scale:orientation:label:)
    /// The label is the image's accessibility label.
    public init(_ cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation = .up, label: Text) {
        self.init(decorative: cgImage.pixels.oriented(orientation), scale: scale)
        self.labelText = label.string
    }
}
#endif
