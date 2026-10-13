import XCTest
import SwiftRightHost

/// The switch artwork against SwiftUI's own render of the same four states (scale 2.5): golden pixels measured on macOS, compared the way the
/// factory gate does: flat colours exact, edges within 32/255 (docs/sr1-decisions.md, decision 5).
final class SwitchArtworkTests: XCTestCase {
    private func composite(_ image: ContinuousRGBAImage, _ x: Int, _ y: Int) -> [Int] {
        let o = (y * image.width + x) * 4
        let a = Double(image.rgba[o + 3]) / 255
        return (0..<3).map { Int((Double(image.rgba[o + $0]) * a + 255 * (1 - a)).rounded()) }
    }

    private func golden(_ rows: [String], _ gy: Int, _ gx: Int) -> [Int] {
        let row = Array(rows[gy])
        let chars = row[(gx * 6)..<(gx * 6 + 6)]
        let hex = String(chars)
        return [0, 2, 4].map { Int(hex.dropFirst($0).prefix(2), radix: 16)! }
    }

    private func assertMatchesSwiftUI(isOn: Bool, isEnabled: Bool, golden rows: [String], file: StaticString = #filePath, line: UInt = #line) {
        let image = SwitchArtwork.render(widthPX: 135, heightPX: 60, isOn: isOn, isEnabled: isEnabled)
        XCTAssertEqual(image.width, 135); XCTAssertEqual(image.height, 60)
        var worst = 0
        for gy in 0..<rows.count {
            for gx in 0..<(135 / 3) {
                let mine = composite(image, gx * 3, gy * 3), mac = golden(rows, gy, gx)
                worst = max(worst, zip(mine, mac).map { abs($0 - $1) }.max()!)
            }
        }
        XCTAssertLessThanOrEqual(worst, 32, "worst probe difference \(worst)", file: file, line: line)
    }

    func testOnMatchesSwiftUI() { assertMatchesSwiftUI(isOn: true, isEnabled: true, golden: SwitchArtworkGolden.on) }
    func testOffMatchesSwiftUI() { assertMatchesSwiftUI(isOn: false, isEnabled: true, golden: SwitchArtworkGolden.off) }
    func testDisabledOnMatchesSwiftUI() { assertMatchesSwiftUI(isOn: true, isEnabled: false, golden: SwitchArtworkGolden.onDisabled) }
    func testDisabledOffMatchesSwiftUI() { assertMatchesSwiftUI(isOn: false, isEnabled: false, golden: SwitchArtworkGolden.offDisabled) }

    func testFlatStateColoursAreExact() {
        let cases: [(on: Bool, enabled: Bool, track: [Int], x: Int)] = [
            (true, true, [0, 120, 249], 10), (true, false, [75, 157, 247], 10),
            (false, true, [230, 230, 230], 120), (false, false, [242, 242, 242], 120),
        ]
        for c in cases {
            let image = SwitchArtwork.render(widthPX: 135, heightPX: 60, isOn: c.on, isEnabled: c.enabled)
            XCTAssertEqual(composite(image, c.x, 30), c.track, "track on=\(c.on) enabled=\(c.enabled)")
            XCTAssertEqual(composite(image, c.on ? 90 : 40, 30), [255, 255, 255], "knob on=\(c.on)")
            XCTAssertEqual(image.rgba[3], 0, "corner is transparent")
        }
    }

    func testKnobSitsAtTheTrailingEndWhenOnAndLeadingWhenOff() {
        XCTAssertEqual(SwitchArtwork.knobOriginX(isOn: true), 20)
        XCTAssertEqual(SwitchArtwork.knobOriginX(isOn: false), 2)
        XCTAssertEqual(SwitchArtwork.trackColor(isOn: true, isEnabled: true), 0x0078f9)
    }

    func testRenderIsDeterministicAndMemoised() {
        let a = SwitchArtwork.render(widthPX: 135, heightPX: 60, isOn: true, isEnabled: true)
        let b = SwitchArtwork.render(widthPX: 135, heightPX: 60, isOn: true, isEnabled: true)
        XCTAssertEqual(a, b)
    }

    func testOtherScalesKeepTheShape() {
        // 2x: the control is 108 x 48 px; the same track colour away from the ends and a transparent corner.
        let image = SwitchArtwork.render(widthPX: 108, heightPX: 48, isOn: true, isEnabled: true)
        XCTAssertEqual(composite(image, 8, 24), [0, 120, 249])
        XCTAssertEqual(image.rgba[3], 0)
    }
}
