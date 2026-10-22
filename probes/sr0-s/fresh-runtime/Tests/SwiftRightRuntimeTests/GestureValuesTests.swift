import SwiftRightRuntime
import XCTest

@MainActor
final class GestureValuesTests: XCTestCase {
    private func graph<V: View>(_ v: V) -> Graph { let g = Graph(v.frame(width: 100, height: 100), scale: 1); g.flush(); return g }

    func testDragReportsAfterTheMinimumDistanceAndEnds() {
        var changes: [DragGesture.Value] = [], ended: DragGesture.Value?
        let g = graph(Color.red.gesture(DragGesture().onChanged { changes.append($0) }.onEnded { ended = $0 }))
        g.pointerPressed(atX: 20, y: 30)
        g.pointerDragged(toX: 24, y: 30)
        XCTAssertTrue(changes.isEmpty, "4 pt is under the minimum distance")
        g.pointerDragged(toX: 40, y: 50)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].startLocation, CGPoint(x: 20, y: 30))
        XCTAssertEqual(changes[0].translation, CGSize(width: 20, height: 20))
        g.pointerDragged(toX: 60, y: 50)
        g.pointerReleased(atX: 60, y: 50)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(ended?.translation, CGSize(width: 40, height: 20))
    }

    func testDragWithoutMovementDoesNotEnd() {
        var ended = false
        let g = graph(Color.red.gesture(DragGesture(minimumDistance: 0).onEnded { _ in ended = true }))
        g.pointerPressed(atX: 10, y: 10)
        g.pointerReleased(atX: 10, y: 10)
        XCTAssertFalse(ended, "a drag with no move never began")
    }

    func testTapAndSpatialTap() {
        var taps = 0, at: CGPoint?
        let g = graph(Color.red.gesture(TapGesture().onEnded { taps += 1 }).simultaneousGesture(SpatialTapGesture().onEnded { at = $0.location }))
        g.pointerPressed(atX: 25, y: 35); g.pointerReleased(atX: 25, y: 35)
        XCTAssertEqual(taps, 1)
        XCTAssertEqual(at, CGPoint(x: 25, y: 35))
        g.pointerPressed(atX: 25, y: 35); g.pointerDragged(toX: 60, y: 35); g.pointerReleased(atX: 60, y: 35)
        XCTAssertEqual(taps, 1, "a press that moved is not a tap")
    }

    func testDoubleTapNeedsTwoQuickTaps() {
        var taps = 0
        let g = graph(Color.red.gesture(TapGesture(count: 2).onEnded { taps += 1 }))
        g.pointerPressed(atX: 5, y: 5); g.pointerReleased(atX: 5, y: 5)
        XCTAssertEqual(taps, 0)
        g.pointerPressed(atX: 5, y: 5); g.pointerReleased(atX: 5, y: 5)
        XCTAssertEqual(taps, 1)
    }

    func testChildGestureHidesParentButSimultaneousStillRuns() {
        var log: [String] = []
        let g = graph(VStack(spacing: 0) {
            Color.red.frame(width: 100, height: 100).gesture(TapGesture().onEnded { log.append("child") })
        }.gesture(TapGesture().onEnded { log.append("parent") }).simultaneousGesture(TapGesture().onEnded { log.append("simul") }))
        g.pointerPressed(atX: 50, y: 50); g.pointerReleased(atX: 50, y: 50)
        XCTAssertEqual(log.sorted(), ["child", "simul"])
    }

    func testHighPriorityBeatsTheChild() {
        var log: [String] = []
        let g = graph(Color.red.frame(width: 100, height: 100).gesture(TapGesture().onEnded { log.append("child") }).highPriorityGesture(TapGesture().onEnded { log.append("high") }))
        g.pointerPressed(atX: 50, y: 50); g.pointerReleased(atX: 50, y: 50)
        XCTAssertEqual(log.sorted(), ["child", "high"], "both modifiers sit on the same view: high priority plus the plain gesture")
    }

    func testOutsideThePointIsIgnored() {
        var taps = 0
        let g = Graph(HStack(spacing: 0) { Color.red.frame(width: 50, height: 50).gesture(TapGesture().onEnded { taps += 1 }); Color.blue.frame(width: 50, height: 50) }, scale: 1)
        g.flush()
        g.pointerPressed(atX: 75, y: 25); g.pointerReleased(atX: 75, y: 25)
        XCTAssertEqual(taps, 0)
    }

    func testContinuousHoverReportsLocationsAndTheEnd() {
        var phases: [HoverPhase] = []
        let g = Graph(Color.red.frame(width: 50, height: 50).onContinuousHover { phases.append($0) }, scale: 1)
        g.flush()
        g.pointerMoved(toX: 10, y: 20)
        g.pointerMoved(toX: 15, y: 22)
        g.pointerMoved(toX: 200, y: 200)
        XCTAssertEqual(phases, [.active(CGPoint(x: 10, y: 20)), .active(CGPoint(x: 15, y: 22)), .ended])
    }
}
