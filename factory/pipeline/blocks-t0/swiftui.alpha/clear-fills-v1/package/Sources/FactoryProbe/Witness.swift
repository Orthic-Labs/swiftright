#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import ImageIO
import CoreGraphics
#endif


/// Straight-alpha RGBA8 pixels drawn 1:1 (scale 2.5: W px = W / 2.5 pt). Windows: RGBAImage -> Image(decorative:scale:) -> swr_image_register. Mac: CGImage (alpha last, not premultiplied).
@MainActor func pixelImage(_ w: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> Image {
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w { let p = f(x, y); let i = (y * w + x) * 4; bytes[i] = p.0; bytes[i + 1] = p.1; bytes[i + 2] = p.2; bytes[i + 3] = p.3 } }
#if os(Windows)
    return Image(decorative: RGBAImage(width: w, height: h, rgba: bytes)!, scale: 2.5)
#else
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return Image(decorative: cg, scale: 2.5)
#endif
}

func band<Content: View>(_ r: Double, _ g: Double, _ b: Double, @ViewBuilder _ cells: () -> Content) -> some View {
    ZStack(alignment: .topLeading) {
        Rectangle().fill(Color(red: r, green: g, blue: b))
        HStack(spacing: 0) { cells() }.padding(.top, 14).padding(.leading, 20)
    }.frame(width: 320, height: 70, alignment: .topLeading)
}

struct Witness_t0_clear_fills: View {
    var body: some View {
        VStack(spacing: 0) {
            band(255.0 / 255, 255.0 / 255, 255.0 / 255) { Color.clear.frame(width: 48, height: 40); Rectangle().fill(Color.clear).frame(width: 48, height: 40); Color.black.opacity(0.001).frame(width: 48, height: 40); Rectangle().fill(Color.black.opacity(0.001)).frame(width: 48, height: 40); Color.red.opacity(0).frame(width: 48, height: 40); Button { } label: { ZStack { Color.black.opacity(0.001); Rectangle().fill(Color(red: 1, green: 0, blue: 0)).frame(width: 16, height: 16) }.frame(width: 48, height: 40) }.buttonStyle(.plain) }
            band(0.0 / 255, 0.0 / 255, 0.0 / 255) { Color.clear.frame(width: 48, height: 40); Rectangle().fill(Color.clear).frame(width: 48, height: 40); Color.black.opacity(0.001).frame(width: 48, height: 40); Rectangle().fill(Color.black.opacity(0.001)).frame(width: 48, height: 40); Color.red.opacity(0).frame(width: 48, height: 40); Button { } label: { ZStack { Color.black.opacity(0.001); Rectangle().fill(Color(red: 1, green: 0, blue: 0)).frame(width: 16, height: 16) }.frame(width: 48, height: 40) }.buttonStyle(.plain) }
            band(40.0 / 255, 120.0 / 255, 200.0 / 255) { Color.clear.frame(width: 48, height: 40); Rectangle().fill(Color.clear).frame(width: 48, height: 40); Color.black.opacity(0.001).frame(width: 48, height: 40); Rectangle().fill(Color.black.opacity(0.001)).frame(width: 48, height: 40); Color.red.opacity(0).frame(width: 48, height: 40); Button { } label: { ZStack { Color.black.opacity(0.001); Rectangle().fill(Color(red: 1, green: 0, blue: 0)).frame(width: 16, height: 16) }.frame(width: 48, height: 40) }.buttonStyle(.plain) }
            Rectangle().fill(Color(red: 1, green: 1, blue: 1)).frame(width: 320, height: 30)
        }.frame(width: 320, height: 240, alignment: .topLeading)
    }
}
