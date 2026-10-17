import XCTest
import SwiftRightBridge
@testable import SwiftRightHost
import SwiftRightRuntime

/// Issue #31 host wiring of the keyboard: Page Up / Page Down / Home / End page or jump the scroll container that holds the keyboard (a List) or,
/// failing that, the innermost container under the last pointer position; a List's scroll bar small change is one row.
@MainActor
final class HostScrollKeyTests: XCTestCase {
    // MARK: key names and virtual key codes

    func testBridgeNamesMapToThePagingKeys() {
        XCTAssertEqual(HostScrollKey(bridgeName: "pageup"), .pageUp)
        XCTAssertEqual(HostScrollKey(bridgeName: "pagedown"), .pageDown)
        XCTAssertEqual(HostScrollKey(bridgeName: "home"), .home)
        XCTAssertEqual(HostScrollKey(bridgeName: "end"), .end)
        XCTAssertEqual(HostScrollKey(bridgeName: "PageDown"), .pageDown, "the bridge name is compared lowercased")
        XCTAssertNil(HostScrollKey(bridgeName: "up"))
        XCTAssertNil(HostScrollKey(bridgeName: "tab"))
    }

    func testVirtualKeyCodesMapToThePagingKeys() {
        XCTAssertEqual(HostScrollKey(virtualKey: 0x21), .pageUp, "VK_PRIOR")
        XCTAssertEqual(HostScrollKey(virtualKey: 0x22), .pageDown, "VK_NEXT")
        XCTAssertEqual(HostScrollKey(virtualKey: 0x23), .end, "VK_END")
        XCTAssertEqual(HostScrollKey(virtualKey: 0x24), .home, "VK_HOME")
        XCTAssertNil(HostScrollKey(virtualKey: 0x25), "VK_LEFT is not a paging key")
    }

    // MARK: paging the container

    private var overflowing: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.red).frame(height: 40)
                Rectangle().fill(Color.green).frame(height: 40)
                Rectangle().fill(Color.purple).frame(height: 40)
            }
        }.frame(width: 120, height: 100)
    }

    private var longList: some View {
        List { ForEach(0..<25, id: \.self) { i in Text("Row \(i)") } }.frame(width: 180, height: 90)
    }

    private func laidOut(_ view: some View) throws -> (painter: ResolvedNodePainter, graph: Graph, root: ResolvedNode) {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, publishesScrollBars: true, log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        return (painter, graph, try XCTUnwrap(graph.snapshot()))
    }

    func testPageDownMovesOnePageAndStopsAtTheEnd() throws {
        let (_, graph, root) = try laidOut(overflowing)
        let view = try XCTUnwrap(flatten(root).first { $0.kind == "ScrollView" })
        // Content 120, viewport 100: the page (100 less the 10 pt overlap) is more than the 20 pt of travel, so one page reaches the end.
        XCTAssertTrue(HostScrollInput.key(.pageDown, graph: graph, focusedOrHovered: view.id))
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(view.id) ?? -1, 20, accuracy: 1e-9)
        XCTAssertFalse(HostScrollInput.key(.pageDown, graph: graph, focusedOrHovered: view.id), "already at the end: no change")
    }

    func testPageUpFromTheMiddleGoesToTheStart() throws {
        let (_, graph, root) = try laidOut(overflowing)
        let view = try XCTUnwrap(flatten(root).first { $0.kind == "ScrollView" })
        graph.scroll(view.id, to: 10); graph.flush()
        XCTAssertTrue(HostScrollInput.key(.pageUp, graph: graph, focusedOrHovered: view.id))
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(view.id) ?? -1, 0, accuracy: 1e-9)
        XCTAssertFalse(HostScrollInput.key(.pageUp, graph: graph, focusedOrHovered: view.id), "already at the start: no change")
    }

    func testHomeAndEndGoToTheEdges() throws {
        let (_, graph, root) = try laidOut(overflowing)
        let view = try XCTUnwrap(flatten(root).first { $0.kind == "ScrollView" })
        XCTAssertTrue(HostScrollInput.key(.end, graph: graph, focusedOrHovered: view.id))
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(view.id) ?? -1, 20, accuracy: 1e-9)
        XCTAssertTrue(HostScrollInput.key(.home, graph: graph, focusedOrHovered: view.id))
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(view.id) ?? -1, 0, accuracy: 1e-9)
        XCTAssertFalse(HostScrollInput.key(.home, graph: graph, focusedOrHovered: view.id))
    }

    func testNoContainerScrollsNothing() throws {
        let (_, graph, _) = try laidOut(overflowing)
        for key in [HostScrollKey.pageUp, .pageDown, .home, .end] {
            XCTAssertFalse(HostScrollInput.key(key, graph: graph, focusedOrHovered: nil), "\(key) with no container")
        }
    }

    func testAListWithTheKeyboardPagesTheList() throws {
        let (_, graph, root) = try laidOut(longList)
        let list = try XCTUnwrap(flatten(root).first { $0.kind == "List" })
        // A List's offset is read from its resolved scroll state (Graph.scrollOffset reports ScrollView offsets).
        func listOffset() throws -> Double { try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.id == list.id }?.scroll).offsetY }
        XCTAssertTrue(HostScrollInput.key(.pageDown, graph: graph, focusedOrHovered: list.id))
        graph.flush()
        XCTAssertGreaterThan(try listOffset(), 0)
        XCTAssertTrue(HostScrollInput.key(.end, graph: graph, focusedOrHovered: list.id))
        graph.flush()
        XCTAssertEqual(try listOffset(), try XCTUnwrap(list.scroll).maxOffset, accuracy: 1e-9)
    }

    func testThePointerContainerIsTheInnermostScrollViewUnderThePoint() throws {
        let (_, graph, root) = try laidOut(overflowing)
        let view = try XCTUnwrap(flatten(root).first { $0.kind == "ScrollView" })
        // Root points, as the host passes them after dividing the physical pixels by the scale.
        XCTAssertEqual(graph.scrollContainerID(atX: view.frame.cgRect.midX, y: view.frame.cgRect.midY), view.id)
        XCTAssertNil(graph.scrollContainerID(atX: -1, y: -1), "outside every container")
    }

    // MARK: List scroll bar small change (one row)

    func testAListScrollBarSmallChangeIsOneRow() throws {
        let (painter, _, root) = try laidOut(longList)
        let list = try XCTUnwrap(flatten(root).first { $0.kind == "List" })
        let state = try XCTUnwrap(list.scroll)
        let rowHeight = try XCTUnwrap(list.children.map { ListMetrics.rowHeight(forContent: CGFloat($0.frame.height)) }.min())
        let semantic = try XCTUnwrap(painter.scrollBarSemantic(for: state, lineHeight: rowHeight)?.range)
        XCTAssertEqual(semantic.step * state.maxOffset, Double(rowHeight), accuracy: 1e-9, "one wheel line over a List is one row")
        XCTAssertNotEqual(Double(rowHeight), Double(ScrollerMetrics.pointsPerLine), "a List row is not the ScrollView's 10 pt line")
    }
}
