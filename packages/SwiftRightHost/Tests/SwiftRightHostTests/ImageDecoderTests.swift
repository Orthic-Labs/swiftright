import XCTest
@testable import SwiftRightHost
import SwiftRightRuntime

/// Round 5 block 35: the Swift PNG / ICO decoder against bytes written by Python's zlib and struct (ImageFixtures.swift).
final class ImageDecoderTests: XCTestCase {
    private func decode(_ base64: String, maxPixel: Int = 0) throws -> RGBAImage {
        try ImageDecoder.decode(ImageFixtures.data(base64), maxPixel: maxPixel)
    }

    func testEveryPNGFixtureDecodesToTheIndependentEncodersPixels() throws {
        XCTAssertGreaterThanOrEqual(ImageFixtures.cases.count, 25)
        for c in ImageFixtures.cases {
            let image = try decode(c.png)
            XCTAssertEqual(image.width, c.width, c.name)
            XCTAssertEqual(image.height, c.height, c.name)
            XCTAssertEqual(image.rgba, [UInt8](ImageFixtures.data(c.rgba)), c.name)
        }
    }

    func testCoverage() {
        let names = Set(ImageFixtures.cases.map(\.name))
        for expected in ["gray1", "gray2", "gray4", "gray8", "gray16", "graya8", "graya16", "rgb8", "rgb16", "rgba8_f0", "rgba8_f1", "rgba8_f2", "rgba8_f3", "rgba8_f4",
                         "rgba16", "pal1", "pal2_trns", "pal4", "pal8_trns", "rgb8_trns", "gray8_trns", "rgba8_stored", "rgba8_dynamic", "rgba8_ancillary", "rgba8_mixed"] {
            XCTAssertTrue(names.contains(expected), expected)
        }
    }

    func testStraightAlphaIsNotPremultiplied() throws {
        let c = ImageFixtures.cases.first { $0.name == "rgba8_f0" }!
        let image = try decode(c.png)
        // the pattern has alpha below 255 with non-zero colour: the colour must stay unscaled
        XCTAssertTrue(stride(from: 3, to: image.rgba.count, by: 4).contains { image.rgba[$0] < 255 && image.rgba[$0 - 3] > image.rgba[$0] })
    }

    func testAdam7IsRefusedVisibly() {
        XCTAssertThrowsError(try decode(ImageFixtures.corrupt["adam7"]!)) { error in
            guard case ImageDecodeError.unsupported(let why) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(why.contains("Adam7"))
        }
    }

    func testCorruptInputThrowsATypedError() {
        for (name, base64) in ImageFixtures.corrupt where name != "adam7" {
            XCTAssertThrowsError(try decode(base64), name) { error in
                XCTAssertTrue(error is ImageDecodeError, "\(name): \(error)")
                XCTAssertFalse("\(error)".isEmpty)
            }
        }
        XCTAssertThrowsError(try ImageDecoder.decode(Data(), maxPixel: 16)) { XCTAssertEqual($0 as? ImageDecodeError, .notAnImage) }
        XCTAssertThrowsError(try decode(ImageFixtures.corrupt["not_an_image"]!)) { XCTAssertEqual($0 as? ImageDecodeError, .notAnImage) }
    }

    func testCorruptKindsAreSpecific() {
        func kind(_ name: String) -> String {
            do { _ = try decode(ImageFixtures.corrupt[name]!); return "decoded" } catch ImageDecodeError.corrupt { return "corrupt" } catch ImageDecodeError.truncated { return "truncated" } catch { return "\(error)" }
        }
        XCTAssertEqual(kind("bad_crc"), "corrupt")
        XCTAssertEqual(kind("truncated"), "truncated")
        XCTAssertEqual(kind("no_iend"), "truncated")
        XCTAssertEqual(kind("bad_zlib_header"), "corrupt")
        XCTAssertEqual(kind("bad_adler"), "corrupt")
        XCTAssertEqual(kind("bad_filter"), "corrupt")
        XCTAssertEqual(kind("short_data"), "truncated")
        XCTAssertEqual(kind("palette_index_out_of_range"), "corrupt")
        XCTAssertEqual(kind("no_plte"), "corrupt")
    }

    func testEveryTruncationOfAGoodFileFailsCleanly() throws {
        let good = ImageFixtures.data(ImageFixtures.cases.first { $0.name == "rgba8_dynamic" }!.png)
        for n in stride(from: 0, to: good.count, by: 7) {
            XCTAssertThrowsError(try ImageDecoder.decode(good.prefix(n), maxPixel: 0), "prefix \(n)")
        }
    }

    func testBitFlipsNeverCrash() {
        let good = [UInt8](ImageFixtures.data(ImageFixtures.cases.first { $0.name == "pal8_trns" }!.png))
        for i in 0..<good.count {
            var d = good; d[i] ^= 0x55
            _ = try? ImageDecoder.decode(Data(d), maxPixel: 0)   // any outcome but a trap
        }
    }

    // MARK: ICO

    func testICOPicksTheSmallestEntryAtLeastMaxPixel() throws {
        let ico = ImageFixtures.ico["ico_png"]!   // 16 red, 32 green, 48 blue
        XCTAssertEqual(try decode(ico, maxPixel: 16).rgba.prefix(4), [255, 0, 0, 255])
        XCTAssertEqual(try decode(ico, maxPixel: 16).width, 16)
        // 17: the 32 entry is the smallest that is big enough, then box-filtered down to 17
        XCTAssertEqual(try decode(ico, maxPixel: 17).width, 17)
        XCTAssertEqual(try decode(ico, maxPixel: 17).rgba.prefix(4), [0, 255, 0, 255])
        XCTAssertEqual(try decode(ico, maxPixel: 32).rgba.prefix(4), [0, 255, 0, 255])
        XCTAssertEqual(try decode(ico, maxPixel: 33).rgba.prefix(4), [0, 0, 255, 255])
    }

    func testICOPicksTheLargestWhenNoneIsBigEnoughThenDownscales() throws {
        let ico = ImageFixtures.ico["ico_png"]!
        XCTAssertEqual(try decode(ico, maxPixel: 48).width, 48)
        // 48 is the largest and over maxPixel 40? no: 48 >= 40 picks 48, then downscales to 40
        XCTAssertEqual(try decode(ico, maxPixel: 40).width, 40)
        XCTAssertEqual(try decode(ico, maxPixel: 40).rgba.prefix(4), [0, 0, 255, 255])
        XCTAssertEqual(try decode(ico, maxPixel: 0).width, 48)   // no limit: the largest
        let big = ImageFixtures.ico["ico_big"]!   // 256 (size byte 0), 32, 16
        XCTAssertEqual(try decode(big, maxPixel: 100).width, 100)
        XCTAssertEqual(try decode(big, maxPixel: 20).width, 20)
        XCTAssertEqual(try decode(big, maxPixel: 20).rgba.prefix(4), [0, 255, 0, 255])   // the 32 entry, scaled to 20
        XCTAssertEqual(try decode(big, maxPixel: 300).width, 256)
    }

    func testICOBMPEntries() throws {
        XCTAssertEqual(try decode(ImageFixtures.ico["ico_dib32"]!).rgba, [UInt8](ImageFixtures.data(ImageFixtures.icoDIB32Expected)))
        XCTAssertEqual(try decode(ImageFixtures.ico["ico_dib4"]!).rgba, [UInt8](ImageFixtures.data(ImageFixtures.icoDIB4Expected)))
        XCTAssertEqual(try decode(ImageFixtures.ico["ico_dib24"]!).rgba, [UInt8](ImageFixtures.data(ImageFixtures.icoDIB24Expected)))
        let dib4 = try decode(ImageFixtures.ico["ico_dib4"]!)
        XCTAssertEqual(dib4.width, 5)
        XCTAssertEqual(dib4.height, 3)
    }

    func testBrokenICOIsRefused() {
        XCTAssertThrowsError(try decode(ImageFixtures.ico["ico_trunc"]!)) { XCTAssertTrue($0 is ImageDecodeError) }
        XCTAssertThrowsError(try decode(ImageFixtures.ico["ico_oob"]!)) { XCTAssertTrue($0 is ImageDecodeError) }
    }

    // MARK: downscale

    func testDownscaleKeepsAspectAndNeverUpscales() throws {
        let c = ImageFixtures.cases.first { $0.name == "rgba8_dynamic" }!   // 64 x 48
        XCTAssertEqual(try decode(c.png, maxPixel: 32).width, 32)
        XCTAssertEqual(try decode(c.png, maxPixel: 32).height, 24)
        XCTAssertEqual(try decode(c.png, maxPixel: 64).width, 64)   // equal: untouched
        XCTAssertEqual(try decode(c.png, maxPixel: 200).width, 64)  // never upscaled
        XCTAssertEqual(try decode(c.png, maxPixel: 200).rgba, try decode(c.png).rgba)
        XCTAssertEqual(try decode(c.png, maxPixel: 10).width, 10)
        XCTAssertEqual(try decode(c.png, maxPixel: 10).height, 8)   // 48 * 10/64 = 7.5 rounds to 8
        XCTAssertEqual(try decode(c.png, maxPixel: 1).height, 1)
    }

    func testBoxFilterAveragesWholePixelsAtAnIntegerRatio() throws {
        // 4x2: left 2x2 block red opaque, right block blue opaque -> 2x1 of exactly red, blue
        var px = [UInt8]()
        for _ in 0..<2 { px += [255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255] }
        let small = ImageDecoder.resample(RGBAImage(width: 4, height: 2, rgba: px)!, width: 2, height: 1)
        XCTAssertEqual(small.rgba, [255, 0, 0, 255, 0, 0, 255, 255])
        // a checkerboard of black and white averages to mid grey
        let board = RGBAImage(width: 2, height: 2, rgba: [0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 255])!
        XCTAssertEqual(ImageDecoder.resample(board, width: 1, height: 1).rgba, [128, 128, 128, 255])
    }

    func testDownscaleDoesNotBleedTransparentColour() {
        // opaque green next to fully transparent red: the average is green at half alpha, not olive
        let image = RGBAImage(width: 2, height: 1, rgba: [0, 255, 0, 255, 255, 0, 0, 0])!
        XCTAssertEqual(ImageDecoder.resample(image, width: 1, height: 1).rgba, [0, 255, 0, 128])
    }

    func testFractionalRatioKeepsFlatColourExactly() {
        let flat = RGBAImage(width: 7, height: 5, rgba: [UInt8](repeating: 0, count: 0) + (0..<35).flatMap { _ in [10, 200, 30, 255] as [UInt8] })!
        let small = ImageDecoder.resample(flat, width: 3, height: 2)
        XCTAssertEqual(small.width, 3)
        XCTAssertTrue(stride(from: 0, to: small.rgba.count, by: 4).allSatisfy { Array(small.rgba[$0..<$0 + 4]) == [10, 200, 30, 255] })
    }

    func testInflateChecksTheStreamStrictly() throws {
        let empty: [UInt8] = [0x78, 0x9c, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]   // fixed block holding only end-of-block; Adler-32 of "" is 1
        XCTAssertEqual(try Inflate.zlibDecompress(empty, limit: 0), [])
        var wrongAdler = empty; wrongAdler[7] = 2
        XCTAssertThrowsError(try Inflate.zlibDecompress(wrongAdler, limit: 10)) { XCTAssertEqual($0 as? Inflate.Failure, .checksum) }
        XCTAssertThrowsError(try Inflate.zlibDecompress([0x78, 0x9d, 3, 0, 0, 0, 0, 1], limit: 10)) { XCTAssertEqual($0 as? Inflate.Failure, .header) }
        XCTAssertThrowsError(try Inflate.zlibDecompress([0x78, 0x9c, 0x03], limit: 10))
        // stored block "abc": over the output limit
        let stored: [UInt8] = [0x78, 0x01, 0x01, 3, 0, 0xfc, 0xff, 0x61, 0x62, 0x63, 0x02, 0x4d, 0x01, 0x27]
        XCTAssertEqual(try Inflate.zlibDecompress(stored, limit: 3), [0x61, 0x62, 0x63])
        XCTAssertThrowsError(try Inflate.zlibDecompress(stored, limit: 2)) { XCTAssertEqual($0 as? Inflate.Failure, .overflow) }
    }
}
