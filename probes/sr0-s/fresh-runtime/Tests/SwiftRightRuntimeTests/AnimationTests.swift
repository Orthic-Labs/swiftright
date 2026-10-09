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
        graph.tick(now: 0.25)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity ?? -1, 0.75, accuracy: 1e-9)
        graph.tick(now: 1.0)
        XCTAssertEqual(textResolved(graph, "fade")?.opacity, 0)
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
