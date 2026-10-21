#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif

@MainActor func g76Bitmap(_ w: Int, _ h: Int) -> Image {
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

// Issue #76, case clip-image-aa-v1: a smooth gradient bitmap (200 x 200 px at scale 2.5, drawn 1:1, 80 pt) under clipShape(Circle()): the rim is the host's anti-aliased
// clip coverage on Windows (the bitmap is masked on the host) against Core Animation's anti-aliased layer mask on the Mac.
struct Witness_g76_clip_image_v1: View {
    var body: some View {
        g76Bitmap(200, 200).clipShape(Circle())
    }
}
