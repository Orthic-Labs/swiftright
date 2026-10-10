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
