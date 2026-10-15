#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import ImageIO
import CoreGraphics
#endif


func i2h32(_ x: UInt32, _ y: UInt32, _ s: UInt32) -> UInt32 {
    var v = x &* 0x9E3779B1 &+ y &* 0x85EBCA77 &+ s &* 0xC2B2AE3D
    v ^= v >> 15; v = v &* 0x2C1B3C6D; v ^= v >> 12; v = v &* 0x297A2D39; v ^= v >> 15
    return v
}
func i2vnoise(_ x: Int, _ y: Int, _ step: Int, _ seed: Int, _ ch: Int) -> Int {
    let gx = x / step, fx = x % step, gy = y / step, fy = y % step
    let s = UInt32(seed * 8 + ch)
    let a = Int(i2h32(UInt32(gx), UInt32(gy), s) & 255), b = Int(i2h32(UInt32(gx + 1), UInt32(gy), s) & 255)
    let c = Int(i2h32(UInt32(gx), UInt32(gy + 1), s) & 255), d = Int(i2h32(UInt32(gx + 1), UInt32(gy + 1), s) & 255)
    return ((a * (step - fx) + b * fx) * (step - fy) + (c * (step - fx) + d * fx) * fy) / (step * step)
}
typealias I2Px = (UInt8, UInt8, UInt8, UInt8)
func i2Pixel(_ family: String, _ w: Int, _ h: Int, _ seed: Int, _ x: Int, _ y: Int) -> I2Px {
    switch family {
    case "photo":
        var p = [UInt8](repeating: 0, count: 3)
        for ch in 0..<3 { p[ch] = UInt8((i2vnoise(x, y, 16, seed, ch) * 5 + i2vnoise(x, y, 6, seed + 100, ch) * 2 + i2vnoise(x, y, 3, seed + 200, ch)) / 8) }
        return (p[0], p[1], p[2], 255)
    case "lineart":
        let s = Int(i2h32(UInt32(seed), 7, 3))
        let a = 1 + s % 3, b = 1 + (s >> 3) % 3, m = 7 + (s >> 6) % 5
        let cx = w / 2, cy = h / 2, r = min(w, h) / 3
        var on = (x * a + y * b) % m == 0
        on = on || x == 3 || x == w - 4 || y == 3 || y == h - 4
        let d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
        on = on || abs(d2 - r * r) <= r
        on = on || y == h / 3 || y == h / 3 + 1
        return on ? (0, 0, 0, 255) : (255, 255, 255, 255)
    case "text":
        let line = y / 9, ly = y % 9
        var on = false
        if ly >= 2 && ly < 8 && x >= 2 {
            let cx = (x - 2) / 4, lx = (x - 2) % 4
            if cx * 4 + 2 + 3 <= w && i2h32(UInt32(cx), UInt32(line), UInt32(seed)) & 7 != 0 && lx < 3 {
                on = (i2h32(UInt32(cx), UInt32(line), UInt32(seed + 1)) >> UInt32(lx + (ly - 2) * 4)) & 1 == 1
            }
        }
        return on ? (20, 20, 20, 255) : (250, 250, 250, 255)
    case "alpha":
        let cx = w / 2, cy = h / 2, R = min(w, h) * 5 / 12
        let lo = (R - 3) * (R - 3), hi = (R + 3) * (R + 3)
        let d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
        if abs(x - cx) < R / 4 && abs(y - cy) < R / 4 { return (20, 160, 60, 255) }
        let a: Int = d2 <= lo ? 255 : (d2 >= hi ? 0 : 255 * (hi - d2) / (hi - lo))
        if a == 0 { return (255, 255, 0, 0) }
        return (UInt8(200 - seed % 5 * 10), UInt8(60 + seed % 7 * 8), UInt8(30 + seed % 3 * 40), UInt8(a))
    default:
        let n = 1 + seed % 3
        return ((x / n) + (y / n)) % 2 == 0 ? (230, 230, 230, 255) : (30, 60, 200, 255)
    }
}

/// Straight-alpha RGBA8 pixels of one synthetic family (i2gen.py) as an Image at scale 2.5 (W px = W / 2.5 pt). Windows: RGBAImage; Mac: CGImage, alpha last, not premultiplied.
@MainActor func i2Image(_ family: String, _ w: Int, _ h: Int, _ seed: Int) -> Image {
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w { let p = i2Pixel(family, w, h, seed, x, y); let i = (y * w + x) * 4; bytes[i] = p.0; bytes[i + 1] = p.1; bytes[i + 2] = p.2; bytes[i + 3] = p.3 } }
#if os(Windows)
    return Image(decorative: RGBAImage(width: w, height: h, rgba: bytes)!, scale: 2.5)
#else
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return Image(decorative: cg, scale: 2.5)
#endif
}

struct Witness_i2_cal_alpha: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(red: 128.0 / 255, green: 128.0 / 255, blue: 128.0 / 255))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) { i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 6.4, height: 4.8).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 9.6, height: 7.2).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 12.8, height: 9.6).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 15.2, height: 11.6).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 19.2, height: 14.4).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 24.0, height: 18.0).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 28.8, height: 21.6).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 38.4, height: 28.8).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 48.0, height: 36.0).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().interpolation(.none).frame(width: 57.6, height: 43.2).padding(.leading, 0.1) }.frame(width: 320, height: 46, alignment: .topLeading)
                HStack(alignment: .top, spacing: 0) { i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 6.4, height: 4.8).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 9.6, height: 7.2).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 12.8, height: 9.6).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 15.2, height: 11.6).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 19.2, height: 14.4).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 24.0, height: 18.0).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 28.8, height: 21.6).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 38.4, height: 28.8).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 48.0, height: 36.0).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().interpolation(.low).frame(width: 57.6, height: 43.2).padding(.leading, 0.1) }.frame(width: 320, height: 46, alignment: .topLeading)
                HStack(alignment: .top, spacing: 0) { i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 6.4, height: 4.8).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 9.6, height: 7.2).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 12.8, height: 9.6).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 15.2, height: 11.6).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 19.2, height: 14.4).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 24.0, height: 18.0).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 28.8, height: 21.6).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 38.4, height: 28.8).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 48.0, height: 36.0).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().interpolation(.medium).frame(width: 57.6, height: 43.2).padding(.leading, 0.1) }.frame(width: 320, height: 46, alignment: .topLeading)
                HStack(alignment: .top, spacing: 0) { i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 6.4, height: 4.8).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 9.6, height: 7.2).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 12.8, height: 9.6).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 15.2, height: 11.6).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 19.2, height: 14.4).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 24.0, height: 18.0).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 28.8, height: 21.6).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 38.4, height: 28.8).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 48.0, height: 36.0).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().interpolation(.high).frame(width: 57.6, height: 43.2).padding(.leading, 0.1) }.frame(width: 320, height: 46, alignment: .topLeading)
                HStack(alignment: .top, spacing: 0) { i2Image("alpha", 48, 36, 41).resizable().frame(width: 6.4, height: 4.8).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().frame(width: 9.6, height: 7.2).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().frame(width: 12.8, height: 9.6).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().frame(width: 15.2, height: 11.6).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().frame(width: 19.2, height: 14.4).padding(.leading, 0.1); i2Image("alpha", 48, 36, 41).resizable().frame(width: 24.0, height: 18.0).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().frame(width: 28.8, height: 21.6).padding(.leading, 0.0); i2Image("alpha", 48, 36, 41).resizable().frame(width: 38.4, height: 28.8).padding(.leading, 0.3); i2Image("alpha", 48, 36, 41).resizable().frame(width: 48.0, height: 36.0).padding(.leading, 0.4); i2Image("alpha", 48, 36, 41).resizable().frame(width: 57.6, height: 43.2).padding(.leading, 0.1) }.frame(width: 320, height: 46, alignment: .topLeading)
            }
        }.frame(width: 320, height: 240, alignment: .topLeading)
    }
}
