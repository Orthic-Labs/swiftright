import Foundation
import XCTest
@testable import SwiftRightBridge

final class FontFileMetricsTests: XCTestCase {
    /// A minimal sfnt: directory with `head` and `hhea` only (parse reads nothing else).
    private func sfnt(units: UInt16, ascent: Int16, descent: Int16, gap: Int16, ttc: Bool = false) -> [UInt8] {
        func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xff)] }
        func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
        let base = ttc ? 16 : 0
        let dir = base + 12 + 2 * 16
        var head = [UInt8](repeating: 0, count: 54); head.replaceSubrange(18..<20, with: be16(units))
        var hhea = [UInt8](repeating: 0, count: 36)
        hhea.replaceSubrange(4..<6, with: be16(UInt16(bitPattern: ascent)))
        hhea.replaceSubrange(6..<8, with: be16(UInt16(bitPattern: descent)))
        hhea.replaceSubrange(8..<10, with: be16(UInt16(bitPattern: gap)))
        var out = [UInt8]()
        if ttc { out += Array("ttcf".utf8) + be32(0x00010000) + be32(1) + be32(16) }
        out += be32(0x00010000) + be16(2) + [0, 0, 0, 0, 0, 0]
        out += Array("head".utf8) + be32(0) + be32(UInt32(dir)) + be32(UInt32(head.count))
        out += Array("hhea".utf8) + be32(0) + be32(UInt32(dir + head.count)) + be32(UInt32(hhea.count))
        out += head + hhea
        return out
    }

    func testParsesHeadAndHheaAndLineHeightIsRoundedAscentPlusRoundedDescent() throws {
        // Tinos: 2048 upem, hhea ascent 1825, descent -443, lineGap 87 -> 18 pt: ascent 16.04, descent 3.89, line 16 + 4 = 20.
        let m = try XCTUnwrap(FontFileMetrics.parse(sfnt(units: 2048, ascent: 1825, descent: -443, gap: 87)))
        XCTAssertEqual(m, FontFileMetrics(unitsPerEm: 2048, ascentUnits: 1825, descentUnits: -443, lineGapUnits: 87))
        XCTAssertEqual(m.ascent(pointSize: 18), 16.040039, accuracy: 1e-4)
        XCTAssertEqual(m.descent(pointSize: 18), 3.8935547, accuracy: 1e-4)
        XCTAssertEqual(m.lineHeight(pointSize: 18), 20)
    }

    func testParsesFirstFaceOfACollection() throws {
        let m = try XCTUnwrap(FontFileMetrics.parse(sfnt(units: 1000, ascent: 800, descent: -200, gap: 0, ttc: true)))
        XCTAssertEqual(m.lineHeight(pointSize: 10), 10)
    }

    func testRejectsMissingTablesAndImplausibleValues() {
        XCTAssertNil(FontFileMetrics.parse([]))
        XCTAssertNil(FontFileMetrics.parse([0xFF, 0, 0, 0, 0, 0]))
        XCTAssertNil(FontFileMetrics.parse(sfnt(units: 0, ascent: 800, descent: -200, gap: 0)))
        XCTAssertNil(FontFileMetrics.parse(sfnt(units: 1000, ascent: -5, descent: -200, gap: 0)))
        XCTAssertNil(FontFileMetrics.parse(sfnt(units: 1000, ascent: 800, descent: 0, gap: 0)))
    }

    func testRealTinosWhenTheRepositoryFileIsPresent() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("render/swiftright-render/testdata/fonts/Tinos-Regular.ttf")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("repository font not staged") }
        let m = try XCTUnwrap(FontFileMetrics.parse([UInt8](data)))
        XCTAssertEqual(m.unitsPerEm, 2048)
        XCTAssertEqual(m.lineHeight(pointSize: 18), 20)
    }
}
