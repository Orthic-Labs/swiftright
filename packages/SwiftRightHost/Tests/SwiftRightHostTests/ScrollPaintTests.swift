import XCTest
import SwiftRightHost

/// ScrollView through the product paint path: the viewport clips every descendant primitive, content below the viewport is reachable by offset.
@MainActor
final class ScrollPaintTests: XCTestCase {
    private func commit<V: View>(_ view: V, proposal: (CGFloat, CGFloat), scale: CGFloat = 2.5, scrolledTo: CGFloat? = nil) throws -> [NodeUpsert] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: Float(scale), log: { _ in })
        let graph = Graph(view, scale: scale)
        graph.rootProposal = ProposedViewSize(width: proposal.0, height: proposal.1)
        graph.flush()
        if let scrolledTo {
            let id = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "ScrollView" }).id
            graph.scroll(id, to: scrolledTo); graph.flush()
        }
        var sent: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: []) { sent = $0.upserts }
        return sent
    }

    private func rects(_ n: NodeUpsert) -> [Rect] { n.primitives.compactMap { if case .rect(let r, _, _, _, _) = $0 { return r } else { return nil } } }

    private var tall: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.red).frame(height: 40)
                Rectangle().fill(Color.green).frame(height: 40)
                Rectangle().fill(Color.purple).frame(height: 40)
            }
        }.frame(width: 120, height: 100)
    }

    func testEveryDescendantPrimitiveIsClippedToTheViewport() throws {
        let nodes = try commit(tall, proposal: (320, 240))
        let viewport = try XCTUnwrap(nodes.first { $0.semantic == nil && $0.bounds.w == 300 && $0.bounds.h == 250 })
        let painted = nodes.filter { !rects($0).isEmpty }
        XCTAssertEqual(painted.count, 3)
        for n in painted {
            guard case .clipPush(let clip) = try XCTUnwrap(n.primitives.first), case .clipPop = try XCTUnwrap(n.primitives.last) else { return XCTFail("not wrapped in a clip") }
            XCTAssertEqual(clip, viewport.bounds)
        }
    }

    func testContentBelowTheViewportStillExistsAndScrollingMovesIt() throws {
        let at0 = try commit(tall, proposal: (320, 240))
        let at30 = try commit(tall, proposal: (320, 240), scrolledTo: 20)
        let ys = { (nodes: [NodeUpsert]) in nodes.flatMap(self.rects).map(\.y).sorted() }
        XCTAssertEqual(ys(at0).count, 3)
        XCTAssertEqual(zip(ys(at0), ys(at30)).map { $0 - $1 }, [50, 50, 50])        // 20 pt * 2.5 (content 120 pt, viewport 100 pt)
        let past = try commit(tall, proposal: (320, 240), scrolledTo: 500)
        XCTAssertEqual(ys(past), ys(at30))                                             // clamped to the content
    }

    /// The same overflowing ScrollView with its default indicators: the legacy scroller is shown.
    private var tallWithScroller: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.red).frame(height: 40)
                Rectangle().fill(Color.green).frame(height: 40)
                Rectangle().fill(Color.purple).frame(height: 40)
            }
        }.frame(width: 120, height: 100)
    }

    func testVerticalScrollerPaintsAboveTheContentAtTheTrailingEdge() throws {
        let nodes = try commit(tallWithScroller, proposal: (320, 240))
        let scroller = try XCTUnwrap(nodes.first { $0.id & (UInt64(1) << 62) != 0 })   // the scroller is its own node, id | flag
        let siblings = nodes.filter { $0.parent == scroller.parent && $0.id != scroller.id }
        XCTAssertFalse(siblings.isEmpty)                                   // the ScrollView's content
        XCTAssertTrue(siblings.allSatisfy { $0.order < scroller.order })   // drawn after the content
        XCTAssertEqual(scroller.bounds.x, 253, accuracy: 1)                // 19 pt strip at the trailing edge of the 300 px viewport
        let thumb = try XCTUnwrap(scroller.primitives.compactMap { p -> Rect? in
            if case .rect(let r, _, let radius, _, _) = p, radius > 0 { return r } else { return nil }
        }.first)
        XCTAssertEqual(thumb.x, 263, accuracy: 1)
        XCTAssertEqual(thumb.y, 7.5, accuracy: 1)                          // value 0: the 3.0 pt top inset (M1)
        guard case .clipPush = try XCTUnwrap(scroller.primitives.first), case .clipPop = try XCTUnwrap(scroller.primitives.last) else {
            return XCTFail("scroller is not clipped to its container")
        }
    }

    func testScrollerRectAndThumbRectAreReadBackAfterCommit() throws {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, log: { _ in })
        let graph = Graph(tallWithScroller, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let root = try XCTUnwrap(graph.snapshot())
        _ = try painter.commit(root: root, version: 1, previousLive: []) { _ in }
        let view = try XCTUnwrap(flatten(root).first { $0.kind == "ScrollView" })
        let strip = try XCTUnwrap(painter.scrollerRect(for: view))
        let thumb = try XCTUnwrap(painter.thumbRect(for: view))
        XCTAssertEqual(strip.maxX, 300, accuracy: 0.001)
        XCTAssertGreaterThan(thumb.height, 0)
        XCTAssertNil(painter.scrollerRect(for: try XCTUnwrap(flatten(root).first { $0.kind == "VStack" })))
    }

    func testSemanticSystemColoursPaint() throws {
        for (color, rgba) in [(Color.orange, UInt32(0xff8d28ff)), (Color.green, 0x34c759ff), (Color.purple, 0xcb30e0ff)] {
            let nodes = try commit(Rectangle().fill(color).frame(width: 10, height: 10), proposal: (50, 50))
            let painted = try XCTUnwrap(nodes.first { !rects($0).isEmpty })
            guard case .rect(_, let c, _, _, _) = painted.primitives[0] else { return XCTFail() }
            XCTAssertEqual(c, rgba)
        }
    }

    func testNestedScrollViewsIntersectTheirClips() {
        XCTAssertEqual(ResolvedNodePainter.intersection(Rect(x: 0, y: 0, w: 100, h: 100), Rect(x: 50, y: 50, w: 100, h: 100)), Rect(x: 50, y: 50, w: 50, h: 50))
        XCTAssertEqual(ResolvedNodePainter.intersection(Rect(x: 0, y: 0, w: 10, h: 10), Rect(x: 20, y: 20, w: 10, h: 10)).w, 0)
    }

    private struct Composite: View {
        @State private var shown = true
        var body: some View { VStack(spacing: 0) { Rectangle().fill(Color.blue).frame(width: 10, height: 10) } }
    }

    func testUserDefinedCompositeViewsPaintThroughTheirChildren() throws {
        let nodes = try commit(Composite(), proposal: (50, 50))
        XCTAssertEqual(nodes.filter { !rects($0).isEmpty }.count, 1)
    }
}
