import XCTest
import SwiftRightHost
import SwiftRightBridge

// Round 6: what the painter publishes for a Slider (ABI 0.9 range, control bounds) and for a view with a tap gesture (one pressable node per leaf, decision H8).

private struct Witness_SliderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: .constant(40), in: 0...100).frame(width: 200)
            Slider(value: .constant(0.5), in: 0...1, step: 0.25) { Text("Volume") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            Slider(value: .constant(30), in: 0...100).frame(width: 200).disabled(true)
        }.frame(width: 240)
    }
}

private struct Witness_TapLeaves: View {
    @State private var count = 0
    var body: some View {
        VStack(spacing: 8) {
            Rectangle().fill(Color.red).frame(width: 60, height: 24).onTapGesture { count += 1 }
            Text("Tap me").frame(width: 60, height: 24).onTapGesture { count += 10 }
            VStack { Rectangle().fill(Color.blue).frame(width: 60, height: 24).onTapGesture { count += 100 } }
            Rectangle().fill(Color.green).frame(width: 60, height: 24).onHover { _ in }
        }
    }
}

@MainActor
final class SliderGesturePainterTests: XCTestCase {
    private func paint<V: View>(_ view: V, scale: CGFloat = 2.5) throws -> [(ResolvedNode, NodeEmission)] {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: Float(scale), text: FakeRuns(), log: { _ in })
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

    func testASliderPublishesItsRangeAndItsControlBounds() throws {
        let nodes = try paint(Witness_SliderView())
        let sliders = nodes.filter { $0.0.kind == "SliderControl" }
        XCTAssertEqual(sliders.count, 3)
        let first = try XCTUnwrap(sliders[0].1.semantic)
        XCTAssertEqual(first.role, .slider)
        XCTAssertEqual(first.value, "40")
        XCTAssertEqual(first.range, SliderRange(value: 40, min: 0, max: 100, step: 10, jump: 10))
        XCTAssertFalse(first.disabled)
        XCTAssertEqual(sliders[0].1.primitives.count, 1)                     // one image: the whole control
        XCTAssertEqual(sliders[0].1.bounds?.w, 500); XCTAssertEqual(sliders[0].1.bounds?.h, 40)

        // stepped: the arrow key moves by the step; a label and value labels are separate nodes around the control, the control's bounds exclude them
        let stepped = try XCTUnwrap(sliders[1].1.semantic)
        XCTAssertEqual(stepped.range, SliderRange(value: 0.5, min: 0, max: 1, step: 0.25, jump: 0.25))
        XCTAssertEqual(stepped.value, "0.5")
        let steppedBounds = try XCTUnwrap(sliders[1].1.bounds)
        XCTAssertLessThan(steppedBounds.w, Float(sliders[1].0.pixelFrame.width) + 1)
        XCTAssertEqual(nodes.filter { $0.0.kind == "Button" }.count, 2, "the value labels are buttons")
        XCTAssertEqual(nodes.filter { $0.0.kind == "Text" && $0.0.text == "Volume" }.count, 1)

        let disabled = try XCTUnwrap(sliders[2].1.semantic)
        XCTAssertTrue(disabled.disabled)
        XCTAssertTrue(disabled.actions.isEmpty)
    }

    func testAViewWithATapGestureIsOnePressableNode() throws {
        let nodes = try paint(Witness_TapLeaves())
        let pressable = nodes.filter { $0.1.semantic?.actions.contains(.invoke) == true }
        XCTAssertEqual(pressable.count, 3, "one pressable node per tap-gesture leaf (the hover leaf is not pressable)")
        XCTAssertTrue(pressable.allSatisfy { $0.1.semantic?.role == .button && $0.1.flags.contains(.hitTarget) })
        // the text of a tapped view names the node (the committed tree publishes no node of its own for it, as for a Button's label)
        XCTAssertNotNil(pressable.first { $0.1.semantic?.label == "Tap me" })
    }
}
