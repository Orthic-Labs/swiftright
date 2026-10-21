import Foundation
import SwiftRightRuntime

/// Why `ImageDecoder.decode` refused. Never a silent blank image: a host shows or logs this.
public enum ImageDecodeError: Error, Equatable, CustomStringConvertible {
    /// Neither a PNG nor an ICO signature (or empty data).
    case notAnImage
    /// Well-formed so far, but the data ends early.
    case truncated(String)
    /// A checksum, size, index or structure is wrong.
    case corrupt(String)
    /// A valid file using a feature this decoder does not implement (Adam7, 16-bit DIB, ...).
    case unsupported(String)

    public var description: String {
        switch self {
        case .notAnImage: return "ImageDecoder: not a recognised image (PNG, JPEG, GIF, BMP, ICO or TIFF)"
        case .truncated(let why): return "ImageDecoder: truncated data (\(why))"
        case .corrupt(let why): return "ImageDecoder: corrupt data (\(why))"
        case .unsupported(let what): return "ImageDecoder: unsupported (\(what))"
        }
    }
}

/// Encoded PNG / ICO bytes -> straight-alpha RGBA8 for `Image(decorative:scale:)`. No system library: the inflate and PNG code are Swift.
/// Hub use: `HubPlatformServices.decodeImage(_:maxPixel:)`.
public enum ImageDecoder {
    /// Which decoder `decode(_:maxPixel:)` uses. `.swift` (the default until the lead decides, docs/sr1-decisions.md G30) is the pure-Swift PNG/ICO decoder of block 35;
    /// `.system` is the wave 0 block I1 service: WIC on Windows, ImageIO on the Mac, under the shared `ImagePolicy` (all formats, ICC to sRGB, EXIF orientation, completeness).
    /// The environment variable `SWIFTRIGHT_IMAGE_DECODER=system` (or `wic`) selects `.system` at launch.
    public enum Backend: Sendable { case swift, system }
    nonisolated(unsafe) public static var backend: Backend = {
        let v = ProcessInfo.processInfo.environment["SWIFTRIGHT_IMAGE_DECODER"]?.lowercased()
        return v == "system" || v == "wic" ? .system : .swift
    }()

    /// Decodes `data`. An ICO yields the entry whose size is the smallest one at least `maxPixel` (else the largest). An image whose longer side is
    /// over `maxPixel` is box-filtered down so the longer side equals `maxPixel` (aspect kept, never upscaled). `maxPixel <= 0` means no limit.
    /// The result has `interpolates == true`: this entry stands for ImageIO's `CGImageSourceCreateImageAtIndex`, whose CGImage the Mac draws with its interpolating-source downscale (issue #72).
    public static func decode(_ data: Data, maxPixel: Int) throws -> RGBAImage {
        try decodeUnmarked(data, maxPixel: maxPixel).withInterpolation(true)
    }

    private static func decodeUnmarked(_ data: Data, maxPixel: Int) throws -> RGBAImage {
        if backend == .system { return try ImagePolicy.decode(data, maxPixel: maxPixel) }
        let bytes = [UInt8](data)
        let image: RGBAImage
        if bytes.count >= 8, Array(bytes[0..<8]) == PNGDecoder.signature {
            image = try PNGDecoder.decode(bytes)
        } else if bytes.count >= 6, bytes[0] == 0, bytes[1] == 0, bytes[2] == 1, bytes[3] == 0 {
            image = try ICOReader.decode(bytes, maxPixel: maxPixel)
        } else {
            throw ImageDecodeError.notAnImage
        }
        guard maxPixel > 0, max(image.width, image.height) > maxPixel else { return image }
        let scale = Double(maxPixel) / Double(max(image.width, image.height))
        return resample(image, width: max(1, Int((Double(image.width) * scale).rounded())), height: max(1, Int((Double(image.height) * scale).rounded())))
    }

    /// Area-average (box) resample on premultiplied alpha, so a transparent pixel never bleeds its colour. Each axis is only ever reduced:
    /// a target larger than the source on an axis keeps the source size there. An exact integer ratio averages whole pixels.
    public static func resample(_ image: RGBAImage, width targetW: Int, height targetH: Int) -> RGBAImage {
        let w = min(image.width, max(1, targetW)), h = min(image.height, max(1, targetH))
        if w == image.width && h == image.height { return image }
        // horizontal pass: premultiplied floats, h_src rows x w columns x 4
        func weights(_ source: Int, _ target: Int) -> [[(index: Int, weight: Float)]] {
            let ratio = Double(source) / Double(target)
            return (0..<target).map { t in
                let start = Double(t) * ratio, end = Double(t + 1) * ratio
                var list: [(Int, Float)] = []
                var i = Int(start.rounded(.down))
                while Double(i) < end - 1e-9, i < source {
                    let cover = min(end, Double(i + 1)) - max(start, Double(i))
                    if cover > 1e-9 { list.append((i, Float(cover / ratio))) }
                    i += 1
                }
                return list
            }
        }
        let wx = weights(image.width, w), wy = weights(image.height, h)
        var mid = [Float](repeating: 0, count: image.height * w * 4)
        for y in 0..<image.height {
            for x in 0..<w {
                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                for (sx, k) in wx[x] {
                    let o = (y * image.width + sx) * 4
                    let alpha = Float(image.rgba[o + 3]) / 255
                    r += Float(image.rgba[o]) * alpha * k; g += Float(image.rgba[o + 1]) * alpha * k
                    b += Float(image.rgba[o + 2]) * alpha * k; a += alpha * k
                }
                let m = (y * w + x) * 4
                mid[m] = r; mid[m + 1] = g; mid[m + 2] = b; mid[m + 3] = a
            }
        }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                for (sy, k) in wy[y] {
                    let m = (sy * w + x) * 4
                    r += mid[m] * k; g += mid[m + 1] * k; b += mid[m + 2] * k; a += mid[m + 3] * k
                }
                let o = (y * w + x) * 4
                guard a > 1e-6 else { continue }
                func byte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
                out[o] = byte(r / a); out[o + 1] = byte(g / a); out[o + 2] = byte(b / a); out[o + 3] = byte(a * 255)
            }
        }
        return RGBAImage(width: w, height: h, rgba: out)!
    }
}

/// Windows icon container: a directory of PNG or BMP (DIB + AND mask) images.
enum ICOReader {
    private struct Entry { var width: Int, height: Int, bpp: Int, size: Int, offset: Int }

    static func decode(_ b: [UInt8], maxPixel: Int) throws -> RGBAImage {
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        let count = u16(4)
        guard count > 0 else { throw ImageDecodeError.corrupt("ICO with no images") }
        guard b.count >= 6 + count * 16 else { throw ImageDecodeError.truncated("ICO directory") }
        var entries: [Entry] = []
        for i in 0..<count {
            let o = 6 + i * 16
            let e = Entry(width: b[o] == 0 ? 256 : Int(b[o]), height: b[o + 1] == 0 ? 256 : Int(b[o + 1]), bpp: u16(o + 6), size: u32(o + 8), offset: u32(o + 12))
            guard e.size > 0, e.offset >= 6 + count * 16, e.offset + e.size <= b.count else { throw ImageDecodeError.corrupt("ICO entry \(i) outside the file") }
            entries.append(e)
        }
        // smallest entry at least maxPixel, else the largest; ties go to the higher bit depth, then the earlier entry
        let side = { (e: Entry) in max(e.width, e.height) }
        let enough = entries.filter { side($0) >= maxPixel }
        let pick: Entry
        if maxPixel > 0, !enough.isEmpty {
            pick = enough.min { (side($0), -$0.bpp) < (side($1), -$1.bpp) }!
        } else {
            pick = entries.max { (side($0), $0.bpp) < (side($1), $1.bpp) }!
        }
        let body = Array(b[pick.offset..<pick.offset + pick.size])
        if body.count >= 8, Array(body[0..<8]) == PNGDecoder.signature { return try PNGDecoder.decode(body) }
        return try decodeDIB(body)
    }

    /// BITMAPINFOHEADER image: height is doubled (XOR bitmap then AND mask). 1/4/8-bit palette, 24- and 32-bit BGR(A), no compression.
    private static func decodeDIB(_ d: [UInt8]) throws -> RGBAImage {
        func u16(_ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        guard d.count >= 40 else { throw ImageDecodeError.truncated("DIB header") }
        let headerSize = u32(0)
        guard headerSize >= 40, headerSize <= d.count else { throw ImageDecodeError.unsupported("DIB header of \(headerSize) bytes") }
        let w = Int(Int32(truncatingIfNeeded: u32(4)))
        let doubled = Int(Int32(truncatingIfNeeded: u32(8)))
        let planes = u16(12), bpp = u16(14), compression = u32(16), clrUsed = u32(32)
        guard w > 0, w <= 1024, doubled > 0, doubled % 2 == 0, doubled / 2 <= 1024 else { throw ImageDecodeError.corrupt("DIB size \(w)x\(doubled)") }
        let h = doubled / 2
        guard planes == 1 else { throw ImageDecodeError.corrupt("DIB planes \(planes)") }
        guard compression == 0 else { throw ImageDecodeError.unsupported("compressed DIB (\(compression))") }
        guard [1, 4, 8, 24, 32].contains(bpp) else { throw ImageDecodeError.unsupported("\(bpp)-bit DIB") }
        var palette: [UInt8] = []   // B, G, R, reserved
        var cursor = headerSize
        if bpp <= 8 {
            let n = clrUsed == 0 ? 1 << bpp : clrUsed
            guard n <= 1 << bpp, cursor + n * 4 <= d.count else { throw ImageDecodeError.truncated("DIB palette") }
            palette = Array(d[cursor..<cursor + n * 4])
            cursor += n * 4
        }
        let xorStride = ((w * bpp + 31) / 32) * 4, maskStride = ((w + 31) / 32) * 4
        guard cursor + xorStride * h <= d.count else { throw ImageDecodeError.truncated("DIB pixels") }
        let maskStart = cursor + xorStride * h
        let hasMask = maskStart + maskStride * h <= d.count   // a 32-bit icon may omit the mask
        guard hasMask || bpp == 32 else { throw ImageDecodeError.truncated("DIB AND mask") }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        var anyAlpha = false
        for y in 0..<h {
            let row = cursor + (h - 1 - y) * xorStride   // bottom-up
            for x in 0..<w {
                let o = (y * w + x) * 4
                switch bpp {
                case 32:
                    out[o] = d[row + x * 4 + 2]; out[o + 1] = d[row + x * 4 + 1]; out[o + 2] = d[row + x * 4]; out[o + 3] = d[row + x * 4 + 3]
                    if out[o + 3] != 0 { anyAlpha = true }
                case 24:
                    out[o] = d[row + x * 3 + 2]; out[o + 1] = d[row + x * 3 + 1]; out[o + 2] = d[row + x * 3]; out[o + 3] = 255
                default:
                    let perByte = 8 / bpp
                    let byte = Int(d[row + x / perByte])
                    let index = (byte >> (8 - bpp - (x % perByte) * bpp)) & ((1 << bpp) - 1)
                    guard index * 4 + 2 < palette.count else { throw ImageDecodeError.corrupt("DIB palette index \(index)") }
                    out[o] = palette[index * 4 + 2]; out[o + 1] = palette[index * 4 + 1]; out[o + 2] = palette[index * 4]; out[o + 3] = 255
                }
            }
        }
        // AND mask (1 = transparent). A 32-bit icon that carries alpha ignores it; one whose alpha is all zero is masked by it.
        if hasMask, !(bpp == 32 && anyAlpha) {
            for y in 0..<h {
                let row = maskStart + (h - 1 - y) * maskStride
                for x in 0..<w where (d[row + x / 8] >> (7 - UInt8(x % 8))) & 1 == 1 {
                    let o = (y * w + x) * 4
                    out[o + 3] = 0
                }
                if bpp == 32 {
                    for x in 0..<w where (d[row + x / 8] >> (7 - UInt8(x % 8))) & 1 == 0 { out[(y * w + x) * 4 + 3] = 255 }
                }
            }
        }
        guard let image = RGBAImage(width: w, height: h, rgba: out) else { throw ImageDecodeError.corrupt("DIB pixel buffer") }
        return image
    }
}
