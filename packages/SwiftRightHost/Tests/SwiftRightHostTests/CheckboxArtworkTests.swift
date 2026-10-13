import XCTest
import SwiftRightHost

/// The checkbox artwork against SwiftUI's own render of the same four states (scale 2.5, 16 x 16 pt = 40 x 40 px): golden pixels measured on
/// macOS, flat colours exact, edges within 32/255 (docs/sr1-decisions.md, decision 5).
final class CheckboxArtworkTests: XCTestCase {
    private func composite(_ image: ContinuousRGBAImage, _ x: Int, _ y: Int) -> [Int] {
        let o = (y * image.width + x) * 4
        let a = Double(image.rgba[o + 3]) / 255
        return (0..<3).map { Int((Double(image.rgba[o + $0]) * a + 255 * (1 - a)).rounded()) }
    }

    private func golden(_ rows: [String], _ gy: Int, _ gx: Int) -> [Int] {
        let hex = String(Array(rows[gy])[(gx * 6)..<(gx * 6 + 6)])
        return [0, 2, 4].map { Int(hex.dropFirst($0).prefix(2), radix: 16)! }
    }

    private func assertMatchesSwiftUI(isOn: Bool, isEnabled: Bool, golden rows: [String], file: StaticString = #filePath, line: UInt = #line) {
        let image = CheckboxArtwork.render(widthPX: 40, heightPX: 40, isOn: isOn, isEnabled: isEnabled)
        XCTAssertEqual(image.width, 40); XCTAssertEqual(image.height, 40)
        var worst = 0
        for gy in 0..<rows.count {
            for gx in 0..<20 {
                let mine = composite(image, gx * 2, gy * 2), mac = golden(rows, gy, gx)
                worst = max(worst, zip(mine, mac).map { abs($0 - $1) }.max()!)
            }
        }
        XCTAssertLessThanOrEqual(worst, 32, "worst probe difference \(worst)", file: file, line: line)
    }

    func testOnMatchesSwiftUI() { assertMatchesSwiftUI(isOn: true, isEnabled: true, golden: CheckboxArtworkGolden.on) }
    func testOffMatchesSwiftUI() { assertMatchesSwiftUI(isOn: false, isEnabled: true, golden: CheckboxArtworkGolden.off) }
    func testDisabledOnMatchesSwiftUI() { assertMatchesSwiftUI(isOn: true, isEnabled: false, golden: CheckboxArtworkGolden.onDisabled) }
    func testDisabledOffMatchesSwiftUI() { assertMatchesSwiftUI(isOn: false, isEnabled: false, golden: CheckboxArtworkGolden.offDisabled) }

    func testFlatStateColoursAreExact() {
        let cases: [(on: Bool, enabled: Bool, box: [Int])] = [
            (true, true, [0, 120, 249]), (false, true, [230, 230, 230]), (true, false, [236, 236, 236]), (false, false, [242, 242, 242]),
        ]
        for c in cases {
            let image = CheckboxArtwork.render(widthPX: 40, heightPX: 40, isOn: c.on, isEnabled: c.enabled)
            XCTAssertEqual(composite(image, 4, 20), c.box, "box on=\(c.on) enabled=\(c.enabled)")
            XCTAssertEqual(image.rgba[3], 0, "corner is transparent")
        }
    }

    func testOnStateDrawsAWhiteCheckAndDisabledADimmedOne() {
        let on = CheckboxArtwork.render(widthPX: 40, heightPX: 40, isOn: true, isEnabled: true)
        XCTAssertEqual(composite(on, 17, 27), [255, 255, 255])        // inside the left arm... bottom of the check
        let disabled = CheckboxArtwork.render(widthPX: 40, heightPX: 40, isOn: true, isEnabled: false)
        XCTAssertEqual(composite(disabled, 17, 27), [175, 175, 175])
        let off = CheckboxArtwork.render(widthPX: 40, heightPX: 40, isOn: false, isEnabled: true)
        XCTAssertEqual(composite(off, 17, 27), [230, 230, 230], "an unchecked box has no mark")
    }
}
