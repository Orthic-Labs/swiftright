import SwiftRightRuntime
import XCTest

@MainActor
final class ScrollViewReaderTests: XCTestCase {
    private var proxy: ScrollViewProxy?

    private func make() -> Graph {
        let g = Graph(ScrollViewReader { p in
            ScrollView {
                VStack(spacing: 0) { ForEach(0..<20, id: \.self) { i in Color.red.frame(height: 30).id(i) } }
            }.frame(width: 80, height: 100).onAppear { self.proxy = p }
        }, scale: 1)
        g.flush()
        return g
    }

    private func offset(_ g: Graph) -> CGFloat { CGFloat(everyNode(g.snapshot()).compactMap { $0.scroll?.offsetY }.first ?? -1) }

    func testScrollToWithTopAnchorPutsTheRowAtTheTop() throws {
        let g = make()
        XCTAssertEqual(offset(g), 0)
        try XCTUnwrap(proxy).scrollTo(10, anchor: .top)
        g.flush()
        XCTAssertEqual(offset(g), 300, accuracy: 0.5)
    }

    func testScrollToWithoutAnchorMovesJustEnough() throws {
        let g = make()
        try XCTUnwrap(proxy).scrollTo(5)   // row 5 spans 150..180; the viewport shows 0..100 -> offset 80
        g.flush()
        XCTAssertEqual(offset(g), 80, accuracy: 0.5)
    }

    func testBottomAnchorClampsAtTheEnd() throws {
        let g = make()
        try XCTUnwrap(proxy).scrollTo(19, anchor: .bottom)
        g.flush()
        XCTAssertEqual(offset(g), 500, accuracy: 0.5)   // content 600, viewport 100
    }
}
