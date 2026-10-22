import SwiftRightRuntime
import XCTest

final class StrokedPathTests: XCTestCase {
    private func line() -> Path { Path { p in p.move(to: CGPoint(x: 0, y: 10)); p.addLine(to: CGPoint(x: 100, y: 10)) } }

    func testButtLineIsARectangleOfTheLineWidth() {
        let r = line().strokedPath(StrokeStyle(lineWidth: 4, lineCap: .butt)).boundingRect
        XCTAssertEqual(r.minX, 0, accuracy: 1e-6); XCTAssertEqual(r.maxX, 100, accuracy: 1e-6)
        XCTAssertEqual(r.minY, 8, accuracy: 1e-6); XCTAssertEqual(r.maxY, 12, accuracy: 1e-6)
    }

    func testRoundCapsExtendByHalfTheWidth() {
        let r = line().strokedPath(StrokeStyle(lineWidth: 4, lineCap: .round)).boundingRect
        XCTAssertEqual(r.minX, -2, accuracy: 0.05); XCTAssertEqual(r.maxX, 102, accuracy: 0.05)
    }

    func testEmptyForZeroWidth() {
        XCTAssertTrue(line().strokedPath(StrokeStyle(lineWidth: 0)).isEmpty)
    }

    func testDashedStrokeHasOnePiecePerDash() {
        let r = line().strokedPath(StrokeStyle(lineWidth: 2, lineCap: .butt, dash: [10, 10]))
        XCTAssertEqual(r.elements.filter { if case .closeSubpath = $0 { return true } else { return false } }.count, 5)
    }
}
