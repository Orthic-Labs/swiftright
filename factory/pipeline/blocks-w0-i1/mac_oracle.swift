import CoreGraphics
import Foundation
import ImageIO

// I1 oracle: what ImageIO (CGImageSource) produces for every corpus case, as straight-alpha RGBA8 in sRGB (the contract of SwiftRightImageIO), written as buffers.
// usage: mac_oracle CORPUS_DIR OUT_DIR      (runs headless: no window, no capture; factory/tools/image-io/mac-tool.sh compiles it on the internal disk)
// Per case OUT_DIR/<id>.rgba (the expected buffer) and an entry in OUT_DIR/oracle.json. Method per case:
//   direct   the CGImage is 8-bit, non-premultiplied alpha (or none), in sRGB: its samples are the buffer (no arithmetic).
//   draw     anything else (16-bit, gray, palette, other spaces, premultiplied): drawn into an 8-bit premultiplied sRGB context and un-premultiplied;
//            `alphaLossy` is true when a pixel has alpha strictly between 0 and 255 (the un-premultiply cannot return the source bytes there).
// Also <id>.raw.rgba for cases whose colour space is not sRGB: the samples drawn into a context of the image's own space (no conversion).

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func spaceName(_ s: CGColorSpace?) -> String {
    guard let s else { return "nil" }
    if let n = s.name as String? { return n }
    return "icc:" + ((s.copyICCData().map { "\(CFDataGetLength($0))B" }) ?? "?")
}

struct Buf { var w: Int; var h: Int; var rgba: [UInt8]; var method: String; var alphaLossy: Bool }

func unpremultiply(_ d: [UInt8]) -> ([UInt8], Bool) {
    var out = d; var lossy = false
    for i in stride(from: 0, to: d.count, by: 4) {
        let a = Int(d[i + 3])
        if a == 0 { out[i] = 0; out[i + 1] = 0; out[i + 2] = 0 }
        else if a < 255 {
            lossy = true
            for c in 0..<3 { out[i + c] = UInt8(min(255, (Int(d[i + c]) * 255 + a / 2) / a)) }
        }
    }
    return (out, lossy)
}

func draw(_ cg: CGImage, into space: CGColorSpace, width: Int, height: Int, transform: CGAffineTransform = .identity) -> [UInt8]? {
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let ok: Bool = data.withUnsafeMutableBytes { p in
        guard let ctx = CGContext(data: p.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.interpolationQuality = .none
        ctx.concatenate(transform)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return true
    }
    return ok ? data : nil
}

func straight(_ cg: CGImage, forceDraw: Bool = false) -> Buf? {
    let w = cg.width, h = cg.height
    let ai = cg.alphaInfo
    let nonPremul: Bool = [.none, .last, .first, .noneSkipLast, .noneSkipFirst].contains(ai)
    let isSRGB = (cg.colorSpace?.name as String?) == (CGColorSpace.sRGB as String)
    if !forceDraw, cg.bitsPerComponent == 8, cg.bitsPerPixel == 32 || cg.bitsPerPixel == 24, nonPremul, isSRGB,
       (cg.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue) == 0, let provider = cg.dataProvider, let cf = provider.data {
        let bytes = [UInt8](cf as Data), bpp = cg.bitsPerPixel / 8, bpr = cg.bytesPerRow
        guard bytes.count >= bpr * h else { return nil }
        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let o = y * bpr + x * bpp, d = (y * w + x) * 4
            switch ai {
            case .last: out[d] = bytes[o]; out[d + 1] = bytes[o + 1]; out[d + 2] = bytes[o + 2]; out[d + 3] = bytes[o + 3]
            case .first: out[d] = bytes[o + 1]; out[d + 1] = bytes[o + 2]; out[d + 2] = bytes[o + 3]; out[d + 3] = bytes[o]
            case .noneSkipLast, .none: out[d] = bytes[o]; out[d + 1] = bytes[o + 1]; out[d + 2] = bytes[o + 2]
            case .noneSkipFirst: out[d] = bytes[o + 1]; out[d + 1] = bytes[o + 2]; out[d + 2] = bytes[o + 3]
            default: break
            }
        } }
        return Buf(w: w, h: h, rgba: out, method: "direct", alphaLossy: false)
    }
    guard let d = draw(cg, into: srgb, width: w, height: h) else { return nil }
    let (u, lossy) = unpremultiply(d)
    return Buf(w: w, h: h, rgba: u, method: "draw", alphaLossy: lossy)
}

func rawSamples(_ cg: CGImage) -> Buf? {
    guard let space = cg.colorSpace, space.model == .rgb || space.model == .monochrome else { return nil }
    let w = cg.width, h = cg.height
    // draw into a context in the image's own space: no conversion; gray expands to RGB
    if space.model == .monochrome {
        var g = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = g.withUnsafeMutableBytes { p in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .none; ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        guard ok else { return nil }
        var out = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<w * h { out[i * 4] = g[i]; out[i * 4 + 1] = g[i]; out[i * 4 + 2] = g[i] }
        return Buf(w: w, h: h, rgba: out, method: "raw-gray", alphaLossy: false)
    }
    guard let d = draw(cg, into: space, width: w, height: h) else { return nil }
    let (u, lossy) = unpremultiply(d)
    return Buf(w: w, h: h, rgba: u, method: "raw", alphaLossy: lossy)
}

func orient(_ b: Buf, _ o: Int) -> Buf {
    if o == 1 || o < 1 || o > 8 { return b }
    let sw = b.w, sh = b.h, swap = o >= 5
    let dw = swap ? sh : sw, dh = swap ? sw : sh
    var out = [UInt8](repeating: 0, count: dw * dh * 4)
    for y in 0..<dh { for x in 0..<dw {
        let sx: Int, sy: Int
        switch o {
        case 2: sx = sw - 1 - x; sy = y
        case 3: sx = sw - 1 - x; sy = sh - 1 - y
        case 4: sx = x; sy = sh - 1 - y
        case 5: sx = y; sy = x
        case 6: sx = y; sy = sh - 1 - x
        case 7: sx = sw - 1 - y; sy = sh - 1 - x
        default: sx = sw - 1 - y; sy = x
        }
        for c in 0..<4 { out[(y * dw + x) * 4 + c] = b.rgba[(sy * sw + sx) * 4 + c] }
    } }
    return Buf(w: dw, h: dh, rgba: out, method: b.method + "+orient", alphaLossy: b.alphaLossy)
}

@main struct Oracle {
    static func main() throws {
        let corpus = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: corpus.appendingPathComponent("manifest.json"))) as! [String: Any]
        var index: [[String: Any]] = []
        for c in (manifest["cases"] as! [[String: Any]]) {
            let id = c["id"] as! String, file = c["file"] as! String, kind = c["kind"] as! String, mp = c["maxPixel"] as? Int ?? 0
            let data = try Data(contentsOf: corpus.appendingPathComponent(file))
            var e: [String: Any] = ["id": id, "kind": kind, "maxPixel": mp, "file": file]
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { e["oracle"] = "no-source"; index.append(e); continue }
            e["imageIOStatus"] = CGImageSourceGetStatus(src).rawValue
            e["imageIOCount"] = CGImageSourceGetCount(src)
            e["imageIOType"] = (CGImageSourceGetType(src) as String?) ?? "nil"
            if kind == "negative" {
                let cg = CGImageSourceGetCount(src) > 0 ? CGImageSourceCreateImageAtIndex(src, 0, nil) : nil
                e["imageIOReturnsImage"] = cg != nil
                if let cg, let b = straight(cg) { e["imageIOPartial"] = "\(b.w)x\(b.h)" }
                e["statusAfterDecode"] = CGImageSourceGetStatus(src).rawValue
                index.append(e); continue
            }
            if kind == "ico-policy" { e["oracle"] = "policy-only"; index.append(e); continue }
            var idx = 0
            if kind == "ico" { idx = c["expectIndex"] as? Int ?? 0 }
            // map the directory index to ImageIO's index by size when ImageIO orders entries differently
            if kind == "ico", let entries = c["ico"] as? [[String: Any]] {
                let want = entries[idx]; let ww = want["w"] as! Int, hh = want["h"] as! Int, bb = want["bpp"] as! Int
                var found: [Int] = []
                for i in 0..<CGImageSourceGetCount(src) {
                    if let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any], (p["PixelWidth"] as? Int) == ww, (p["PixelHeight"] as? Int) == hh { found.append(i) }
                }
                e["icoDirectoryIndex"] = idx; e["icoSameSizeIOIndexes"] = found
                // same-size entries: pick by order among entries of that size in the directory
                let sameSizeBefore = entries[..<idx].filter { ($0["w"] as! Int) == ww && ($0["h"] as! Int) == hh }.count
                if sameSizeBefore < found.count { idx = found[sameSizeBefore] } else if let f = found.first { idx = f }
                _ = bb
            }
            e["imageIOIndex"] = idx
            let props = CGImageSourceCopyPropertiesAtIndex(src, idx, nil) as? [String: Any] ?? [:]
            let orientation = (props[kCGImagePropertyOrientation as String] as? Int) ?? 1
            e["sourceOrientation"] = orientation
            e["hasProfile"] = props["ProfileName"] as? String ?? ""
            var result: Buf?
            if kind == "thumbnail" { e["thumbnailOracle"] = true }
            if kind == "thumbnail" || kind == "orientation" {
                let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: kind == "orientation" ? 10000 : mp,
                                             kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
                if let cg = CGImageSourceCreateThumbnailAtIndex(src, idx, opts as CFDictionary) {
                    e["thumbColorSpace"] = spaceName(cg.colorSpace); e["thumbAlphaInfo"] = cg.alphaInfo.rawValue; e["thumbBPC"] = cg.bitsPerComponent
                    result = straight(cg)
                }
                if kind == "orientation", let cg = CGImageSourceCreateImageAtIndex(src, idx, nil), let plain = straight(cg) {
                    let manual = orient(plain, orientation)
                    e["orientManualEqualsImageIO"] = (manual.w == result?.w && manual.h == result?.h && manual.rgba == result?.rgba)
                    e["plainSize"] = "\(plain.w)x\(plain.h)"
                    if let rr = result, rr.w != manual.w || rr.h != manual.h { result = manual; e["orientFallbackManual"] = true }
                }
            } else {
                guard let cg = CGImageSourceCreateImageAtIndex(src, idx, nil) else { e["oracle"] = "ImageIO returned nil"; index.append(e); continue }
                e["colorSpace"] = spaceName(cg.colorSpace)
                e["colorModel"] = cg.colorSpace.map { "\($0.model.rawValue)" } ?? "nil"
                e["bpc"] = cg.bitsPerComponent; e["bpp"] = cg.bitsPerPixel; e["alphaInfo"] = cg.alphaInfo.rawValue; e["bitmapInfo"] = cg.bitmapInfo.rawValue
                result = straight(cg)
                if kind == "ico", mp > 0, max(cg.width, cg.height) > mp {
                    // the entry is larger than maxPixel: the service scales it down; the oracle is ImageIO's own thumbnail of that entry
                    let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: mp, kCGImageSourceShouldCacheImmediately: true]
                    if let t = CGImageSourceCreateThumbnailAtIndex(src, idx, opts as CFDictionary) { result = straight(t); e["thumbnailOracle"] = true }
                }
                if (cg.colorSpace?.name as String?) != (CGColorSpace.sRGB as String), let raw = rawSamples(cg) {
                    try Data(raw.rgba).write(to: out.appendingPathComponent("\(id).raw.rgba"))
                    e["rawMethod"] = raw.method
                }
            }
            guard let r = result else { e["oracle"] = "conversion failed"; index.append(e); continue }
            try Data(r.rgba).write(to: out.appendingPathComponent("\(id).rgba"))
            e["w"] = r.w; e["h"] = r.h; e["method"] = r.method; e["alphaLossy"] = r.alphaLossy
            index.append(e)
        }
        let j = try JSONSerialization.data(withJSONObject: ["os": ProcessInfo.processInfo.operatingSystemVersionString, "cases": index], options: [.prettyPrinted, .sortedKeys])
        try j.write(to: out.appendingPathComponent("oracle.json"))
        print("oracle cases:", index.count)
    }
}
