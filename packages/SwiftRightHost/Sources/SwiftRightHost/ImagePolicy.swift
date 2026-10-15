import Foundation
import SwiftRightRuntime

// Wave 0 block I1: the policy layer above the OS codec (WIC on Windows, ImageIO on the Mac). Pure Swift, identical on both platforms, unit-tested on the Mac:
//   - format sniffing and a structural COMPLETENESS check (a truncated or damaged file throws; an OS codec may return a partly grey picture, which is never delivered),
//   - the ICO entry choice (the block 35 rule: smallest entry at least `maxPixel`, else the largest; ties go to the higher bit depth, then the earlier entry),
//   - EXIF orientation 1-8 (read from the file, applied to the pixels here, so both platforms move pixels the same way),
//   - the `maxPixel` thumbnail (area-average on premultiplied alpha, the block 35 resampler `ImageDecoder.resample`).
// The codec only turns one frame into straight-alpha RGBA8 sRGB (`SystemImageCodec`).

enum ImageContainer: Equatable { case png, jpeg, gif, bmp, ico, tiff }

struct ICOEntry: Equatable { var width: Int, height: Int, bpp: Int, size: Int, offset: Int }

enum ImagePolicy {
    // MARK: sniffing

    static func sniff(_ b: [UInt8]) -> ImageContainer? {
        if b.count >= 8, Array(b[0..<8]) == PNGDecoder.signature { return .png }
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return .jpeg }
        if b.count >= 6, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46, b[3] == 0x38, (b[4] == 0x37 || b[4] == 0x39), b[5] == 0x61 { return .gif }
        if b.count >= 2, b[0] == 0x42, b[1] == 0x4D { return .bmp }
        if b.count >= 4, b[0] == 0, b[1] == 0, b[2] == 1, b[3] == 0 { return .ico }
        if b.count >= 4, (b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0) || (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0 && b[3] == 0x2A) { return .tiff }
        return nil
    }

    // MARK: completeness

    /// Throws `.truncated` / `.corrupt` when the container's own structure says the file is cut or damaged.
    static func checkComplete(_ b: [UInt8], _ container: ImageContainer) throws {
        switch container {
        case .png: try checkPNG(b)
        case .jpeg: try checkJPEG(b)
        case .gif: try checkGIF(b)
        case .bmp: try checkBMP(b)
        case .ico: _ = try icoEntries(b)
        case .tiff: break
        }
    }

    private static func be32(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
    private static func le16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    private static func le32(_ b: [UInt8], _ i: Int) -> Int { le16(b, i) | le16(b, i + 2) << 16 }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n); for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }; return c
    }
    static func crc32(_ b: [UInt8], _ from: Int, _ to: Int) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for i in from..<to { c = crcTable[Int((c ^ UInt32(b[i])) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func checkPNG(_ b: [UInt8]) throws {
        var i = 8, sawIHDR = false, sawIDAT = false
        while true {
            guard i + 8 <= b.count else { throw ImageDecodeError.truncated("PNG ends before the IEND chunk") }
            let length = be32(b, i)
            let type = String(decoding: b[i + 4..<i + 8], as: UTF8.self)
            guard length >= 0, length <= 0x7FFFFFFF else { throw ImageDecodeError.corrupt("PNG chunk length") }
            guard i + 12 + length <= b.count else { throw ImageDecodeError.truncated("PNG chunk \(type) is cut off") }
            let stored = UInt32(be32(b, i + 8 + length) & 0xFFFFFFFF)
            guard crc32(b, i + 4, i + 8 + length) == stored else { throw ImageDecodeError.corrupt("PNG chunk \(type) has a bad CRC") }
            if i == 8 {
                guard type == "IHDR", length == 13 else { throw ImageDecodeError.corrupt("PNG does not start with IHDR") }
                guard be32(b, i + 8) > 0, be32(b, i + 12) > 0 else { throw ImageDecodeError.corrupt("PNG size is zero") }
                sawIHDR = true
            }
            if type == "IDAT" { sawIDAT = true }
            if type == "IEND" { break }
            i += 12 + length
        }
        guard sawIHDR, sawIDAT else { throw ImageDecodeError.corrupt("PNG has no image data") }
    }

    private static func checkJPEG(_ b: [UInt8]) throws {
        var i = 2, sawSOS = false
        while true {
            // find the next marker
            while i < b.count, b[i] != 0xFF { i += 1 }
            while i < b.count, b[i] == 0xFF { i += 1 }
            guard i < b.count else { throw ImageDecodeError.truncated("JPEG ends before the EOI marker") }
            let marker = b[i]; i += 1
            switch marker {
            case 0xD9:
                guard sawSOS else { throw ImageDecodeError.corrupt("JPEG has no scan") }
                return
            case 0x00, 0x01, 0xD0...0xD7, 0xD8: continue
            default:
                guard i + 2 <= b.count else { throw ImageDecodeError.truncated("JPEG segment header") }
                let length = Int(b[i]) << 8 | Int(b[i + 1])
                guard length >= 2 else { throw ImageDecodeError.corrupt("JPEG segment length \(length)") }
                guard i + length <= b.count else { throw ImageDecodeError.truncated("JPEG segment is cut off") }
                i += length
                if marker == 0xDA { sawSOS = true }   // entropy-coded data follows; the marker search above skips it up to the next marker
            }
        }
    }

    private static func checkGIF(_ b: [UInt8]) throws {
        guard b.count >= 13 else { throw ImageDecodeError.truncated("GIF header") }
        var i = 13
        if b[10] & 0x80 != 0 { i += 3 * (1 << (Int(b[10] & 7) + 1)) }
        func skipSubBlocks() throws {
            while true {
                guard i < b.count else { throw ImageDecodeError.truncated("GIF data ends inside a block") }
                let n = Int(b[i]); i += 1
                if n == 0 { return }
                guard i + n <= b.count else { throw ImageDecodeError.truncated("GIF sub-block is cut off") }
                i += n
            }
        }
        while true {
            guard i < b.count else { throw ImageDecodeError.truncated("GIF ends before the first image") }
            switch b[i] {
            case 0x21: i += 2; try skipSubBlocks()
            case 0x2C:
                guard i + 10 <= b.count else { throw ImageDecodeError.truncated("GIF image descriptor") }
                let flags = b[i + 9]; i += 10
                if flags & 0x80 != 0 { i += 3 * (1 << (Int(flags & 7) + 1)) }
                guard i < b.count else { throw ImageDecodeError.truncated("GIF image data") }
                i += 1
                try skipSubBlocks()
                return   // first frame complete: later frames are never decoded
            case 0x3B: throw ImageDecodeError.corrupt("GIF has no image")
            default: throw ImageDecodeError.corrupt("GIF block \(b[i])")
            }
        }
    }

    private static func checkBMP(_ b: [UInt8]) throws {
        guard b.count >= 30 else { throw ImageDecodeError.truncated("BMP header") }
        let offset = le32(b, 10), headerSize = le32(b, 14)
        guard headerSize >= 12 else { throw ImageDecodeError.corrupt("BMP header size \(headerSize)") }
        guard b.count >= 14 + headerSize else { throw ImageDecodeError.truncated("BMP info header") }
        var w = 0, h = 0, bpp = 0, compression = 0
        if headerSize == 12 { w = le16(b, 18); h = le16(b, 20); bpp = le16(b, 24) }
        else { w = Int(Int32(truncatingIfNeeded: le32(b, 18))); h = abs(Int(Int32(truncatingIfNeeded: le32(b, 22)))); bpp = le16(b, 28); compression = b.count >= 34 ? le32(b, 30) : 0 }
        guard w > 0, h > 0, bpp > 0, w <= 1 << 16, h <= 1 << 16 else { throw ImageDecodeError.corrupt("BMP size \(w)x\(h) at \(bpp) bpp") }
        if compression == 0 || compression == 3 || compression == 6 {
            let stride = ((w * bpp + 31) / 32) * 4
            guard offset >= 14 + headerSize, offset <= b.count else { throw ImageDecodeError.truncated("BMP pixel offset") }
            guard b.count >= offset + stride * h else { throw ImageDecodeError.truncated("BMP pixel data (\(b.count - offset) of \(stride * h) bytes)") }
        }
    }

    // MARK: ICO

    static func icoEntries(_ b: [UInt8]) throws -> [ICOEntry] {
        guard b.count >= 6 else { throw ImageDecodeError.truncated("ICO header") }
        let count = le16(b, 4)
        guard count > 0 else { throw ImageDecodeError.corrupt("ICO with no images") }
        guard b.count >= 6 + count * 16 else { throw ImageDecodeError.truncated("ICO directory") }
        var entries: [ICOEntry] = []
        for i in 0..<count {
            let o = 6 + i * 16
            let e = ICOEntry(width: b[o] == 0 ? 256 : Int(b[o]), height: b[o + 1] == 0 ? 256 : Int(b[o + 1]), bpp: le16(b, o + 6), size: le32(b, o + 8), offset: le32(b, o + 12))
            guard e.size > 0, e.offset >= 6 + count * 16, e.offset + e.size <= b.count else { throw ImageDecodeError.corrupt("ICO entry \(i) outside the file") }
            entries.append(e)
        }
        return entries
    }

    /// The block 35 rule: the smallest entry whose longer side is at least `maxPixel`, else the largest; ties go to the higher bit depth, then the earlier entry.
    static func pickICO(_ entries: [ICOEntry], maxPixel: Int) -> Int {
        let side = { (e: ICOEntry) in max(e.width, e.height) }
        let enough = entries.indices.filter { side(entries[$0]) >= maxPixel }
        if maxPixel > 0, !enough.isEmpty {
            return enough.min { (side(entries[$0]), -entries[$0].bpp, $0) < (side(entries[$1]), -entries[$1].bpp, $1) }!
        }
        return entries.indices.max { (side(entries[$0]), entries[$0].bpp, -$0) < (side(entries[$1]), entries[$1].bpp, -$1) }!
    }

    // MARK: EXIF orientation

    /// 1...8 from the file's EXIF (JPEG APP1, PNG eXIf, TIFF IFD0); 1 when there is none or it is out of range.
    static func exifOrientation(_ b: [UInt8], _ container: ImageContainer) -> Int {
        switch container {
        case .tiff: return tiffOrientation(b, 0, b.count)
        case .jpeg:
            var i = 2
            while i + 4 <= b.count {
                guard b[i] == 0xFF else { return 1 }
                let marker = b[i + 1]
                if marker == 0xFF { i += 1; continue }
                if marker == 0xD8 || (0xD0...0xD7).contains(marker) || marker == 0x01 { i += 2; continue }
                if marker == 0xDA || marker == 0xD9 { return 1 }
                let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
                guard length >= 2, i + 2 + length <= b.count else { return 1 }
                if marker == 0xE1, length >= 8, Array(b[i + 4..<i + 10]) == [0x45, 0x78, 0x69, 0x66, 0, 0] { return tiffOrientation(b, i + 10, i + 2 + length) }
                i += 2 + length
            }
            return 1
        case .png:
            var i = 8
            while i + 12 <= b.count {
                let length = be32(b, i)
                guard length >= 0, i + 12 + length <= b.count else { return 1 }
                let type = String(decoding: b[i + 4..<i + 8], as: UTF8.self)
                if type == "eXIf" { return tiffOrientation(b, i + 8, i + 8 + length) }
                if type == "IDAT" || type == "IEND" { return 1 }
                i += 12 + length
            }
            return 1
        default: return 1
        }
    }

    private static func tiffOrientation(_ b: [UInt8], _ start: Int, _ end: Int) -> Int {
        guard end - start >= 8, end <= b.count else { return 1 }
        let little = b[start] == 0x49
        guard little || b[start] == 0x4D else { return 1 }
        func u16(_ i: Int) -> Int { little ? Int(b[i]) | Int(b[i + 1]) << 8 : Int(b[i]) << 8 | Int(b[i + 1]) }
        func u32(_ i: Int) -> Int { little ? u16(i) | u16(i + 2) << 16 : u16(i) << 16 | u16(i + 2) }
        guard u16(start + 2) == 42 else { return 1 }
        let ifd = start + u32(start + 4)
        guard ifd >= start, ifd + 2 <= end else { return 1 }
        let n = u16(ifd)
        for k in 0..<n {
            let e = ifd + 2 + k * 12
            guard e + 12 <= end else { return 1 }
            if u16(e) == 0x0112 {
                let v = u16(e + 8)   // SHORT, count 1: the value sits in the first two bytes of the value field
                return (1...8).contains(v) ? v : 1
            }
        }
        return 1
    }

    // MARK: the whole decode

    /// Decodes `data` with the platform codec under the shared policy. Never returns a blank or partial image: anything the policy or the codec cannot vouch for throws.
    static func decode(_ data: Data, maxPixel: Int) throws -> RGBAImage {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty, let container = sniff(bytes) else { throw ImageDecodeError.notAnImage }
        try checkComplete(bytes, container)
        var frame = 0
        if container == .ico {
            let entries = try icoEntries(bytes)
            let want = pickICO(entries, maxPixel: maxPixel)
            let body = Array(bytes[entries[want].offset..<entries[want].offset + entries[want].size])
            if sniff(body) == .png { try checkPNG(body) }
            let sizes = try SystemImageCodec.frameSizes(data)
            let nth = entries[..<want].filter { $0.width == entries[want].width && $0.height == entries[want].height }.count
            let candidates = sizes.indices.filter { sizes[$0] == (entries[want].width, entries[want].height) }
            guard nth < candidates.count else { throw ImageDecodeError.corrupt("ICO entry \(want) (\(entries[want].width)x\(entries[want].height)) was not decoded as a frame") }
            frame = candidates[nth]
        }
        var (image, profile) = try SystemImageCodec.decode(data, frameIndex: frame, applyProfile: false)
        if let profile {
            if let converter = ICCMatrixTRC(profile: profile) { image = converter.toSRGB(image) }
            else { image = try SystemImageCodec.decode(data, frameIndex: frame, applyProfile: true).image }   // LUT, grey or CMYK profile: the codec's colour transform
        }
        if container != .ico { image = image.oriented(exif: exifOrientation(bytes, container)) }
        guard maxPixel > 0, max(image.width, image.height) > maxPixel else { return image }
        let scale = Double(maxPixel) / Double(max(image.width, image.height))
        return ImageDecoder.resample(image, width: max(1, Int((Double(image.width) * scale).rounded())), height: max(1, Int((Double(image.height) * scale).rounded())))
    }
}

enum ICCProfile {
    /// True when the profile's description names sRGB (nothing to convert). Reads the `desc` tag text (v2 ASCII or v4 UTF-16BE) and looks for "sRGB".
    static func isSRGB(_ p: [UInt8]) -> Bool {
        guard p.count >= 132 else { return false }
        func u32(_ i: Int) -> Int { Int(p[i]) << 24 | Int(p[i + 1]) << 16 | Int(p[i + 2]) << 8 | Int(p[i + 3]) }
        let n = u32(128)
        guard n > 0, n < 200, p.count >= 132 + n * 12 else { return false }
        for k in 0..<n {
            let e = 132 + k * 12
            guard String(decoding: p[e..<e + 4], as: UTF8.self) == "desc" else { continue }
            let off = u32(e + 4), size = u32(e + 8)
            guard off >= 0, size > 0, off + size <= p.count else { return false }
            let text = Array(p[off..<min(off + size, off + 160)])
            let ascii = text.filter { $0 != 0 }
            return String(decoding: ascii, as: UTF8.self).contains("sRGB")
        }
        return false
    }
}
