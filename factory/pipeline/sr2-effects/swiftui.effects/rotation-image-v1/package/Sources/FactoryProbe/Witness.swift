#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif

// Issue #69, case rotation-image-v1: a smooth two-axis gradient bitmap (160 x 100 px at scale 2.5, drawn 1:1) and a resizable star.fill symbol, each under
// rotationEffect(.degrees(30)). The host resamples each bitmap through the rotation (bilinear, premultiplied) and the renderer draws it 1:1.
@MainActor func e69Bitmap(_ w: Int, _ h: Int) -> Image {
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        bytes[i] = UInt8(40 + 200 * x / (w - 1)); bytes[i + 1] = UInt8(60 + 160 * y / (h - 1)); bytes[i + 2] = 180; bytes[i + 3] = 255
    } }
#if os(Windows)
    return Image(decorative: RGBAImage(width: w, height: h, rgba: bytes)!, scale: 2.5)
#else
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    return Image(decorative: cg, scale: 2.5)
#endif
}

struct Witness_e69_rotation_image_v1: View {
    var body: some View {
        HStack(spacing: 30) {
            e69Bitmap(160, 100).rotationEffect(.degrees(30))
            Image(systemName: "star.fill").resizable().scaledToFit().frame(width: 50, height: 50).foregroundColor(.blue).rotationEffect(.degrees(30))
        }
    }
}
