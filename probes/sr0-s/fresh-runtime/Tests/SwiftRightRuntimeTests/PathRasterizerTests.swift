import Foundation
@testable import SwiftRightRuntime
import XCTest

/// F-path P0/P2 core: invariants of `PathRasterizer` that hold exactly by construction. Pixel parity with SwiftUI is the Mac spike's job
/// (factory/tools PathParitySpike), not these tests.
final class PathRasterizerTests: XCTestCase {
    private let red: UInt32 = 0xff0000ff
    private let white: UInt32 = 0xffffffff

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path { Path(CGRect(x: x, y: y, width: w, height: h)) }

    /// Alpha at a device pixel (0 outside the bitmap).
    private func alpha(_ r: PathRasterImage, _ x: Int, _ y: Int) -> Int {
        let ix = x - r.originX, iy = y - r.originY
        guard ix >= 0, iy >= 0, ix < r.image.width, iy < r.image.height else { return 0 }
        return Int(r.image.rgba[(iy * r.image.width + ix) * 4 + 3])
    }

    private func coverageSum(_ r: PathRasterImage) -> Double {
        var sum = 0.0
        for i in stride(from: 3, to: r.image.rgba.count, by: 4) { sum += Double(r.image.rgba[i]) / 255 }
        return sum
    }

    private func raster(_ path: Path, translate: CGPoint = .zero, scale: CGFloat = 1, fill: UInt32? = nil, fillStyle: FillStyle = FillStyle(),
                        stroke: UInt32? = nil, style: StrokeStyle = StrokeStyle()) throws -> PathRasterImage {
        try XCTUnwrap(PathRasterizer.rasterize(path: path, transform: CGAffineTransform(translationX: translate.x, y: translate.y), scale: scale,
                                               fillRGBA: fill, fillStyle: fillStyle, strokeRGBA: stroke, strokeStyle: style))
    }

    // MARK: Fill

    func testASquareOnWholePixelsIsExactColourInsideAndAbsentOutside() throws {
        let r = try raster(rect(0, 0, 10, 10), translate: CGPoint(x: 3, y: 4), fill: red)
        XCTAssertEqual(r.originX, 3); XCTAssertEqual(r.originY, 4)
        XCTAssertEqual(r.image.width, 10); XCTAssertEqual(r.image.height, 10)
        for i in 0..<100 { XCTAssertEqual(Array(r.image.rgba[(i * 4)..<(i * 4 + 4)]), [255, 0, 0, 255], "pixel \(i)") }
        XCTAssertEqual(alpha(r, 2, 4), 0); XCTAssertEqual(alpha(r, 13, 4), 0)
    }

    func testFractionalEdgesGiveExactSampleCoverage() throws {
        // x edge at .25 and y edge at .5: columns/rows of 0.75 and 0.5 coverage; total area 100 exactly.
        let r = try raster(rect(0.25, 0.5, 10, 10), fill: white)
        XCTAssertEqual(coverageSum(r), 100, accuracy: 0.5)
        XCTAssertEqual(alpha(r, 5, 5), 255)
        XCTAssertEqual(alpha(r, 0, 5), Int((0.75 * 255).rounded()))      // left column
        XCTAssertEqual(alpha(r, 10, 5), Int((0.25 * 255).rounded()))     // right column
        XCTAssertEqual(alpha(r, 5, 0), Int((0.5 * 255).rounded()))       // top row (127.5 rounds up)
        XCTAssertEqual(alpha(r, 0, 0), Int((0.375 * 255).rounded()))     // corner: 0.75 * 0.5
    }

    func testNonAntialiasedFillHasOnlyFullOrZeroAlpha() throws {
        let r = try raster(Path(ellipseIn: CGRect(x: 0.3, y: 0.3, width: 20, height: 20)), fill: red, fillStyle: FillStyle(antialiased: false))
        XCTAssertTrue(stride(from: 3, to: r.image.rgba.count, by: 4).allSatisfy { r.image.rgba[$0] == 0 || r.image.rgba[$0] == 255 })
    }

    func testACircleFillMatchesItsAreaAndHasTransparentCorners() throws {
        let r = try raster(Path(ellipseIn: CGRect(x: 0, y: 0, width: 40, height: 40)), fill: red)
        XCTAssertEqual(coverageSum(r), Double.pi * 400, accuracy: Double.pi * 400 * 0.005)
        XCTAssertEqual(alpha(r, 0, 0), 0); XCTAssertEqual(alpha(r, 39, 39), 0)
        XCTAssertEqual(alpha(r, 20, 20), 255)
    }

    func testEvenOddFillLeavesAHoleAndNonZeroDependsOnWinding() throws {
        var same = Path()
        same.addRect(CGRect(x: 0, y: 0, width: 20, height: 20))
        same.addRect(CGRect(x: 5, y: 5, width: 10, height: 10))
        let evenOdd = try raster(same, fill: red, fillStyle: FillStyle(eoFill: true))
        XCTAssertEqual(alpha(evenOdd, 10, 10), 0); XCTAssertEqual(alpha(evenOdd, 2, 2), 255)
        XCTAssertEqual(coverageSum(evenOdd), 400 - 100, accuracy: 0.5)
        let nonZero = try raster(same, fill: red)
        XCTAssertEqual(alpha(nonZero, 10, 10), 255, "same winding twice is non-zero")

        var reversed = Path()
        reversed.addRect(CGRect(x: 0, y: 0, width: 20, height: 20))
        reversed.move(to: CGPoint(x: 5, y: 5)); reversed.addLine(to: CGPoint(x: 5, y: 15)); reversed.addLine(to: CGPoint(x: 15, y: 15))
        reversed.addLine(to: CGPoint(x: 15, y: 5)); reversed.closeSubpath()
        XCTAssertEqual(alpha(try raster(reversed, fill: red), 10, 10), 0, "opposite winding cancels under non-zero")
    }

    func testAPentagramCentreIsFilledNonZeroAndEmptyEvenOdd() throws {
        let c = CGPoint(x: 50, y: 50), radius = 40.0
        func vertex(_ k: Int) -> CGPoint {
            let a = -Double.pi / 2 + Double(k) * 2 * Double.pi / 5
            return CGPoint(x: Double(c.x) + radius * cos(a), y: Double(c.y) + radius * sin(a))
        }
        var star = Path()
        star.move(to: vertex(0)); star.addLine(to: vertex(2)); star.addLine(to: vertex(4)); star.addLine(to: vertex(1)); star.addLine(to: vertex(3))
        star.closeSubpath()
        XCTAssertEqual(alpha(try raster(star, fill: red), 50, 50), 255)
        XCTAssertEqual(alpha(try raster(star, fill: red, fillStyle: FillStyle(eoFill: true)), 50, 50), 0)
        // a point in one of the five tips is filled either way
        XCTAssertEqual(alpha(try raster(star, fill: red, fillStyle: FillStyle(eoFill: true)), 50, 16), 255)
    }

    func testOpenSubpathsFillAsIfClosed() throws {
        var triangle = Path()
        triangle.move(to: CGPoint(x: 0, y: 0)); triangle.addLine(to: CGPoint(x: 20, y: 0)); triangle.addLine(to: CGPoint(x: 0, y: 20))
        let r = try raster(triangle, fill: red)
        XCTAssertEqual(coverageSum(r), 200, accuracy: 2)
    }

    // MARK: Stroke

    func testButtCapStrokeOfAHorizontalLineIsExactlyItsRectangle() throws {
        var line = Path(); line.move(to: CGPoint(x: 10, y: 10)); line.addLine(to: CGPoint(x: 60, y: 10))
        let r = try raster(line, stroke: white, style: StrokeStyle(lineWidth: 8))
        XCTAssertEqual(coverageSum(r), 400, accuracy: 1)
        XCTAssertEqual(alpha(r, 9, 10), 0); XCTAssertEqual(alpha(r, 10, 10), 255)
        XCTAssertEqual(alpha(r, 59, 10), 255); XCTAssertEqual(alpha(r, 60, 10), 0)
        XCTAssertEqual(alpha(r, 30, 5), 0); XCTAssertEqual(alpha(r, 30, 6), 255); XCTAssertEqual(alpha(r, 30, 13), 255); XCTAssertEqual(alpha(r, 30, 14), 0)
    }

    func testRoundCapStrokeCoversItsRectanglePlusTwoHalfDiscsWithinTwoPercent() throws {
        var line = Path(); line.move(to: CGPoint(x: 10, y: 10)); line.addLine(to: CGPoint(x: 60, y: 10))
        let r = try raster(line, stroke: white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
        let expected = 50.0 * 8 + Double.pi * 16
        XCTAssertEqual(coverageSum(r), expected, accuracy: expected * 0.02)
        XCTAssertEqual(alpha(r, 7, 10), 255, "inside the cap")
        XCTAssertEqual(alpha(r, 5, 5), 0, "outside the round cap's corner")
    }

    func testSquareCapExtendsByHalfTheWidth() throws {
        var line = Path(); line.move(to: CGPoint(x: 10, y: 10)); line.addLine(to: CGPoint(x: 60, y: 10))
        let r = try raster(line, stroke: white, style: StrokeStyle(lineWidth: 8, lineCap: .square))
        XCTAssertEqual(alpha(r, 6, 10), 255); XCTAssertEqual(alpha(r, 5, 10), 0)
        XCTAssertEqual(alpha(r, 63, 10), 255); XCTAssertEqual(alpha(r, 64, 10), 0)
        XCTAssertEqual(coverageSum(r), 58 * 8, accuracy: 1)
    }

    private func corner(_ join: LineJoin, miterLimit: CGFloat = 10) throws -> PathRasterImage {
        var p = Path()
        p.move(to: CGPoint(x: 10, y: 30)); p.addLine(to: CGPoint(x: 40, y: 30)); p.addLine(to: CGPoint(x: 40, y: 60))
        return try raster(p, stroke: white, style: StrokeStyle(lineWidth: 10, lineJoin: join, miterLimit: miterLimit))
    }

    func testMiterRoundAndBevelJoinsDifferAtTheOuterCorner() throws {
        // Outer corner of the turn is at (45, 25); the tip pixel is (44, 25), a pixel just inside the round join's arc is (43, 27).
        let miter = try corner(.miter)
        XCTAssertEqual(alpha(miter, 44, 25), 255)
        XCTAssertEqual(alpha(miter, 43, 27), 255)
        let bevel = try corner(.bevel)
        XCTAssertEqual(alpha(bevel, 44, 25), 0)
        XCTAssertEqual(alpha(bevel, 43, 27), 0)
        XCTAssertEqual(alpha(bevel, 41, 28), 255)
        let round = try corner(.round)
        XCTAssertEqual(alpha(round, 44, 25), 0)
        XCTAssertEqual(alpha(round, 43, 27), 255)
        // area ordering: miter > round > bevel, by the wedge each adds beyond the shared body
        XCTAssertGreaterThan(coverageSum(miter), coverageSum(round))
        XCTAssertGreaterThan(coverageSum(round), coverageSum(bevel))
        // exact wedge areas: miter 25 (a 5x5 corner square), bevel 12.5, round pi * 25 / 4
        XCTAssertEqual(coverageSum(miter) - coverageSum(bevel), 12.5, accuracy: 1.0)
        XCTAssertEqual(coverageSum(round) - coverageSum(bevel), Double.pi * 25 / 4 - 12.5, accuracy: 1.0)
    }

    func testMiterLimitBelowTheCornersRatioFallsBackToABevel() throws {
        // a right angle has miter ratio sqrt(2) = 1.414
        XCTAssertEqual(alpha(try corner(.miter, miterLimit: 1.5), 44, 25), 255)
        XCTAssertEqual(alpha(try corner(.miter, miterLimit: 1.4), 44, 25), 0)
    }

    func testClosedSubpathsJoinAtTheStartAndHaveNoCaps() throws {
        let r = try raster(rect(0, 0, 20, 20), translate: CGPoint(x: 5, y: 5), stroke: white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        // miter joins at all four corners: the stroke is the 24x24 outer square minus the 16x16 inner square, so area 576 - 256 = 320
        XCTAssertEqual(coverageSum(r), 320, accuracy: 1)
        XCTAssertEqual(alpha(r, 3, 3), 255, "outer corner of the start vertex is mitred, not capped")
        XCTAssertEqual(alpha(r, 15, 15), 0)
    }

    func testHairlineAtScaleTwoAndAHalfStraddlesTwoRows() throws {
        var line = Path(); line.move(to: CGPoint(x: 0, y: 10)); line.addLine(to: CGPoint(x: 20, y: 10))
        let r = try raster(line, scale: 2.5, stroke: white, style: StrokeStyle(lineWidth: 0.4))
        // 0.4 pt * 2.5 = 1 px wide centred on device y = 25: rows 24 and 25 each half covered (smoothstep(0.5) = 0.5)
        XCTAssertEqual(alpha(r, 20, 24), 128, accuracy: 1)
        XCTAssertEqual(alpha(r, 20, 25), 128, accuracy: 1)
        XCTAssertEqual(alpha(r, 20, 23), 0); XCTAssertEqual(alpha(r, 20, 26), 0)
        XCTAssertEqual(r.image.width, 50)
    }

    func testStrokeOverFillCompositesOverTheFill() throws {
        let r = try raster(rect(0, 0, 20, 20), translate: CGPoint(x: 5, y: 5), fill: red, stroke: 0x0000ffff, style: StrokeStyle(lineWidth: 4))
        func px(_ x: Int, _ y: Int) -> [UInt8] { let i = ((y - r.originY) * r.image.width + (x - r.originX)) * 4; return Array(r.image.rgba[i..<(i + 4)]) }
        XCTAssertEqual(px(15, 15), [255, 0, 0, 255])
        XCTAssertEqual(px(5, 15), [0, 0, 255, 255])
    }

    func testRoundCapStrokeOfATrimmedCircleCoversItsRingArcPlusCaps() throws {
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 40, height: 40))
        let arc = circle.trimmedPath(from: 0, to: 0.5)
        let r = try raster(arc, translate: CGPoint(x: 5, y: 5), stroke: white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
        let expected = Double.pi * 20 * 6 + Double.pi * 9          // half circumference * width + two half discs
        XCTAssertEqual(coverageSum(r), expected, accuracy: expected * 0.03)
    }

    func testZeroOrMissingPaintsAndPathsGiveNothing() throws {
        XCTAssertNil(try PathRasterizer.rasterize(path: Path(), fillRGBA: red))
        XCTAssertNil(try PathRasterizer.rasterize(path: rect(0, 0, 5, 5)))
        XCTAssertNil(try PathRasterizer.rasterize(path: rect(0, 0, 5, 5), strokeRGBA: red, strokeStyle: StrokeStyle(lineWidth: 0)))
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertNil(try PathRasterizer.rasterize(path: circle.trimmedPath(from: 0, to: 0), strokeRGBA: red, strokeStyle: StrokeStyle(lineWidth: 2, lineCap: .round)))
    }

    func testInvalidInputsAndOversizeThrow() {
        XCTAssertThrowsError(try PathRasterizer.rasterize(path: rect(0, 0, 5, 5), scale: 0, fillRGBA: red))
        XCTAssertThrowsError(try PathRasterizer.rasterize(path: rect(0, 0, 5, 5), strokeRGBA: red, strokeStyle: StrokeStyle(lineWidth: .nan)))
        XCTAssertThrowsError(try PathRasterizer.rasterize(path: rect(0, 0, 1800, 1800), fillRGBA: red)) { XCTAssertEqual($0 as? PathRasterError, .workLimitExceeded) }
    }

    // MARK: Dashes

    private func line(_ length: Double) -> PathRasterizer.Poly {
        PathRasterizer.Poly(points: [PathPoint(0, 0), PathPoint(length, 0)], smooth: [false, false], closed: false, hint: nil)
    }

    private func extents(_ pieces: [PathRasterizer.Poly]) -> [[Double]] { pieces.map { [$0.points.first!.x, $0.points.last!.x] } }

    func testDashExpansionWithPhase() throws {
        func run(_ pattern: [Double], _ phase: Double, _ length: Double = 30) throws -> [[Double]] { extents(try PathRasterizer.dash(line(length), pattern: pattern, phase: phase)) }
        XCTAssertEqual(try run([6, 3], 0), [[0, 6], [9, 15], [18, 24], [27, 30]])
        XCTAssertEqual(try run([6, 3], 2), [[0, 4], [7, 13], [16, 22], [25, 30]])
        XCTAssertEqual(try run([6, 3], 7), [[2, 8], [11, 17], [20, 26], [29, 30]])
        XCTAssertEqual(try run([6, 3], -2), try run([6, 3], 7), "a negative phase wraps by the period")
        XCTAssertEqual(try run([6, 3], 9), try run([6, 3], 0), "a whole period changes nothing")
        XCTAssertEqual(try run([4], 0, 14), [[0, 4], [8, 12]], "an odd pattern repeats, swapping on and off")
        XCTAssertEqual(try run([2, 1, 3], 0, 12), [[0, 2], [3, 6], [8, 9]], "three entries: on 2, off 1, on 3, then off 2, on 1, off 3")
    }

    func testDashPiecesKeepTheCornersTheyCross() throws {
        let corner = PathRasterizer.Poly(points: [PathPoint(0, 0), PathPoint(10, 0), PathPoint(10, 10)], smooth: [false, false, false], closed: false, hint: nil)
        let pieces = try PathRasterizer.dash(corner, pattern: [15, 5], phase: 0)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].points.map { [$0.x, $0.y] }, [[0, 0], [10, 0], [10, 5]])
    }

    func testClosedPolylinesDashThroughTheirClosingEdge() throws {
        let square = PathRasterizer.Poly(points: [PathPoint(0, 0), PathPoint(10, 0), PathPoint(10, 10), PathPoint(0, 10)], smooth: [false, false, false, false], closed: true, hint: nil)
        let pieces = try PathRasterizer.dash(square, pattern: [30, 10], phase: 0)      // perimeter 40: one dash 0...30, then a gap
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].points.last!.x, 0, accuracy: 1e-9)
        XCTAssertEqual(pieces[0].points.last!.y, 10, accuracy: 1e-9)
    }

    func testZeroLengthDashesAreDots() throws {
        let pieces = try PathRasterizer.dash(line(40), pattern: [0, 10], phase: 0)
        XCTAssertEqual(pieces.count, 5)
        XCTAssertEqual(pieces.map { $0.points.first!.x }, [0, 10, 20, 30, 40])
        XCTAssertTrue(pieces.allSatisfy { $0.hint != nil })
        var p = Path(); p.move(to: CGPoint(x: 2, y: 5)); p.addLine(to: CGPoint(x: 42, y: 5))
        let r = try raster(p, stroke: white, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [0, 10]))
        XCTAssertEqual(coverageSum(r), 5 * Double.pi * 4, accuracy: 5 * Double.pi * 4 * 0.03)
    }

    func testInvalidDashPatternsMeanNoDashing() throws {
        XCTAssertEqual(try PathRasterizer.dash(line(30), pattern: [0, 0], phase: 0).count, 1)
        XCTAssertEqual(try PathRasterizer.dash(line(30), pattern: [4, -1], phase: 0).count, 1)
        XCTAssertEqual(try PathRasterizer.dash(line(30), pattern: [], phase: 0).count, 1)
    }

    func testDashedStrokeRasterLeavesTheGapsEmpty() throws {
        var p = Path(); p.move(to: CGPoint(x: 0, y: 5)); p.addLine(to: CGPoint(x: 30, y: 5))
        let r = try raster(p, stroke: white, style: StrokeStyle(lineWidth: 4, dash: [6, 3], dashPhase: 2))
        // on 0...4, off 4...7, on 7...13, off 13...16 ...
        XCTAssertEqual(alpha(r, 2, 5), 255); XCTAssertEqual(alpha(r, 5, 5), 0); XCTAssertEqual(alpha(r, 9, 5), 255); XCTAssertEqual(alpha(r, 14, 5), 0)
        XCTAssertEqual(coverageSum(r), (4 + 6 + 6 + 5) * 4, accuracy: 1)
    }

    // MARK: Flattening

    func testFlatteningUsesTheWangCountAndFlagsInteriorPointsSmooth() {
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100))
        let sub = PathSegments.subpaths(of: circle)
        let coarse = PathRasterizer.flatten(sub[0], PathRasterizer.Matrix(transform: .identity, scale: 1), tolerance: 0.2)
        let fine = PathRasterizer.flatten(sub[0], PathRasterizer.Matrix(transform: .identity, scale: 1), tolerance: 0.02)
        XCTAssertGreaterThan(fine.points.count, coarse.points.count)
        XCTAssertTrue(coarse.closed)
        // every point of the flattening lies within 0.2 of the true circle of radius 50
        for p in coarse.points { XCTAssertEqual(((p.x - 50) * (p.x - 50) + (p.y - 50) * (p.y - 50)).squareRoot(), 50, accuracy: 0.25) }
        XCTAssertEqual(coarse.smooth.filter { !$0 }.count, 4, "only the four quadrant joints are non-smooth vertices")
    }
}
