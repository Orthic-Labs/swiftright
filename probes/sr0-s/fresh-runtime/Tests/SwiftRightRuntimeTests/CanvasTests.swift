import SwiftRightRuntime
import XCTest

@MainActor
final class CanvasTests: XCTestCase {
    func testCanvasDrawsRecordedPathsInItsOwnSize() throws {
        let graph = Graph(Canvas { context, size in
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)), with: .color(.red))
            context.translateBy(x: 10, y: 10)
            context.stroke(Path(CGRect(x: 0, y: 0, width: 20, height: 20)), with: .color(.blue), lineWidth: 2)
        }.frame(width: 100, height: 60), scale: 1)
        graph.flush()
        let nodes = everyNode(graph.snapshot())
        let canvas = try XCTUnwrap(nodes.first { $0.frame.width == 100 && $0.frame.height == 60 })
        XCTAssertEqual(canvas.frame.width, 100)
        XCTAssertGreaterThanOrEqual(nodes.filter { $0.kind.lowercased().contains("path") || $0.kind.lowercased().contains("shape") }.count, 2, nodes.map(\.kind).joined(separator: ","))
    }
}
