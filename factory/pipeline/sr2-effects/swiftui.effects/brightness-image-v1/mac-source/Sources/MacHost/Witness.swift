#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif


// Issue #54, case brightness-image-v1: a two-tone bitmap (100 x 60 px at scale 2.5, drawn 1:1) plain, with brightness(0.2) and with brightness(-0.2).
// Channels are whole numbers of levels, so the expected values are exact: (51, 102, 153) + 51 = (102, 153, 204); (230, 120, 40) + 51 = (255, 171, 91).
@MainActor func e54Bitmap(_ w: Int, _ h: Int) -> Image {
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        let left = x < w / 2
        bytes[i] = left ? 51 : 230; bytes[i + 1] = left ? 102 : 120; bytes[i + 2] = left ? 153 : 40; bytes[i + 3] = 255
    } }
#if os(Windows)
    return Image(decorative: RGBAImage(width: w, height: h, rgba: bytes)!, scale: 2.5)
#else
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return Image(decorative: cg, scale: 2.5)
#endif
}

struct Witness_e54_brightness_image_v1: View {
    var body: some View {
        HStack(spacing: 8) {
            e54Bitmap(100, 60)
            e54Bitmap(100, 60).brightness(0.2)
            e54Bitmap(100, 60).brightness(-0.2)
        }
        .frame(width: 240, height: 160)
    }
}
