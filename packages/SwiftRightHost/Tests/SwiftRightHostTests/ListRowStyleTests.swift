import XCTest
import SwiftRightHost
import SwiftRightBridge

// Block swiftui.list-row-style: `.listRowSeparator` and `.listRowBackground`, from SwiftUI on macOS 27 (factory/pipeline/blocks-24-25, scale 2.5): a hidden separator is the one under
// that row only; a row background fills the row's rectangle (not the list's top inset), separators over it are translucent black, and it replaces the selection highlight.

private struct Witness_RowsHiddenOdd: View {
    var body: some View {
        List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").listRowSeparator(i % 2 == 1 ? .hidden : .visible) } }.frame(width: 200, height: 160)
    }
}
private struct Witness_RowsRed: View {
    var body: some View {
        List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").listRowBackground(Color.red) } }.frame(width: 200, height: 160)
    }
}
private struct Witness_RowsBlueRect: View {
    var body: some View {
        List { ForEach(0..<2, id: \.self) { i in Text("Row \(i)").listRowBackground(Rectangle().fill(Color.blue)) } }.frame(width: 200, height: 160)
    }
}
private struct Witness_RowsText: View {
    var body: some View {
        List { ForEach(0..<2, id: \.self) { i in Text("Row \(i)").listRowBackground(Text("no")) } }.frame(width: 200, height: 160)
    }
}
private struct Witness_RowsSelectedRed: View {
    @State private var sel: Int? = 2
    var body: some View {
        List(selection: $sel) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").listRowBackground(Color.red).tag(i) } }.frame(width: 200, height: 160)
    }
}

@MainActor
final class ListRowStyleTests: XCTestCase {
    private func list<V: View>(_ view: V) throws -> [Primitive] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        painter.beginCommit()
        defer { painter.endCommit(committed: false) }
        let node = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "List" })
        let b = Rect(x: Float(node.pixelFrame.x), y: Float(node.pixelFrame.y), w: Float(node.pixelFrame.width), h: Float(node.pixelFrame.height))
        return try painter.emit(node, id: 1, bounds: b).primitives
    }

    private func rects(_ p: [Primitive]) -> [(Rect, UInt32)] {
        p.compactMap { if case .rect(let r, let c, _, _, _) = $0 { return (r, c) } else { return nil } }
    }

    func testHiddenSeparatorsAreTheOnesUnderTheHiddenRows() throws {
        let r = rects(try list(Witness_RowsHiddenOdd()))
        // background + separators under rows 0 and 2 (rows 1 and 3 hidden, row 4 is last): whole device pixels, 1 pt = 2.5 px -> a 2 px line and a half-coverage pixel row each
        let lines = r.filter { $0.0.h == 2 }
        XCTAssertEqual(lines.count, 2)
    }

    func testRowBackgroundFillsEachRowAndSeparatorsOverItAreTranslucent() throws {
        let r = rects(try list(Witness_RowsRed()))
        let fills = r.filter { $0.1 == 0xff383cff }
        XCTAssertEqual(fills.count, 5)
        XCTAssertEqual(fills.first?.0.w, 500, "the whole list width")
        XCTAssertEqual(fills.first?.0.y, 25, "the list's 10 pt inset (25 px) above the first row stays the list's own (the list is the root here, at y 0)")
        XCTAssertEqual(r.filter { $0.1 == 0x00000019 }.count, 4, "four separators, translucent black over the colour")
    }

    func testRectangleFilledWithAColourIsARowBackgroundToo() throws {
        XCTAssertEqual(rects(try list(Witness_RowsBlueRect())).filter { $0.1 == 0x0088ffff }.count, 2)
    }

    func testAnotherViewAsRowBackgroundFailsVisibly() {
        XCTAssertThrowsError(try list(Witness_RowsText()))
    }

    func testRowBackgroundReplacesTheSelectionHighlight() throws {
        let p = try list(Witness_RowsSelectedRed())
        XCTAssertEqual(rects(p).filter { $0.1 == 0xff383cff }.count, 5)
    }
}
