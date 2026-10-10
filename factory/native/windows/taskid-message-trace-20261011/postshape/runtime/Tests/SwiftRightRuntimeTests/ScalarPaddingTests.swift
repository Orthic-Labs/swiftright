import SwiftRightRuntime
import XCTest

struct ScalarPaddingProbe: View {
    var body: some View { Text("ab").padding(10) }
}

@MainActor
final class ScalarPaddingTests: XCTestCase {
    func testScalarPaddingInsetsEveryEdge() throws {
        let graph = Graph(ScalarPaddingProbe(), measurer: FixedAdvanceTextMeasurer())
        graph.flush()
        let padding = try XCTUnwrap(graph.snapshot()).children[0]
        XCTAssertEqual(padding.kind, "modifier.padding")
        XCTAssertEqual(padding.frame, LayoutRect(x: 0, y: 0, width: 36, height: 36))
        XCTAssertEqual(padding.children[0].frame, LayoutRect(x: 10, y: 10, width: 16, height: 16))
    }
}
