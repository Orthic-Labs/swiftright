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

    /// Every corner must be the same cubic family rotated; a swapped endpoint on
    /// one corner (bottom-left) breaks this on a square.
    func testAllFourCornersAreRotationsOfTopLeft() throws {
        let n: CGFloat = 60, r: CGFloat = 10
        let path = try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: n, height: n), cornerRadius: r)
        // Path order: BR cubics 2,3,4 ; BL 6,7,8 ; TL 10,11,12 ; TR 14,15,16.
        func pts(_ start: Int) -> [(LayoutPoint, LayoutPoint, LayoutPoint)] {
            (start..<start + 3).map { i -> (LayoutPoint, LayoutPoint, LayoutPoint) in
                guard case .cubic(let to, let c1, let c2) = path[i] else { XCTFail("expected cubic at \(i)"); return (to0, to0, to0) }
                return (to, c1, c2)
            }
        }
        let to0 = LayoutPoint(x: 0, y: 0)
        let tl = pts(10)
        // Rotate TL by 90 degree steps about the square centre to reach TR, BR, BL.
        func rot(_ p: LayoutPoint, _ k: Int) -> LayoutPoint {
            var x = p.x, y = p.y
            for _ in 0..<k { (x, y) = (n - y, x) }   // clockwise 90 in y-down space
            return LayoutPoint(x: x, y: y)
        }
        // Rotated corners are traversed in the same direction as the path.
        for (k, start) in [(1, 14), (2, 2), (3, 6)] {
            let got = pts(start)
            for j in 0..<3 {
                for (a, b) in [(got[j].0, rot(tl[j].0, k)), (got[j].1, rot(tl[j].1, k)), (got[j].2, rot(tl[j].2, k))] {
                    XCTAssertEqual(a.x, b.x, accuracy: 1e-9, "corner rot \(k) cubic \(j) x")
                    XCTAssertEqual(a.y, b.y, accuracy: 1e-9, "corner rot \(k) cubic \(j) y")
                }
            }
        }
    }

    func testFractionalOffsetBakesSubpixelCoverageIntoBitmap() throws {
        let image = try ContinuousRoundedRasterizer.rasterize(width: 12, height: 12, cornerRadius: 0,
                                                               fillRGBA: 0x336699ff,
                                                               shapeWidth: 10, shapeHeight: 10,
                                                               offsetX: 0.5, offsetY: 0.25)
        func alpha(_ x: Int, _ y: Int) -> Int { Int(image.rgba[(y * 12 + x) * 4 + 3]) }
        XCTAssertEqual(alpha(0, 5), 128)            // half-covered left column
        XCTAssertEqual(alpha(10, 5), 128)           // right edge at 10.5
        XCTAssertEqual(alpha(11, 5), 0)
        XCTAssertEqual(alpha(5, 5), 255)
        XCTAssertEqual(alpha(5, 0), 191)            // top row 0.75 covered
        XCTAssertEqual(alpha(5, 10), 64)            // bottom edge at 10.25
        XCTAssertEqual(alpha(5, 11), 0)
        XCTAssertThrowsError(try ContinuousRoundedRasterizer.rasterize(width: 12, height: 12, cornerRadius: 0,
                                                                        fillRGBA: 1, offsetX: 1.0))
    }

    func testCoverageIsSixteenByThirtyTwoQuantisedAndSymmetric() throws {
        // A 45-degree-ish corner must produce more than the 17 levels of 4x4 sampling.
        let n = 40
        let image = try ContinuousRoundedRasterizer.rasterize(width: n, height: n, cornerRadius: 6,
                                                               fillRGBA: 0xffffffff,
                                                               strokeRGBA: 0xff0000ff, strokeWidth: 3)
        let big = try ContinuousRoundedRasterizer.rasterize(width: 120, height: 120, cornerRadius: 30,
                                                             strokeRGBA: 0xff0000ff, strokeWidth: 2.5)
        var levels = Set<UInt8>()
        for i in 0..<120 * 120 { levels.insert(big.rgba[i * 4 + 3]) }
        XCTAssertGreaterThan(levels.count, 17)
        func px(_ x: Int, _ y: Int, _ c: Int) -> Int { Int(image.rgba[(y * n + x) * 4 + c]) }
        for y in 0..<n { for x in 0..<n { for c in 0..<4 {
            XCTAssertLessThanOrEqual(abs(px(x, y, c) - px(n - 1 - x, y, c)), 1, "mirror x \(x),\(y),\(c)")
            XCTAssertLessThanOrEqual(abs(px(x, y, c) - px(x, n - 1 - y, c)), 1, "mirror y \(x),\(y),\(c)")
            XCTAssertLessThanOrEqual(abs(px(x, y, c) - px(y, x, c)), 1, "transpose \(x),\(y),\(c)")
        } } }
    }
}
