import XCTest
import SwiftRightBridge
@testable import SwiftRightHost
import SwiftRightRuntime

/// Issue #31 host wiring: the wheel's line conversion, the opt-in flag's effect on the scroller node, and the scroll bar semantic (present with a
/// range when the renderer publishes scroll bars, a plain painted node when it does not).
@MainActor
final class HostWheelTests: XCTestCase {
    // MARK: line conversion

    func testOneNotchIsThreeLinesAwayFromTheUserScrollingContentUp() {
        // Windows sign: deltaY 120 = the wheel moved away from the user, content scrolls UP, so the line count is negative (a positive count moves it down).
        XCTAssertEqual(HostScrollInput.lines(deltaY: 120, wheelScrollLines: 3), -3, accuracy: 1e-12)
        XCTAssertEqual(HostScrollInput.lines(deltaY: -120, wheelScrollLines: 3), 3, accuracy: 1e-12)
        XCTAssertEqual(HostScrollInput.lines(deltaY: 240, wheelScrollLines: 3), -6, accuracy: 1e-12)
    }

    func testPreciseDeltasGiveFractionalLines() {
        XCTAssertEqual(HostScrollInput.lines(deltaY: 60, wheelScrollLines: 3), -1.5, accuracy: 1e-12)
        XCTAssertEqual(HostScrollInput.lines(deltaY: -30, wheelScrollLines: 3), 0.75, accuracy: 1e-12)
    }

    func testTheUserLinesSettingScalesTheNotch() {
        XCTAssertEqual(HostScrollInput.lines(deltaY: 120, wheelScrollLines: 5), -5, accuracy: 1e-12)
        XCTAssertEqual(HostScrollInput.lines(deltaY: 120, wheelScrollLines: 0), 0, "wheel scrolling turned off")
        XCTAssertEqual(HostScrollInput.lines(deltaY: 0, wheelScrollLines: 3), 0)
    }

    func testPhysicalPixelsBecomeLogicalPoints() {
        XCTAssertEqual(HostScrollInput.points(500, scale: 2.5), 200, accuracy: 1e-9)
        XCTAssertEqual(HostScrollInput.points(300, scale: 1), 300, accuracy: 1e-9)
    }

    func testWheelEventDecodesItsDeltasAndPrecision() {
        let notch = BridgeEvent.wheel(x: 10, y: 20, deltaY: 120)
        XCTAssertEqual(notch.wheel, BridgeEvent.Wheel(x: 10, y: 20, deltaY: 120, deltaX: 0, precise: false))
        let touchpad = BridgeEvent.wheel(x: 10, y: 20, deltaY: 37, precise: true)
        XCTAssertEqual(touchpad.wheel?.precise, true)
        XCTAssertNil(BridgeEvent(kindRaw: BridgeEvent.Kind.pointer.rawValue, action: 1).wheel, "a press is not a wheel")
    }

    // MARK: opt-in and scroll bar semantic

    private func commit(_ view: some View, publishesScrollBars: Bool) throws -> (nodes: [NodeUpsert], painter: ResolvedNodePainter, graph: Graph) {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, publishesScrollBars: publishesScrollBars, log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var sent: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: []) { sent = $0.upserts }
        return (sent, painter, graph)
    }

    private var overflowing: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.red).frame(height: 40)
                Rectangle().fill(Color.green).frame(height: 40)
                Rectangle().fill(Color.purple).frame(height: 40)
            }
        }.frame(width: 120, height: 100)
    }

    private func scroller(_ nodes: [NodeUpsert]) throws -> NodeUpsert {
        try XCTUnwrap(nodes.first { $0.id & ResolvedNodePainter.scrollerNodeFlag != 0 })
    }

    func testScrollerPublishesARangedScrollBarOnlyWhenTheRendererTakesOne() throws {
        let supported = try scroller(try commit(overflowing, publishesScrollBars: true).nodes)
        let semantic = try XCTUnwrap(supported.semantic)
        XCTAssertEqual(semantic.role, .scrollBar)
        let range = try XCTUnwrap(semantic.range)
        XCTAssertEqual(range.value, 0, accuracy: 1e-9)
        XCTAssertEqual(range.min, 0); XCTAssertEqual(range.max, 1)
        XCTAssertEqual(range.step, 10 / 20, accuracy: 1e-9)             // one line (10 pt) over the 20 pt of offset travel (content 120, viewport 100)
        XCTAssertEqual(range.jump, 90 / 20, accuracy: 1e-9)             // page = viewport 100 less the 10 pt overlap, over the 20 pt of travel
        let plain = try scroller(try commit(overflowing, publishesScrollBars: false).nodes)
        XCTAssertNil(plain.semantic, "an older renderer gets a painted scroller with no role it would refuse")
        XCTAssertFalse(plain.primitives.isEmpty)
    }

    func testScrollBarValueFollowsTheOffset() throws {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, publishesScrollBars: true, log: { _ in })
        let graph = Graph(overflowing, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let view = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "ScrollView" })
        graph.scroll(view.id, to: 10); graph.flush()
        var sent: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 2, previousLive: []) { sent = $0.upserts }
        XCTAssertEqual(try XCTUnwrap(try scroller(sent).semantic?.range).value, 0.5, accuracy: 1e-9)
    }

    func testWheelScrollsTheContainerUnderThePointerAndReportsTheChange() throws {
        let (_, painter, graph) = try commit(overflowing, publishesScrollBars: true)
        let view = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "ScrollView" })
        // Points to physical px for the event: the wheel's position is physical px, the runtime works in root points.
        let inside = Float(view.frame.cgRect.midX * 2.5), insideY = Float(view.frame.cgRect.midY * 2.5)
        let w = try XCTUnwrap(BridgeEvent.wheel(x: inside, y: insideY, deltaY: -120).wheel)
        XCTAssertTrue(HostScrollInput.wheel(w, graph: graph, scale: painter.scale, wheelScrollLines: 3))
        graph.flush()
        // One notch away from the user is +3 lines (10 pt each): 30 pt, clamped to the 20 pt of travel.
        XCTAssertEqual(graph.scrollOffset(view.id) ?? -1, 20, accuracy: 1e-9)
        let outside = try XCTUnwrap(BridgeEvent.wheel(x: 0, y: 0, deltaY: -120).wheel)
        XCTAssertFalse(HostScrollInput.wheel(outside, graph: graph, scale: painter.scale, wheelScrollLines: 3))
        XCTAssertFalse(HostScrollInput.wheel(w, graph: graph, scale: painter.scale, wheelScrollLines: 0), "wheel scrolling turned off")
    }

    func testScrollBarPressDragAndReleaseMoveTheThumb() throws {
        let (_, painter, graph) = try commit(overflowing, publishesScrollBars: true)
        let pointer = HostScrollBarPointer()
        let strip = try XCTUnwrap(painter.scrollerLayouts.values.first?.strip)
        let thumb = try XCTUnwrap(painter.scrollerLayouts.values.first?.thumb)
        let x = Float(strip.x + 2), startY = Float(thumb.y + thumb.h / 2)
        XCTAssertFalse(pointer.press(x: 5, y: startY, graph: graph, painter: painter), "outside every strip")
        XCTAssertTrue(pointer.press(x: x, y: startY, graph: graph, painter: painter))
        XCTAssertNotNil(pointer.dragging)
        XCTAssertTrue(pointer.move(y: startY + 20, graph: graph, painter: painter))
        pointer.release(graph: graph)
        XCTAssertNil(pointer.dragging)
        XCTAssertFalse(pointer.move(y: startY + 40, graph: graph, painter: painter), "no drag after the release")
    }
}
