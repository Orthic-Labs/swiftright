import XCTest
import SwiftRightHost
import SwiftRightBridge

private struct Witness_DarkSwitchView: View {
    @State private var on: Bool
    init(on: Bool) { _on = State(wrappedValue: on) }
    var body: some View { Toggle("Enabled", isOn: $on).labelsHidden().toggleStyle(.switch).environment(\.colorScheme, .dark) }
}
private struct Witness_DarkCheckboxView: View {
    @State private var on: Bool
    init(on: Bool) { _on = State(wrappedValue: on) }
    var body: some View { Toggle("Enabled", isOn: $on).labelsHidden().environment(\.colorScheme, .dark) }
}
private struct Witness_SwatchesView: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.primary).frame(width: 10, height: 10)
            Rectangle().fill(.secondary).frame(width: 10, height: 10)
            Rectangle().fill(Color.accentColor).frame(width: 10, height: 10)
            Rectangle().fill(.background).frame(width: 10, height: 10)
            Rectangle().fill(Color.red).frame(width: 10, height: 10)
            Text("Hello")
        }
    }
}
private struct Witness_PreferredDarkView: View {
    var body: some View { Witness_SwatchesView().preferredColorScheme(.dark) }
}

/// Dark appearance: semantic colour tables and Toggle artwork, from numbers measured on macOS (docs/sr1-decisions.md, block 20).
@MainActor
final class ColorSchemePaintTests: XCTestCase {
    private func paint<V: View>(_ view: V, scale: CGFloat = 2.5) throws -> (nodes: [(ResolvedNode, NodeEmission)], images: FakeImages, runs: FakeRuns) {
        let images = FakeImages(), runs = FakeRuns()
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
        return (out, images, runs)
    }

    private func rectColours(_ r: [(ResolvedNode, NodeEmission)]) -> [UInt32] {
        r.compactMap { pair -> UInt32? in
            guard pair.0.kind == "Rectangle", case .rect(_, let color, _, _, _)? = pair.1.primitives.first else { return nil }
            return color
        }
    }

    func testSemanticColoursLight() throws {
        let colours = rectColours(try paint(Witness_SwatchesView()).nodes)
        XCTAssertEqual(colours, [0x000000d8, 0x0000007f, 0x007affff, 0xffffffff, 0xff383cff])
    }

    func testSemanticColoursDarkViaPreferredColorScheme() throws {
        let r = try paint(Witness_PreferredDarkView())
        XCTAssertEqual(rectColours(r.nodes), [0xffffffd8, 0xffffff8c, 0x007affff, 0x1e1e1eff, 0xff4245ff])
    }

    func testDefaultTextTakesTheDarkLabelColourOnlyInDark() throws {
        XCTAssertEqual(try paint(Witness_PreferredDarkView()).runs.colours, [0xffffffd8])
        XCTAssertEqual(try paint(Witness_SwatchesView()).runs.colours, [nil])
    }

    func testDarkSwitchUsesTheDarkTrackAndTranslucentKnob() throws {
        func pixel(_ e: FakeImages.Entry, _ x: Int, _ y: Int) -> [UInt8] { Array(e.rgba[(y * Int(e.width) + x) * 4..<(y * Int(e.width) + x) * 4 + 4]) }
        let on = try XCTUnwrap(try paint(Witness_DarkSwitchView(on: true)).images.registered.values.first)
        XCTAssertEqual(pixel(on, 20, 30), [0x06, 0x7e, 0xff, 255])     // flat track, left of the trailing knob
        XCTAssertEqual(pixel(on, 100, 30), [218, 236, 255, 255], "knob: white at 0.85 over the on track")
        let off = try XCTUnwrap(try paint(Witness_DarkSwitchView(on: false)).images.registered.values.first)
        XCTAssertEqual(pixel(off, 110, 30), [0x34, 0x34, 0x34, 255])
        XCTAssertEqual(pixel(off, 30, 30)[0], 225, accuracy: 1)
    }

    func testDarkCheckboxColours() throws {
        func pixel(_ e: FakeImages.Entry, _ x: Int, _ y: Int) -> [UInt8] { Array(e.rgba[(y * Int(e.width) + x) * 4..<(y * Int(e.width) + x) * 4 + 4]) }
        let on = try XCTUnwrap(try paint(Witness_DarkCheckboxView(on: true)).images.registered.values.first)
        XCTAssertEqual(pixel(on, 6, 30), [0x06, 0x7e, 0xff, 255])
        let off = try XCTUnwrap(try paint(Witness_DarkCheckboxView(on: false)).images.registered.values.first)
        XCTAssertEqual(pixel(off, 30, 30), [0x34, 0x34, 0x34, 255])
    }

    func testHostPaintTablesCoverEveryLightNameInDark() throws {
        for name in ["system.red", "system.blue", "system.yellow", "system.orange", "system.green", "system.purple", "system.pink", "system.gray", "label", "secondaryLabel", "accentColor", "background"] {
            XCTAssertNoThrow(try HostPaint.semantic(name, scheme: .dark), name)
            XCTAssertNoThrow(try HostPaint.semantic(name), name)
        }
        XCTAssertEqual(try HostPaint.semantic("black", scheme: .dark), 0x000000ff, "names without a dark variant resolve as in light")
    }
}
