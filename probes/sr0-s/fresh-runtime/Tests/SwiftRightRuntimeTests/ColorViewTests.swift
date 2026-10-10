import SwiftRightRuntime
import XCTest

struct ColorViewProbe: View {
    var body: some View { Color.red.frame(width: 50, height: 20) }
}

@MainActor
final class ColorViewTests: XCTestCase {
    func testColorIsFlexibleViewWithResolvedColor() throws {
        let graph = Graph(ColorViewProbe())
        graph.flush()
        let frame = try XCTUnwrap(graph.snapshot()).children[0]
        let color = try XCTUnwrap(frame.children.first)
        XCTAssertEqual(frame.frame.size, LayoutSize(width: 50, height: 20))
        XCTAssertEqual(color.kind, "Color")
        XCTAssertEqual(color.frame, LayoutRect(x: 0, y: 0, width: 50, height: 20))
        XCTAssertEqual(color.color, .semantic("system.red"))
    }
}
