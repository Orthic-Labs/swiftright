import XCTest
@testable import SwiftRightRuntime

final class SystemImageLayoutMetricsTests: XCTestCase {
    /// star.fill as measured on macOS (factory/tools/symbol-metrics).
    private let star = SystemImageLayoutMetrics(aspect: 1.0701468189233279, inkLeft: 0.0048828125,
                                                inkTop: 0.00045880913539967229, inkRight: 0.94482421875,
                                                inkBottom: 0.96139630913539975)

    private func solid(_ w: Int, _ h: Int, rect: (Int, Int, Int, Int), value: UInt8 = 64) -> [UInt8] {
        var c = [UInt8](repeating: 0, count: w * h)
        for y in rect.1..<rect.3 { for x in rect.0..<rect.2 { c[y * w + x] = value } }
        return c
    }

    private func input(_ cov: [UInt8], _ w: Int, _ h: Int, order: SystemImageRasterRowOrder = .topDown,
                       face: String = "Segoe Fluent Icons") -> SystemImageRasterInput {
        SystemImageRasterInput(sourceWidth: UInt32(w), sourceHeight: UInt32(h), rowBytes: UInt32(w), coverage: cov,
                               coverageMaximum: 64, rowOrder: order, selectedFace: face, expectedFace: "Segoe Fluent Icons")
    }

    func testLayoutBoxAspectFitsAndCentres() {
        let square = SystemImageFit.layoutBox(aspect: 2, targetWidth: 80, targetHeight: 80)
        XCTAssertEqual(square, SystemImageFitRect(x: 0, y: 20, width: 80, height: 40))
        let tall = SystemImageFit.layoutBox(aspect: 0.5, targetWidth: 80, targetHeight: 80)
        XCTAssertEqual(tall, SystemImageFitRect(x: 20, y: 0, width: 40, height: 80))
        let wideFrame = SystemImageFit.layoutBox(aspect: 1, targetWidth: 200, targetHeight: 50)
        XCTAssertEqual(wideFrame, SystemImageFitRect(x: 75, y: 0, width: 50, height: 50))
    }

    func testStarInkRectAtMeasuredFrame() {
        let ink = SystemImageFit.inkRect(star, targetWidth: 80, targetHeight: 80)
        // Mac half-coverage ink at 80px: layout box 80x74.76 centred, ink 0.39..75.58 x 2.63..74.5
        XCTAssertEqual(ink.x, 0.390625, accuracy: 1e-9)
        XCTAssertEqual(ink.width, 75.1953125, accuracy: 1e-6)
        XCTAssertEqual(ink.y, 2.6 + 0.0, accuracy: 0.1)
        XCTAssertEqual(ink.y + ink.height, 74.5, accuracy: 0.1)
    }

    func testInkRectScalesLinearlyWithFrame() {
        let a = SystemImageFit.inkRect(star, targetWidth: 80, targetHeight: 80)
        let b = SystemImageFit.inkRect(star, targetWidth: 160, targetHeight: 160)
        XCTAssertEqual(b.x, a.x * 2, accuracy: 1e-9)
        XCTAssertEqual(b.y, a.y * 2, accuracy: 1e-9)
        XCTAssertEqual(b.width, a.width * 2, accuracy: 1e-9)
        XCTAssertEqual(b.height, a.height * 2, accuracy: 1e-9)
    }

    func testMetricsValidation() {
        XCTAssertTrue(star.isValid)
        XCTAssertFalse(SystemImageLayoutMetrics(aspect: 0, inkLeft: 0, inkTop: 0, inkRight: 1, inkBottom: 1).isValid)
        XCTAssertFalse(SystemImageLayoutMetrics(aspect: 1, inkLeft: 0.5, inkTop: 0, inkRight: 0.5, inkBottom: 1).isValid)
        XCTAssertTrue(SystemImageLayoutMetrics(aspect: 1, inkLeft: -0.01, inkTop: -0.0001, inkRight: 1.02, inkBottom: 1).isValid)
        XCTAssertFalse(SystemImageLayoutMetrics(aspect: 1, inkLeft: -0.5, inkTop: 0, inkRight: 1, inkBottom: 1).isValid)
        XCTAssertFalse(SystemImageLayoutMetrics(aspect: .nan, inkLeft: 0, inkTop: 0, inkRight: 1, inkBottom: 1).isValid)
        XCTAssertThrowsError(try SystemImageRasterProvider.composeMetricsAligned(
            input(solid(4, 4, rect: (0, 0, 4, 4)), 4, 4),
            metrics: SystemImageLayoutMetrics(aspect: -1, inkLeft: 0, inkTop: 0, inkRight: 1, inkBottom: 1),
            targetWidth: 8, targetHeight: 8, tintRGBA: 0xffffffff)) {
            XCTAssertEqual($0 as? SystemImageRasterError, .invalidDimensions)
        }
    }

    func testHalfCoverageBoundsIgnoreFaintFringe() {
        var cov = solid(10, 10, rect: (2, 3, 8, 9))
        cov[3 * 10 + 0] = 10   // faint tip left of the ink, below half of 64
        cov[0 * 10 + 5] = 31
        let b = SystemImageFit.halfCoverageBounds(coverage: cov, rowBytes: 10, width: 10, height: 10,
                                                  rowOrder: .topDown, coverageMaximum: 64)
        XCTAssertEqual(b, SystemImageFitRect(x: 2, y: 3, width: 6, height: 6))
        cov[0 * 10 + 5] = 32   // exactly half counts as ink
        let c = SystemImageFit.halfCoverageBounds(coverage: cov, rowBytes: 10, width: 10, height: 10,
                                                  rowOrder: .topDown, coverageMaximum: 64)
        XCTAssertEqual(c?.y, 0)
        XCTAssertNil(SystemImageFit.halfCoverageBounds(coverage: [UInt8](repeating: 0, count: 4), rowBytes: 2, width: 2,
                                                       height: 2, rowOrder: .topDown, coverageMaximum: 64))
    }

    func testBottomUpBoundsFlip() {
        let cov = solid(4, 4, rect: (0, 0, 2, 1))   // first memory row only
        let up = SystemImageFit.halfCoverageBounds(coverage: cov, rowBytes: 4, width: 4, height: 4,
                                                   rowOrder: .bottomUp, coverageMaximum: 64)
        XCTAssertEqual(up, SystemImageFitRect(x: 0, y: 3, width: 2, height: 1))
    }

    /// Ink pixels of an RGBA buffer at coverage >= half.
    private func inkBounds(_ out: SystemImageRasterOutput) -> (Int, Int, Int, Int)? {
        var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
        for y in 0..<Int(out.height) { for x in 0..<Int(out.width) where out.rgba[(y * Int(out.width) + x) * 4 + 3] >= 128 {
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        return x1 < 0 ? nil : (x0, y0, x1 + 1, y1 + 1)
    }

    func testComposeLandsInkOnMetricsRectWithFractionalEdges() throws {
        // 8x oversampled source: ink occupies (5,9)-(75,70) inside an 80x80 bitmap
        let src = solid(80, 80, rect: (5, 9, 75, 70))
        let metrics = SystemImageLayoutMetrics(aspect: 1, inkLeft: 0.1, inkTop: 0.2, inkRight: 0.9, inkBottom: 0.75)
        let out = try SystemImageRasterProvider.composeMetricsAligned(input(src, 80, 80), metrics: metrics,
                                                                      targetWidth: 40, targetHeight: 40, tintRGBA: 0xffcc00ff)
        // exact ink rect: x 4..36, y 8..30 in a 40x40 frame -> whole pixels, interior fully covered
        XCTAssertEqual(out.width, 40); XCTAssertEqual(out.height, 40)
        let b = inkBounds(out)!
        XCTAssertEqual(b.0, 4); XCTAssertEqual(b.1, 8); XCTAssertEqual(b.2, 36); XCTAssertEqual(b.3, 30)
        let mid = (20 * 40 + 20) * 4
        XCTAssertEqual(Array(out.rgba[mid..<mid + 4]), [0xff, 0xcc, 0x00, 0xff])
        XCTAssertEqual(out.rgba[(7 * 40 + 20) * 4 + 3], 0)
        XCTAssertEqual(out.rgba[(30 * 40 + 20) * 4 + 3], 0)
    }

    func testComposeProducesAreaWeightedPartialCoverageAtFractionalEdges() throws {
        let src = solid(8, 8, rect: (0, 0, 8, 8))
        // ink rect x 1.5..6.5 in an 8x8 frame (aspect 1; fractions .1875..0.8125)
        let metrics = SystemImageLayoutMetrics(aspect: 1, inkLeft: 0.1875, inkTop: 0.25, inkRight: 0.8125, inkBottom: 0.75)
        let out = try SystemImageRasterProvider.composeMetricsAligned(input(src, 8, 8), metrics: metrics,
                                                                      targetWidth: 8, targetHeight: 8, tintRGBA: 0xff0000ff)
        XCTAssertEqual(out.rgba[(4 * 8 + 1) * 4 + 3], 128, accuracy: 1)   // half-covered column
        XCTAssertEqual(out.rgba[(4 * 8 + 6) * 4 + 3], 128, accuracy: 1)
        XCTAssertEqual(out.rgba[(4 * 8 + 3) * 4 + 3], 255)
        XCTAssertEqual(out.rgba[(4 * 8 + 0) * 4 + 3], 0)
    }

    func testComposeCentresLayoutBoxInNonSquareFrameAndKeepsOrientation() throws {
        // bottom-up bitmap: memory row 0 (wide) is visually the bottom, memory row 7 (narrow) the top
        var cov = [UInt8](repeating: 0, count: 8 * 8)
        for x in 0..<8 { cov[x] = 64 }
        for x in 3..<5 { cov[7 * 8 + x] = 64 }
        let metrics = SystemImageLayoutMetrics(aspect: 1, inkLeft: 0, inkTop: 0, inkRight: 1, inkBottom: 1)
        let out = try SystemImageRasterProvider.composeMetricsAligned(input(cov, 8, 8, order: .bottomUp), metrics: metrics,
                                                                      targetWidth: 40, targetHeight: 20, tintRGBA: 0xffffffff)
        let b = inkBounds(out)!
        XCTAssertEqual(b.0, 10); XCTAssertEqual(b.2, 30)      // 20x20 box centred in 40 wide
        XCTAssertEqual(b.1, 0); XCTAssertEqual(b.3, 20)
        func row(_ y: Int) -> Int { (0..<40).filter { out.rgba[(y * 40 + $0) * 4 + 3] > 0 }.count }
        XCTAssertGreaterThan(row(19), row(0))                 // wide row at the visual bottom
    }

    func testComposeRejectsFaceMismatchAndEmptyCoverage() {
        let metrics = SystemImageLayoutMetrics(aspect: 1, inkLeft: 0, inkTop: 0, inkRight: 1, inkBottom: 1)
        XCTAssertThrowsError(try SystemImageRasterProvider.composeMetricsAligned(
            input(solid(4, 4, rect: (0, 0, 4, 4)), 4, 4, face: "Other"), metrics: metrics,
            targetWidth: 8, targetHeight: 8, tintRGBA: 0xffffffff)) {
            XCTAssertEqual($0 as? SystemImageRasterError, .selectedFaceMismatch)
        }
        XCTAssertThrowsError(try SystemImageRasterProvider.composeMetricsAligned(
            input([UInt8](repeating: 0, count: 16), 4, 4), metrics: metrics,
            targetWidth: 8, targetHeight: 8, tintRGBA: 0xffffffff)) {
            XCTAssertEqual($0 as? SystemImageRasterError, .emptyCoverage)
        }
    }

    func testTintAlphaScalesCoverage() throws {
        let metrics = SystemImageLayoutMetrics(aspect: 1, inkLeft: 0, inkTop: 0, inkRight: 1, inkBottom: 1)
        let out = try SystemImageRasterProvider.composeMetricsAligned(
            input(solid(4, 4, rect: (0, 0, 4, 4)), 4, 4), metrics: metrics, targetWidth: 4, targetHeight: 4, tintRGBA: 0x10203080)
        XCTAssertEqual(Array(out.rgba[0..<4]), [0x10, 0x20, 0x30, 0x80])
    }
}

final class SystemImageDeviceInkTests: XCTestCase {
    private func input(_ cov: [UInt8], _ w: Int, _ h: Int) -> SystemImageRasterInput {
        SystemImageRasterInput(sourceWidth: UInt32(w), sourceHeight: UInt32(h), rowBytes: UInt32(w), coverage: cov,
                               coverageMaximum: 64, rowOrder: .topDown, selectedFace: "F", expectedFace: "F")
    }
    private let metrics = SystemImageLayoutMetrics(aspect: 1, inkLeft: 0, inkTop: 0, inkRight: 1, inkBottom: 1)

    /// A diamond (sharp tips at the four extremes), 8x oversampled.
    private func diamond(_ n: Int) -> [UInt8] {
        var c = [UInt8](repeating: 0, count: n * n)
        let m = Double(n) / 2
        for y in 0..<n { for x in 0..<n {
            let d = abs(Double(x) + 0.5 - m) + abs(Double(y) + 0.5 - m)
            if d <= m { c[y * n + x] = 64 } } }
        return c
    }

    func testDeviceInkBoxIsReachedExactlyEvenWithSharpTips() throws {
        let target = SystemImageDeviceInkBox(left: 1, top: 1, right: 78, bottom: 76)
        let a = try SystemImageRasterProvider.composeAligned(input(diamond(640), 640, 640), metrics: metrics,
                                                             deviceInk: target, targetWidth: 80, targetHeight: 80,
                                                             tintRGBA: 0xffcc00ff)
        XCTAssertEqual(a.halfCoverageBox, target)
        XCTAssertEqual(a.deviceInkMatched, true)
        XCTAssertEqual(a.inkRect.width, 77, accuracy: 2.0)     // refinement stays within 2px of the nominal box
        XCTAssertEqual(a.raster.width, 80)
    }

    func testWithoutCalibrationLinearMetricsPlacementIsUsed() throws {
        let a = try SystemImageRasterProvider.composeAligned(input(diamond(160), 160, 160), metrics: metrics,
                                                             targetWidth: 40, targetHeight: 20, tintRGBA: 0xffffffff)
        XCTAssertNil(a.deviceInkMatched)
        XCTAssertEqual(a.inkRect, SystemImageFitRect(x: 10, y: 0, width: 20, height: 20))
    }

    func testUnreachableDeviceBoxIsReportedNotHidden() throws {
        // a box one pixel wide can never be produced by an 8x diamond placed with 2px of leeway
        let target = SystemImageDeviceInkBox(left: 10, top: 10, right: 11, bottom: 70)
        let a = try SystemImageRasterProvider.composeAligned(input(diamond(640), 640, 640), metrics: metrics,
                                                             deviceInk: target, targetWidth: 80, targetHeight: 80,
                                                             tintRGBA: 0xffffffff)
        XCTAssertEqual(a.deviceInkMatched, false)
    }

    func testInkMayOverflowTheFrameThroughTheInset() throws {
        // frame 80x76, Mac ink starts one pixel above the frame (top = -1) and ends one past the bottom
        let target = SystemImageDeviceInkBox(left: 1, top: -1, right: 78, bottom: 77)
        let a = try SystemImageRasterProvider.composeAligned(input(diamond(640), 640, 640), metrics: metrics,
                                                             deviceInk: target, targetWidth: 80, targetHeight: 76,
                                                             inset: 4, tintRGBA: 0xffcc00ff)
        XCTAssertEqual(a.raster.width, 88); XCTAssertEqual(a.raster.height, 84)   // frame + 2*inset canvas
        XCTAssertEqual(a.halfCoverageBox, target)                                // reported frame-relative
        XCTAssertEqual(a.deviceInkMatched, true)
        // without enough inset the same box is refused
        XCTAssertThrowsError(try SystemImageRasterProvider.composeAligned(
            input(diamond(640), 640, 640), metrics: metrics, deviceInk: target, targetWidth: 80, targetHeight: 76,
            inset: 0, tintRGBA: 0xffffffff))
    }

    func testDeviceBoxOutsideFrameThrows() {
        XCTAssertThrowsError(try SystemImageRasterProvider.composeAligned(
            input(diamond(16), 16, 16), metrics: metrics, deviceInk: SystemImageDeviceInkBox(left: 0, top: 0, right: 90, bottom: 10),
            targetWidth: 80, targetHeight: 80, tintRGBA: 0xffffffff)) {
            XCTAssertEqual($0 as? SystemImageRasterError, .invalidDimensions)
        }
        XCTAssertFalse(SystemImageDeviceInkBox(left: 5, top: 0, right: 5, bottom: 3).isValid)
    }
}

@MainActor final class SystemImageFitIntrinsicTests: XCTestCase {
    func testScaledToFitUsesHostFitIntrinsicSizeWhileNaturalSizeStaysForFixedImages() {
        let fit = Graph(Image(systemName: "star.fill").resizable().scaledToFit())
        fit.imageIntrinsicSize = { _ in LayoutSize(width: 17, height: 16) }
        fit.imageFitIntrinsicSize = { _ in LayoutSize(width: 29, height: 28) }
        fit.rootProposal = ProposedViewSize(width: 32, height: 32)
        fit.flush()
        let image = fit.snapshot()
        XCTAssertEqual(Double(image?.frame.width ?? 0), 32, accuracy: 1e-9)
        XCTAssertEqual(Double(image?.frame.height ?? 0), 32.0 * 28 / 29, accuracy: 0.5)   // frames snap to whole pixels

        let natural = Graph(Image(systemName: "star.fill"))
        natural.imageIntrinsicSize = { _ in LayoutSize(width: 17, height: 16) }
        natural.imageFitIntrinsicSize = { _ in LayoutSize(width: 29, height: 28) }
        natural.flush()
        XCTAssertEqual(natural.snapshot()?.frame.width, 17)
        XCTAssertEqual(natural.snapshot()?.frame.height, 16)
    }

    func testDefaultFitIntrinsicKeepsNaturalSize() {
        let fit = Graph(Image(systemName: "star.fill").resizable().scaledToFit())
        fit.imageIntrinsicSize = { _ in LayoutSize(width: 40, height: 12) }
        fit.rootProposal = ProposedViewSize(width: 80, height: 80)
        fit.flush()
        XCTAssertEqual(fit.snapshot()?.frame.width, 80)
        XCTAssertEqual(fit.snapshot()?.frame.height, 24)
    }

    /// star.fill at scale class 2x (fitted by factory/tools/symbol-metrics/fit-layout.py): predicts the
    /// Mac half-coverage ink box for several frame sizes without a per-configuration calibration.
    func testScaleClassModelPredictsInkBoxForAnyFrame() {
        let star2x = SystemImageLayoutMetrics(aspect: 29.0 / 28.0, inkLeft: 0.0047, inkTop: 0.0, inkRight: 0.9775, inkBottom: 0.962,
                                              inkBias: [0.7, 0.5, 0.29, 0.35])
        // (view frame px, measured Mac box) at scale 2.5 for 12, 20, 32, 40, 100 and 120x60 pt frames.
        let measured: [((Int, Int), [Int])] = [((30, 28), [0, 0, 29, 27]), ((50, 48), [0, 0, 49, 46]), ((80, 78), [1, 0, 78, 75]),
                                               ((100, 96), [1, 0, 98, 92]), ((250, 242), [1, 0, 244, 233]), ((156, 150), [1, 0, 152, 144])]
        for ((w, h), box) in measured {
            let p = star2x.predictedInkBox(widthPx: w, heightPx: h)
            XCTAssertEqual([p?.left, p?.top, p?.right, p?.bottom].compactMap { $0 }, box, "view \(w)x\(h)")
        }
        XCTAssertNil(star2x.predictedInkBox(widthPx: 0, heightPx: 10))
        XCTAssertEqual(SystemImageLayoutMetrics(aspect: 1, inkLeft: 0, inkTop: 0, inkRight: 1, inkBottom: 1).inkBias, [0.5, 0.5, 0.5, 0.5])
    }
}
