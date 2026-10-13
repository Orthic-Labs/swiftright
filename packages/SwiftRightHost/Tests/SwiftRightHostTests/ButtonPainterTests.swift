import XCTest
import SwiftRightHost
import SwiftRightBridge

private struct Witness_ButtonView: View {
    var body: some View { Button("Run") {} }
}

private struct Witness_DisabledButtonView: View {
    var body: some View { Button("Run") {}.disabled(true) }
}

/// A Button is one image primitive (the bordered push button artwork) plus button semantics; its label paints itself in the button's label colour.
@MainActor
final class ButtonPainterTests: XCTestCase {
    private func paint<V: View>(_ view: V, runs fakeRuns: FakeRuns? = nil) throws -> (nodes: [(ResolvedNode, NodeEmission)], images: FakeImages, runs: FakeRuns) {
        let runs = fakeRuns ?? FakeRuns()
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: runs, log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let root = try XCTUnwrap(graph.snapshot())
        var out: [(ResolvedNode, NodeEmission)] = []
        // walk through commit so the label colour is inherited exactly as in a window
        _ = try painter.commit(root: root, version: 1, previousLive: [], submit: { _ in })        // `runs` records what the commit asked for
        let emitImages = FakeImages()
        let emitPainter = ResolvedNodePainter(images: emitImages, scale: 2.5, text: FakeRuns(), log: { _ in })
        emitPainter.beginCommit()
        for n in flatten(root) {
            let b = Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
            out.append((n, try emitPainter.emit(n, id: UInt64(n.instance + 1), bounds: b)))
        }
        emitPainter.endCommit(committed: true)
        return (out, emitImages, runs)
    }

    func testButtonPaintsOneImageAndButtonSemantics() throws {
        let r = try paint(Witness_ButtonView())
        let button = try XCTUnwrap(r.nodes.first { $0.0.kind == "Button" })
        guard case .image(let handle, _, _) = try XCTUnwrap(button.1.primitives.first) else { return XCTFail("a button is an image primitive") }
        XCTAssertEqual(button.1.primitives.count, 1)
        let entry = try XCTUnwrap(r.images.registered[handle.raw])
        XCTAssertEqual(entry.width, UInt32(button.0.pixelFrame.width))
        XCTAssertEqual(Float(entry.height), 60, "a 24 pt body-text button is 60 px tall at scale 2.5")
        XCTAssertEqual(button.1.semantic?.role, .button)
        XCTAssertEqual(button.1.semantic?.actions, [.invoke])
        XCTAssertEqual(button.1.semantic?.disabled, false)
        XCTAssertEqual(button.1.flags, [.hitTarget])
    }

    func testTheLabelTakesTheButtonsLabelColour() throws {
        let enabled = try paint(Witness_ButtonView()), disabled = try paint(Witness_DisabledButtonView())
        XCTAssertEqual(enabled.runs.colours, [0x242424ff])
        XCTAssertEqual(disabled.runs.colours, [0xb6b6b6ff])
    }

    func testDisabledButtonIsFlaggedOffersNoActionAndHasADifferentFill() throws {
        let r = try paint(Witness_DisabledButtonView())
        let button = try XCTUnwrap(r.nodes.first { $0.0.kind == "Button" })
        XCTAssertEqual(button.1.semantic?.disabled, true)
        XCTAssertEqual(button.1.semantic?.actions, [])
        let enabled = try paint(Witness_ButtonView())
        XCTAssertNotEqual(try XCTUnwrap(r.images.registered.values.first).rgba, try XCTUnwrap(enabled.images.registered.values.first).rgba)
    }

    func testButtonFrameIsLabelPlusPadding() throws {
        let r = try paint(Witness_ButtonView())
        let button = try XCTUnwrap(r.nodes.first { $0.0.kind == "Button" }).0
        let label = try XCTUnwrap(flatten(button).first { $0.kind == "Text" })
        XCTAssertEqual(Double(button.pixelFrame.width - label.pixelFrame.width), 24 * 2.5, accuracy: 1.0)
        XCTAssertEqual(Double(button.pixelFrame.height - label.pixelFrame.height), 8 * 2.5, accuracy: 1.0)
        XCTAssertEqual(Double(label.pixelFrame.x - button.pixelFrame.x), 12 * 2.5, accuracy: 1.0)
    }
}
