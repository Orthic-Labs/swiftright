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
        // Round 5 block 30: past the extent limit and past half the short side the radius is no longer refused: see `testLargeRadiiFollowTheMeasuredFamily`
        XCTAssertNoThrow(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 40, height: 20), cornerRadius: 100))
        XCTAssertNoThrow(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 48, height: 48), cornerRadius: 23))
    }

    private func flatten(_ path: [ContinuousPathElement]) -> [[Double]] {
        path.map { element in
            switch element {
            case .move(let p), .line(let p): return [Double(p.x), Double(p.y)]
            case .cubic(let p, let c1, let c2): return [Double(p.x), Double(p.y), Double(c1.x), Double(c1.y), Double(c2.x), Double(c2.y)]
            case .close: return []
            }
        }
    }

    /// Measured: `RoundedRectangle(cornerRadius: r, style: .continuous).path(in:)` on macOS 27 (printed to 4 decimals), 100 x 40 at r = 15, r = 20 and r = 99 (a clamped radius),
    /// and 40 x 40 at r = 99 (the vertical and the horizontal edge both clamp).
    func testLargeRadiiFollowTheMeasuredFamily() throws {
        let r20 = flatten(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 100, height: 40), cornerRadius: 20))
        let r99 = flatten(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 100, height: 40), cornerRadius: 99))
        XCTAssertEqual(r20, r99, "a radius past half the short side is clamped to it")
        let expected20: [[Double]] = [
            [100, 20], [100, 20],
            [98.5018, 27.3701, 100, 20.8, 100, 23.6],
            [87.3701, 38.5018, 96.6188, 32.5435, 92.5435, 36.6188],
            [69.4267, 40, 82.6319, 40, 78.2302, 40],
            [30.5733, 40],
            [12.6299, 38.5018, 21.7698, 40, 17.3681, 40],
            [1.4982, 27.3701, 7.4565, 36.6188, 3.3812, 32.5435],
            [0, 20, 0, 23.6, 0, 20.8],
            [0, 20],
            [1.4982, 12.6299, 0, 19.2, 0, 16.4],
            [12.6299, 1.4982, 3.3812, 7.4565, 7.4565, 3.3812],
            [30.5733, 0, 17.3681, 0, 21.7698, 0],
            [69.4267, 0],
            [87.3701, 1.4982, 78.2302, 0, 82.6319, 0],
            [98.5018, 12.6299, 92.5435, 3.3812, 96.6188, 7.4565],
            [100, 20, 100, 16.4, 100, 19.2],
            [],
        ]
        XCTAssertEqual(r20.count, expected20.count)
        for (got, want) in zip(r20, expected20) {
            XCTAssertEqual(got.count, want.count)
            for (g, w) in zip(got, want) { XCTAssertEqual(g, w, accuracy: 0.00006) }
        }
        // r = 15 (between the extent limit 13.08 and half 20): the first cubic starts at the mid-point and its controls moved
        let r15 = flatten(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 100, height: 40), cornerRadius: 15))
        for (g, w) in zip(r15[2], [98.8763, 30.5276, 100, 24.3848, 100, 27.2422]) { XCTAssertEqual(g, w, accuracy: 0.0002) }
        for (g, w) in zip(r15[4], [77.07, 40, 86.9739, 40, 83.6726, 40]) { XCTAssertEqual(g, w, accuracy: 0.0002) }   // the long edge keeps the ordinary coefficients
        // a square pill: both edges clamp, the straight segments collapse to points
        let square = flatten(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 40, height: 40), cornerRadius: 99))
        for (g, w) in zip(square[4], [20, 40, 23.6, 40, 20.8, 40]) { XCTAssertEqual(g, w, accuracy: 0.0002) }
        XCTAssertEqual(square[5], [20, 40])
        // continuity at the extent limit
        let at = flatten(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 100, height: 40), cornerRadius: 13.0833))
        let beyond = flatten(try ContinuousRoundedGeometry.path(in: LayoutRect(x: 0, y: 0, width: 100, height: 40), cornerRadius: 13.0834))
        for (g, w) in zip(at[2], beyond[2]) { XCTAssertEqual(g, w, accuracy: 0.001) }
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
        XCTAssertNoThrow(try ContinuousRoundedRasterizer.rasterize(width: 40, height: 20, cornerRadius: 100, strokeRGBA: 0x2563ebff, strokeWidth: 2))
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

    func testStrokeEdgeCoverageIsSmoothstepOfLinearCoverage() {
        XCTAssertEqual(ContinuousRoundedRasterizer.strokeEdgeCoverage(0), 0)
        XCTAssertEqual(ContinuousRoundedRasterizer.strokeEdgeCoverage(1), 1)
        // Measured against SwiftUI: 0.25 -> 0.157, 0.5 -> 0.498, 0.75 -> 0.843.
        XCTAssertEqual(ContinuousRoundedRasterizer.strokeEdgeCoverage(0.25), 0.157, accuracy: 0.004)
        XCTAssertEqual(ContinuousRoundedRasterizer.strokeEdgeCoverage(0.5), 0.5, accuracy: 0.004)
        XCTAssertEqual(ContinuousRoundedRasterizer.strokeEdgeCoverage(0.75), 0.843, accuracy: 0.004)
        // A 2.5 px stroke on a pixel-aligned straight edge: 0.25 true coverage each side -> 0.157 alpha.
        let image = try! ContinuousRoundedRasterizer.rasterize(width: 60, height: 40, cornerRadius: 0,
                                                                strokeRGBA: 0x000000ff, strokeWidth: 2.5,
                                                                shapeWidth: 55, shapeHeight: 35,
                                                                offsetX: 0.75, offsetY: 0.75)
        let alpha = Int(image.rgba[(20 * 60 + 0) * 4 + 3])
        XCTAssertEqual(Double(alpha) / 255, 0.157, accuracy: 0.01)
    }

    func testLargeRadiusFullScreenStrokeRasterizesWithinWorkBudget() throws {
        // 500 x 350 px, 100 px radius, 20 px stroke (radius 40 pt, stroke 8 pt at 2.5x) used to exceed the
        // brute-force work limit; the spatial index makes cost proportional to the area.
        let image = try ContinuousRoundedRasterizer.rasterize(width: 521, height: 371, cornerRadius: 100,
                                                               strokeRGBA: 0x0088ffff, strokeWidth: 20,
                                                               shapeWidth: 500, shapeHeight: 350)
        XCTAssertEqual(image.rgba.count, 521 * 371 * 4)
        XCTAssertEqual(image.rgba[(185 * 521 + 10) * 4 + 3], 255)    // left side, mid height: fully covered stroke
        XCTAssertEqual(image.rgba[(185 * 521 + 260) * 4 + 3], 0)     // interior
        let full = try ContinuousRoundedRasterizer.rasterize(width: 1000, height: 700, cornerRadius: 120,
                                                              fillRGBA: 0xff0000ff, strokeRGBA: 0x0000ffff, strokeWidth: 12)
        XCTAssertEqual(full.rgba[(350 * 1000 + 500) * 4 + 3], 255)
    }

    func testDevicePixelSnapMatchesSwiftUIEdgeRounding() {
        func snap(_ o: Double, _ l: Double) -> (Double, Double) { let r = DevicePixelSnap.edges(origin: o, length: l, scale: 2.5); return (r.origin, r.length) }
        XCTAssertEqual(snap(350, 100).0, 350); XCTAssertEqual(snap(350, 100).1, 100)
        // 112.5 x 62.5 px at 343.75 / 268.75 -> 344...456 and 269...331
        XCTAssertEqual(snap(343.75, 112.5).0, 344); XCTAssertEqual(snap(343.75, 112.5).1, 112)
        XCTAssertEqual(snap(268.75, 62.5).0, 269); XCTAssertEqual(snap(268.75, 62.5).1, 62)
        // .5 ties as observed: 362.5 + 75 -> 362...437, 237.5 + 125 -> 238...362
        XCTAssertEqual(snap(362.5, 75).0, 362); XCTAssertEqual(snap(362.5, 75).1, 75)
        XCTAssertEqual(snap(237.5, 125).0, 238); XCTAssertEqual(snap(237.5, 125).1, 124)
    }
}
