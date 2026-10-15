import Foundation
import SwiftRightRuntime
import XCTest

struct ZStackProbe: View {
    let alignment: Alignment
    var body: some View {
        ZStack(alignment: alignment) {
            Text("long")
            Text("x")
        }
    }
}

@MainActor
final class StackAdditionTests: XCTestCase {
    func testZStackMeasuresLargestChildPlacesByAlignmentAndKeepsOrder() throws {
        let graph = Graph(ZStackProbe(alignment: .bottomTrailing), measurer: FixedAdvanceTextMeasurer())
        graph.flush()
        let stack = try XCTUnwrap(graph.snapshot()).children[0]
        XCTAssertEqual(stack.kind, "ZStack")
        XCTAssertEqual(stack.frame.size, LayoutSize(width: 32, height: 16))
        XCTAssertEqual(stack.children.map(\.text), ["long", "x"])
        XCTAssertEqual(stack.children.map(\.frame.origin), [LayoutPoint(x: 0, y: 0), LayoutPoint(x: 24, y: 0)])
    }
}

struct OverlayProbe: View {
    var body: some View {
        Text("base").overlay(alignment: .bottomTrailing) { Text("longlong") }
    }
}

extension StackAdditionTests {
    func testOverlayKeepsBaseMeasurementPlacesAboveBaseAndPreservesOrder() throws {
        let graph = Graph(OverlayProbe(), measurer: FixedAdvanceTextMeasurer())
        graph.flush()
        let overlay = try XCTUnwrap(graph.snapshot()).children[0]
        XCTAssertEqual(overlay.kind, "Overlay")
        XCTAssertEqual(overlay.frame.size, LayoutSize(width: 32, height: 16))
        XCTAssertEqual(overlay.children.map(\.text), ["base", "longlong"])
        XCTAssertEqual(overlay.children[0].frame, LayoutRect(x: 0, y: 0, width: 32, height: 16))
        // decision L1: a Text reports at most the width it is offered, so the unbreakable word is 32 wide (the base's width), not 64 overflowing to the left
        XCTAssertEqual(overlay.children[1].frame, LayoutRect(x: 0, y: 0, width: 32, height: 16))
    }
}
