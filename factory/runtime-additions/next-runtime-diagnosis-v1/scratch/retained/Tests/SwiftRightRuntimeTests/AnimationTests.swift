import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// Animation transactions on the injected clock (SR0-S F6 oracle, headless form). The Mac F6 fixture
// shows two overlapping animated inserts, both completing, with the final order settled. Geometry: 16 pt
// lines and 8 pt spacing, so line i sits at minY 24 * i once the list is settled.

@Observable
@MainActor
final class ListModel {
    var items: [String] = []
}

struct AnimatedListScreen: View {
    @Bindable var model: ListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.items, id: \.self) { item in
                Text(item)
            }
        }
    }
}

@Observable
@MainActor
final class OpacityModel {
    var value = 1.0
}

struct OpacityScreen: View {
    @Bindable var model: OpacityModel

    var body: some View {
        Text("fade").opacity(model.value)
    }
}

@MainActor
func textResolved(_ graph: Graph, _ text: String) -> ResolvedNode? {
    var nodes: [ResolvedNode] = []
    collect(graph.snapshot(), into: &nodes) { $0.kind == "Text" && $0.text == text }
    return nodes.first
}

@MainActor
final class AnimationTests: XCTestCase {

    // Insert under withAnimation: the existing line moves, the new line fades in, the completion runs
    // once when the animation finishes.
    func testAnimatedInsertInterpolatesFramesAndOpacityAndCompletesOnce() {
        let model = ListModel()
        model.items = ["A"]
        let graph = Graph(AnimatedListScreen(model: model))
        graph.flush()
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY, 0)

        var done = 0
        withAnimation(.linear(duration: 1.0)) {
            model.items.insert("B", at: 0)
        } completion: {
            done += 1
        }
        graph.flush()
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY, 0, "A starts where it was")
        XCTAssertEqual(textResolved(graph, "B")?.opacity, 0, "B starts transparent")
        XCTAssertEqual(done, 0)

        graph.tick(now: 0)  // the motion begins at the first tick
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY, 0, "progress 0")
        graph.tick(now: 0.5)
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY ?? -1, 12, accuracy: 1e-9, "A halfway to 24")
        XCTAssertEqual(textResolved(graph, "B")?.opacity ?? -1, 0.5, accuracy: 1e-9, "B halfway in")
        XCTAssertEqual(done, 0, "completion waits for the motion")

        graph.tick(now: 1.0)
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY ?? -1, 24, accuracy: 1e-9, "A settled at 24")
        XCTAssertEqual(textResolved(graph, "B")?.opacity, 1, "B fully visible")
        XCTAssertEqual(done, 1, "completion fires once")

        graph.tick(now: 2.0)
        XCTAssertEqual(done, 1, "completion does not fire again")
    }

    // A second animated insert mid-flight retargets from the presented value (interruption). The first
    // transaction's completion fires when it is superseded, and the second completes at its own end.
    func testInterruptionRetargetsFromPresentedValueAndCompletesEachTransactionOnce() {
        let model = ListModel()
        model.items = ["A"]
        let graph = Graph(AnimatedListScreen(model: model))
        graph.flush()

        var first = 0
        var second = 0
        withAnimation(.linear(duration: 1.0)) {
            model.items.insert("B", at: 0)
        } completion: {
            first += 1
        }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY ?? -1, 12, accuracy: 1e-9)

        withAnimation(.linear(duration: 1.0)) {
            model.items.insert("C", at: 0)
        } completion: {
            second += 1
        }
        graph.flush()
        XCTAssertEqual(first, 1, "superseded transaction completes")
        XCTAssertEqual(second, 0)
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY ?? -1, 12, accuracy: 1e-9,
                       "the new motion starts from the presented value, not the old target")

        graph.tick(now: 0.5)  // the second motion begins at the next tick
        graph.tick(now: 1.0)
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY ?? -1, 30, accuracy: 1e-9, "12 + (48 - 12) * 0.5")

        graph.tick(now: 1.5)
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY ?? -1, 48, accuracy: 1e-9, "A at 48 after both inserts")
        XCTAssertEqual(textResolved(graph, "C")?.frame.minY, 0)
        XCTAssertEqual(textResolved(graph, "B")?.frame.minY ?? -1, 24, accuracy: 1e-9)
        XCTAssertEqual(second, 1, "second completion fires once at its end")
        XCTAssertEqual(first, 1, "first completion did not fire again")
    }

    // Reduce motion: changes jump to their final values, and the completion is still delivered.
    func testReduceMotionJumpsToFinalValueAndStillCompletes() {
        let model = ListModel()
        model.items = ["A"]
        let graph = Graph(AnimatedListScreen(model: model))
        graph.flush()
        graph.setRootEnvironment { $0.accessibilityReduceMotion = true }
        graph.flush()

        var done = 0
        withAnimation(.linear(duration: 1.0)) {
            model.items.insert("B", at: 0)
        } completion: {
            done += 1
        }
        graph.flush()
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY, 24, "final layout at once")
        XCTAssertEqual(textResolved(graph, "B")?.opacity, 1, "no fade")
        XCTAssertEqual(done, 1, "completion delivered without any tick")

        graph.tick(now: 5)
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY, 24)
        XCTAssertEqual(done, 1)
    }

    // An opacity modifier animates its value under withAnimation.
    func testOpacityChangeInterpolates() {
        let model = OpacityModel()
        let graph = Graph(OpacityScreen(model: model))
        graph.flush()
        XCTAssertEqual(textResolved(graph, "fade")?.opacity, 1)

        withAnimation(.linear(duration: 1.0)) {
            model.value = 0
        }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.25)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity ?? -1, 0.75, accuracy: 1e-9)
        graph.tick(now: 1.0)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity, 0)
    }

    // MARK: Host clock (Windows F6, tuple 09)

    /// Opacity of the text `text` in each commit record, in order (nil when the node is not in the record).
    private func opacities(of text: String, in records: [CommitRecord]) -> [Double?] {
        records.map { record in
            var nodes: [ResolvedNode] = []
            collect(record.root, into: &nodes) { $0.kind == "Text" && $0.text == text }
            return nodes.first?.opacity
        }
    }

    /// Absolute host timestamps: a real display tick carries a monotonic clock (seconds since boot, here QPC-like 5398 s), not
    /// a count from zero. An animation begun before the first tick must still be drawn frame by frame, not finished by it.
    func testAnimationStartedBeforeFirstTickRunsFrameByFrameOnAnAbsoluteHostClock() {
        let model = ListModel()
        model.items = ["A"]
        let graph = Graph(AnimatedListScreen(model: model))
        var records: [CommitRecord] = []
        graph.commitSink = { records.append($0) }
        graph.flush()

        var done = 0
        withAnimation(.default, {
            model.items.insert("B", at: 0)
        }, completion: { done += 1 })
        graph.flush()
        XCTAssertEqual(done, 0, "the motion is running")
        records.removeAll()

        // 60 Hz display ticks, the first at an absolute host time. The default animation lasts 0.35 s.
        let base = 5398.255
        var tickCommits = 0
        for frame in 0..<40 {
            let before = records.count
            graph.tick(now: base + Double(frame) / 60)
            tickCommits += records.count - before
        }
        let fade = opacities(of: "B", in: records).compactMap { $0 }
        let intermediate = fade.filter { $0 > 0.001 && $0 < 0.999 }
        XCTAssertGreaterThanOrEqual(intermediate.count, 3, "fade frames committed: \(fade)")
        XCTAssertEqual(intermediate, intermediate.sorted(), "the fade only gets more opaque")
        XCTAssertEqual(fade.last, 1, "the last frame presents the target")
        XCTAssertGreaterThanOrEqual(tickCommits, 3, "frames come from display ticks")
        XCTAssertLessThanOrEqual(tickCommits, 24, "a tick commits only while a motion runs: 0.35 s is about 21 frames")
        XCTAssertEqual(done, 1, "completion fires once, after the last frame")
        XCTAssertEqual(textResolved(graph, "A")?.frame.minY ?? -1, 24, accuracy: 1e-9)
    }

    /// The motion's first frame is its start: progress is 0 at the first tick that sees it, whatever the host clock reads and
    /// however long ticks were off before.
    func testMotionBeginsAtTheFirstTickAfterItIsCreatedEvenAfterLongTickPause() {
        let model = OpacityModel()
        let graph = Graph(OpacityScreen(model: model))
        graph.flush()
        graph.tick(now: 100)
        graph.tick(now: 100.016)

        // Ticks were off for ten minutes; the animation starts at a flush between ticks.
        withAnimation(.linear(duration: 1.0)) {
            model.value = 0
        }
        graph.flush()
        XCTAssertEqual(textResolved(graph, "fade")?.opacity, 1, "a flush alone does not advance a motion")

        graph.tick(now: 700)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity ?? -1, 1, accuracy: 1e-9, "first tick is progress 0")
        graph.tick(now: 700.25)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity ?? -1, 0.75, accuracy: 1e-9)
        graph.tick(now: 701.0)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity, 0)
    }

    /// A flush between ticks (for example a model edit) leaves a not-yet-begun motion alone and does not end it.
    func testFlushBetweenTicksDoesNotBeginOrFinishAMotion() {
        let model = OpacityModel()
        let graph = Graph(OpacityScreen(model: model))
        graph.flush()
        graph.tick(now: 5000)

        var done = 0
        withAnimation(.linear(duration: 1.0), {
            model.value = 0
        }, completion: { done += 1 })
        graph.flush()
        graph.flush()
        graph.tick(now: 5000.5)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity ?? -1, 1, accuracy: 1e-9, "begins at this tick")
        graph.flush()
        graph.tick(now: 5001.0)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(done, 0)
        graph.tick(now: 5001.5)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity, 0)
        XCTAssertEqual(done, 1)
    }

    /// Reduce motion on a tick-driven host: no fade frame is ever committed and the completion is delivered at the commit.
    func testReduceMotionCommitsNoIntermediateFramesWhileTicksArrive() {
        let model = ListModel()
        model.items = ["A"]
        let graph = Graph(AnimatedListScreen(model: model))
        graph.setRootEnvironment { $0.accessibilityReduceMotion = true }
        var records: [CommitRecord] = []
        graph.commitSink = { records.append($0) }
        graph.flush()

        var done = 0
        withAnimation(.default, {
            model.items.insert("B", at: 0)
        }, completion: { done += 1 })
        graph.flush()
        XCTAssertEqual(done, 1)
        records.removeAll()
        for frame in 0..<40 { graph.tick(now: 5398.255 + Double(frame) / 60) }
        XCTAssertTrue(records.isEmpty, "no motion, so a tick commits nothing")
        let fade = opacities(of: "B", in: records).compactMap { $0 }
        XCTAssertTrue(fade.isEmpty)
        XCTAssertEqual(textResolved(graph, "B")?.opacity, 1)
    }

    // An animation with no layout change still completes, at its commit.
    func testAnimationWithoutChangeCompletesAtCommit() {
        let model = ListModel()
        model.items = ["A"]
        let graph = Graph(AnimatedListScreen(model: model))
        graph.flush()
        var done = 0
        withAnimation(.linear(duration: 1.0)) {
            // No observed change.
        } completion: {
            done += 1
        }
        graph.flush()
        XCTAssertEqual(done, 1)
    }
}
