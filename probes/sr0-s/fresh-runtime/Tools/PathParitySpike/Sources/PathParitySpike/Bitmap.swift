import Foundation
import CoreGraphics
import ImageIO

/// The 11 cases of the F-path spike (sr1-decisions.md). Frame sizes are in points; both renderers draw at `spikeScale`.
struct CaseInfo {
    let name: String
    let widthPt: Int
    let heightPt: Int
}

let spikeScale = 2.5

let spikeCases: [CaseInfo] = [
    CaseInfo(name: "ring-trim-round", widthPt: 60, heightPt: 60),
    CaseInfo(name: "ring-trim-dashed-butt", widthPt: 60, heightPt: 60),
    CaseInfo(name: "ring-track-dashed", widthPt: 60, heightPt: 60),
    CaseInfo(name: "ring-trim-tiny", widthPt: 60, heightPt: 60),
    CaseInfo(name: "ring-trim-zero", widthPt: 60, heightPt: 60),
    CaseInfo(name: "path-fill-nonzero", widthPt: 60, heightPt: 60),
    CaseInfo(name: "path-fill-evenodd", widthPt: 60, heightPt: 60),
    CaseInfo(name: "path-joins", widthPt: 160, heightPt: 60),
    CaseInfo(name: "path-curves", widthPt: 100, heightPt: 100),
    CaseInfo(name: "stroke-hairline", widthPt: 60, heightPt: 30),
    CaseInfo(name: "dash-phase", widthPt: 60, heightPt: 20),
]

/// RGBA8, PREMULTIPLIED alpha, top row first. Both renderers end in this form so the comparison is on what is composited.
struct Bitmap {
    let width: Int
    let height: Int
    var px: [UInt8]

    init(width: Int, height: Int) {
        self.width = width; self.height = height
        px = [UInt8](repeating: 0, count: width * height * 4)
    }

    /// Source-over of a straight-alpha RGBA8 image (the runtime's output) placed at (x, y).
    mutating func composite(straight rgba: [UInt8], width w: Int, height h: Int, atX x: Int, y: Int) {
        for j in 0..<h {
            let dy = y + j
            guard dy >= 0, dy < height else { continue }
            for i in 0..<w {
                let dx = x + i
                guard dx >= 0, dx < width else { continue }
                let s = (j * w + i) * 4, d = (dy * width + dx) * 4
                let a = Double(rgba[s + 3]) / 255
                guard a > 0 else { continue }
                for c in 0..<3 {
                    let src = Double(rgba[s + c]) * a
                    let dst = Double(px[d + c]) * (1 - a)
                    px[d + c] = UInt8(max(0, min(255, (src + dst).rounded())))
                }
                let dstA = Double(px[d + 3]) * (1 - a)
                px[d + 3] = UInt8(max(0, min(255, (Double(rgba[s + 3]) + dstA).rounded())))
            }
        }
    }

    init?(cgImage: CGImage) {
        width = cgImage.width; height = cgImage.height
        px = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn: Bool = px.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !drawn { return nil }
    }

    func cgImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var copy = px
        return copy.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)?.makeImage()
        }
    }

    func writePNG(_ url: URL) {
        guard let image = cgImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

struct Comparison {
    var bandMax = 0            // max abs channel error over pixels in the 1 px edge band
    var bandPixels = 0
    var outsideDiffPixels = 0  // pixels outside the band where any channel differs at all
    var outsideMax = 0
    var refAlphaSum = 0.0
    var mineAlphaSum = 0.0
    var diff: Bitmap
}

/// A pixel is in the edge band when it, or any of its 8 neighbours, is partially covered in either image, or when the two images
/// disagree about whether it is empty or full. "Full" is the largest alpha in the reference (an opacity-0.7 shape is full at 179).
func compare(reference: Bitmap, mine: Bitmap) -> Comparison {
    precondition(reference.width == mine.width && reference.height == mine.height)
    let w = reference.width, h = reference.height
    let full = max(reference.px.enumerated().filter { $0.offset % 4 == 3 }.map { Int($0.element) }.max() ?? 0,
                   mine.px.enumerated().filter { $0.offset % 4 == 3 }.map { Int($0.element) }.max() ?? 0)
    func state(_ b: Bitmap, _ i: Int) -> Int { let a = Int(b.px[i * 4 + 3]); return a == 0 ? 0 : (a == full ? 2 : 1) }
    let refState = (0..<(w * h)).map { state(reference, $0) }, mineState = (0..<(w * h)).map { state(mine, $0) }
    var result = Comparison(diff: Bitmap(width: w, height: h))
    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x
            var band = refState[i] != mineState[i]
            if !band {
                search: for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let n = ny * w + nx
                        if refState[n] == 1 || mineState[n] == 1 || refState[n] != refState[i] || mineState[n] != mineState[i] { band = true; break search }
                    }
                }
            }
            var worst = 0
            for c in 0..<4 { worst = max(worst, abs(Int(reference.px[i * 4 + c]) - Int(mine.px[i * 4 + c]))) }
            result.diff.px[i * 4] = UInt8(min(255, worst * 8)); result.diff.px[i * 4 + 3] = worst > 0 ? 255 : 0
            if band { result.bandPixels += 1; result.bandMax = max(result.bandMax, worst) }
            else if worst > 0 { result.outsideDiffPixels += 1; result.outsideMax = max(result.outsideMax, worst) }
        }
    }
    result.refAlphaSum = Double(reference.px.enumerated().filter { $0.offset % 4 == 3 }.reduce(0) { $0 + Int($1.element) }) / Double(max(1, full))
    result.mineAlphaSum = Double(mine.px.enumerated().filter { $0.offset % 4 == 3 }.reduce(0) { $0 + Int($1.element) }) / Double(max(1, full))
    return result
}
