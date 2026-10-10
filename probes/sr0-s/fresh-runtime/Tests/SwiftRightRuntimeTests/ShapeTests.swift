import Foundation
import SwiftRightRuntime
import XCTest

@MainActor
final class ShapeTests: XCTestCase {
    func testRectangleFillRecordsProposedBoundsAndResolvedPaint() {
        let graph = Graph(Rectangle().fill(Color.red))
        graph.rootProposal = ProposedViewSize(width: 40, height: 20)
        graph.flush()

        let node = graph.snapshot()
        XCTAssertEqual(node?.kind, "Rectangle")
        XCTAssertEqual(node?.frame, LayoutRect(x: 0, y: 0, width: 40, height: 20))
        XCTAssertEqual(node?.shape?.geometry, .rectangle)
        XCTAssertEqual(node?.shape?.paint?.kind, .fill)
        XCTAssertEqual(node?.shape?.paint?.color, Color.red.resolvedColor)
        XCTAssertNil(node?.shape?.paint?.lineWidth)
    }
}
