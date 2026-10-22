@testable import SwiftRightRuntime
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

    // Values from SwiftUI's KeyframeTimeline on macOS 27 (value(time:) of a single track starting at 0), 22 Oct 2026.
    private func value(at t: Double, _ segments: [KeyframeSegment<Double>]) -> Double {
        var start = 0.0, velocity = 0.0, elapsed = 0.0
        for segment in segments {
            if t < elapsed + segment.duration { return segment.evaluate(start, velocity, t - elapsed).0 }
            let end = segment.evaluate(start, velocity, segment.duration)
            (start, velocity) = (end.0, end.1); elapsed += segment.duration
        }
        return start
    }

    func testSpringKeyframesMatchSwiftUI() {
        let times = [0.1, 0.2, 0.3, 0.5, 0.75]
        let cases: [(String, [KeyframeSegment<Double>], [Double])] = [
            ("smooth", [SpringKeyframe(100, duration: 1, spring: .smooth).segment], [35.774, 71.542, 89.003, 98.640, 99.916]),
            ("bouncy", [SpringKeyframe(100, duration: 1, spring: .bouncy).segment], [42.330, 87.371, 103.393, 101.450, 99.819]),
            ("snappy", [SpringKeyframe(100, spring: .snappy).segment], [38.810, 78.637, 95.645, 100.602, 100.044]),
            ("custom", [SpringKeyframe(100, duration: 1.5, spring: Spring(duration: 0.4, bounce: 0.5)).segment], [64.733, 114.070, 110.012, 97.725, 100.309]),
        ]
        for (name, segments, expected) in cases {
            for (t, want) in zip(times, expected) { XCTAssertEqual(value(at: t, segments), want, accuracy: 0.1, "\(name) at \(t)") }
        }
    }

    func testLinearAndCubicMatchSwiftUI() {
        XCTAssertEqual(value(at: 0.3, [LinearKeyframe(100, duration: 1).segment]), 30, accuracy: 1e-9)
        for (t, want) in [(0.1, 2.8), (0.2, 10.4), (0.3, 21.6), (0.75, 84.375)] { XCTAssertEqual(value(at: t, [CubicKeyframe(100, duration: 1).segment]), want, accuracy: 1e-6) }
        for (t, want) in [(0.1, 6.85), (0.2, 16.8), (0.3, 28.95), (0.5, 56.25), (0.75, 86.719)] {
            XCTAssertEqual(value(at: t, [CubicKeyframe(100, duration: 1, startVelocity: 50, endVelocity: 0).segment]), want, accuracy: 0.01)
        }
    }

    func testSpringContinuesFromTheVelocityOfALinearKeyframe() {
        let segments = [LinearKeyframe(100.0, duration: 0.5).segment, SpringKeyframe(0.0, duration: 1, spring: .bouncy).segment]
        XCTAssertEqual(value(at: 0.75, segments), 3.524, accuracy: 0.1)
        XCTAssertEqual(value(at: 1.0, segments), -1.717, accuracy: 0.1)
    }
}
