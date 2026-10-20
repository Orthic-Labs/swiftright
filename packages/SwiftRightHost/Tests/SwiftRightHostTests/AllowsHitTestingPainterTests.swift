import XCTest
import SwiftRightHost
import SwiftRightBridge

// SR2 R1 (#36): `.allowsHitTesting(false)` removes the hit-target flag the renderer hit-tests with, on the node and its subtree; painting and accessibility actions stay.

private struct Witness_HitTesting: View {
    var body: some View {
        VStack(spacing: 8) {
            Button("Off") {}.allowsHitTesting(false)
            Button("On") {}
            VStack { Rectangle().fill(Color.red).frame(width: 60, height: 24).onTapGesture {} }.allowsHitTesting(false)
            Rectangle().fill(Color.blue).frame(width: 60, height: 24).onTapGesture {}
            Button("Nested") {}.allowsHitTesting(true).opacity(1).allowsHitTesting(false)
        }
    }
}

@MainActor
final class AllowsHitTestingPainterTests: XCTestCase {
    private func paint<V: View>(_ view: V, scale: CGFloat = 2.5) throws -> [(ResolvedNode, NodeEmission)] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: Float(scale), text: FakeRuns(), log: { _ in })
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
        return out
    }

    func testAHitTestingOffSubtreeEmitsNoHitTargetsButKeepsItsActionsAndPainting() throws {
        let nodes = try paint(Witness_HitTesting())
        let buttons = nodes.filter { $0.0.kind == "Button" }
        XCTAssertEqual(buttons.count, 3)
        XCTAssertFalse(buttons[0].1.flags.contains(.hitTarget), "Off")
        XCTAssertTrue(buttons[1].1.flags.contains(.hitTarget), "On is unaffected")
        XCTAssertFalse(buttons[2].1.flags.contains(.hitTarget), "an ancestor's false cannot be undone below")
        XCTAssertTrue(buttons[0].1.semantic?.actions.contains(.invoke) == true, "accessibility still invokes it (SwiftUI)")
        XCTAssertEqual(buttons[0].1.semantic?.disabled, false)

        let taps = nodes.filter { $0.0.kind == "modifier.onTapGesture" }
        XCTAssertEqual(taps.count, 2)
        XCTAssertFalse(taps[0].1.flags.contains(.hitTarget), "tap gesture under an off subtree")
        XCTAssertTrue(taps[1].1.flags.contains(.hitTarget))
        XCTAssertEqual(nodes.filter { $0.1.flags.contains(.hitTarget) }.count, 2, "exactly the On button and the second tap gesture")
    }
}
