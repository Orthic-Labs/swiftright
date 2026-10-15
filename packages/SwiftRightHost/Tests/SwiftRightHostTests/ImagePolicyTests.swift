import XCTest
@testable import SwiftRightHost
import SwiftRightRuntime

/// Wave 0 block I1: the policy layer above the OS codec (sniffing, completeness, ICO entry rule, EXIF orientation, thumbnail), plus the Mac ImageIO backend against the corpus.
/// The corpus is `factory/pipeline/blocks-w0-i1/corpus` (found from this file, or from SWR_I1_CORPUS when the package runs from a copy).
final class ImagePolicyTests: XCTestCase {
    /// A missing corpus skips the whole case here. It must not be thrown from `corpusDir()` itself: a test that calls it inside an assertion
    /// autoclosure (`XCTAssertEqual(try file(..), ..)`, `XCTUnwrap(try ..)`) reports an XCTSkip as a FAILURE (six failures on a Mac stage that lacked the corpus).
    override func setUpWithError() throws { _ = try corpusDir() }
    private func corpusDir() throws -> URL {
        if let e = ProcessInfo.processInfo.environment["SWR_I1_CORPUS"] { return URL(fileURLWithPath: e) }
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        let c = u.appendingPathComponent("factory/pipeline/blocks-w0-i1/corpus")
        guard FileManager.default.fileExists(atPath: c.path) else { throw XCTSkip("corpus not found at \(c.path)") }
        return c
    }
    private func file(_ name: String) throws -> Data { try Data(contentsOf: corpusDir().appendingPathComponent(name)) }

    // MARK: ICO entry rule (the block 35 rule: smallest entry at least maxPixel, else the largest; ties -> higher bit depth -> earlier entry)
    private func entry(_ side: Int, _ bpp: Int) -> ICOEntry { ICOEntry(width: side, height: side, bpp: bpp, size: 1, offset: 0) }

    func testICOPick() {
        let e = [entry(16, 32), entry(32, 32), entry(48, 24), entry(64, 32), entry(256, 32)]
        XCTAssertEqual(ImagePolicy.pickICO(e, maxPixel: 0), 4)
        XCTAssertEqual(ImagePolicy.pickICO(e, maxPixel: 16), 0)
        XCTAssertEqual(ImagePolicy.pickICO(e, maxPixel: 17), 1)
        XCTAssertEqual(ImagePolicy.pickICO(e, maxPixel: 33), 2)
        XCTAssertEqual(ImagePolicy.pickICO(e, maxPixel: 100), 4)
        XCTAssertEqual(ImagePolicy.pickICO(e, maxPixel: 1000), 4, "nothing is big enough: the largest")
    }

    func testICOTiesGoToHigherDepthThenEarlierEntry() {
        XCTAssertEqual(ImagePolicy.pickICO([entry(16, 4), entry(16, 8)], maxPixel: 16), 1)
        XCTAssertEqual(ImagePolicy.pickICO([entry(16, 8), entry(16, 4)], maxPixel: 16), 0)
        XCTAssertEqual(ImagePolicy.pickICO([entry(16, 8), entry(16, 8)], maxPixel: 16), 0)
        XCTAssertEqual(ImagePolicy.pickICO([entry(16, 4), entry(16, 8), entry(16, 8)], maxPixel: 0), 1)
        XCTAssertEqual(ImagePolicy.pickICO([entry(32, 8), entry(32, 32)], maxPixel: 0), 1)
    }

    func testICOPolicyAgreesWithTheOldDecoderOnEntrySize() throws {
        let data = try file("ico-multi.ico")
        for mp in [0, 16, 17, 33, 48, 100, 256, 1000] {
            let saved = ImageDecoder.backend; ImageDecoder.backend = .swift; defer { ImageDecoder.backend = saved }
            let old = try ImageDecoder.decode(data, maxPixel: mp)
            let entries = try ImagePolicy.icoEntries([UInt8](data))
            let e = entries[ImagePolicy.pickICO(entries, maxPixel: mp)]
            let side = max(e.width, e.height)
            XCTAssertEqual(max(old.width, old.height), mp > 0 && side > mp ? mp : side, "maxPixel \(mp)")
        }
    }

    // MARK: sniffing and completeness
    func testSniff() throws {
        XCTAssertEqual(ImagePolicy.sniff([UInt8](try file("png-rgba8.png"))), .png)
        XCTAssertEqual(ImagePolicy.sniff([UInt8](try file("jpeg-baseline-420.jpg"))), .jpeg)
        XCTAssertEqual(ImagePolicy.sniff([UInt8](try file("gif-3frames.gif"))), .gif)
        XCTAssertEqual(ImagePolicy.sniff([UInt8](try file("bmp-24.bmp"))), .bmp)
        XCTAssertEqual(ImagePolicy.sniff([UInt8](try file("ico-two.ico"))), .ico)
        XCTAssertNil(ImagePolicy.sniff([]))
        XCTAssertNil(ImagePolicy.sniff(Array("hello world".utf8)))
    }

    func testEveryNegativeControlThrowsAndNeverReturnsAnImage() throws {
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: corpusDir().appendingPathComponent("manifest.json"))) as! [String: Any]
        var checked = 0
        for c in manifest["cases"] as! [[String: Any]] where c["kind"] as? String == "negative" {
            let data = try file(c["file"] as! String)
            XCTAssertThrowsError(try ImagePolicy.decode(data, maxPixel: 0), "\(c["id"]!)") { error in XCTAssertTrue(error is ImageDecodeError, "\(c["id"]!): \(error)") }
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 20)
    }

    func testCompletenessOnGoodFiles() throws {
        for name in ["png-rgba8-adam7.png", "png-photo-rgb8.png", "jpeg-progressive.jpg", "jpeg-cmyk.jpg", "gif-3frames.gif", "bmp-32-alpha-v5.bmp", "ico-multi.ico"] {
            let b = [UInt8](try file(name))
            XCTAssertNoThrow(try ImagePolicy.checkComplete(b, ImagePolicy.sniff(b)!), name)
        }
    }

    // MARK: EXIF orientation: every file shows the same upright 12 x 8 picture
    func testEXIFOrientationRead() throws {
        for o in 1...8 {
            let b = [UInt8](try file("jpeg-exif-\(o).jpg"))
            XCTAssertEqual(ImagePolicy.exifOrientation(b, .jpeg), o)
        }
        XCTAssertEqual(ImagePolicy.exifOrientation([UInt8](try file("jpeg-baseline-420.jpg")), .jpeg), 1)
    }

    func testEightOrientationsDecodeToTheSameUprightPictureOnTheMac() throws {
        #if canImport(ImageIO)
        let upright = try ImagePolicy.decode(try file("jpeg-exif-1.jpg"), maxPixel: 0)
        XCTAssertEqual(upright.width, 12); XCTAssertEqual(upright.height, 8)
        for o in 2...8 {
            let r = try ImagePolicy.decode(try file("jpeg-exif-\(o).jpg"), maxPixel: 0)
            XCTAssertEqual(r.width, 12, "orientation \(o)"); XCTAssertEqual(r.height, 8, "orientation \(o)")
            var worst = 0
            for i in 0..<r.rgba.count { worst = max(worst, abs(Int(r.rgba[i]) - Int(upright.rgba[i]))) }
            XCTAssertLessThanOrEqual(worst, 3, "orientation \(o): lossy JPEG q100 4:4:4, the same picture within the codec's rounding")
        }
        #endif
    }

    func testICCProfileDescriptionCheck() throws {
        let png = [UInt8](try file("png-p3-rgb8.png"))
        // the P3 test profile is not sRGB; an sRGB-described profile would be skipped (nothing to convert)
        var profile: [UInt8]?
        var i = 8
        while i + 12 <= png.count {
            let len = Int(png[i]) << 24 | Int(png[i + 1]) << 16 | Int(png[i + 2]) << 8 | Int(png[i + 3])
            if String(decoding: png[i + 4..<i + 8], as: UTF8.self) == "iCCP" {
                var j = i + 8; while png[j] != 0 { j += 1 }
                let z = Data(png[j + 2..<i + 8 + len])
                profile = Self.inflate(z)
            }
            i += 12 + len
        }
        XCTAssertNotNil(profile)
        if let profile { XCTAssertFalse(ICCProfile.isSRGB(profile)) }
    }

    private static func inflate(_ zlibData: Data) -> [UInt8]? {
        // zlib stream = 2 byte header + raw deflate + adler32; the host's own Inflate reads raw deflate
        try? Inflate.zlibDecompress([UInt8](zlibData), limit: 1 << 20)
    }

    func testThumbnailDimensions() throws {
        #if canImport(ImageIO)
        for mp in [32, 20, 8] {
            let r = try ImagePolicy.decode(try file("png-photo-rgb8.png"), maxPixel: mp)
            XCTAssertEqual(max(r.width, r.height), mp)
            XCTAssertEqual(r.width, mp); XCTAssertEqual(r.height, Int((48.0 * Double(mp) / 64.0).rounded()))
        }
        let same = try ImagePolicy.decode(try file("png-photo-rgb8.png"), maxPixel: 200)
        XCTAssertEqual(same.width, 64, "never upscaled")
        #endif
    }

    func testSelectableBackend() throws {
        let data = try file("png-rgba8.png")
        let saved = ImageDecoder.backend
        defer { ImageDecoder.backend = saved }
        ImageDecoder.backend = .swift
        let a = try ImageDecoder.decode(data, maxPixel: 0)
        #if canImport(ImageIO)
        ImageDecoder.backend = .system
        let b = try ImageDecoder.decode(data, maxPixel: 0)
        XCTAssertEqual(a, b, "both backends decode a lossless RGBA PNG to the same bytes")
        XCTAssertEqual(a.rgba, b.rgba)
        #endif
    }

    // MARK: ICC matrix/TRC against CoreGraphics' own conversion (the Mac oracle: raw samples and converted pixels, dumped by mac_oracle.swift into ../expected)
    private func expected(_ name: String) throws -> [UInt8] {
        let dir = try corpusDir().deletingLastPathComponent().appendingPathComponent("expected")
        return try Inflate.zlibDecompress([UInt8](try Data(contentsOf: dir.appendingPathComponent(name))), limit: 1 << 24)
    }

    private func profileOf(png: String) throws -> [UInt8] {
        let b = [UInt8](try file(png))
        var i = 8
        while i + 12 <= b.count {
            let len = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            if String(decoding: b[i + 4..<i + 8], as: UTF8.self) == "iCCP" {
                var j = i + 8; while b[j] != 0 { j += 1 }
                return try Inflate.zlibDecompress(Array(b[j + 2..<i + 8 + len]), limit: 1 << 20)
            }
            i += 12 + len
        }
        throw XCTSkip("no iCCP")
    }

    func testMatrixTRCMatchesCoreGraphicsWithinOneLevelAndClipsLikeIt() throws {
        for (png, w, h) in [("png-p3-rgb8", 24, 20), ("png-p3-rgba8", 24, 20)] {
            let converter = try XCTUnwrap(ICCMatrixTRC(profile: try profileOf(png: png + ".png")))
            let raw = try expected("\(png).raw.rgba.z"), want = try expected("\(png).rgba.z")
            let out = converter.toSRGB(RGBAImage(width: w, height: h, rgba: raw)!)
            var worst = 0, exact = 0
            for i in stride(from: 0, to: raw.count, by: 4) where want[i + 3] == 255 {
                for c in 0..<3 { let d = abs(Int(out.rgba[i + c]) - Int(want[i + c])); worst = max(worst, d); if d == 0 { exact += 1 } }
            }
            XCTAssertLessThanOrEqual(worst, 1, "\(png): measured against CoreGraphics on macOS 27")
            XCTAssertGreaterThan(exact, 0)
        }
    }

    func testMatrixTRCRefusesWhatItCannotConvert() {
        XCTAssertNil(ICCMatrixTRC(profile: []))
        XCTAssertNil(ICCMatrixTRC(profile: [UInt8](repeating: 0, count: 200)))
    }
}
