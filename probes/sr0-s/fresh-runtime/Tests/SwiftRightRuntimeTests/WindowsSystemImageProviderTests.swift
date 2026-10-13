#if os(Windows)
import XCTest
@testable import SwiftRightRuntime

final class WindowsSystemImageProviderTests: XCTestCase {
    func testFaceDecodeUsesNulTerminationWhenReportedLengthExcludesNul() {
        let name = Array("Segoe Fluent Icons".utf16)
        let buffer = name + [0, 0, 0]
        XCTAssertEqual(
            WindowsSystemImageProvider.decodeSelectedFace(buffer, reportedLength: Int32(name.count)),
            "Segoe Fluent Icons")
    }

    func testFaceDecodeUsesNulTerminationWhenReportedLengthIncludesNul() {
        let name = Array("Segoe Fluent Icons".utf16)
        let buffer = name + [0, 0, 0]
        XCTAssertEqual(
            WindowsSystemImageProvider.decodeSelectedFace(buffer, reportedLength: Int32(name.count + 1)),
            "Segoe Fluent Icons")
    }

    func testFaceDecodeKeepsWrongFaceVisibleAndRejectsUnterminatedFace() {
        let wrong = Array("Segoe UI".utf16) + [0, 0]
        XCTAssertNotEqual(
            WindowsSystemImageProvider.decodeSelectedFace(wrong, reportedLength: Int32(wrong.count - 1)),
            "Segoe Fluent Icons")
        let unterminated = Array("Segoe Fluent Icons".utf16) + [0xffff]
        XCTAssertNil(
            WindowsSystemImageProvider.decodeSelectedFace(unterminated, reportedLength: Int32(unterminated.count - 1)))
    }

    func testDeclaredSegoeGlyphReturnsExactFaceAndCoverage() throws {
        let coverage = try WindowsSystemImageProvider.rasterize(
            WindowsSystemImageGlyphRequest(providerFamily: "Segoe Fluent Icons",
                                            glyph: 0xE735,
                                            targetWidth: 80,
                                            targetHeight: 80))
        XCTAssertEqual(coverage.selectedFace, "Segoe Fluent Icons")
        XCTAssertEqual(coverage.rowOrder, .topDown)
        XCTAssertGreaterThan(coverage.sourceWidth, 0)
        XCTAssertGreaterThan(coverage.sourceHeight, 0)
        XCTAssertGreaterThan(coverage.averageCharWidth, 0)
        XCTAssertGreaterThan(coverage.cellIncrementX, 0)
        XCTAssertTrue(coverage.coverage.contains { $0 > 0 })
    }

    func testInvalidTargetFailsBeforeNativeAllocation() {
        XCTAssertThrowsError(try WindowsSystemImageProvider.rasterize(
            WindowsSystemImageGlyphRequest(providerFamily: "Segoe Fluent Icons",
                                            glyph: 0xE735,
                                            targetWidth: 0,
                                            targetHeight: 80))) { error in
            XCTAssertEqual(error as? WindowsSystemImageProviderError, .invalidRequest)
        }
    }
}
#endif
