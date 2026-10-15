import XCTest
@testable import SwiftRightHost

final class RetainedRunTests: XCTestCase {
    private func e(_ w: Float, _ h: Float, proposed: CGFloat? = nil, base: Float = 40) -> RetainedRunChoice.Entry {
        RetainedRunChoice.Entry(proposedWidth: proposed, width: w, height: h, lines: 1, firstBaseline: base)
    }
    func testSnappedExtentsMatchFloorOrCeilOfTheMeasuredExtent() {
        XCTAssertTrue(snappedExtentCanMatch(17.4, 17, scale: 1)); XCTAssertTrue(snappedExtentCanMatch(17.4, 18, scale: 1))
        XCTAssertFalse(snappedExtentCanMatch(17.4, 19, scale: 1)); XCTAssertFalse(snappedExtentCanMatch(17.4, 17.5, scale: 1))
        XCTAssertFalse(snappedExtentCanMatch(.nan, 17)); XCTAssertFalse(snappedExtentCanMatch(17, 17, origin: 0.5))
    }
    func testChoosesTheMatchingMeasurementAndRefusesTheAmbiguousOrMissing() throws {
        let chosen = try RetainedRunChoice.choose([e(100.2, 20), e(50, 20)], bounds: Rect(x: 0, y: 0, w: 101, h: 20), scale: 1, text: "t")
        XCTAssertEqual(chosen.width, 100.2)
        // a measurement within one pixel of the bounds on each axis is a half-pixel tie, not a mismatch (round 5)
        XCTAssertEqual(try RetainedRunChoice.choose([e(100.2, 40)], bounds: Rect(x: 0, y: 0, w: 101, h: 39), scale: 1, text: "t").height, 40)
        XCTAssertEqual(try RetainedRunChoice.choose([e(100.2, 40, proposed: 10), e(60, 40, proposed: 20)], bounds: Rect(x: 0, y: 0, w: 100, h: 39), scale: 1, text: "t").width, 100.2, "the closest run")
        XCTAssertThrowsError(try RetainedRunChoice.choose([e(100.2, 42)], bounds: Rect(x: 0, y: 0, w: 101, h: 39), scale: 1, text: "t"))
        XCTAssertThrowsError(try RetainedRunChoice.choose([e(10, 20)], bounds: Rect(x: 0, y: 0, w: 101, h: 20), scale: 1, text: "t")) {
            XCTAssertEqual($0 as? HostPaintError, .measuredRunGeometryMismatch("t")) }
        XCTAssertThrowsError(try RetainedRunChoice.choose([e(100.2, 20, base: 40), e(100.6, 20, base: 41)], bounds: Rect(x: 0, y: 0, w: 101, h: 20), scale: 1, text: "t")) {
            XCTAssertEqual($0 as? HostPaintError, .ambiguousMeasuredRun("t")) }
        // Equal candidates (same text measured at two proposals) are one run.
        XCTAssertNoThrow(try RetainedRunChoice.choose([e(100, 20, proposed: 50), e(100, 20, proposed: nil)], bounds: Rect(x: 0, y: 0, w: 100, h: 20), scale: 1, text: "t"))
    }

    // Decision L1: a Text never reports more width than it was offered; the shaped run keeps its own extent and the lookup compares the reported one.
    func testAReportedWidthIsNeverMoreThanTheOffer() {
        XCTAssertEqual(TextReportedWidth.clamp(267.5, proposedDIP: 0, scale: 2.5), 0, "offered 0: 0, whatever the renderer shaped")
        XCTAssertEqual(TextReportedWidth.clamp(27.5, proposedDIP: 5, scale: 2.5), 12.5, "an ellipsis wider than the offer reports the offer")
        XCTAssertEqual(TextReportedWidth.clamp(100, proposedDIP: 80, scale: 2.5), 100, "narrower than the offer: unchanged")
        XCTAssertEqual(TextReportedWidth.clamp(267.5, proposedDIP: nil, scale: 2.5), 267.5, "unbounded: unchanged")
        XCTAssertEqual(TextReportedWidth.clamp(267.5, proposedDIP: .infinity, scale: 2.5), 267.5)
        XCTAssertEqual(TextReportedWidth.clamp(267.5, proposedDIP: -3, scale: 2.5), 0, "a negative offer is no room")
    }
    func testAZeroWidthRunIsChosenByItsReportedWidth() throws {
        // the runtime laid the Text out 0 wide (offered 0); the entry carries the clamped width, so the snapped bounds (0) match it and the full-width run is painted
        let reported = TextReportedWidth.clamp(267.5, proposedDIP: 0, scale: 2.5)
        let chosen = try RetainedRunChoice.choose([e(reported, 40, proposed: 0), e(267.5, 40, proposed: nil)], bounds: Rect(x: 0, y: 0, w: 0, h: 40), scale: 2.5, text: "t")
        XCTAssertEqual(chosen.proposedWidth, 0)
    }
}
