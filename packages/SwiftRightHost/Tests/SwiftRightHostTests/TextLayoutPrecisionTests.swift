import XCTest
import SwiftRightRuntime
@testable import SwiftRightHost

/// Issue #7, G74/G76: text height and baseline reach the layout in Double, so a centred text snaps like the Mac at half-pixel ties.
/// Rows: (name, frame top pt in the 20 pt-origin window, frame height pt, text height px, table baseline px, Mac baseline boundary px).
final class TextLayoutPrecisionTests: XCTestCase {
    private let scale: Float = 2.5

    private func paintedBaselinePX(frameTop: Double, frame: Double, heightPX: Float, baselinePX: Float) -> Double {
        let h = Double(TextLayoutPrecision.dip(px: heightPX, scale: scale))
        let y = frameTop + (frame - h) / 2
        let top = DevicePixelSnap.pixel(y, scale: 2.5)
        let b = Double(TextLayoutPrecision.exactDIP(baselinePX / scale, scale: scale)) * 2.5
        return top + b.rounded()
    }

    func testHeightIsDoubleQuotient() {
        XCTAssertEqual(Double(TextLayoutPrecision.dip(px: 83, scale: 2.5)), 83.0 / 2.5)
        XCTAssertEqual(Double(TextLayoutPrecision.exactDIP(Float(27.2), scale: 2.5)), 68.0 / 2.5)
        XCTAssertNotEqual(Double(Float(83) / Float(2.5)), 83.0 / 2.5)   // the Float quotient the host used to report
    }

    func testMacBoundaries() {
        let rows: [(String, Double, Double, Float, Float, Double)] = [
            ("28 in 60", 80, 60, 83, 68, 302),
            ("caption2 in 24", 140, 24, 33, 25, 388),
            ("subheadline in 24", 20, 24, 35, 28, 90),
            ("caption in 24", 116, 24, 33, 25, 329),
            ("footnote in 24", 92, 24, 33, 25, 269),
            ("24 in 60", 20, 60, 70, 58, 148),
            ("32 in 60", 140, 60, 95, 78, 455),
            ("11.5 in 40", 20, 40, 35, 28, 111),
            ("12 in 40", 60, 40, 38, 30, 211),
            ("13sb in 40", 100, 40, 40, 33, 313),
            ("18 in 40", 140, 40, 53, 43, 416),
            ("24 in 40", 180, 40, 70, 58, 523),
        ]
        for (name, top, frame, h, b, mac) in rows {
            XCTAssertEqual(paintedBaselinePX(frameTop: top, frame: frame, heightPX: h, baselinePX: b), mac, name)
        }
    }
}
