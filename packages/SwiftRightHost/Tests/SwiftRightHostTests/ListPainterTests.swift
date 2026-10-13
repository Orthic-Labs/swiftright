import XCTest
import SwiftRightHost
import SwiftRightBridge

private struct Witness_ListFive: View {
    @State var selection: Int? = 2
    var body: some View {
        List(selection: $selection) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } }.frame(width: 200, height: 160)
    }
}

private struct Witness_ListNoSelection: View {
    var body: some View { List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)") } }.frame(width: 200, height: 160) }
}

private struct Witness_ListPlainSelected: View {
    @State var selection: Int? = 1
    var body: some View {
        List(selection: $selection) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } }.listStyle(.plain).frame(width: 200, height: 160)
    }
}

private struct Witness_ListSidebar: View {
    var body: some View { List { Text("A") }.listStyle(.sidebar).frame(width: 200, height: 160) }
}

/// The List paint (decision 12): rows, separators, selection and semantics, from the default macOS List measured at scale 2.5.
@MainActor
final class ListPainterTests: XCTestCase {
    private struct Result { var transaction: SwiftRightBridge.Transaction; var runs: FakeRuns; var images: FakeImages; var root: ResolvedNode }

    private func commit<V: View>(_ view: V, active: Bool = false, origin: (Float, Float) = (150, 100)) throws -> Result {
        let runs = FakeRuns(), images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: runs, log: { _ in })
        painter.listIsActive = active
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let root = try XCTUnwrap(graph.snapshot())
        var sent: SwiftRightBridge.Transaction?
        _ = try painter.commit(root: root, version: 1, previousLive: [], place: { Rect(x: $0.x + origin.0, y: $0.y + origin.1, w: $0.w, h: $0.h) }, submit: { sent = $0 })
        return Result(transaction: try XCTUnwrap(sent), runs: runs, images: images, root: root)
    }

    private func upsert(_ r: Result, kind: String, _ index: Int = 0) throws -> NodeUpsert {
        let ids = flatten(r.root).filter { $0.kind == kind }.map { UInt64($0.instance + 1) }
        return try XCTUnwrap(r.transaction.upserts.first { $0.id == ids[index] })
    }

    private func rects(_ primitives: [Primitive]) -> [(Rect, UInt32)] {
        primitives.compactMap { if case .rect(let r, let c, _, _, _) = $0 { return (r, c) } else { return nil } }
    }

    func testRowsAreSixtyPixelsFromTheTenPointInset() throws {
        let r = try commit(Witness_ListNoSelection())
        let list = try upsert(r, kind: "List")
        XCTAssertEqual(list.bounds.x, 150); XCTAssertEqual(list.bounds.y, 100)
        let rows = list.semantic.map { _ in flatten(r.root).first { $0.kind == "List" }!.children } ?? []
        let rects = ListPainter.rows(of: flatten(r.root).first { $0.kind == "List" }!, bounds: list.bounds, scale: 2.5)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rects.map { $0.rect.y }, [125, 185, 245, 305, 365])
        XCTAssertEqual(rects.map { $0.rect.h }, [60, 60, 60, 60, 60])
        XCTAssertEqual(rects.map { $0.rect.x }, [150, 150, 150, 150, 150]); XCTAssertEqual(rects[0].rect.w, 500)
    }

    func testBackgroundAndFourSeparatorsInTwoLayers() throws {
        let r = try commit(Witness_ListNoSelection())
        let list = try upsert(r, kind: "List")
        guard case .clipPush(let clip) = list.primitives.first else { return XCTFail("a list clips its own paint") }
        XCTAssertEqual(clip.w, 500)
        let rs = rects(list.primitives)
        XCTAssertEqual(rs[0].0.w, 500); XCTAssertEqual(rs[0].1, 0xffffffff)
        let seps = Array(rs.dropFirst())
        XCTAssertEqual(seps.count, 8, "4 separators (none after the last row), each a 2 px line and a half-coverage pixel row above it")
        // under row 0 (125..185): the 2 px line 183..185 in 230 and the pixel row 182 in 242.5 (243), from 16 pt (40 px) inside both edges
        XCTAssertEqual(seps[0].0.y, 183); XCTAssertEqual(seps[0].0.h, 2); XCTAssertEqual(seps[0].0.x, 190); XCTAssertEqual(seps[0].0.w, 420); XCTAssertEqual(seps[0].1, 0xe6e6e6ff)
        XCTAssertEqual(seps[1].0.y, 182); XCTAssertEqual(seps[1].0.h, 1); XCTAssertEqual(seps[1].1, 0xf3f3f3ff)
    }

    func testSeparatorsNextToTheSelectedRowAreHidden() throws {
        let r = try commit(Witness_ListFive())
        let list = try upsert(r, kind: "List")
        XCTAssertEqual(rects(list.primitives).count - 1, 4, "rows 1, 2, 3 touch the selected row 2: only the separators under row 0 and under row 3 remain (two layers each)")
    }

    func testSelectedRowIsARoundedRectAndGreyUntilTheListIsActive() throws {
        for (active, colour) in [(false, [220, 220, 220]), (true, [0, 100, 225])] {
            let r = try commit(Witness_ListFive(), active: active)
            let rows = flatten(r.root).first { $0.kind == "List" }!.children
            let selected = try XCTUnwrap(r.transaction.upserts.first { $0.id == UInt64(rows[2].instance + 1) })
            let rs = rects(selected.primitives)
            guard rs.count == 1, case .rect(let place, let rgba, let radius, _, _) = selected.primitives.first(where: { if case .rect = $0 { return true } else { return false } })! else { return XCTFail("inset selection is one rounded rect") }
            XCTAssertEqual(place.x, 175); XCTAssertEqual(place.w, 450, "180 pt: the highlight is inset 10 pt from both edges"); XCTAssertEqual(place.y, 245); XCTAssertEqual(place.h, 60)
            XCTAssertEqual(radius, 20, "8 pt")
            XCTAssertEqual([Int(rgba >> 24), Int(rgba >> 16 & 255), Int(rgba >> 8 & 255)], colour)
            XCTAssertEqual(selected.bounds.x, 150, "a row is hit along its whole width"); XCTAssertEqual(selected.bounds.w, 500); XCTAssertEqual(selected.bounds.h, 60)
            XCTAssertEqual(selected.flags, [.hitTarget])
            XCTAssertEqual(selected.semantic?.role, .listItem); XCTAssertEqual(selected.semantic?.selected, true); XCTAssertEqual(selected.semantic?.label, "Row 2")
        }
    }

    func testTextInAnActiveSelectionIsWhiteAndOtherTextKeepsItsColour() throws {
        let inactive = try commit(Witness_ListFive(), active: false), active = try commit(Witness_ListFive(), active: true)
        XCTAssertEqual(inactive.runs.colours, [nil, nil, nil, nil, nil])
        XCTAssertEqual(active.runs.colours, [nil, nil, 0xffffffff, nil, nil])
    }

    func testListAndRowsPublishListSemantics() throws {
        let r = try commit(Witness_ListNoSelection())
        let list = try upsert(r, kind: "List")
        XCTAssertEqual(list.semantic?.role, .list)
        let rows = flatten(r.root).first { $0.kind == "List" }!.children
        let first = try XCTUnwrap(r.transaction.upserts.first { $0.id == UInt64(rows[0].instance + 1) })
        XCTAssertEqual(first.semantic?.role, .listItem); XCTAssertEqual(first.semantic?.selected, false); XCTAssertEqual(first.primitives.count, 0)
    }

    func testPlainStyleSelectionIsAFlatFullWidthRectangleAndSeparatorsReachTheEdge() throws {
        let r = try commit(Witness_ListPlainSelected())
        let rows = flatten(r.root).first { $0.kind == "List" }!.children
        let selected = try XCTUnwrap(r.transaction.upserts.first { $0.id == UInt64(rows[1].instance + 1) })
        let rs = rects(selected.primitives)
        XCTAssertEqual(rs.count, 1); XCTAssertEqual(rs[0].0.x, 150); XCTAssertEqual(rs[0].0.w, 500); XCTAssertEqual(rs[0].0.y, 160); XCTAssertEqual(rs[0].0.h, 60); XCTAssertEqual(rs[0].1, 0xdcdcdcff)
        let list = try upsert(r, kind: "List")
        let seps = Array(rects(list.primitives).dropFirst())
        XCTAssertEqual(seps[0].0.x, 150 + 20); XCTAssertEqual(seps[0].0.w, 500 - 20, "plain separators run from 8 pt inside the leading edge to the trailing edge")
    }

    func testSidebarStyleIsNotPaintedAndSaysSo() {
        XCTAssertThrowsError(try commit(Witness_ListSidebar())) { XCTAssertEqual($0 as? HostPaintError, .unsupportedListStyle("sidebar")) }
    }

    func testSeparatorColumnMatchesTheMacPixels() {
        XCTAssertEqual(ListPaintGolden.separatorColumn, ["ffffff", "ffffff", "f3f3f3", "e6e6e6", "e6e6e6", "ffffff", "ffffff"])
    }
}
