import XCTest
import SwiftRightRuntime
@testable import SwiftRightHost

/// The Slider model (decision H4) against the Mac captures it was fitted to, composited over white: <= 1 level except at the track end caps (<= 4).
final class SliderArtworkTests: XCTestCase {
    private func overWhite(_ image: ContinuousRGBAImage, x: Int, y: Int, margin: Int) -> Int {
        let ix = x + margin, iy = y + margin
        guard ix >= 0, ix < image.width, iy >= 0, iy < image.height else { return 255 }
        let o = (iy * image.width + ix) * 4
        let a = Double(image.rgba[o + 3]) / 255
        return Int((Double(image.rgba[o]) * a + 255 * (1 - a)).rounded())
    }

    private func check(_ scheme: ColorScheme, rows: [Int: [Int]], cols: [Int: [Int]]) {
        let image = SliderArtwork.render(widthPX: 500, heightPX: 40, thumbOffsetPX: 225, fillEndPX: 250, isEnabled: true, scheme: scheme)
        let margin = SliderArtwork.marginPX(scale: 2.5)
        XCTAssertEqual(margin, 16)
        XCTAssertEqual(image.width, 532); XCTAssertEqual(image.height, 72)
        var worst = 0, over1 = 0, total = 0
        for (y, row) in rows { for (k, expected) in row.enumerated() { let x = k - 16; let d = abs(overWhite(image, x: x, y: y, margin: margin) - expected); worst = max(worst, d); total += 1; if d > 1 { over1 += 1 } } }
        for (x, col) in cols { for (k, expected) in col.enumerated() { let y = k - 16; let d = abs(overWhite(image, x: x, y: y, margin: margin) - expected); worst = max(worst, d); total += 1; if d > 1 { over1 += 1 } } }
        XCTAssertLessThanOrEqual(worst, 4, "\(scheme): worst level difference")
        XCTAssertLessThanOrEqual(over1, 12, "\(scheme): pixels off by more than 1 (the end caps)")
        XCTAssertGreaterThan(total, 3000)
    }

    func testLightMatchesTheMac() { check(.light, rows: SliderArtworkGolden.lightRows, cols: SliderArtworkGolden.lightCols) }
    func testDarkMatchesTheMac() { check(.dark, rows: SliderArtworkGolden.darkRows, cols: SliderArtworkGolden.darkCols) }

    func testDisabledFillIsAFlatGreyAndTheThumbIsUnchanged() {
        let on = SliderArtwork.render(widthPX: 500, heightPX: 40, thumbOffsetPX: 225, fillEndPX: 250, isEnabled: true, scheme: .light)
        let off = SliderArtwork.render(widthPX: 500, heightPX: 40, thumbOffsetPX: 225, fillEndPX: 250, isEnabled: false, scheme: .light)
        let m = SliderArtwork.marginPX(scale: 2.5)
        XCTAssertEqual(overWhite(off, x: 100, y: 20, margin: m), 218)      // measured: 255 * (1 - 37/255)
        XCTAssertEqual(overWhite(off, x: 400, y: 20, margin: m), 230)      // the empty track, as enabled
        XCTAssertEqual(overWhite(on, x: 400, y: 20, margin: m), 230)
        XCTAssertEqual(overWhite(off, x: 250, y: 20, margin: m), 255)      // the thumb body
    }

    func testOtherScalesRenderAtScaledSizes() {
        let image = SliderArtwork.render(widthPX: 400, heightPX: 32, thumbOffsetPX: 90, fillEndPX: 200, isEnabled: true, scheme: .light, scale: 2)
        XCTAssertEqual(image.width, 400 + 2 * SliderArtwork.marginPX(scale: 2))
        XCTAssertEqual(SliderArtwork.thumbPX(scale: 2).width, 40)
        XCTAssertTrue(image.rgba.contains { $0 != 0 })
    }
}
