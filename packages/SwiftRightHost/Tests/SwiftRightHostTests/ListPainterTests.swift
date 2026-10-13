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

private struct Witness_ListBareRows: View {
    var body: some View { List { Text("A"); Text("B") }.frame(width: 200, height: 160) }
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

    func testSelectedRowIsARasterisedRoundedRectAndGreyUntilTheListIsActive() throws {
        for (active, colour) in [(false, [220, 220, 220]), (true, [0, 100, 225])] {
            let r = try commit(Witness_ListFive(), active: active)
            let rows = flatten(r.root).first { $0.kind == "List" }!.children
            let selected = try XCTUnwrap(r.transaction.upserts.first { $0.id == UInt64(rows[2].instance + 1) })
            guard case .image(let handle, let place, _) = try XCTUnwrap(selected.primitives.first(where: { if case .image = $0 { return true } else { return false } })) else { return XCTFail("inset selection is a rasterised rounded rectangle") }
            let image = try XCTUnwrap(r.images.registered[handle.raw])
            XCTAssertEqual(Float(image.width), 450, "180 pt: the highlight is inset 10 pt from both edges"); XCTAssertEqual(Float(image.height), 60)
            XCTAssertEqual(place.x, 175, accuracy: 0.1); XCTAssertEqual(place.y, 245, accuracy: 0.1)
            let mid = (30 * Int(image.width) + 225) * 4
            XCTAssertEqual(Array(image.rgba[mid..<mid + 3]).map(Int.init), colour)
            XCTAssertEqual(image.rgba[3], 0, "the corner is transparent")
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
        XCTAssertEqual(first.semantic?.role, .listItem); XCTAssertEqual(first.semantic?.selected, false); XCTAssertFalse(first.primitives.contains { if case .image = $0 { return true } else { return false } }, "no highlight")
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

    func testHighlightCornerMatchesSwiftUI() {
        // the Mac's selected row spans x 175..624 from y 258 (a 180 pt wide, 24 pt tall highlight): the corner rows free of the row's text, within edge-aa 32
        let image = ListHighlightArtwork.render(widthPX: 450, heightPX: 60, scale: 2.5, rgb: 0x0064e1)
        var worst = 0, at = (0, 0)
        for y in 0..<16 {
            for x in 0..<36 {
                let o = (y * image.width + x) * 4
                let a = Double(image.rgba[o + 3]) / 255
                let got = (0..<3).map { Int((Double(image.rgba[o + $0]) * a + 255 * (1 - a)).rounded()) }
                let hex = String(Array(ListPaintGolden.selectionCorner[y])[(x * 6)..<(x * 6 + 6)])
                let want = [0, 2, 4].map { Int(hex.dropFirst($0).prefix(2), radix: 16)! }
                let d = zip(got, want).map { abs($0 - $1) }.max()!
                if d > worst { worst = d; at = (x, y) }
            }
        }
        XCTAssertLessThanOrEqual(worst, 32, "worst corner difference \(worst) at \(at)")
    }

    func testARowThatIsABareTextStillPaintsItsText() throws {
        let r = try commit(Witness_ListBareRows())
        XCTAssertEqual(r.runs.asked.map { $0.0 }, ["A", "B"])
        let rows = flatten(r.root).first { $0.kind == "List" }!.children
        let first = try XCTUnwrap(r.transaction.upserts.first { $0.id == UInt64(rows[0].instance + 1) })
        XCTAssertEqual(first.semantic?.role, .listItem)
        XCTAssertTrue(first.primitives.contains { if case .text = $0 { return true } else { return false } })
    }
}
