import SwiftRightRuntime
import XCTest

/// Ten 24 pt text rows in a 200 x 100 inset List: the document is 10 + 240 + 10 = 260 pt, so the maximum offset is 160 pt.
private struct TenTaggedRows: View {
    var body: some View {
        List { ForEach(0..<10, id: \.self) { i in Text("Row \(i)").tag(i) } }.frame(width: 200, height: 100)
    }
}

private struct TenRows: View {
    var body: some View {
        List { ForEach(0..<10, id: \.self) { i in Text("Row \(i)") } }.frame(width: 200, height: 100)
    }
}

/// Three rows: the document is 10 + 72 + 10 = 92 pt, which fits the 100 pt List (no scroller).
private struct ThreeRows: View {
    var body: some View {
        List { ForEach(0..<3, id: \.self) { i in Text("Row \(i)") } }.frame(width: 200, height: 100)
    }
}

/// A List that takes whole proposal (the root's), so the viewport follows the proposal.
private struct FreeRows: View {
    var body: some View {
        List { ForEach(0..<10, id: \.self) { i in Text("Row \(i)") } }
    }
}

/// Four 30 pt blocks in an 80 x 60 vertical ScrollView: content 120 pt, viewport 60 pt, maximum offset 60 pt.
private struct Blocks: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(width: 50, height: 30)
                Color.red.frame(width: 50, height: 30)
                Color.red.frame(width: 50, height: 30)
                Color.red.frame(width: 50, height: 30)
            }
        }.frame(width: 80, height: 60)
    }
}

private struct QuietBlocks: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Color.red.frame(width: 50, height: 30)
                Color.red.frame(width: 50, height: 30)
                Color.red.frame(width: 50, height: 30)
                Color.red.frame(width: 50, height: 30)
            }
        }.frame(width: 80, height: 60)
    }
}

@MainActor
final class ScrollStateTests: XCTestCase {
    private func resolved(_ view: some View, width: CGFloat = 200, height: CGFloat = 100) -> (Graph, ResolvedNode) {
        let graph = Graph(view)
        graph.rootProposal = ProposedViewSize(width: width, height: height)
        graph.flush()
        return (graph, graph.snapshot()!)
    }

    private func list(_ root: ResolvedNode) -> ResolvedNode {
        everyNode(root).first { $0.kind == "List" }!
    }

    /// The middle of row `i` relative to the List's top edge (22 + 24 i at offset 0).
    private func rowMid(_ root: ResolvedNode, _ i: Int) -> Double {
        let owner = list(root)
        let row = owner.children[i]
        return Double(row.frame.minY - owner.frame.minY) + Double(row.frame.height) / 2
    }

    private func listID(_ graph: Graph) -> String { graph.ids(ofKind: "List").first! }

    private func listScroll(_ graph: Graph) -> ScrollState? {
        graph.flush()
        return graph.snapshot().flatMap { everyNode($0).first { $0.kind == "List" }?.scroll }
    }

    // MARK: ScrollState and ResolvedNode.scroll

    func testListScrollStateFillsContentAndViewport() throws {
        let (_, root) = resolved(TenRows())
        let state = try XCTUnwrap(list(root).scroll)
        XCTAssertEqual(state.viewportHeight, 100, accuracy: 1e-9)
        XCTAssertEqual(state.contentHeight, 260, accuracy: 0.5)
        XCTAssertEqual(state.maxOffset, 160, accuracy: 0.5)
        XCTAssertEqual(state.offsetY, 0)
        XCTAssertEqual(state.value, 0)
        XCTAssertTrue(state.showsScroller)
    }

    func testFittingListHasNoScroller() throws {
        let (graph, root) = resolved(ThreeRows())
        let state = try XCTUnwrap(list(root).scroll)
        XCTAssertFalse(state.showsScroller)
        XCTAssertEqual(state.maxOffset, 0)
        XCTAssertFalse(graph.scrollWheel(atX: 100, y: 50, lines: 3))
    }

    func testScrollStateValueIsTheFractionOfMaxOffset() {
        let state = ScrollState(offsetY: 80, contentHeight: 260, viewportHeight: 100, showsScroller: true)
        XCTAssertEqual(state.maxOffset, 160)
        XCTAssertEqual(state.value, 0.5, accuracy: 1e-12)
        XCTAssertEqual(ScrollState(offsetY: 0, contentHeight: 50, viewportHeight: 100, showsScroller: false).value, 0)
    }

    func testScrollViewScrollStateAndIndicatorFlag() throws {
        let (_, root) = resolved(Blocks(), width: 80, height: 60)
        let shown = try XCTUnwrap(everyNode(root).first { $0.kind == "ScrollView" }?.scroll)
        XCTAssertEqual(shown.contentHeight, 120, accuracy: 1e-9)
        XCTAssertEqual(shown.viewportHeight, 60, accuracy: 1e-9)
        XCTAssertEqual(shown.maxOffset, 60, accuracy: 1e-9)
        XCTAssertTrue(shown.showsScroller)

        let (_, quiet) = resolved(QuietBlocks(), width: 80, height: 60)
        let hidden = try XCTUnwrap(everyNode(quiet).first { $0.kind == "ScrollView" }?.scroll)
        XCTAssertFalse(hidden.showsScroller)
        XCTAssertEqual(hidden.maxOffset, 60, accuracy: 1e-9)
    }

    func testNonScrollNodesHaveNoScrollState() {
        let (_, root) = resolved(Text("Plain"))
        XCTAssertNil(root.scroll)
        XCTAssertNil(everyNode(root).first { $0.kind == "Text" }?.scroll)
    }

    // MARK: Offset at zero keeps the existing layout

    func testListRowsAreUnshiftedAtOffsetZero() {
        let (_, root) = resolved(TenRows())
        for i in 0..<10 {
            XCTAssertEqual(rowMid(root, i), 22 + 24 * Double(i), accuracy: 0.5)
        }
    }

    // MARK: Wheel

    func testWheelLinesMoveTenPointsEach() {
        let (graph, _) = resolved(TenRows())
        XCTAssertTrue(graph.scrollWheel(atX: 100, y: 50, lines: 3))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 30, accuracy: 1e-9)
        XCTAssertEqual(rowMid(graph.snapshot()!, 0), -8, accuracy: 0.5)
        XCTAssertTrue(graph.scrollWheel(atX: 100, y: 50, lines: -1))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 20, accuracy: 1e-9)
    }

    func testWheelOutsideTheListDoesNothing() {
        let (graph, _) = resolved(TenRows())
        XCTAssertFalse(graph.scrollWheel(atX: 300, y: 50, lines: 3))
        XCTAssertFalse(graph.scrollWheel(atX: 50, y: 150, lines: 3))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 0, accuracy: 1e-9)
    }

    func testWheelClampsAtBothEnds() {
        let (graph, _) = resolved(TenRows())
        XCTAssertTrue(graph.scrollWheel(atX: 100, y: 50, lines: 100))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 160, accuracy: 1e-9)
        XCTAssertFalse(graph.scrollWheel(atX: 100, y: 50, lines: 1))
        XCTAssertTrue(graph.scrollWheel(atX: 100, y: 50, lines: -100))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 0, accuracy: 1e-9)
        XCTAssertFalse(graph.scrollWheel(atX: 100, y: 50, lines: -1))
    }

    func testWheelOnAScrollViewUsesItsOwnOffset() {
        let (graph, _) = resolved(Blocks(), width: 80, height: 60)
        XCTAssertTrue(graph.scrollWheel(atX: 10, y: 10, lines: 1))
        XCTAssertEqual(graph.scrollOffset(graph.ids(ofKind: "ScrollView").first!) ?? -1, 10, accuracy: 1e-9)
    }

    func testHiddenIndicatorScrollViewStillScrolls() {
        let (graph, root) = resolved(QuietBlocks(), width: 80, height: 60)
        XCTAssertTrue(graph.scrollWheel(atX: 10, y: 10, lines: 2))
        graph.flush()
        let state = everyNode(graph.snapshot()).first { $0.kind == "ScrollView" }?.scroll
        XCTAssertEqual(state?.offsetY ?? -1, 20, accuracy: 1e-9)
        XCTAssertEqual(state?.showsScroller, false)
        _ = root
    }

    // MARK: Page and edge

    func testPageMovesByViewportLessOverlap() {
        let (graph, _) = resolved(TenRows())
        let id = listID(graph)
        XCTAssertTrue(graph.scrollPage(id, down: true))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 90, accuracy: 1e-9)
        XCTAssertTrue(graph.scrollPage(id, down: true))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 160, accuracy: 1e-9)
        XCTAssertFalse(graph.scrollPage(id, down: true))
        XCTAssertTrue(graph.scrollPage(id, down: false))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 70, accuracy: 1e-9)
    }

    func testEdgesJumpToStartAndEnd() {
        let (graph, _) = resolved(TenRows())
        let id = listID(graph)
        XCTAssertTrue(graph.scrollToEdge(id, end: true))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 160, accuracy: 1e-9)
        XCTAssertFalse(graph.scrollToEdge(id, end: true))
        XCTAssertTrue(graph.scrollToEdge(id, end: false))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 0, accuracy: 1e-9)
        XCTAssertFalse(graph.scrollToEdge(id, end: false))
    }

    // MARK: Scroll bar

    func testThumbLengthAndTrackFormulas() {
        XCTAssertEqual(ScrollerMetrics.trackLength(viewport: 100), 90, accuracy: 1e-9)
        // track 90 x viewport 100 / content 260 = 34.615..., above the 18 pt minimum.
        XCTAssertEqual(ScrollerMetrics.thumbLength(viewport: 100, content: 260), 90 * 100 / 260, accuracy: 1e-9)
        // A long document gives the minimum thumb.
        XCTAssertEqual(ScrollerMetrics.thumbLength(viewport: 100, content: 2000), ScrollerMetrics.minThumbLength, accuracy: 1e-9)
        XCTAssertEqual(ScrollerMetrics.thumbLength(viewport: 100, content: 0), ScrollerMetrics.minThumbLength, accuracy: 1e-9)
    }

    func testThumbDragMapsPointerDeltaToOffset() {
        let (graph, _) = resolved(TenRows())
        let id = listID(graph)
        // The thumb spans 3.8 to 3.8 + 34.615 from the List's top; press at 13.8 is inside it.
        graph.scrollBarPress(id, atY: 13.8)
        // Travel is 90 - 34.615 = 55.385 pt of pointer for 160 pt of offset: half the travel is 80 pt.
        graph.scrollBarDrag(id, toY: 13.8 + (90 - 90 * 100.0 / 260) / 2)
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 80, accuracy: 0.01)
        graph.scrollBarRelease(id)
        graph.scrollBarDrag(id, toY: 0)
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 80, accuracy: 0.01)
    }

    func testTrackPressPagesTowardThePointer() {
        let (graph, _) = resolved(TenRows())
        let id = listID(graph)
        // Below the thumb (3.8 to 38.4): one page down.
        graph.scrollBarPress(id, atY: 60)
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 90, accuracy: 1e-9)
        // Above the thumb, which now sits at 3.8 + (90 / 160) * 55.385 = 34.95: one page up.
        graph.scrollBarPress(id, atY: 5)
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 0, accuracy: 1e-9)
    }

    // MARK: Scroll into view

    func testSelectedRowScrollsIntoViewBySmallestMove() {
        let (graph, _) = resolved(TenTaggedRows())
        let id = listID(graph)
        // Row 6 spans 154...178 in the document; the viewport is 100 pt: the smallest move puts its bottom at the viewport's bottom (offset 78).
        XCTAssertTrue(graph.scrollListRow(id, tag: 6))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 78, accuracy: 1e-9)
        XCTAssertEqual(rowMid(graph.snapshot()!, 6), 22 + 144 - 78, accuracy: 0.5)
        // Already visible: no move.
        XCTAssertFalse(graph.scrollListRow(id, tag: 6))
        // Row 0 spans 10...34, above the viewport (top at 78): the move puts its top at the viewport's top (offset 10).
        XCTAssertTrue(graph.scrollListRow(id, tag: 0))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 10, accuracy: 1e-9)
    }

    // MARK: Gutter (H21) and content shrink

    func testInsetGutterIsUnchangedForAnOverflowingList() throws {
        let (_, root) = resolved(TenRows())
        XCTAssertEqual(ListMetrics.insetScrollerGutter, 16.8, accuracy: 1e-9)
        XCTAssertEqual(ListMetrics.trailingGutter(.inset, overflows: true), 16.8, accuracy: 1e-9)
        XCTAssertEqual(ListMetrics.trailingGutter(.inset, overflows: false), 0)
        XCTAssertTrue(try XCTUnwrap(list(root).scroll).showsScroller)
    }

    func testOffsetIsReclampedWhenTheContentShrinks() {
        let graph = Graph(FreeRows())
        graph.rootProposal = ProposedViewSize(width: 200, height: 100)
        graph.flush()
        XCTAssertTrue(graph.scrollWheel(atX: 100, y: 50, lines: 100))
        XCTAssertEqual(listScroll(graph)?.offsetY ?? -1, 160, accuracy: 1e-9)
        // The viewport grows to the 260 pt document: nothing scrolls, so the offset returns to zero.
        graph.rootProposal = ProposedViewSize(width: 200, height: 260)
        let state = listScroll(graph)
        XCTAssertEqual(state?.offsetY ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(state?.showsScroller, false)
    }
}
