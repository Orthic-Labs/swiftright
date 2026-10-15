import XCTest
import SwiftRightHost

/// The button artwork against SwiftUI's own render of a 48 x 24 pt (120 x 60 px at scale 2.5) default Button, enabled and disabled: golden pixels measured on
/// macOS (every 3rd pixel, label region excluded), flat fills exact, edges within 32/255 (docs/sr1-decisions.md, decision 5).
final class ButtonArtworkTests: XCTestCase {
    private func composite(_ image: ContinuousRGBAImage, _ x: Int, _ y: Int) -> [Int] {
        let o = (y * image.width + x) * 4
        let a = Double(image.rgba[o + 3]) / 255
        return (0..<3).map { Int((Double(image.rgba[o + $0]) * a + 255 * (1 - a)).rounded()) }
    }

    private func golden(_ rows: [String], _ gy: Int, _ gx: Int) -> [Int] {
        let hex = String(Array(rows[gy])[(gx * 6)..<(gx * 6 + 6)])
        return [0, 2, 4].map { Int(hex.dropFirst($0).prefix(2), radix: 16)! }
    }

    private func assertMatchesSwiftUI(isEnabled: Bool, prominent: Bool = false, golden rows: [String], file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI draws the 47.6 pt (label 23.6 + 24) button 119 px wide inside its 120 px frame
        let image = ButtonArtwork.render(widthPX: 119, heightPX: 60, scale: 2.5, isEnabled: isEnabled, prominent: prominent)
        XCTAssertEqual(image.width, 119); XCTAssertEqual(image.height, 60)
        var worst = 0, at = (0, 0)
        for gy in 0..<rows.count {
            for gx in 0..<40 {
                let x = gx * 3, y = gy * 3
                if x >= 20 && x < 100 && y >= 10 && y < 50 { continue }          // the label region: the artwork has no label
                let d = zip(composite(image, x, y), golden(rows, gy, gx)).map { abs($0 - $1) }.max()!
                if d > worst { worst = d; at = (x, y) }
            }
        }
        XCTAssertLessThanOrEqual(worst, 32, "worst probe difference \(worst) at \(at)", file: file, line: line)
    }

    func testEnabledMatchesSwiftUI() { assertMatchesSwiftUI(isEnabled: true, golden: ButtonArtworkGolden.enabled) }
    func testDisabledMatchesSwiftUI() { assertMatchesSwiftUI(isEnabled: false, golden: ButtonArtworkGolden.disabled) }

    func testProminentMatchesSwiftUI() { assertMatchesSwiftUI(isEnabled: true, prominent: true, golden: ButtonArtworkGolden.prominent) }
    func testProminentDisabledMatchesSwiftUI() { assertMatchesSwiftUI(isEnabled: false, prominent: true, golden: ButtonArtworkGolden.prominentDisabled) }

    func testLookColoursAreTheMeasuredOnes() {
        XCTAssertEqual(composite(ButtonArtwork.render(widthPX: 120, heightPX: 60, scale: 2.5, isEnabled: true, prominent: true), 60, 5), [0, 123, 255])
        XCTAssertEqual(composite(ButtonArtwork.render(widthPX: 120, heightPX: 60, scale: 2.5, isEnabled: false, prominent: true), 60, 5), [79, 163, 255])
        XCTAssertEqual(ButtonArtwork.labelColor(look: .prominent, isEnabled: true), 0xffffff)
        XCTAssertEqual(ButtonArtwork.labelColor(look: .prominent, isEnabled: false), 0xa7d1ff)
        XCTAssertEqual(ButtonArtwork.labelColor(look: .borderless, isEnabled: true), 0x7f7f7f)
        XCTAssertEqual(ButtonArtwork.labelColor(look: .borderless, isEnabled: false), 0xbfbfbf)
        XCTAssertNil(ButtonArtwork.labelColor(look: .plain, isEnabled: true))
        XCTAssertEqual(ButtonArtwork.labelColor(look: .plain, isEnabled: false), 0x939393)
    }

    func testFlatFillsAndLabelColoursAreExact() {
        XCTAssertEqual(composite(ButtonArtwork.render(widthPX: 120, heightPX: 60, scale: 2.5, isEnabled: true), 60, 5), [235, 235, 235])
        XCTAssertEqual(composite(ButtonArtwork.render(widthPX: 120, heightPX: 60, scale: 2.5, isEnabled: false), 60, 5), [245, 245, 245])
        XCTAssertEqual(ButtonArtwork.labelColor(isEnabled: true), 0x242424)
        XCTAssertEqual(ButtonArtwork.labelColor(isEnabled: false), 0xb6b6b6)
        XCTAssertEqual(ButtonArtwork.render(widthPX: 120, heightPX: 60, scale: 2.5, isEnabled: true).rgba[3], 0, "corner is transparent")
    }

    func testWiderButtonKeepsItsCornersAndFlatMiddle() {
        let wide = ButtonArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5, isEnabled: true)
        XCTAssertEqual(composite(wide, 150, 30), [235, 235, 235])
        XCTAssertEqual(wide.rgba[3], 0)
        XCTAssertEqual(wide.rgba[(299) * 4 + 3], 0, "right corner is transparent too")
    }
}

/// Round 5 block 36 (hub: dark bordered buttons drew as white blobs): the dark fills and label colours, measured on macOS 27 (darkAqua, scale 2.5).
final class ButtonArtworkDarkTests: XCTestCase {
    private func centre(_ i: ContinuousRGBAImage) -> [UInt8] { let o = (30 * i.width + 60) * 4; return Array(i.rgba[o..<o + 3]) }
    func testDarkFillsAndLabels() {
        XCTAssertEqual(centre(ButtonArtwork.render(widthPX: 120, heightPX: 60, scale: 2.5, isEnabled: true, dark: true)), [48, 48, 48])
        XCTAssertEqual(centre(ButtonArtwork.render(widthPX: 120, heightPX: 60, scale: 2.5, isEnabled: false, dark: true)), [38, 38, 38])
        XCTAssertEqual(centre(ButtonArtwork.render(widthPX: 120, heightPX: 60, scale: 2.5, isEnabled: false, prominent: true, dark: true)), [9, 93, 185])
        XCTAssertEqual(centre(ButtonArtwork.render(widthPX: 120, heightPX: 60, scale: 2.5, isEnabled: true)), [235, 235, 235], "light unchanged")
        XCTAssertEqual(ButtonArtwork.labelColor(look: .bordered, isEnabled: true, dark: true), 0xdfdfdf)
        XCTAssertEqual(ButtonArtwork.labelColor(look: .bordered, isEnabled: false, dark: true), 0x5c5c5c)
        XCTAssertEqual(ButtonArtwork.labelColor(look: .borderless, isEnabled: true, dark: true), 0x9a9a9a)
        XCTAssertEqual(ButtonArtwork.labelColor(look: .prominent, isEnabled: false, dark: true), 0x84aedc)
    }
}
