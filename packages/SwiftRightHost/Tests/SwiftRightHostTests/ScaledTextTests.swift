import XCTest
@testable import SwiftRightHost
import SwiftRightBridge

// R4b (#42): the font a one-line Text under `.scaleEffect` is shaped at.
@MainActor
final class ScaledTextTests: XCTestCase {
    func testScaledFontTakesTheSizeTimesTheFactorInHalfPoints() {
        let f = ResolvedNodePainter.scaledFont(.system(size: 13, weight: .semibold), by: 1.5)
        XCTAssertEqual(f?.metadata?.pointSize, 19.5)
        XCTAssertEqual(f?.metadata?.weight, .semibold)
        XCTAssertEqual(ResolvedNodePainter.scaledFont(.system(size: 13), by: 1.3)?.metadata?.pointSize, 16.5, "16.9 floored to a half point")
    }

    func testTextStylesUseTheirMacSizeAndWeight() {
        XCTAssertEqual(ResolvedNodePainter.scaledFont(nil, by: 2)?.metadata?.pointSize, 26, "body is 13 pt")
        let headline = ResolvedNodePainter.scaledFont(.headline, by: 1)
        XCTAssertEqual(headline?.metadata?.pointSize, 13); XCTAssertEqual(headline?.metadata?.weight, .bold)
    }

    func testTheMeasurerTableBoundsAndTabularFigures() {
        XCTAssertEqual(ResolvedNodePainter.scaledFont(.system(size: 13), by: 0.3)?.metadata?.pointSize, 9)
        XCTAssertEqual(ResolvedNodePainter.scaledFont(.system(size: 30), by: 2)?.metadata?.pointSize, 40)
        XCTAssertEqual(ResolvedNodePainter.scaledFont(.system(size: 13).monospacedDigit(), by: 1.5)?.metadata?.monospacedDigit, true)
        XCTAssertNil(ResolvedNodePainter.scaledFont(.custom("Brand", size: 13), by: 1.5), "custom fonts keep the counted fallback")
    }

    func testWithoutAShapingMeasurerScaledTextFallsBackCentredAndCounted() throws {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(Text("Hi").frame(width: 40, height: 20).scaleEffect(2), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { _ in })
        XCTAssertEqual(painter.scaleTextLimitationCount, 1)
    }
}
