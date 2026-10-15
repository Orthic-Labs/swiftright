import SwiftRightRuntime
import XCTest

// Round 6 block 37: Slider (decisions H1, H2). Layout, value model, pointer / key / accessibility routes.

private final class Box { var value = 40.0; var edits: [Bool] = [] }

private struct Plain: View {
    let box: Box
    @State private var v = 40.0
    var body: some View {
        Slider(value: Binding(get: { box.value }, set: { box.value = $0; v = $0 }), in: 0...100, onEditingChanged: { box.edits.append($0) }).frame(width: 200)
    }
}

private struct Stepped: View {
    let box: Box
    @State private var v = 40.0
    var body: some View {
        Slider(value: Binding(get: { box.value }, set: { box.value = $0; v = $0 }), in: 0...100, step: 10, onEditingChanged: { box.edits.append($0) }).frame(width: 200)
    }
}

private struct Labelled: View {
    let box: Box
    @State private var v = 40.0
    var body: some View {
        VStack(alignment: .leading) {
            Slider(value: Binding(get: { box.value }, set: { box.value = $0; v = $0 }), in: 0...100) { Text("Volume") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("100") }
        }.frame(width: 240)
    }
}

@MainActor
final class SliderBlockTests: XCTestCase {
    private func make(_ view: some View, scale: CGFloat = 2.5) -> Graph {
        let graph = Graph(view, scale: scale)
        graph.flush()
        return graph
    }
    private func slider(_ g: Graph) -> ResolvedNode? { everyNode(g.snapshot()).first { $0.kind == "Slider" } }

    func testGeometryIsTheMeasuredOne() throws {
        let g = make(Plain(box: Box()))
        let n = try XCTUnwrap(slider(g))
        XCTAssertEqual(n.frame.width, 200); XCTAssertEqual(n.frame.height, 16)
        XCTAssertEqual(n.pixelFrame.width, 500); XCTAssertEqual(n.pixelFrame.height, 40)
        let s = try XCTUnwrap(n.slider)
        XCTAssertEqual(s.trackPixelFrame.width, 500)
        XCTAssertEqual(s.value, 40)
        XCTAssertEqual(s.thumbOffsetPixels, 180)             // 0.4 * 450
        XCTAssertEqual(n.accessibility.role, "slider")
        XCTAssertEqual(n.accessibility.value, "40")
    }

    func testThumbOffsetIsRoundHalfUp() {
        // decision H2: floor(t * 450 + 0.5); 0.25 * 450 = 112.5 -> 113, 0.5 -> 225
        XCTAssertEqual(Graph.thumbOffsetPixels(fraction: 0.25, trackPixelWidth: 500, thumbPixels: 50), 113)
        XCTAssertEqual(Graph.thumbOffsetPixels(fraction: 0.5, trackPixelWidth: 500, thumbPixels: 50), 225)
        XCTAssertEqual(Graph.thumbOffsetPixels(fraction: 0, trackPixelWidth: 500, thumbPixels: 50), 0)
        XCTAssertEqual(Graph.thumbOffsetPixels(fraction: 1, trackPixelWidth: 500, thumbPixels: 50), 450)
    }

    func testIdealWidthIsThirtyAndLabelsAreMeasuredSizes() throws {
        let box = Box()
        let alone = make(Slider(value: Binding(get: { box.value }, set: { box.value = $0 }), in: 0...100))
        XCTAssertEqual(try XCTUnwrap(slider(alone)).frame.width, 30)
        XCTAssertEqual(try XCTUnwrap(slider(alone)).frame.height, 16)
    }

    func testLabelsSitAtTheEndsAndTheTrackTakesTheRest() throws {
        let g = make(Labelled(box: Box()))
        let n = try XCTUnwrap(slider(g))
        let s = try XCTUnwrap(n.slider)
        XCTAssertEqual(n.frame.width, 240)
        XCTAssertEqual(n.children.count, 3)
        let label = n.children[0], lo = n.children[1], hi = n.children[2]
        XCTAssertEqual(label.frame.minX, n.frame.minX)
        XCTAssertEqual(lo.frame.minX, label.frame.maxX + 8, accuracy: 0.5)
        XCTAssertEqual(s.trackFrame.minX, lo.frame.maxX + 4, accuracy: 0.5)
        XCTAssertEqual(hi.frame.minX, s.trackFrame.maxX + 4, accuracy: 0.5)
        XCTAssertEqual(hi.frame.maxX, n.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(n.accessibility.label, "Volume")
    }

    func testPressOnTheTrackPutsTheThumbCentreThere() throws {
        let box = Box(); let g = make(Plain(box: box))
        let n = try XCTUnwrap(slider(g))
        let x0 = n.frame.minX
        // x = 100 pt from the left edge: centre of the 180 pt travel (10 .. 190) -> 50
        XCTAssertTrue(g.sliderPress(n.id, atX: x0 + 100))
        XCTAssertEqual(box.value, 50, accuracy: 1e-9)
        XCTAssertEqual(box.edits, [true])
        XCTAssertTrue(g.sliderRelease(n.id))
        XCTAssertEqual(box.edits, [true, false])
        // clamped at both ends
        XCTAssertTrue(g.sliderPress(n.id, atX: x0 + 3)); XCTAssertEqual(box.value, 0); g.sliderRelease(n.id)
        XCTAssertTrue(g.sliderPress(n.id, atX: x0 + 199)); XCTAssertEqual(box.value, 100); g.sliderRelease(n.id)
    }

    func testDragStartedOnTheThumbKeepsTheGrabOffset() throws {
        let box = Box(); box.value = 50; let g = make(Plain(box: box))
        let n = try XCTUnwrap(slider(g))
        let x0 = n.frame.minX
        // thumb centre at 10 + 0.5 * 180 = 100; press 6 pt right of it: no jump
        XCTAssertTrue(g.sliderPress(n.id, atX: x0 + 106)); XCTAssertEqual(box.value, 50, accuracy: 1e-9)
        XCTAssertTrue(g.sliderDrag(n.id, toX: x0 + 106 + 36)); XCTAssertEqual(box.value, 70, accuracy: 1e-9)
        XCTAssertTrue(g.sliderRelease(n.id))
        XCTAssertFalse(g.sliderDrag(n.id, toX: x0 + 10), "no drag after the release")
    }

    func testSteppedValuesSnapAndKeysMoveByTheStep() throws {
        let box = Box(); let g = make(Stepped(box: box))
        let n = try XCTUnwrap(slider(g))
        XCTAssertTrue(g.sliderPress(n.id, atX: n.frame.minX + 10 + 0.33 * 180)); XCTAssertEqual(box.value, 30, accuracy: 1e-9); g.sliderRelease(n.id)
        XCTAssertTrue(g.sliderAdjust(n.id, by: 1)); XCTAssertEqual(box.value, 40)
        XCTAssertTrue(g.sliderAdjust(n.id, by: -2)); XCTAssertEqual(box.value, 20)
        XCTAssertTrue(g.sliderAdjust(n.id, by: 20)); XCTAssertEqual(box.value, 100, "clamped")
        XCTAssertTrue(g.sliderSet(n.id, toBound: false)); XCTAssertEqual(box.value, 0)
    }

    func testUnsteppedKeyMovesATenthOfTheRange() throws {
        let box = Box(); let g = make(Plain(box: box))
        let n = try XCTUnwrap(slider(g))
        XCTAssertTrue(g.sliderAdjust(n.id, by: 1)); XCTAssertEqual(box.value, 50, accuracy: 1e-9)
        XCTAssertTrue(g.sliderAdjust(n.id, by: -1)); XCTAssertEqual(box.value, 40, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(slider(g)?.slider).smallChange, 10)
    }

    func testDisabledSliderRefusesEverything() throws {
        let box = Box()
        let g = make(Slider(value: Binding(get: { box.value }, set: { box.value = $0 }), in: 0...100).frame(width: 200).disabled(true))
        let n = try XCTUnwrap(slider(g))
        XCTAssertFalse(n.accessibility.isEnabled)
        XCTAssertFalse(g.sliderPress(n.id, atX: n.frame.minX + 100))
        XCTAssertFalse(g.sliderAdjust(n.id, by: 1))
        XCTAssertEqual(box.value, 40)
    }

    func testFocusFollowsAPress() throws {
        let g = make(Plain(box: Box()))
        let n = try XCTUnwrap(slider(g))
        XCTAssertNil(g.focusedSliderID)
        g.sliderPress(n.id, atX: n.frame.minX + 50); g.sliderRelease(n.id)
        XCTAssertEqual(g.focusedSliderID, n.id)
        XCTAssertEqual(slider(g)?.slider?.isFocused, true)
    }
}
