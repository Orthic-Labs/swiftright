import XCTest
import SwiftRightHost

@MainActor
final class FakeRuns: TextRunSource {
    var asked: [(String, Rect)] = []
    /// The colour each coloured run was asked for (nil for a plain run), in order.
    var colours: [UInt32?] = []
    func run(text: String, font: Font?, bounds: Rect) throws -> TextRunHandle { asked.append((text, bounds)); colours.append(nil); return TextRunHandle(raw: 77) }
    func run(text: String, font: Font?, bounds: Rect, color: UInt32) throws -> TextRunHandle { asked.append((text, bounds)); colours.append(color); return TextRunHandle(raw: 78) }
}

/// The product path end to end on the Mac: SwiftUI-source views -> runtime graph -> painter -> primitives, with no case adapter.
@MainActor
final class PainterTests: XCTestCase {
    private func paint<V: View>(_ view: V, proposal: (CGFloat, CGFloat), scale: CGFloat = 2.5, images: FakeImages = FakeImages(),
                                runs: FakeRuns? = nil, glyphs: Bool = true) throws -> (nodes: [(ResolvedNode, NodeEmission)], images: FakeImages, painter: ResolvedNodePainter) {
        let registry: SystemImageRegistry? = glyphs ? try SystemImageRegistry(images: images, rasterizer: FakeGlyphs(), log: { _ in }) : nil
        registry?.scale = Double(scale)
        let painter = ResolvedNodePainter(images: images, scale: Float(scale), text: runs, systemImages: registry, log: { _ in })
        let graph = Graph(view, scale: scale)
        registry?.install(on: graph)
        graph.rootProposal = ProposedViewSize(width: proposal.0, height: proposal.1)
        graph.flush()
        painter.beginCommit()
        var out: [(ResolvedNode, NodeEmission)] = []
        for n in flatten(try XCTUnwrap(graph.snapshot())) {
            let b = Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
            out.append((n, try painter.emit(n, id: UInt64(n.instance + 1), bounds: b)))
        }
        painter.endCommit(committed: true)
        return (out, images, painter)
    }

    func testContinuousStrokeBecomesAnImagePrimitiveWithNoAdapter() throws {
        let r = try paint(RoundedRectangle(cornerRadius: 6).stroke(Color.blue, lineWidth: 2).frame(width: 40, height: 20), proposal: (100, 100), glyphs: false)
        let shape = try XCTUnwrap(r.nodes.first { $0.0.kind == "RoundedRectangle" })
        guard case .image = try XCTUnwrap(shape.1.primitives.first) else { return XCTFail("continuous stroke must be an image primitive") }
        XCTAssertEqual(r.images.live.count, 1)
        r.painter.releaseAll(); XCTAssertEqual(r.images.live.count, 0)
    }

    func testSystemImageBecomesAnImagePrimitiveFromTheShippedTable() throws {
        let r = try paint(Image(systemName: "star.fill").resizable().scaledToFit().frame(width: 32, height: 32).foregroundStyle(Color.yellow), proposal: (100, 100))
        let node = try XCTUnwrap(r.nodes.first { $0.0.kind == "Image" })
        guard case .image(_, let rect, _) = try XCTUnwrap(node.1.primitives.first) else { return XCTFail() }
        XCTAssertEqual(node.1.semantic?.role, .image)
        XCTAssertEqual(rect.w, Float(node.0.pixelFrame.width) + 8 - 2.0 / 64, accuracy: 1e-5)      // frame + 4 px inset each side
        XCTAssertEqual(r.images.live.count, 1)
    }

    func testImageWithoutAnAppliedForegroundUsesTheSymbolsOwnColour() throws {
        let r = try paint(Image(systemName: "star.fill").resizable().scaledToFit().frame(width: 32, height: 32), proposal: (100, 100))
        let node = try XCTUnwrap(r.nodes.first { $0.0.kind == "Image" })
        guard case .image(let h, _, _) = try XCTUnwrap(node.1.primitives.first) else { return XCTFail() }
        let rgba = try XCTUnwrap(r.images.registered[h.raw]).rgba
        let px = rgba.enumerated().first { $0.offset % 4 == 3 && $0.element == 255 }.map { $0.offset - 3 }
        XCTAssertEqual(px.map { Array(rgba[$0..<($0 + 3)]) }, [0xff, 0xcc, 0x00])
    }

    func testAnUnknownSymbolFailsVisibly() throws {
        XCTAssertThrowsError(try paint(Image(systemName: "no.such.symbol").resizable().scaledToFit().frame(width: 32, height: 32), proposal: (100, 100))) {
            XCTAssertTrue(String(describing: $0).contains("not in the table"), "\($0)")
        }
    }

    func testStackOverlayTextAndShapesPaintFromTheRuntimeTree() throws {
        let runs = FakeRuns()
        let view = ZStack(alignment: .trailing) {
            Rectangle().fill(Color.blue).frame(width: 48, height: 32)
            Circle().fill(Color.red).frame(width: 12, height: 12)
        }.overlay(alignment: .bottomTrailing) { Text("+") }
        // A text measurer is needed for Text; the fixed-advance one is enough to resolve a frame here.
        let r = try paint(view, proposal: (320, 240), runs: runs, glyphs: false)
        XCTAssertEqual(r.nodes.compactMap { $0.1.primitives.first }.count, 3)
        XCTAssertEqual(runs.asked.first?.0, "+")
    }

    func testUnsupportedNodesFailVisibly() throws {
        XCTAssertThrowsError(try paint(TextField("t", text: .constant("")), proposal: (100, 100), glyphs: false))
    }

    /// Opacity is baked into the text run's colour alpha: an unstyled text fades the primary label colour, a coloured one its own colour.
    func testTextOpacityIsBakedIntoTheRunColourAlpha() throws {
        let runs = FakeRuns()
        _ = try paint(VStack { Text("a").opacity(0.5); Text("b").foregroundStyle(Color.red).opacity(0.5); Text("c") }, proposal: (320, 240), runs: runs, glyphs: false)
        let label = try HostPaint.rgba(.semantic("label"), opacity: 0.5)
        XCTAssertEqual(runs.colours, [label, 0xff383c80, nil])
        XCTAssertEqual(label & 255, 108, "216 * 0.5")
    }

    func testForegroundColourReachesTheTextRun() throws {
        let runs = FakeRuns()
        let r = try paint(VStack { Text("a").foregroundStyle(Color.red); Text("b") }, proposal: (320, 240), runs: runs, glyphs: false)
        XCTAssertEqual(runs.asked.map { $0.0 }, ["a", "b"])
        XCTAssertEqual(runs.colours, [0xff383cff, nil], "the red text asks for its colour, an unstyled one for the plain run")
        XCTAssertEqual(r.nodes.compactMap { $0.1.primitives.first }.count, 2)
    }

    func testAFailedCommitReleasesTheNewShapeImagesAndKeepsTheOld() throws {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, log: { _ in })
        let graph = Graph(RoundedRectangle(cornerRadius: 4).fill(Color.red).frame(width: 40, height: 20), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 100, height: 100); graph.flush()
        let node = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "RoundedRectangle" })
        let b = Rect(x: 0, y: 0, w: 100, h: 50)
        painter.beginCommit(); _ = try painter.emit(node, id: 5, bounds: b); painter.endCommit(committed: true)
        XCTAssertEqual(images.live.count, 1)
        painter.beginCommit(); _ = try painter.emit(node, id: 5, bounds: b); XCTAssertEqual(images.live.count, 2)
        painter.endCommit(committed: false); XCTAssertEqual(images.live.count, 1)
        painter.beginCommit(); _ = try painter.emit(node, id: 5, bounds: b); painter.endCommit(committed: true)
        XCTAssertEqual(images.live.count, 1, "the replaced handle is released once the new commit lands")
    }
}

@MainActor
final class TreeCommitTests: XCTestCase {
    private func tree<V: View>(_ view: V) throws -> ResolvedNode {
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 100, height: 100); graph.flush()
        return try XCTUnwrap(graph.snapshot())
    }

    func testCommitUpsertsEveryNodeUnderItsParentAndRemovesWhatIsGone() throws {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, log: { _ in })
        let first = try tree(VStack { Rectangle().fill(Color.red).frame(width: 10, height: 10); Circle().fill(Color.blue).frame(width: 8, height: 8) })
        var sent: [SwiftRightBridge.Transaction] = []
        let bg = ResolvedNodePainter.Background(bounds: Rect(x: 0, y: 0, w: 250, h: 250), color: 0xffffffff)
        let a = try painter.commit(root: first, version: 1, previousLive: [], background: bg, place: { Rect(x: $0.x + 5, y: $0.y + 5, w: $0.w, h: $0.h) }) { sent.append($0) }
        let tx = try XCTUnwrap(sent.first)
        XCTAssertEqual(tx.upserts.first?.id, bg.id)
        XCTAssertEqual(tx.upserts.count, a.nodeCount); XCTAssertTrue(a.live.contains(bg.id)); XCTAssertEqual(tx.removes, [])
        let rect = try XCTUnwrap(tx.upserts.first { $0.primitives.contains { if case .rect(_, let c, _, _, _) = $0 { return c == 0xff383cff }; return false } })
        XCTAssertEqual(rect.bounds.x, 5 + Float(try XCTUnwrap(flatten(first).first { $0.kind == "Rectangle" }).pixelFrame.x))
        // Second commit of a smaller tree removes the ids that vanished.
        let second = try tree(Rectangle().fill(Color.red).frame(width: 10, height: 10))
        _ = try painter.commit(root: second, version: 2, previousLive: a.live, background: bg) { sent.append($0) }
        XCTAssertFalse(try XCTUnwrap(sent.last).removes.isEmpty)
    }

    func testAFailedSubmitReleasesTheImagesOfThatCommit() throws {
        struct Rejected: Error {}
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, log: { _ in })
        let root = try tree(RoundedRectangle(cornerRadius: 4).fill(Color.red).frame(width: 40, height: 20))
        XCTAssertThrowsError(try painter.commit(root: root, version: 1, previousLive: []) { _ in throw Rejected() })
        XCTAssertEqual(images.live.count, 0)
        _ = try painter.commit(root: root, version: 1, previousLive: []) { _ in }
        XCTAssertEqual(images.live.count, 1)
    }

    func testAnUnsupportedNodeAbortsBeforeSubmitting() throws {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, log: { _ in })
        let root = try tree(Button("x") {})
        var submitted = false
        XCTAssertThrowsError(try painter.commit(root: root, version: 1, previousLive: []) { _ in submitted = true })
        XCTAssertFalse(submitted)
    }
}
