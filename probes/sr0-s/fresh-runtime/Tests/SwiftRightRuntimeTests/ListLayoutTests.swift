import SwiftRightRuntime
import XCTest

private struct FiveRows: View {
    @State var selection: Int? = nil
    var body: some View {
        List(selection: $selection) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } }.frame(width: 200, height: 150)
    }
}

private struct PlainFiveRows: View {
    var body: some View { List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)") } }.listStyle(.plain).frame(width: 200, height: 150) }
}

private struct MixedRows: View {
    var body: some View {
        List { Color.red.frame(width: 30, height: 10); Color.red.frame(width: 30, height: 40); Color.red.frame(width: 30, height: 24) }.frame(width: 200, height: 150)
    }
}

private struct Unframed: View {
    var body: some View { List { Text("Only") } }
}

private struct Reorderable: View {
    @State var items = ["a", "b", "c", "d"]
    @State var calls: [String] = []
    var body: some View {
        VStack {
            List { ForEach(items, id: \.self) { Text($0) }.onMove { source, destination in calls.append("\(Array(source))->\(destination)"); items.move(fromOffsets: source, toOffset: destination) } }
                .frame(width: 100, height: 100)
            Text(items.joined() + "|" + calls.joined(separator: ","))
        }
    }
}

/// A List's layout, measured from SwiftUI on macOS 27 (NSTableView rows at scale 2.5): a row is its content plus 8 pt, at least 24 pt tall; content 16 pt from the
/// leading edge (8 pt plain), centred in its row; 10 pt above the first row of the inset style; a List takes the whole proposal and has no ideal size.
@MainActor
final class ListLayoutTests: XCTestCase {
    private func resolved(_ view: some View, scale: CGFloat = 2.5) -> (Graph, ResolvedNode) {
        let graph = Graph(view, scale: scale)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        return (graph, graph.snapshot()!)
    }

    private func mid(_ f: LayoutRect) -> Double { Double(f.minY) + Double(f.height) / 2 }
    private func rows(_ root: ResolvedNode) -> [ResolvedNode] { everyNode(root).first { $0.kind == "List" }!.children }

    func testTextRowsAreTwentyFourPointsFromTenPointsDown() throws {
        let (_, root) = resolved(FiveRows())
        let list = try XCTUnwrap(everyNode(root).first { $0.kind == "List" })
        XCTAssertEqual(list.frame.width, 200); XCTAssertEqual(list.frame.height, 150)
        let ys = rows(root).map { $0.frame.minY - list.frame.minY }
        XCTAssertEqual(ys.count, 5)
        // body text is 16 pt (SF) or about that: the row centre is 10 + 12 + 24 i
        for (i, row) in rows(root).enumerated() {
            XCTAssertEqual((mid(row.frame) - Double(list.frame.minY)), 22 + 24 * Double(i), accuracy: 0.5)
            XCTAssertEqual(Double(row.frame.minX - list.frame.minX), 16, accuracy: 1e-9)
        }
    }

    func testRowHeightIsContentPlusEightAtLeastTwentyFour() throws {
        let (_, root) = resolved(MixedRows())
        let list = try XCTUnwrap(everyNode(root).first { $0.kind == "List" })
        let r = rows(root)
        XCTAssertEqual((mid(r[0].frame) - Double(list.frame.minY)), 22, accuracy: 0.5)          // 10 pt content: a 24 pt row
        XCTAssertEqual((mid(r[1].frame) - Double(list.frame.minY)), 58, accuracy: 0.5)     // 40 pt content: a 48 pt row
        XCTAssertEqual((mid(r[2].frame) - Double(list.frame.minY)), 98, accuracy: 0.5) // 24 pt content: a 32 pt row
        XCTAssertEqual(Double(r[0].frame.minX - list.frame.minX), 16)
        XCTAssertEqual(ListMetrics.rowHeight(forContent: 10), 24)
        XCTAssertEqual(ListMetrics.rowHeight(forContent: 40), 48)
        XCTAssertEqual(ListMetrics.rowHeight(forContent: 24), 32)
    }

    func testPlainStyleStartsAtTheTopAndInsetsEightPoints() throws {
        let (_, root) = resolved(PlainFiveRows())
        let list = try XCTUnwrap(everyNode(root).first { $0.kind == "List" })
        XCTAssertEqual(list.listStyle, "PlainListStyle")
        for (i, row) in rows(root).enumerated() {
            XCTAssertEqual((mid(row.frame) - Double(list.frame.minY)), 12 + 24 * Double(i), accuracy: 0.5)
            XCTAssertEqual(Double(row.frame.minX - list.frame.minX), 8, accuracy: 1e-9)
        }
    }

    func testListTakesTheWholeProposalAndHasNoIdealSize() throws {
        let (_, root) = resolved(Unframed())
        let list = try XCTUnwrap(everyNode(root).first { $0.kind == "List" })
        XCTAssertEqual(list.frame.width, 320); XCTAssertEqual(list.frame.height, 240)
        let graph = Graph(Unframed(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: nil, height: nil)
        graph.flush()
        let ideal = try XCTUnwrap(everyNode(graph.snapshot()!).first { $0.kind == "List" })
        XCTAssertEqual(ideal.frame.width, 0); XCTAssertEqual(ideal.frame.height, 0)
    }

    func testRowFrameFromContent() throws {
        let (_, root) = resolved(MixedRows())
        let list = try XCTUnwrap(everyNode(root).first { $0.kind == "List" })
        let r = rows(root)
        let full = ListMetrics.rowFrame(content: r[1].frame, listFrame: list.frame)
        XCTAssertEqual(full.height, 48); XCTAssertEqual(full.minX, list.frame.minX)
        XCTAssertEqual(Double(full.width), 200, accuracy: 1e-9, "the rows fit: no gutter, the row spans the list")
        let scrolled = ListMetrics.rowFrame(content: r[1].frame, listFrame: list.frame, trailingGutter: ListMetrics.trailingGutter(.inset, overflows: true))
        XCTAssertEqual(Double(scrolled.width), 200 - 16.8, accuracy: 1e-6, "an overflowing inset list: the row ends 16.8 pt before the trailing edge")
        XCTAssertEqual(Double(full.minY - list.frame.minY), 34, accuracy: 0.5)
    }

    func testScrollerGutterOnlyForAnOverflowingInsetList() {
        XCTAssertEqual(Double(ListMetrics.trailingGutter(.inset, overflows: true)), 16.8, accuracy: 1e-6)
        XCTAssertEqual(ListMetrics.trailingGutter(.inset, overflows: false), 0)
        XCTAssertEqual(ListMetrics.trailingGutter(.plain, overflows: true), 0, "the plain style's gutter is unmeasured: none")
    }

    func testControlsBDocumentOverflowsItsNinetyPointList() {
        // controls-b (CI): 10 + 3 x 24 + 10 = 92 pt document in a 90 pt list (AXOutline 92 pt, AXScrollArea 90 pt)
        let rows: [CGFloat] = [24, 24, 24]
        XCTAssertEqual(ListMetrics.documentHeight(.inset, rowHeights: rows), 92)
        XCTAssertTrue(ListMetrics.overflows(.inset, rowHeights: rows, viewportHeight: 90))
        XCTAssertFalse(ListMetrics.overflows(.inset, rowHeights: rows, viewportHeight: 92), "a document exactly the viewport's height fits")
    }

    func testFiveRowsFitTheirOneSixtyPointList() {
        // five-rows (CI): 10 + 5 x 24 + 10 = 140 pt in 160 pt, no AXScrollBar, rows span the full width
        XCTAssertFalse(ListMetrics.overflows(.inset, rowHeights: [CGFloat](repeating: 24, count: 5), viewportHeight: 160))
    }

    func testListStyleMetadata() throws {
        let (_, root) = resolved(FiveRows())
        XCTAssertNil(try XCTUnwrap(everyNode(root).first { $0.kind == "List" }).listStyle)
        XCTAssertEqual(ListLook(style: nil), .inset)
        XCTAssertEqual(ListLook(style: "InsetListStyle"), .inset)
        XCTAssertEqual(ListLook(style: "PlainListStyle"), .plain)
        XCTAssertEqual(ListLook(style: "SidebarListStyle"), .sidebar)
    }

    func testOnMoveReceivesSourceOffsetsAndTheDestinationBeforeTheMove() throws {
        let (graph, root) = resolved(Reorderable())
        let rowIDs = rows(root).map(\.id)
        XCTAssertEqual(rowIDs.count, 4)
        XCTAssertTrue(graph.moveRow(rowIDs[1], by: 1))          // b below c: SwiftUI passes [1] and 3
        graph.flush()
        let label = try XCTUnwrap(everyNode(graph.snapshot()!).last { $0.kind == "Text" })
        XCTAssertEqual(label.text, "acbd|[1]->3")
    }

    func testOnMoveUpAndTheSelectionRoute() throws {
        let (graph, root) = resolved(Reorderable())
        let ids = rows(root).map(\.id)
        XCTAssertTrue(graph.moveRow(ids[2], by: -1))            // c above b: [2] and 1
        graph.flush()
        XCTAssertEqual(try XCTUnwrap(everyNode(graph.snapshot()!).last { $0.kind == "Text" }).text, "acbd|[2]->1")
        XCTAssertFalse(graph.moveRow(ids[0], by: 0))
    }

    func testOnMoveRowWithoutAHandlerDoesNothing() throws {
        let (graph, root) = resolved(FiveRows())
        XCTAssertFalse(graph.moveRow(rows(root)[0].id, by: 1))
    }
}
