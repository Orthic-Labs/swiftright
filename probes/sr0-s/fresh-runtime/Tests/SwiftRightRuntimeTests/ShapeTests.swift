import Foundation
import SwiftRightRuntime
import XCTest

@MainActor
final class ShapeTests: XCTestCase {
    func testRoundedRectangleDefaultMatchesSDKContinuousStyle() {
        let graph = Graph(RoundedRectangle(cornerRadius: 6))
        graph.flush()
        XCTAssertEqual(graph.snapshot()?.shape?.geometry, .roundedRectangle(cornerRadius: 6, style: .continuous))
        XCTAssertEqual(RoundedRectangle(cornerRadius: 6, style: .circular).shapeGeometry,
                       .roundedRectangle(cornerRadius: 6, style: .circular))
    }

    func testRoundedRectangleStrokeRecordsGeometryAndLineWidth() {
        let graph = Graph(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.blue, lineWidth: 2.5))
        graph.rootProposal = ProposedViewSize(width: 32, height: 24)
        graph.flush()

        let node = graph.snapshot()
        XCTAssertEqual(node?.kind, "RoundedRectangle")
        XCTAssertEqual(node?.frame, LayoutRect(x: 0, y: 0, width: 32, height: 24))
        XCTAssertEqual(node?.shape?.geometry, .roundedRectangle(cornerRadius: 6, style: .continuous))
        XCTAssertEqual(node?.shape?.paint?.kind, .stroke)
        XCTAssertEqual(node?.shape?.paint?.color, Color.blue.resolvedColor)
        XCTAssertEqual(node?.shape?.paint?.lineWidth, 2.5)
    }

    func testCircleFillRecordsShapeIdentityAndBounds() {
        let graph = Graph(Circle().fill(Color.green))
        graph.rootProposal = ProposedViewSize(width: 18, height: 18)
        graph.flush()

        let node = graph.snapshot()
        XCTAssertEqual(node?.kind, "Circle")
        XCTAssertEqual(node?.frame, LayoutRect(x: 0, y: 0, width: 18, height: 18))
        XCTAssertEqual(node?.shape?.geometry, .circle)
        XCTAssertEqual(node?.shape?.paint?.kind, .fill)
        XCTAssertEqual(node?.shape?.paint?.color, Color.green.resolvedColor)
    }

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
