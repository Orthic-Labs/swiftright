#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif

// Issue #43, case clip-bitmap-v1: a flat-colour bitmap (200 x 140 px at scale 2.5, drawn 1:1) and a second, two-tone one, clipped to a Circle and to a
// Capsule. The renderer draws bitmaps (and text) itself and clips by rectangles, so the host draws them once per band of the clip's inside.
@MainActor func r6Bitmap(_ w: Int, _ h: Int, twoTone: Bool) -> Image {
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        let left = !twoTone || x < w / 2
        bytes[i] = left ? 51 : 230; bytes[i + 1] = left ? 102 : 120; bytes[i + 2] = left ? 255 : 40; bytes[i + 3] = 255
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

struct Witness_r6_clip_bitmap_v1: View {
    var body: some View {
        HStack(spacing: 12) {
            r6Bitmap(200, 140, twoTone: false).clipShape(Circle())
            r6Bitmap(200, 140, twoTone: true).clipShape(Capsule(style: .circular))
        }
        .frame(width: 240, height: 160)
    }
}
