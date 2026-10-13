import XCTest
@testable import SwiftRightRuntime

final class SystemImageRasterProviderTests: XCTestCase {
    private func input(_ coverage: [UInt8],
                       width: UInt32,
                       height: UInt32,
                       rowOrder: SystemImageRasterRowOrder = .topDown,
                       selectedFace: String = "Segoe Fluent Icons\0ignored") -> SystemImageRasterInput {
        SystemImageRasterInput(sourceWidth: width, sourceHeight: height, rowBytes: width,
                               coverage: coverage, coverageMaximum: 1, rowOrder: rowOrder,
                               selectedFace: selectedFace, expectedFace: "Segoe Fluent Icons")
    }

    func testTopDownAndBottomUpPreserveDeclaredOrientation() throws {
        let coverage: [UInt8] = [1, 0, 0, 0, 1, 0]
        let top = try SystemImageRasterProvider.compose(input(coverage, width: 3, height: 2),
                                                        targetWidth: 3, targetHeight: 2,
                                                        tintRGBA: 0xffffffff)
        let bottom = try SystemImageRasterProvider.compose(input(coverage, width: 3, height: 2,
                                                                 rowOrder: .bottomUp),
                                                           targetWidth: 3, targetHeight: 2,
                                                           tintRGBA: 0xffffffff)
        XCTAssertEqual(top.rgba[3], 255)
        XCTAssertEqual(top.rgba[3 + 4 * 4], 255)
        XCTAssertEqual(bottom.rgba[3 + 3 * 4], 255)
        XCTAssertEqual(bottom.rgba[3 + 1 * 4], 255)
    }

    func testSelectedFaceMismatchFailsVisible() {
        XCTAssertThrowsError(try SystemImageRasterProvider.compose(
            input([1], width: 1, height: 1, selectedFace: "Other\0Segoe Fluent Icons"),
            targetWidth: 1, targetHeight: 1, tintRGBA: 0xffffffff)) { error in
            XCTAssertEqual(error as? SystemImageRasterError, .selectedFaceMismatch)
        }
    }

    func testAspectFitDoesNotClipWideCoverage() throws {
        let output = try SystemImageRasterProvider.compose(
            input(Array(repeating: UInt8(1), count: 6 * 2), width: 6, height: 2),
            targetWidth: 4, targetHeight: 4, tintRGBA: 0xffffffff)
        XCTAssertEqual(output.renderedWidth, 4)
        XCTAssertEqual(output.renderedHeight, 1)
        XCTAssertEqual(output.nonZeroCoverage, 4)
    }
}
