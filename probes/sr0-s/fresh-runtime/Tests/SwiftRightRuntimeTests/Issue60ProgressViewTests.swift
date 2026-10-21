import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: ProgressView (determinate bar, indeterminate ring, label).

@MainActor
final class Issue60ProgressViewTests: XCTestCase {
    func testFractionClampsAndRejectsDegenerateInput() {
        typealias P = ProgressView<EmptyView, EmptyView>
        XCTAssertEqual(P.fractionOf(value: Double(0.25), total: 1), 0.25)
        XCTAssertEqual(P.fractionOf(value: Double(2), total: 1), 1)
        XCTAssertEqual(P.fractionOf(value: Double(-1), total: 1), 0)
        XCTAssertEqual(P.fractionOf(value: Double(5), total: 10), 0.5)
        XCTAssertNil(P.fractionOf(value: nil as Double?, total: 1))
        XCTAssertNil(P.fractionOf(value: Double(1), total: 0))
        XCTAssertEqual(P.fractionOf(value: Double.nan, total: 1), 0)
    }

    func testDeterminateBarIsSixPointsTallAndFillsTheFraction() throws {
        let graph = i60Graph(ProgressView(value: 0.25).frame(width: 100), width: 300, height: 200)
        let capsules = i60Nodes(graph, kind: "Capsule")
        XCTAssertEqual(capsules.count, 2, "track, fill")
        let track = capsules[0], fill = capsules[1]
        XCTAssertEqual(track.frame.width, 100); XCTAssertEqual(track.frame.height, 6)
        XCTAssertEqual(fill.frame.width, 25); XCTAssertEqual(fill.frame.height, 6)
        XCTAssertEqual(fill.frame.minX, track.frame.minX, "the fill starts at the leading edge")
        XCTAssertEqual(fill.frame.minY, track.frame.minY)
        XCTAssertEqual(fill.shape?.paint?.color, .semantic("accentColor"), "the tint, which is the accent colour unless .tint(_:) set one")
    }

    func testValueBeyondTotalFillsTheTrackAndTotalScalesTheFraction() {
        let full = i60Graph(ProgressView(value: 5.0, total: 4.0).frame(width: 80))
        XCTAssertEqual(i60Nodes(full, kind: "Capsule")[1].frame.width, 80)
        let half = i60Graph(ProgressView(value: 5.0, total: 10.0).frame(width: 80))
        XCTAssertEqual(i60Nodes(half, kind: "Capsule")[1].frame.width, 40)
    }

    func testLabelSitsAboveTheBarLeadingAligned() throws {
        let graph = i60Graph(ProgressView("Loading", value: 0.5, total: 1).frame(width: 120))
        let label = try XCTUnwrap(i60Text(graph, "Loading"))
        let track = try XCTUnwrap(i60Nodes(graph, kind: "Capsule").first)
        XCTAssertEqual(label.frame.minX, track.frame.minX)
        XCTAssertEqual(Double(track.frame.minY), Double(label.frame.minY) + Double(label.frame.height) + 4, accuracy: 0.5)
    }

    func testIndeterminateIsASixteenPointRing() throws {
        let graph = i60Graph(ProgressView())
        let ring = try XCTUnwrap(i60Nodes(graph, kind: "Circle").first)
        XCTAssertEqual(ring.frame.width, 16); XCTAssertEqual(ring.frame.height, 16)
        XCTAssertEqual(ring.shape?.geometry, .trimmed(.circle, from: 0, to: 0.75))
        XCTAssertEqual(ring.shape?.paint?.kind, .stroke)
        XCTAssertEqual(i60Nodes(graph, kind: "Capsule").count, 0)
    }

    func testNilValueAndLabelledSpinnerStackLabelBelowTheRing() throws {
        let nilValue = i60Graph(ProgressView(value: nil as Double?))
        XCTAssertEqual(i60Nodes(nilValue, kind: "Circle").count, 1)
        let graph = i60Graph(ProgressView("Please wait"))
        let ring = try XCTUnwrap(i60Nodes(graph, kind: "Circle").first)
        let label = try XCTUnwrap(i60Text(graph, "Please wait"))
        XCTAssertEqual(Double(label.frame.minY), Double(ring.frame.minY) + 16 + 8, accuracy: 0.5)
    }

    func testViewBuilderLabelForms() {
        let determinate = i60Graph(ProgressView(value: 0.5) { Text("Upload") }.frame(width: 100))
        XCTAssertNotNil(i60Text(determinate, "Upload"))
        XCTAssertEqual(i60Nodes(determinate, kind: "Capsule").count, 2)
        let spinner = i60Graph(ProgressView { Text("Working") })
        XCTAssertNotNil(i60Text(spinner, "Working"))
        XCTAssertEqual(i60Nodes(spinner, kind: "Circle").count, 1)
    }
}
