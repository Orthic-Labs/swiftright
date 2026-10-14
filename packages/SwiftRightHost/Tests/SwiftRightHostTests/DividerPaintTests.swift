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

/// Block swiftui.spacer-divider: the Divider is the measured light separator (black at 25/255) over its snapped 1 pt box; dark is not measured and fails visibly.
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

    func testDarkDividerFailsVisiblyUntilItIsMeasured() throws {
        XCTAssertThrowsError(try emit(Witness_DarkDivider()))
    }
}
