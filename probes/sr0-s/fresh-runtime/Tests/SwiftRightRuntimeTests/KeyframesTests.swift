import SwiftRightRuntime
import XCTest

@MainActor
final class KeyframesTests: XCTestCase {
    struct Values { var x: Double = 0; var y: Double = 10 }

    private func text(_ g: Graph) -> String? { everyNode(g.snapshot()).first { $0.kind == "Text" }?.text }

    private func animated(repeating: Bool = false) -> Graph {
        let g = Graph(ZStack { Color.clear.frame(width: 10, height: 10).keyframeAnimator(initialValue: Values(), repeating: repeating) { view, v in
            ZStack { view; Text("\(Int(v.x.rounded())),\(Int(v.y.rounded()))") }
        } keyframes: { _ in
            KeyframeTrack(\.x) { LinearKeyframe(100, duration: 1); MoveKeyframe(0); LinearKeyframe(50, duration: 1) }
            KeyframeTrack(\.y) { CubicKeyframe(0, duration: 2) }
        } }, scale: 1)
        g.flush()
        return g
    }

    func testLinearMoveAndCubicTracksFollowTheHostClock() {
        let g = animated()
        g.tick(now: 10); g.flush()           // the first evaluation fixes the start
        XCTAssertEqual(text(g), "0,10")
        g.tick(now: 10.5); g.flush()
        XCTAssertEqual(text(g), "50,8", "x halfway to 100; y eased with zero end velocities: 10 + (0-10) * 0.5^... at u = .25")
        g.tick(now: 11.5); g.flush()
        XCTAssertEqual(text(g), "25,2")
        g.tick(now: 20); g.flush()
        XCTAssertEqual(text(g), "50,0", "held at the end")
    }

    func testRepeatingLoops() {
        let g = animated(repeating: true)
        g.tick(now: 0); g.flush()
        g.tick(now: 2.5); g.flush()           // total 2 s: back at 0.5 s
        XCTAssertEqual(text(g), "50,8")
    }

    func testSpringKeyframeSettlesOnItsTarget() {
        let g = Graph(ZStack { Color.clear.frame(width: 10, height: 10).keyframeAnimator(initialValue: Values(), repeating: false) { view, v in
            ZStack { view; Text("\(Int(v.x.rounded()))") }
        } keyframes: { _ in
            KeyframeTrack(\.x) { SpringKeyframe(100, duration: 1, spring: .bouncy) }
        } }, scale: 1)
        g.flush(); g.tick(now: 1); g.flush(); g.tick(now: 1.2); g.flush()
        let early = Int(text(g) ?? "") ?? -1
        XCTAssertTrue(early > 0 && early < 120, "moving toward 100: \(early)")
        g.tick(now: 30); g.flush()
        XCTAssertEqual(text(g), "100", "after the keyframe the value holds its target")
    }
}
