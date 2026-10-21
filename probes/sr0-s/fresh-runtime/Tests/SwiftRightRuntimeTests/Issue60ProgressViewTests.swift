import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: ProgressView (determinate bar, indeterminate stepped spinner, label).

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

    func testDeterminateBarIsEightPointsTallAndFillsTheFractionLessTwoPixels() throws {
        let graph = i60Graph(ProgressView(value: 0.25).frame(width: 100), width: 300, height: 200)
        let capsules = i60Nodes(graph, kind: "Capsule")
        XCTAssertEqual(capsules.count, 4, "track edge, track ring, track body, fill")
        let track = capsules[0], fill = capsules[3]
        XCTAssertEqual(track.frame.width, 100); XCTAssertEqual(track.frame.height, 8)
        XCTAssertEqual(Double(fill.frame.width), 25 - 0.8, accuracy: 0.5, "0.8 pt (2 px at scale 2.5) shorter than the fraction")
        XCTAssertEqual(fill.frame.height, 8)
        let greys = capsules[0..<3].compactMap { node -> Double? in
            if case .rgba(let r, _, _, 1)? = node.shape?.paint?.color { return r }
            return nil
        }
        XCTAssertEqual(greys.count, 3, "opaque greys: translucent layers would accumulate")
        XCTAssertEqual(greys[0], 223.0 / 255.0, accuracy: 1e-9); XCTAssertEqual(greys[2], 240.0 / 255.0, accuracy: 1e-9)
        XCTAssertEqual(fill.frame.minX, track.frame.minX, "the fill starts at the leading edge")
        XCTAssertEqual(fill.frame.minY, track.frame.minY)
        XCTAssertEqual(fill.shape?.paint?.color, .semantic("accentColor"), "the tint, which is the accent colour unless .tint(_:) set one")
    }

    func testValueBeyondTotalFillsTheTrackAndTotalScalesTheFraction() {
        let full = i60Graph(ProgressView(value: 5.0, total: 4.0).frame(width: 80))
        XCTAssertEqual(Double(i60Nodes(full, kind: "Capsule")[3].frame.width), 80 - 0.8, accuracy: 0.5)
        let half = i60Graph(ProgressView(value: 5.0, total: 10.0).frame(width: 80))
        XCTAssertEqual(Double(i60Nodes(half, kind: "Capsule")[3].frame.width), 40 - 0.8, accuracy: 0.5)
    }

    func testLabelSitsAboveTheBarLeadingAligned() throws {
        let graph = i60Graph(ProgressView("Loading", value: 0.5, total: 1).frame(width: 120))
        let label = try XCTUnwrap(i60Text(graph, "Loading"))
        let track = try XCTUnwrap(i60Nodes(graph, kind: "Capsule").first)
        XCTAssertEqual(label.frame.minX, track.frame.minX)
        // the 8 pt bar is centred in its 19.6 pt view, 4 pt under the label
        XCTAssertEqual(Double(track.frame.minY), Double(label.frame.minY) + Double(label.frame.height) + 4 + (19.6 - 8) / 2, accuracy: 0.6)
    }

    /// The spinner's own rotation node: the outermost `.rotationEffect`-kind node (the tick rotations sit inside it).
    private func spinnerNode(_ graph: Graph) throws -> ResolvedNode {
        try XCTUnwrap(i60Nodes(graph, kind: "modifier.rotationEffect").first)
    }

    func testIndeterminateIsASixteenPointSpinnerOfTwelveTicks() throws {
        let graph = i60Graph(ProgressView())
        let spinner = try spinnerNode(graph)
        XCTAssertEqual(spinner.frame.width, 16); XCTAssertEqual(spinner.frame.height, 16)
        let ticks = i60Nodes(graph, kind: "Capsule")
        XCTAssertEqual(ticks.count, 12)
        // 1.5 x 4 pt ticks, snapped to the device-pixel grid of the test graph (scale 1: 1.5 pt rounds to 2).
        XCTAssertTrue(ticks.allSatisfy { abs($0.frame.width - 1.5) <= 0.5 && abs($0.frame.height - 4) <= 0.5 }, "\(ticks.map { $0.frame.size })")
        XCTAssertEqual(i60Nodes(graph, kind: "modifier.rotationEffect").count, 13, "the spinner and one rotation per tick")
        XCTAssertEqual(i60Nodes(graph, kind: "Circle").count, 0)
        let opacities = ticks.compactMap { node -> Double? in
            if case .semanticAlpha("label", let a)? = node.shape?.paint?.color { return a }
            return nil
        }
        XCTAssertEqual(opacities.first, 1)
        XCTAssertEqual(try XCTUnwrap(opacities.last), 0.15, accuracy: 1e-9)
        XCTAssertEqual(opacities, opacities.sorted(by: >), "the tail fades")
    }

    func testNilValueAndLabelledSpinnerStackLabelBelowTheSpinner() throws {
        let nilValue = i60Graph(ProgressView(value: nil as Double?))
        XCTAssertEqual(i60Nodes(nilValue, kind: "Capsule").count, 12)
        let graph = i60Graph(ProgressView("Please wait"))
        let spinner = try spinnerNode(graph)
        let label = try XCTUnwrap(i60Text(graph, "Please wait"))
        XCTAssertEqual(Double(label.frame.minY), Double(spinner.frame.minY) + 16 + 8, accuracy: 0.5)
    }

    func testSpinnerTurnsInThirtyDegreeStepsByTheHostClock() throws {
        let graph = i60Graph(ProgressView())
        func degrees() throws -> Double { try XCTUnwrap(spinnerNode(graph).rotation).angle.degrees }
        XCTAssertEqual(try degrees(), 0, "before the first tick")
        graph.tick(now: 5.0)
        XCTAssertEqual(try degrees(), 0, accuracy: 1e-9, "clock 5.0 s is a whole number of turns")
        graph.tick(now: 5.5)
        XCTAssertEqual(try degrees(), 180, accuracy: 1e-9)
        graph.tick(now: 5.99)
        XCTAssertEqual(try degrees(), 330, accuracy: 1e-9)
        graph.tick(now: 6.0)
        XCTAssertEqual(try degrees(), 0, accuracy: 1e-9)
        graph.tick(now: 6.1)
        XCTAssertEqual(try degrees(), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(spinnerNode(graph).rotation).anchor, .center)
    }

    func testTickCommitsOnlyWhenTheSpinnerStepChanges() {
        let graph = i60Graph(ProgressView())
        var records = 0
        graph.commitSink = { _ in records += 1 }
        graph.tick(now: 1.01)   // the first tick: the spinner has not been shown at a step yet
        let first = records
        XCTAssertEqual(first, 1)
        graph.tick(now: 1.02)
        graph.tick(now: 1.05)
        XCTAssertEqual(records, first, "same step (a step is 1/12 s): no commit")
        graph.tick(now: 1.09)
        XCTAssertEqual(records, first + 1)
        graph.tick(now: 1.10)
        XCTAssertEqual(records, first + 1)
        graph.tick(now: 1.17)
        XCTAssertEqual(records, first + 2)
    }

    func testAGraphWithoutASpinnerCommitsNothingOnTicks() {
        let graph = i60Graph(Text("no spinner"))
        var records = 0
        graph.commitSink = { _ in records += 1 }
        graph.tick(now: 1)
        graph.tick(now: 2)
        XCTAssertEqual(records, 0)
    }

    func testViewBuilderLabelForms() {
        let determinate = i60Graph(ProgressView(value: 0.5) { Text("Upload") }.frame(width: 100))
        XCTAssertNotNil(i60Text(determinate, "Upload"))
        XCTAssertEqual(i60Nodes(determinate, kind: "Capsule").count, 4)
        let spinner = i60Graph(ProgressView { Text("Working") })
        XCTAssertNotNil(i60Text(spinner, "Working"))
        XCTAssertEqual(i60Nodes(spinner, kind: "Capsule").count, 12)
    }
}
