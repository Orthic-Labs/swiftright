import XCTest
@testable import SwiftRightRuntime

/// Wave 0 block I1: EXIF orientation 1-8 as exact pixel moves.
@MainActor final class ImageOrientationTests: XCTestCase {
    /// 3 x 2 image, pixel (x, y) has R = 10 * (y * 3 + x) so each pixel is unique (A = 255).
    private func sample() -> RGBAImage {
        var d = [UInt8](); for y in 0..<2 { for x in 0..<3 { d += [UInt8(10 * (y * 3 + x)), 0, 0, 255] } }
        return RGBAImage(width: 3, height: 2, rgba: d)!
    }
    private func reds(_ i: RGBAImage) -> [Int] { stride(from: 0, to: i.rgba.count, by: 4).map { Int(i.rgba[$0]) / 10 } }

    func testAllEightOrientations() {
        // source indices (row-major, 3 wide):  0 1 2 / 3 4 5
        let expected: [Int: (w: Int, h: Int, idx: [Int])] = [
            1: (3, 2, [0, 1, 2, 3, 4, 5]),
            2: (3, 2, [2, 1, 0, 5, 4, 3]),     // mirrored left-right
            3: (3, 2, [5, 4, 3, 2, 1, 0]),     // rotated 180
            4: (3, 2, [3, 4, 5, 0, 1, 2]),     // mirrored top-bottom
            5: (2, 3, [0, 3, 1, 4, 2, 5]),     // transpose
            6: (2, 3, [3, 0, 4, 1, 5, 2]),     // 90 degrees clockwise
            7: (2, 3, [5, 2, 4, 1, 3, 0]),     // transverse
            8: (2, 3, [2, 5, 1, 4, 0, 3]),     // 90 degrees counter-clockwise
        ]
        for (o, e) in expected {
            let r = sample().oriented(exif: o)
            XCTAssertEqual(r.width, e.w, "orientation \(o)"); XCTAssertEqual(r.height, e.h, "orientation \(o)")
            XCTAssertEqual(reds(r), e.idx, "orientation \(o)")
        }
    }

    func testOutOfRangeAndEnum() {
        XCTAssertEqual(sample().oriented(exif: 0), sample()); XCTAssertEqual(sample().oriented(exif: 9), sample())
        XCTAssertEqual(Image.Orientation.right.exif, 6); XCTAssertEqual(Image.Orientation(exif: 8), .left); XCTAssertNil(Image.Orientation(exif: 0))
        XCTAssertEqual(Image.Orientation.allCases.map(\.exif), Array(1...8))
        XCTAssertEqual(sample().oriented(.leftMirrored), sample().oriented(exif: 5))
    }

    func testRotateFourTimesIsIdentity() {
        var i = sample(); for _ in 0..<4 { i = i.oriented(exif: 6) }
        XCTAssertEqual(reds(i), reds(sample()))
    }
}
