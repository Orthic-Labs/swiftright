import Foundation
import SwiftRightRuntime

/// PNG decoder for the Windows host: every colour type and bit depth the specification allows (gray 1/2/4/8/16, RGB 8/16, palette 1/2/4/8,
/// gray+alpha 8/16, RGBA 8/16), tRNS (palette alpha, gray and RGB colour keys), all five filters. sRGB, gAMA, cHRM, iCCP and other ancillary
/// chunks are ignored (no colour management: stored sample values are the output values; 16-bit samples round to 8 bits). Adam7 interlace is refused
/// with `ImageDecodeError.unsupported`. Chunk CRCs, the zlib checksum, sizes and chunk order are all checked.
enum PNGDecoder {
    static let signature: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    /// Largest accepted image, in pixels (a corrupt header must not allocate gigabytes).
    static let maxPixels = 1 << 26

    static func decode(_ data: [UInt8]) throws -> RGBAImage {
        guard data.count >= 8, Array(data[0..<8]) == signature else { throw ImageDecodeError.notAnImage }
        var pos = 8
        var header: (w: Int, h: Int, depth: Int, type: Int)?
        var palette: [UInt8] = []
        var trns: [UInt8]?
        var idat: [UInt8] = []
        var sawIDAT = false, idatEnded = false, sawEnd = false
        func be32(_ i: Int) -> Int { Int(data[i]) << 24 | Int(data[i + 1]) << 16 | Int(data[i + 2]) << 8 | Int(data[i + 3]) }

        while pos < data.count {
            guard pos + 12 <= data.count else { throw ImageDecodeError.truncated("chunk header") }
            let length = be32(pos)
            guard length >= 0, length <= data.count - pos - 12 else { throw ImageDecodeError.truncated("chunk data") }
            let typeBytes = Array(data[pos + 4..<pos + 8])
            let type = String(decoding: typeBytes, as: UTF8.self)
            let body = pos + 8
            let stored = UInt32(truncatingIfNeeded: be32(body + length))
            guard Inflate.crc32(data[pos + 4..<body + length]) == stored else { throw ImageDecodeError.corrupt("CRC mismatch in chunk \(type)") }
            switch type {
            case "IHDR":
                guard header == nil, pos == 8, length == 13 else { throw ImageDecodeError.corrupt("bad IHDR") }
                let w = be32(body), h = be32(body + 4)
                let depth = Int(data[body + 8]), colorType = Int(data[body + 9])
                guard w > 0, h > 0, w <= 1 << 24, h <= 1 << 24, w * h <= maxPixels else { throw ImageDecodeError.corrupt("image size \(w)x\(h) out of range") }
                let allowed: [Int: [Int]] = [0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]]
                guard allowed[colorType]?.contains(depth) == true else { throw ImageDecodeError.corrupt("colour type \(colorType) with bit depth \(depth)") }
                guard data[body + 10] == 0, data[body + 11] == 0 else { throw ImageDecodeError.corrupt("unknown compression or filter method") }
                switch data[body + 12] {
                case 0: break
                case 1: throw ImageDecodeError.unsupported("Adam7 interlaced PNG")
                default: throw ImageDecodeError.corrupt("unknown interlace method")
                }
                header = (w, h, depth, colorType)
            case "PLTE":
                guard let hd = header, !sawIDAT, palette.isEmpty, hd.type != 0, hd.type != 4 else { throw ImageDecodeError.corrupt("misplaced PLTE") }
                guard length % 3 == 0, length >= 3, length <= 768, length / 3 <= 1 << hd.depth else { throw ImageDecodeError.corrupt("bad palette size") }
                palette = Array(data[body..<body + length])
            case "tRNS":
                guard header != nil, !sawIDAT else { throw ImageDecodeError.corrupt("misplaced tRNS") }
                trns = Array(data[body..<body + length])
            case "IDAT":
                guard header != nil, !idatEnded else { throw ImageDecodeError.corrupt("misplaced IDAT") }
                sawIDAT = true
                idat.append(contentsOf: data[body..<body + length])
            case "IEND":
                sawEnd = true
            default:
                // ancillary chunks (lowercase first letter: sRGB, gAMA, cHRM, pHYs, tEXt, ...) are skipped; an unknown critical chunk is an error
                if sawIDAT { idatEnded = true }
                if typeBytes[0] & 0x20 == 0 { throw ImageDecodeError.unsupported("critical chunk \(type)") }
            }
            if type != "IDAT", sawIDAT { idatEnded = true }
            pos = body + length + 4
            if sawEnd { break }
        }
        guard let hd = header else { throw ImageDecodeError.corrupt("no IHDR") }
        guard sawIDAT else { throw ImageDecodeError.truncated("no image data") }
        guard sawEnd else { throw ImageDecodeError.truncated("no IEND") }
        if hd.type == 3 { guard !palette.isEmpty else { throw ImageDecodeError.corrupt("palette image without PLTE") } }

        let channels = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4][hd.type]!
        let bitsPerPixel = channels * hd.depth
        let rowBytes = (hd.w * bitsPerPixel + 7) / 8
        let rawSize = hd.h * (rowBytes + 1)
        let raw: [UInt8]
        do { raw = try Inflate.zlibDecompress(idat, limit: rawSize) } catch { throw ImageDecodeError.corrupt("deflate stream: \(error)") }
        guard raw.count == rawSize else { throw ImageDecodeError.truncated("image data is \(raw.count) bytes, expected \(rawSize)") }

        // unfilter in place into `pixels` (rows without the filter byte)
        let bpp = max(1, bitsPerPixel / 8)
        var pixels = [UInt8](repeating: 0, count: hd.h * rowBytes)
        for y in 0..<hd.h {
            let src = y * (rowBytes + 1)
            let filter = raw[src]
            let row = y * rowBytes, prev = row - rowBytes
            for i in 0..<rowBytes {
                let x = raw[src + 1 + i]
                let a = i >= bpp ? Int(pixels[row + i - bpp]) : 0
                let b = y > 0 ? Int(pixels[prev + i]) : 0
                let c = (y > 0 && i >= bpp) ? Int(pixels[prev + i - bpp]) : 0
                let value: Int
                switch filter {
                case 0: value = Int(x)
                case 1: value = Int(x) + a
                case 2: value = Int(x) + b
                case 3: value = Int(x) + (a + b) / 2
                case 4:
                    let p = a + b - c
                    let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                    value = Int(x) + (pa <= pb && pa <= pc ? a : (pb <= pc ? b : c))
                default: throw ImageDecodeError.corrupt("unknown filter type \(filter) in row \(y)")
                }
                pixels[row + i] = UInt8(truncatingIfNeeded: value)
            }
        }

        // tRNS interpretation
        var paletteAlpha: [UInt8] = []
        var keyGray: Int?, keyRGB: (Int, Int, Int)?
        if let t = trns {
            switch hd.type {
            case 3:
                guard t.count <= palette.count / 3 else { throw ImageDecodeError.corrupt("tRNS longer than the palette") }
                paletteAlpha = t
            case 0:
                guard t.count == 2 else { throw ImageDecodeError.corrupt("bad tRNS for gray") }
                keyGray = Int(t[0]) << 8 | Int(t[1])
            case 2:
                guard t.count == 6 else { throw ImageDecodeError.corrupt("bad tRNS for RGB") }
                keyRGB = (Int(t[0]) << 8 | Int(t[1]), Int(t[2]) << 8 | Int(t[3]), Int(t[4]) << 8 | Int(t[5]))
            default:
                throw ImageDecodeError.corrupt("tRNS with an alpha colour type")
            }
        }

        let depth = hd.depth
        let maxSample = (1 << depth) - 1
        func sample(_ row: Int, _ index: Int) -> Int {   // sample `index` (0-based, in samples) of the row starting at byte `row`
            switch depth {
            case 8: return Int(pixels[row + index])
            case 16: return Int(pixels[row + index * 2]) << 8 | Int(pixels[row + index * 2 + 1])
            default:
                let bit = index * depth
                let byte = Int(pixels[row + bit / 8])
                return (byte >> (8 - depth - bit % 8)) & maxSample
            }
        }
        func to8(_ v: Int) -> UInt8 {
            switch depth {
            case 8: return UInt8(v)
            case 16: return UInt8((v * 255 + 32767) / 65535)
            default: return UInt8((v * 255) / maxSample)
            }
        }

        var out = [UInt8](repeating: 0, count: hd.w * hd.h * 4)
        for y in 0..<hd.h {
            let row = y * rowBytes
            for x in 0..<hd.w {
                let o = (y * hd.w + x) * 4
                switch hd.type {
                case 0:
                    let v = sample(row, x)
                    let g = to8(v)
                    out[o] = g; out[o + 1] = g; out[o + 2] = g
                    out[o + 3] = keyGray == v ? 0 : 255
                case 2:
                    let r = sample(row, x * 3), g = sample(row, x * 3 + 1), b = sample(row, x * 3 + 2)
                    out[o] = to8(r); out[o + 1] = to8(g); out[o + 2] = to8(b)
                    out[o + 3] = (keyRGB.map { $0.0 == r && $0.1 == g && $0.2 == b } ?? false) ? 0 : 255
                case 3:
                    let i = sample(row, x)
                    guard i * 3 + 2 < palette.count else { throw ImageDecodeError.corrupt("palette index \(i) out of range at row \(y)") }
                    out[o] = palette[i * 3]; out[o + 1] = palette[i * 3 + 1]; out[o + 2] = palette[i * 3 + 2]
                    out[o + 3] = i < paletteAlpha.count ? paletteAlpha[i] : 255
                case 4:
                    let g = to8(sample(row, x * 2))
                    out[o] = g; out[o + 1] = g; out[o + 2] = g
                    out[o + 3] = to8(sample(row, x * 2 + 1))
                default:
                    out[o] = to8(sample(row, x * 4)); out[o + 1] = to8(sample(row, x * 4 + 1))
                    out[o + 2] = to8(sample(row, x * 4 + 2)); out[o + 3] = to8(sample(row, x * 4 + 3))
                }
            }
        }
        guard let image = RGBAImage(width: hd.w, height: hd.h, rgba: out) else { throw ImageDecodeError.corrupt("pixel buffer") }
        return image
    }
}
