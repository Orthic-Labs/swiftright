import XCTest
import SwiftRightHost
import SwiftRightBridge

private struct Witness_DividerColumn: View {
    var body: some View {
        VStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 100, height: 40); Divider(); Rectangle().fill(Color.blue).frame(width: 100, height: 40) }.frame(width: 100)
    }
}
private struct Witness_DarkDivider: View {
    var body: some View { Divider().frame(width: 100).environment(\.colorScheme, .dark) }
}
private struct Witness_FadedDivider: View {
    var body: some View { Divider().frame(width: 100).opacity(0.5) }
}

/// Block swiftui.spacer-divider: the Divider is the measured separator (black at 25/255 light, white at 25/255 dark) over its snapped 1 pt box.
@MainActor
final class DividerPaintTests: XCTestCase {
    private func emit<V: View>(_ view: V) throws -> [(ResolvedNode, NodeEmission)] {
        let images = FakeImages(), runs = FakeRuns()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: runs, log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        painter.beginCommit()
        var out: [(ResolvedNode, NodeEmission)] = []
        for n in flatten(try XCTUnwrap(graph.snapshot())) {
            let b = Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
            out.append((n, try painter.emit(n, id: UInt64(n.instance + 1), bounds: b)))
        }
        painter.endCommit(committed: true)
        return out
    }

    func testDividerPaintsTheSeparatorRectOverItsBox() throws {
        let nodes = try emit(Witness_DividerColumn())
        let divider = try XCTUnwrap(nodes.first { $0.0.kind == "Divider" })
        guard case .rect(let rect, let colour, _, _, _)? = divider.1.primitives.first else { return XCTFail("a Divider emits one rect") }
        XCTAssertEqual(colour, 0x00000019)
        XCTAssertEqual(rect.w, 250, "100 pt at scale 2.5")
        XCTAssertTrue(rect.h == 2 || rect.h == 3, "1 pt = 2.5 px snaps to 2 or 3 device pixels, got \(rect.h)")
        XCTAssertNil(divider.1.semantic)
    }

    func testDividerOpacityScalesTheSeparatorAlpha() throws {
        let nodes = try emit(Witness_FadedDivider())
        let divider = try XCTUnwrap(nodes.first { $0.0.kind == "Divider" })
        guard case .rect(_, let colour, _, _, _)? = divider.1.primitives.first else { return XCTFail("a Divider emits one rect") }
        XCTAssertEqual(colour, 0x0000000d, "25 x 0.5 rounded")
    }

    /// Round 5 block 31: measured on macOS 27 dark appearance (swiftui.paint-states/divider-dark-v1): white at alpha 25/255.
    func testDarkDividerIsWhiteAtAlpha25() throws {
        let nodes = try emit(Witness_DarkDivider())
        let divider = try XCTUnwrap(nodes.first { $0.0.kind == "Divider" })
        guard case .rect(_, let colour, _, _, _)? = divider.1.primitives.first else { return XCTFail("a Divider emits one rect") }
        XCTAssertEqual(colour, 0xffffff19)
    }

    /// A fully transparent fill draws nothing: the renderer paints a rect whose colour is 0 as opaque black (hub gap R12), so no rect is emitted for it.
    func testTransparentFillsEmitNoRect() throws {
        for view in [AnyView(Color.clear.frame(width: 10, height: 10)), AnyView(Color.black.opacity(0.001).frame(width: 10, height: 10)),
                     AnyView(Rectangle().fill(Color.red.opacity(0)).frame(width: 10, height: 10)), AnyView(Color.red.opacity(0.5).opacity(0).frame(width: 10, height: 10))] {
            let nodes = try emit(ZStack { view })
            for (n, e) in nodes where ["Color", "Rectangle"].contains(n.kind) { XCTAssertTrue(e.primitives.isEmpty, "\(n.kind) with alpha 0 emitted \(e.primitives)") }
        }
        let visible = try emit(Color.black.opacity(0.1).frame(width: 10, height: 10))
        XCTAssertEqual(visible.filter { $0.0.kind == "Color" }.first?.1.primitives.count, 1)
    }
}
