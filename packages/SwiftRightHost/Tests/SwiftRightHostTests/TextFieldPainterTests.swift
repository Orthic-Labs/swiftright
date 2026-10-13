import XCTest
import SwiftRightHost
import SwiftRightBridge

// SR1 block 13 painter tests. The bezel numbers are pixels of a SwiftUI `TextField(...).textFieldStyle(.roundedBorder)` 120 x 24 pt field at scale 2.5
// on white, rendered by an offscreen NSHostingView (factory/pipeline/blocks-6-10/swiftui.textfield/FACTS.md): grey level of the red channel.

/// Natural-size runs: width 6 px per character, height 40 px.
final class NaturalRuns: TextRunSource {
    var asked: [(text: String, color: UInt32)] = []
    func run(text: String, font: Font?, bounds: Rect) throws -> TextRunHandle { TextRunHandle(raw: 77) }
    func naturalRun(text: String, font: Font?, color: UInt32) throws -> NaturalTextRun? {
        asked.append((text, color))
        return NaturalTextRun(run: TextRunHandle(raw: 90 + UInt64(asked.count)), width: Float(text.utf16.count * 6), height: 40, baseline: 32)
    }
    func cells(of run: TextRunHandle) -> [CharCell] { [] }
}

private let measuredTopLeft: [[Int]] = [
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 251],
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 249, 237, 228, 218, 217],
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 245, 226, 217, 217, 217, 217, 217],
        [255, 255, 255, 255, 255, 255, 255, 251, 228, 217, 217, 217, 217, 224, 233, 241],
        [255, 255, 255, 255, 255, 255, 245, 220, 217, 217, 219, 237, 251, 255, 255, 255],
        [255, 255, 255, 255, 255, 243, 218, 217, 217, 233, 253, 255, 255, 255, 255, 255],
        [255, 255, 255, 255, 245, 218, 217, 217, 243, 255, 255, 255, 255, 255, 255, 255],
        [255, 255, 255, 251, 220, 217, 217, 247, 255, 255, 255, 255, 255, 255, 255, 255],
        [255, 255, 255, 228, 217, 217, 243, 255, 255, 255, 255, 255, 255, 255, 255, 255],
        [255, 255, 245, 217, 217, 233, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255],
        [255, 255, 226, 217, 219, 253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255],
        [255, 249, 217, 217, 237, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255],
        [255, 237, 217, 217, 251, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255],
        [255, 228, 217, 224, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255],
        [255, 218, 217, 233, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255],
        [251, 217, 217, 241, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255],
]
private let measuredBottomRight: [[Int]] = [
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 241, 217, 217, 251],
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 233, 217, 218, 255],
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 224, 217, 228, 255],
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 251, 217, 217, 237, 255],
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 237, 217, 217, 249, 255],
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 253, 219, 217, 226, 255, 255],
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 233, 217, 217, 245, 255, 255],
        [255, 255, 255, 255, 255, 255, 255, 255, 255, 243, 217, 217, 228, 255, 255, 255],
        [255, 255, 255, 255, 255, 255, 255, 255, 247, 217, 217, 220, 251, 255, 255, 255],
        [255, 255, 255, 255, 255, 255, 255, 243, 217, 217, 218, 245, 255, 255, 255, 255],
        [255, 255, 255, 255, 255, 253, 233, 217, 217, 218, 243, 255, 255, 255, 255, 255],
        [255, 255, 255, 251, 237, 219, 217, 217, 220, 245, 255, 255, 255, 255, 255, 255],
        [241, 233, 224, 217, 217, 217, 217, 228, 251, 255, 255, 255, 255, 255, 255, 255],
        [217, 217, 217, 217, 217, 226, 245, 255, 255, 255, 255, 255, 255, 255, 255, 255],
        [217, 218, 228, 237, 249, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255],
        [251, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255],
]

private struct Witness_Field: View {
    @State private var text: String
    init(_ text: String) { _text = State(wrappedValue: text) }
    var body: some View { TextField("Name", text: $text).textFieldStyle(.roundedBorder).frame(width: 120) }
}
private struct Witness_PlainField: View {
    @State private var text = ""
    var body: some View { TextField("Name", text: $text, prompt: Text("Enter")).textFieldStyle(.plain).frame(width: 120) }
}
private struct Witness_FocusedField: View {
    @State private var text = "hello"
    @FocusState private var focus: Int?
    var body: some View { TextField("Name", text: $text).focused($focus, equals: 1).frame(width: 120) }
}

@MainActor
final class TextFieldPainterTests: XCTestCase {
    private func onWhite(_ bezel: TextFieldArtwork.Bezel, x: Int, y: Int) -> Int {
        let o = (y * bezel.image.width + x) * 4
        let a = Double(bezel.image.rgba[o + 3]) / 255
        return Int((255 * (1 - a) + Double(bezel.image.rgba[o]) * a).rounded())
    }

    func testBezelMatchesMeasuredCornersAndEdges() {
        let bezel = TextFieldArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5)
        XCTAssertEqual(bezel.pad, 3)
        XCTAssertEqual(bezel.image.width, 306)
        XCTAssertEqual(bezel.image.height, 66)
        var worst = 0, total = 0, n = 0
        for (y, row) in measuredTopLeft.enumerated() { for (x, v) in row.enumerated() {
            let d = abs(onWhite(bezel, x: x, y: y) - v); worst = max(worst, d); total += d; n += 1 } }
        for (y, row) in measuredBottomRight.enumerated() { for (x, v) in row.enumerated() {
            let d = abs(onWhite(bezel, x: 306 - 16 + x, y: 66 - 16 + y) - v); worst = max(worst, d); total += d; n += 1 } }
        XCTAssertLessThanOrEqual(worst, 14, "worst grey-level difference vs the measured corners")
        XCTAssertLessThan(Double(total) / Double(n), 2.0)
        // straight top edge: 0.53 coverage then two full rows (235, 217, 217), then the fill
        XCTAssertEqual((0..<6).map { onWhite(bezel, x: 153, y: $0) }, [236, 217, 217, 255, 255, 255])
        XCTAssertEqual((63..<66).map { onWhite(bezel, x: 153, y: $0) }, [217, 217, 236])
    }

    func testBezelFillIsNearlyOpaqueWhite() {
        let bezel = TextFieldArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5)
        let o = (33 * bezel.image.width + 150) * 4
        XCTAssertEqual(Int(bezel.image.rgba[o]), 255)
        XCTAssertEqual(Int(bezel.image.rgba[o + 3]), 250)   // 0.98
    }

    private func paint<V: View>(_ view: V, runs: NaturalRuns, focused: String? = nil) throws -> [(ResolvedNode, NodeEmission)] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: runs, log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var out: [(ResolvedNode, NodeEmission)] = []
        painter.beginCommit()
        for n in flatten(try XCTUnwrap(graph.snapshot())) {
            let b = Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
            out.append((n, try painter.emit(n, id: UInt64(n.instance + 1), bounds: b)))
        }
        painter.endCommit(committed: true)
        return out
    }

    func testBezeledFieldPaintsBezelPlaceholderAndSemantics() throws {
        let runs = NaturalRuns()
        let nodes = try paint(Witness_Field(""), runs: runs)
        let field = try XCTUnwrap(nodes.first { $0.0.kind == "TextField" })
        XCTAssertEqual(field.0.pixelFrame.width, 300); XCTAssertEqual(field.0.pixelFrame.height, 60)
        guard case .image(_, let rect, _) = field.1.primitives[0] else { return XCTFail("bezel image first") }
        XCTAssertEqual(rect.w, 306 - 2.0 / 64, accuracy: 0.0001)
        guard case .clipPush(let clip) = field.1.primitives[1] else { return XCTFail("clip") }
        XCTAssertEqual(clip.x, Float(field.0.pixelFrame.x) + 10); XCTAssertEqual(clip.w, 280)
        guard case .text(_, let x, let y) = field.1.primitives[2] else { return XCTFail("text") }
        XCTAssertEqual(x, Float(field.0.pixelFrame.x) + 10)          // 4 pt inset
        XCTAssertEqual(y, Float(field.0.pixelFrame.y) + 10)          // (60 - 40) / 2
        XCTAssertEqual(runs.asked.map(\.text), ["Name"])
        XCTAssertEqual(runs.asked.map(\.color), [TextFieldColors.placeholder])
        XCTAssertEqual(field.1.semantic?.role, .textField)
        XCTAssertEqual(field.1.semantic?.label, "Name")
        XCTAssertEqual(field.1.semantic?.value, "")
        XCTAssertTrue(field.1.flags.contains(.editable)); XCTAssertTrue(field.1.flags.contains(.focusable))
    }

    func testTypedTextUsesTheTextColourAndTheValueIsPublished() throws {
        let runs = NaturalRuns()
        let nodes = try paint(Witness_Field("Hello"), runs: runs)
        let field = try XCTUnwrap(nodes.first { $0.0.kind == "TextField" })
        XCTAssertEqual(runs.asked.map(\.color), [TextFieldColors.text])
        XCTAssertEqual(field.1.semantic?.value, "Hello")
    }

    func testPlainFieldHasNoBezelAndUsesThePrompt() throws {
        let runs = NaturalRuns()
        let nodes = try paint(Witness_PlainField(), runs: runs)
        let field = try XCTUnwrap(nodes.first { $0.0.kind == "TextField" })
        if case .image = field.1.primitives[0] { XCTFail("plain draws no bezel") }
        XCTAssertEqual(runs.asked.map(\.text), ["Enter"])
        XCTAssertEqual(runs.asked.map(\.color), [TextFieldColors.plainPlaceholder])
        XCTAssertEqual(field.0.pixelFrame.x, 0)
    }

    func testCommitPublishesTheFocusedFieldAndDrawsItsCaret() throws {
        let runs = NaturalRuns()
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: runs, log: { _ in })
        let graph = Graph(Witness_FocusedField(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        var record: CommitRecord?
        graph.commitSink = { record = $0 }
        graph.flush()
        _ = graph.applyInitialFocus()
        graph.flush()
        let root = try XCTUnwrap(record?.root)
        var sent: [SwiftRightBridge.Transaction] = []
        _ = try painter.commit(root: root, version: 1, previousLive: [], focused: record?.focused) { sent.append($0) }
        let tx = try XCTUnwrap(sent.first)
        let field = try XCTUnwrap(flatten(root).first { $0.kind == "TextField" })
        XCTAssertEqual(tx.focus, UInt64(field.instance + 1))
        let upsert = try XCTUnwrap(tx.upserts.first { $0.id == tx.focus })
        // initial focus selects the whole text: a selection rect is painted before the text
        XCTAssertTrue(upsert.primitives.contains { if case .rect = $0 { return true }; return false })
    }
}
