import XCTest
@testable import SwiftRightRuntime

@MainActor
final class ScrollAnchorTests: XCTestCase {
    private func rows<V: View>(_ view: V) -> (graph: Graph, scroll: String, ys: [CGFloat]) {
        let graph = Graph(view, scale: 2)
        graph.rootProposal = ProposedViewSize(width: 200, height: 200)
        graph.flush()
        var nodes: [ResolvedNode] = []
        func walk(_ n: ResolvedNode) { nodes.append(n); n.children.forEach(walk) }
        walk(graph.snapshot()!)
        return (graph, nodes.first { $0.kind == "ScrollView" }!.id, nodes.filter { $0.kind == "Rectangle" }.map(\.frame.minY))
    }

    private func content(_ axes: Axis.Set = .vertical) -> some View {
        ScrollView(axes, showsIndicators: false) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.red).frame(width: 50, height: 24)
                Rectangle().fill(Color.blue).frame(width: 50, height: 24)
                Rectangle().fill(Color.green).frame(width: 50, height: 24)
                Rectangle().fill(Color.orange).frame(width: 50, height: 24)
                Rectangle().fill(Color.purple).frame(width: 50, height: 24)
            }
        }.frame(width: 50, height: 100)
    }

    func testWithoutAnAnchorTheContentStartsAtTheTop() {
        XCTAssertEqual(rows(content()).ys.first, 0)
    }

    func testBottomAnchorStartsAtTheEndOfTheContent() {
        let r = rows(content().defaultScrollAnchor(.bottom))
        XCTAssertEqual(r.graph.scrollOffset(r.scroll), 20)      // content 120, viewport 100
        XCTAssertEqual(r.ys.first, -20)
    }

    func testCenterAnchorStartsHalfWay() {
        XCTAssertEqual(rows(content().defaultScrollAnchor(.center)).ys.first, -10)
    }

    func testTopAnchorAndShortContentStayAtOffsetZero() {
        XCTAssertEqual(rows(content().defaultScrollAnchor(.top)).ys.first, 0)
        let short = ScrollView(.vertical, showsIndicators: false) { Rectangle().fill(Color.red).frame(width: 10, height: 20) }.frame(width: 50, height: 100).defaultScrollAnchor(.bottom)
        XCTAssertEqual(rows(short).ys.first, 0)
    }

    func testProgrammaticScrollOverridesTheAnchor() {
        let r = rows(content().defaultScrollAnchor(.bottom))
        r.graph.scroll(r.scroll, to: 5); r.graph.flush()
        XCTAssertEqual(r.graph.scrollOffset(r.scroll), 5)
    }

    func testAnchorAppliesToTheScrollingAxisOnly() {
        let r = rows(content(.horizontal).defaultScrollAnchor(.bottomTrailing))
        XCTAssertEqual(r.graph.scrollOffsets(r.scroll)?.y, 0)
    }
}
