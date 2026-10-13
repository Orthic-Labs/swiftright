import XCTest
import SwiftRightHost
import SwiftRightBridge

private struct Witness_HiddenSwitchView: View {
    @State private var on: Bool
    init(on: Bool) { _on = State(wrappedValue: on) }
    var body: some View { Toggle("Enabled", isOn: $on).labelsHidden().toggleStyle(.switch) }
}

private struct Witness_LabelledSwitchView: View {
    @State private var on = true
    var body: some View { Toggle("Enabled", isOn: $on).toggleStyle(.switch) }
}

private struct Witness_DisabledSwitchView: View {
    @State private var on = true
    var body: some View { Toggle("Enabled", isOn: $on).labelsHidden().toggleStyle(.switch).disabled(true) }
}

private struct Witness_UnstyledToggleView: View {
    @State private var on = true
    var body: some View { Toggle("Enabled", isOn: $on).labelsHidden() }
}

/// A Toggle with `.switch` becomes one image primitive (the switch artwork) plus switch semantics; the label paints itself.
@MainActor
final class TogglePainterTests: XCTestCase {
    private func paint<V: View>(_ view: V, scale: CGFloat = 2.5) throws -> (nodes: [(ResolvedNode, NodeEmission)], images: FakeImages) {
        let images = FakeImages()
        let runs = FakeRuns()
        let painter = ResolvedNodePainter(images: images, scale: Float(scale), text: runs, log: { _ in })
        let graph = Graph(view, scale: scale)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        painter.beginCommit()
        var out: [(ResolvedNode, NodeEmission)] = []
        for n in flatten(try XCTUnwrap(graph.snapshot())) {
            let b = Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
            out.append((n, try painter.emit(n, id: UInt64(n.instance + 1), bounds: b)))
        }
        painter.endCommit(committed: true)
        return (out, images)
    }

    func testSwitchWithoutLabelPaintsOneImageOverItsFrame() throws {
        let r = try paint(Witness_HiddenSwitchView(on: true))
        let toggle = try XCTUnwrap(r.nodes.first { $0.0.kind == "Toggle" })
        guard case .image(let handle, let rect, _) = try XCTUnwrap(toggle.1.primitives.first) else { return XCTFail("a switch is an image primitive") }
        XCTAssertEqual(toggle.1.primitives.count, 1)
        let entry = try XCTUnwrap(r.images.registered[handle.raw])
        XCTAssertEqual(entry.width, 135); XCTAssertEqual(entry.height, 60)
        XCTAssertEqual(rect.x, Float(toggle.0.pixelFrame.x) + 1.0 / 64, accuracy: 1e-5)
        XCTAssertEqual(rect.w, 135 - 2.0 / 64, accuracy: 1e-5)
        XCTAssertEqual(toggle.1.semantic?.role, .switchControl)
        XCTAssertEqual(toggle.1.semantic?.toggled, .on)
        XCTAssertEqual(toggle.1.semantic?.value, "1")
        XCTAssertEqual(toggle.1.semantic?.label, "Enabled")
        XCTAssertEqual(toggle.1.semantic?.actions, [.invoke])
        XCTAssertEqual(toggle.1.semantic?.disabled, false)
        XCTAssertEqual(toggle.1.flags, [.hitTarget])
    }

    func testOffSwitchReportsOffAndDrawsADifferentImage() throws {
        let on = try paint(Witness_HiddenSwitchView(on: true)), off = try paint(Witness_HiddenSwitchView(on: false))
        let offToggle = try XCTUnwrap(off.nodes.first { $0.0.kind == "Toggle" })
        XCTAssertEqual(offToggle.1.semantic?.toggled, .off)
        XCTAssertEqual(offToggle.1.semantic?.value, "0")
        let onBytes = try XCTUnwrap(on.images.registered.values.first).rgba, offBytes = try XCTUnwrap(off.images.registered.values.first).rgba
        XCTAssertNotEqual(onBytes, offBytes)
    }

    func testDisabledSwitchIsFlaggedAndOffersNoAction() throws {
        let r = try paint(Witness_DisabledSwitchView())
        let toggle = try XCTUnwrap(r.nodes.first { $0.0.kind == "Toggle" })
        XCTAssertEqual(toggle.1.semantic?.disabled, true)
        XCTAssertEqual(toggle.1.semantic?.actions, [])
        let enabled = try paint(Witness_HiddenSwitchView(on: true))
        XCTAssertNotEqual(try XCTUnwrap(r.images.registered.values.first).rgba, try XCTUnwrap(enabled.images.registered.values.first).rgba,
                          "disabled colours differ from enabled ones")
    }

    func testControlTrailsItsLabel() throws {
        let r = try paint(Witness_LabelledSwitchView())
        let toggle = try XCTUnwrap(r.nodes.first { $0.0.kind == "Toggle" })
        let label = try XCTUnwrap(r.nodes.first { $0.0.kind == "Text" })
        guard case .image(_, let rect, _) = try XCTUnwrap(toggle.1.primitives.first) else { return XCTFail() }
        XCTAssertEqual(Float(label.0.pixelFrame.x), Float(toggle.0.pixelFrame.x))
        XCTAssertEqual(rect.x + rect.w, Float(toggle.0.pixelFrame.x + toggle.0.pixelFrame.width) - 1.0 / 64, accuracy: 1e-4)
        XCTAssertGreaterThan(rect.x, Float(label.0.pixelFrame.x + label.0.pixelFrame.width))
        XCTAssertEqual(label.1.primitives.count, 1)
    }

    func testToggleWithoutSwitchStyleFailsVisibly() {
        XCTAssertThrowsError(try paint(Witness_UnstyledToggleView())) { XCTAssertTrue(String(describing: $0).contains("no artwork yet"), "\($0)") }
    }

    func testRepaintReleasesTheReplacedImage() throws {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: nil, log: { _ in })
        let graph = Graph(Witness_HiddenSwitchView(on: true), scale: 2.5)
        graph.flush()
        let toggleNode = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "Toggle" })
        let bounds = Rect(x: 0, y: 0, w: 135, h: 60)
        for _ in 0..<2 {
            painter.beginCommit(); _ = try painter.emit(toggleNode, id: 5, bounds: bounds); painter.endCommit(committed: true)
        }
        XCTAssertEqual(images.live.count, 1)
        painter.releaseAll(); XCTAssertEqual(images.live.count, 0)
    }
}
