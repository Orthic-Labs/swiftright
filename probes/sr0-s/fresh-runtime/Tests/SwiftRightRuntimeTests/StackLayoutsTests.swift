import SwiftRightRuntime
import XCTest

@MainActor
final class StackLayoutsTests: XCTestCase {
    private func frames<V: View>(_ v: V) -> [[CGFloat]] {
        let g = Graph(ZStack { v }, scale: 1); g.flush()
        return everyNode(g.snapshot()).filter { $0.kind == "Color" }.map { [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height] }
    }
    private func row() -> some View { Group { Color.red.frame(width: 30, height: 10); Color.blue.frame(width: 20, height: 24) } }

    func testHStackLayoutIsAnHStack() {
        XCTAssertEqual(frames(HStackLayout(spacing: 6) { row() }), frames(HStack(spacing: 6) { row() }))
        XCTAssertEqual(frames(VStackLayout(alignment: .leading) { row() }), frames(VStack(alignment: .leading) { row() }))
    }

    func testAnyLayoutBuildsTheWrappedLayout() {
        let h = AnyLayout(HStackLayout()), v = AnyLayout(VStackLayout())
        XCTAssertEqual(frames(h { row() }), frames(HStack { row() }))
        XCTAssertEqual(frames(v { row() }), frames(VStack { row() }))
        XCTAssertNotEqual(frames(h { row() }), frames(v { row() }))
    }

    func testLazyHStackLaysOutLikeHStack() {
        XCTAssertEqual(frames(LazyHStack(spacing: 4) { row() }), frames(HStack(spacing: 4) { row() }))
    }
}
