import SwiftRightRuntime
import XCTest

final class ContinuousRoundedGeometryTests: XCTestCase {
    func testPathUsesThreeCubicSegmentsPerCornerAcrossAspectRatios() throws {
        let cases: [(CGFloat, CGFloat, CGFloat)] = [(40, 20, 6), (105, 55, 17.5), (64, 64, 12), (120, 40, 10)]
        for (width, height, radius) in cases {
            let path = try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: width, height: height), cornerRadius: radius)
            XCTAssertEqual(path.count, 18)
            XCTAssertEqual(path.filter { if case .cubic = $0 { return true }; return false }.count, 12)
            XCTAssertEqual(path.filter { if case .line = $0 { return true }; return false }.count, 4)
        }
    }

    func testCornerExtentScalesWithinObservedRadiusRange() throws {
        let small = try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 40, height: 20), cornerRadius: 6)
        let wide = try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 120, height: 40), cornerRadius: 10)
        guard case .cubic(let smallEnd, _, _) = small[4],
              case .cubic(let wideEnd, _, _) = wide[4] else {
            return XCTFail("expected bottom-right terminal cubic")
        }
        let smallExtent = 40 - smallEnd.x
        let wideExtent = 120 - wideEnd.x
        XCTAssertEqual(smallExtent / 6, wideExtent / 10, accuracy: 0.00001)
        XCTAssertThrowsError(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 40, height: 20), cornerRadius: 100)) { error in
            XCTAssertEqual(error as? ContinuousRoundedGeometryError, .unsupportedRadiusExtent)
        }
        XCTAssertThrowsError(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 48, height: 48), cornerRadius: 23)) { error in
            XCTAssertEqual(error as? ContinuousRoundedGeometryError, .unsupportedRadiusExtent)
        }
    }

    func testTranslationPreservesLocalCornerGeometry() throws {
        let origin = try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 64, height: 32), cornerRadius: 8)
        let translated = try ContinuousRoundedGeometry.path(in: LayoutRect(x: 13, y: 7, width: 64, height: 32), cornerRadius: 8)
        guard case .move(let p0) = origin[0], case .move(let p1) = translated[0] else {
            return XCTFail("expected move elements")
        }
        XCTAssertEqual(p1.x - p0.x, 13, accuracy: 0.00001)
        XCTAssertEqual(p1.y - p0.y, 7, accuracy: 0.00001)
    }

    func testZeroRadiusUsesRectanglePath() throws {
        let path = try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 40, height: 20), cornerRadius: 0)
        XCTAssertEqual(path.count, 5)
        XCTAssertEqual(path.filter { if case .cubic = $0 { return true }; return false }.count, 0)
    }

    func testRejectsNonFiniteAndOverflowingBounds() {
        XCTAssertThrowsError(try ContinuousRoundedGeometry.path(
            in: LayoutRect(x: .infinity, y: 0, width: 40, height: 20), cornerRadius: 6)) { error in
            XCTAssertEqual(error as? ContinuousRoundedGeometryError, .invalidBounds)
        }
        XCTAssertThrowsError(try ContinuousRoundedGeometry.path(
            in: LayoutRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
                           width: CGFloat.greatestFiniteMagnitude, height: 20), cornerRadius: 6)) { error in
            XCTAssertEqual(error as? ContinuousRoundedGeometryError, .invalidBounds)
        }
    }

    func testRasterizerReturnsBoundedRGBAWithObservedCoverage() throws {
        let image = try ContinuousRoundedRasterizer.rasterize(width: 40, height: 20,
                                                               cornerRadius: 5,
                                                               strokeRGBA: 0x2563ebff,
                                                               strokeWidth: 2)
        XCTAssertEqual(image.rgba.count, 40 * 20 * 4)
        XCTAssertTrue(image.rgba.contains { $0 != 0 })
        // Stroke-only image is transparent at interior center; top-center
        // sample intersects centered stroke on inset path boundary.
        XCTAssertGreaterThan(image.rgba[(0 * 40 + 20) * 4 + 3], 0)
        let combined = try ContinuousRoundedRasterizer.rasterize(width: 40, height: 20,
                                                                  cornerRadius: 5,
                                                                  fillRGBA: 0xff0000ff,
                                                                  strokeRGBA: 0x0000ffff,
                                                                  strokeWidth: 2)
        XCTAssertGreaterThan(combined.rgba[(10 * 40 + 20) * 4 + 3], 0)
        XCTAssertThrowsError(try ContinuousRoundedRasterizer.rasterize(width: 40, height: 20,
                                                                        cornerRadius: 100,
                                                                        strokeRGBA: 0x2563ebff,
                                                                        strokeWidth: 2)) { error in
            XCTAssertEqual(error as? ContinuousRoundedRasterError, .unsupportedGeometry)
        }
        XCTAssertThrowsError(try ContinuousRoundedRasterizer.rasterize(width: 4096, height: 4096, cornerRadius: 6)) { error in
            XCTAssertEqual(error as? ContinuousRoundedRasterError, .pixelLimitExceeded)
        }
        XCTAssertThrowsError(try ContinuousRoundedRasterizer.rasterize(width: 2048, height: 2048, cornerRadius: 6)) { error in
            XCTAssertEqual(error as? ContinuousRoundedRasterError, .workLimitExceeded)
        }
    }
}
