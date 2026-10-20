import XCTest
@testable import SwiftRightRuntime

final class ColorSpaceTests: XCTestCase {
    private func rgba(_ c: Color) -> (Double, Double, Double, Double) {
        guard case let .rgba(r, g, b, a) = c.resolvedColor else { XCTFail("not rgba"); return (0, 0, 0, 0) }
        return (r, g, b, a)
    }

    func testDefaultAndExplicitSRGBAreTheComponentsUnchanged() {
        XCTAssertEqual(Color(red: 0.2, green: 0.6, blue: 1).resolvedColor, Color(.sRGB, red: 0.2, green: 0.6, blue: 1).resolvedColor)
        let c = rgba(Color(.sRGB, red: 0.2, green: 0.6, blue: 1, opacity: 0.5))
        XCTAssertEqual(c.0, 0.2); XCTAssertEqual(c.1, 0.6); XCTAssertEqual(c.2, 1); XCTAssertEqual(c.3, 0.5)
    }

    func testLinearMidGreyEncodesToSRGB() {
        let c = rgba(Color(.sRGBLinear, red: 0.5, green: 0.5, blue: 0.5))
        XCTAssertEqual(c.0, 0.7353569, accuracy: 1e-6)   // sRGB encode of 0.5
    }

    func testDisplayP3WhiteAndBlackStayWhiteAndBlack() {
        let w = rgba(Color(.displayP3, red: 1, green: 1, blue: 1)), k = rgba(Color(.displayP3, red: 0, green: 0, blue: 0))
        XCTAssertEqual(w.0, 1, accuracy: 1e-6); XCTAssertEqual(w.1, 1, accuracy: 1e-6); XCTAssertEqual(w.2, 1, accuracy: 1e-6)
        XCTAssertEqual(k.0, 0, accuracy: 1e-9)
    }
}
