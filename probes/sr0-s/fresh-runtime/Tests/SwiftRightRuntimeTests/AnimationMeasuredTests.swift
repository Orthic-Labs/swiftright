import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// SR1 round 3 block 18 (swiftui.animation) and block 19 (swiftui.opacity-transition): every expected number below was measured on macOS SwiftUI
// (macOS 27, Xcode 27 RC) with the manual-clock harness in factory/pipeline/blocks-6-10 (a CustomAnimation wrapper that evaluates the original
// Animation at a clock the host moves) or, for completion timing, with a real-time probe. Evidence: docs/sr1-decisions.md "Animation facts".

@Observable
@MainActor
final class BarModel {
    var wide = false
    var shown = false
    var other = false
}

struct BarScreen: View {
    @Bindable var model: BarModel
    var body: some View {
        Color.blue.frame(width: model.wide ? 200 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
    }
}

/// A modifier-driven animation: `.animation(a, value:)` right above the bar.
struct ModifierBarScreen: View {
    @Bindable var model: BarModel
    let animation: Animation?
    var body: some View {
        Color.blue.frame(width: model.wide ? 200 : 100, height: 40)
            .animation(animation, value: model.wide)
            .frame(width: 300, height: 60, alignment: .leading)
    }
}

struct AppearBarScreen: View {
    @State private var wide = false
    var body: some View {
        Color.blue.frame(width: wide ? 200 : 100, height: 40)
            .frame(width: 300, height: 60, alignment: .leading)
            .onAppear { withAnimation(.linear(duration: 1)) { wide = true } }
    }
}

struct TransitionScreen: View {
    @Bindable var model: BarModel
    let transition: AnyTransition?
    var body: some View {
        VStack(spacing: 0) {
            if model.shown {
                if let transition {
                    Color.blue.frame(width: 120, height: 40).transition(transition)
                } else {
                    Color.blue.frame(width: 120, height: 40)
                }
            }
        }
        .frame(width: 200, height: 60)
    }
}

@MainActor
func bar(_ graph: Graph) -> ResolvedNode? {
    var nodes: [ResolvedNode] = []
    collect(graph.snapshot(), into: &nodes) { $0.kind == "Color" }
    return nodes.first
}

@MainActor
final class AnimationMeasuredTests: XCTestCase {

    /// width of the bar at progress p of a 100 -> 200 change
    private func p(_ graph: Graph) -> Double { Double((bar(graph)?.frame.width ?? 0) - 100) / 100 }

    // MARK: curves (measured: `Animation.animate(value:time:context:)` at fixed times)

    func testEaseInOutIsTheCubicBezierFortyTwoZeroFiftyEightOne() {
        let table: [(Double, Double)] = [
            (0.05, 0.004829), (0.10, 0.019722), (0.20, 0.081660), (0.25, 0.129162), (0.30, 0.187396), (0.40, 0.331883),
            (0.50, 0.500000), (0.60, 0.668117), (0.70, 0.812604), (0.75, 0.870838), (0.80, 0.918340), (0.90, 0.980278), (0.95, 0.995171),
        ]
        let model = BarModel()
        let graph = Graph(BarScreen(model: model))
        graph.flush()
        withAnimation(.easeInOut(duration: 1)) { model.wide = true }
        graph.flush()
        graph.tick(now: 10)
        for (t, expected) in table {
            graph.tick(now: 10 + t)
            XCTAssertEqual(p(graph), expected, accuracy: 2e-6, "easeInOut at \(t)")
        }
    }

    func testEaseInAndEaseOutMatchSwiftUI() {
        for (animation, expected) in [(Animation.easeIn(duration: 1), 0.315357), (Animation.easeOut(duration: 1), 0.684643)] {
            let model = BarModel()
            let graph = Graph(BarScreen(model: model))
            graph.flush()
            withAnimation(animation) { model.wide = true }
            graph.flush()
            graph.tick(now: 0)
            graph.tick(now: 0.5)
            XCTAssertEqual(p(graph), expected, accuracy: 2e-6, animation.name)
        }
    }

    func testLinearAndTheNoDurationVariantsLastThirtyFiveHundredths() {
        for animation in [Animation.linear, .easeIn, .easeOut, .easeInOut] {
            XCTAssertEqual(animation.duration, 0.35, animation.name)
        }
        let model = BarModel()
        let graph = Graph(BarScreen(model: model))
        graph.flush()
        withAnimation(.linear) { model.wide = true }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.3)
        XCTAssertEqual(p(graph), 0.3 / 0.35, accuracy: 1e-9)
        graph.tick(now: 0.36)
        XCTAssertEqual(p(graph), 1)
    }

    func testDefaultIsTheSmoothSpringOfHalfASecond() {
        XCTAssertEqual(Animation.default.duration, 0.5)
        XCTAssertEqual(Animation.default.curve, Animation.smooth.curve)
        XCTAssertEqual(Animation.default.curve, Animation.spring.curve)
        let model = BarModel()
        let graph = Graph(BarScreen(model: model))
        graph.flush()
        withAnimation(.default) { model.wide = true }
        graph.flush()
        graph.tick(now: 0)
        // measured from SwiftUI's Animation.default, sampled 0.1 s apart
        for (t, expected) in [(0.1, 0.370762), (0.2, 0.721278), (0.3, 0.890036), (0.4, 0.957431), (0.5, 0.984469)] {
            graph.tick(now: t)
            XCTAssertEqual(p(graph), expected, accuracy: 1e-6, "default at \(t)")
        }
        graph.tick(now: 0.53)
        XCTAssertLessThan(p(graph), 1, "still settling at 0.53 s")
        graph.tick(now: 0.54)
        XCTAssertEqual(p(graph), 1, "SwiftUI removes the spring at 0.537 s and the value snaps to the target")
    }

    // MARK: onAppear

    func testOnAppearWithAnimationAnimatesFromTheStateTheViewFirstAppearedIn() {
        let graph = Graph(AppearBarScreen())
        var commits = 0
        graph.commitSink = { _ in commits += 1 }
        graph.flush()
        XCTAssertEqual(bar(graph)?.frame.width, 100, "first presentation is the initial state, not the final one")
        XCTAssertEqual(bar(graph)?.opacity, 1, "and the view does not fade in: it appeared before the animation began")
        XCTAssertEqual(commits, 2, "the initial state is presented, then the appear action's change")
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 150, accuracy: 1e-9)
        graph.tick(now: 1.2)
        XCTAssertEqual(bar(graph)?.frame.width, 200)
    }

    // MARK: interruption (additive: the first animation keeps running underneath)

    func testInterruptionBlendsTheFirstAnimationWithTheSecond() {
        // measured with Animation.linear(duration: 1): 100 -> 200, at 0.4 s back to 100; presented = 100 + res1 * (1 - p2), p2 the second one's own progress
        let model = BarModel()
        let graph = Graph(BarScreen(model: model))
        graph.flush()
        var first = 0, second = 0
        withAnimation(.linear(duration: 1)) { model.wide = true } completion: { first += 1 }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.4)
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 140, accuracy: 1e-9)
        withAnimation(.linear(duration: 1)) { model.wide = false } completion: { second += 1 }
        graph.flush()
        graph.tick(now: 0.4)
        graph.tick(now: 0.6)   // first at 0.6 -> 160, second at 0.2 -> 160 - 0.2 * 60
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 148, accuracy: 1e-9)
        graph.tick(now: 0.9)   // first at 0.9 -> 190, second at 0.5
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 145, accuracy: 1e-9)
        XCTAssertEqual(first, 0)
        graph.tick(now: 1.0)   // the first reaches its end (200): second at 0.6
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 140, accuracy: 1e-9)
        XCTAssertEqual(first, 1, "the first completes at its own end, measured at 1.0003 s")
        XCTAssertEqual(second, 0)
        graph.tick(now: 1.2)
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 120, accuracy: 1e-9)
        graph.tick(now: 1.41)
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(second, 1, "the second completes at 1.4 s")
        XCTAssertEqual(first, 1)
    }

    func testInterruptionWithEaseInOutUsesTheSameLayering() {
        // measured: delta2 = -res1(t) and res2 = delta2 * easeInOut(own time)
        let model = BarModel()
        let graph = Graph(BarScreen(model: model))
        graph.flush()
        withAnimation(.easeInOut(duration: 1)) { model.wide = true }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.4)
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 133.1883, accuracy: 1e-3)
        withAnimation(.easeInOut(duration: 1)) { model.wide = false }
        graph.flush()
        graph.tick(now: 0.4)
        graph.tick(now: 0.8)
        // res1(0.8) = 91.834, p2(0.4) = 0.331883 -> 100 + 91.834 * (1 - 0.331883)
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 100 + 91.834 * (1 - 0.331883), accuracy: 1e-3)
        graph.tick(now: 1.41)
        XCTAssertEqual(bar(graph)?.frame.width ?? 0, 100, accuracy: 1e-9)
    }

    func testRemovedCompletionWaitsForTheWholeChain() {
        // measured: with .removed the first transaction of an interrupted pair fires at 1.4 s, together with the second
        let model = BarModel()
        let graph = Graph(BarScreen(model: model))
        graph.flush()
        var first = 0, second = 0
        withAnimation(.linear(duration: 1), completionCriteria: .removed) { model.wide = true } completion: { first += 1 }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.4)
        withAnimation(.linear(duration: 1), completionCriteria: .removed) { model.wide = false } completion: { second += 1 }
        graph.flush()
        graph.tick(now: 0.4)
        graph.tick(now: 1.0)
        XCTAssertEqual(first, 0, "the first animation ended but is still part of the presentation")
        graph.tick(now: 1.41)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
    }

    func testSpringCompletionLogicalAtHalfASecondRemovedAtSettle() {
        for (criteria, early, late) in [(AnimationCompletionCriteria.logicallyComplete, 0.51, 0.51), (.removed, 0.51, 0.54)] {
            let model = BarModel()
            let graph = Graph(BarScreen(model: model))
            graph.flush()
            var fired = 0
            withAnimation(.default, completionCriteria: criteria) { model.wide = true } completion: { fired += 1 }
            graph.flush()
            graph.tick(now: 0)
            graph.tick(now: 0.49)
            XCTAssertEqual(fired, 0)
            graph.tick(now: early)
            if criteria == .removed {
                XCTAssertEqual(fired, 0, "removed waits for the settle at 0.537 s")
                graph.tick(now: late)
            }
            XCTAssertEqual(fired, 1, "\(criteria)")
        }
    }

    func testNoChangeAndNilAnimationCompleteAtOnce() {
        let model = BarModel()
        let graph = Graph(BarScreen(model: model))
        graph.flush()
        var a = 0, b = 0
        withAnimation(.linear(duration: 1)) { model.wide = false } completion: { a += 1 }
        graph.flush()
        XCTAssertEqual(a, 1)
        withAnimation(nil) { model.wide = true } completion: { b += 1 }
        graph.flush()
        XCTAssertEqual(b, 1)
        XCTAssertEqual(bar(graph)?.frame.width, 200, "nil animation snaps")
    }

    // MARK: .animation(_:value:) scoping and Transaction.disablesAnimations

    func testAnimationModifierAnimatesAPlainChange() {
        let model = BarModel()
        let graph = Graph(ModifierBarScreen(model: model, animation: .linear(duration: 1)))
        graph.flush()
        model.wide = true
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.25)
        XCTAssertEqual(p(graph), 0.25, accuracy: 1e-9)
    }

    func testAnimationModifierBeatsTheExplicitAnimationBelowIt() {
        // measured: withAnimation(.linear(1)) over `.animation(.linear(2), value:)` runs for 2 s
        let model = BarModel()
        let graph = Graph(ModifierBarScreen(model: model, animation: .linear(duration: 2)))
        graph.flush()
        withAnimation(.linear(duration: 1)) { model.wide = true }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(p(graph), 0.25, accuracy: 1e-9)
        graph.tick(now: 1.5)
        XCTAssertEqual(p(graph), 0.75, accuracy: 1e-9)
    }

    func testNilAnimationModifierSnapsAnExplicitAnimation() {
        let model = BarModel()
        let graph = Graph(ModifierBarScreen(model: model, animation: nil))
        graph.flush()
        withAnimation(.linear(duration: 1)) { model.wide = true }
        graph.flush()
        XCTAssertEqual(bar(graph)?.frame.width, 200)
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(bar(graph)?.frame.width, 200)
    }

    func testDisablesAnimationsSilencesTheModifierButNotAnExplicitAnimation() {
        // measured: a transaction with disablesAnimations and no animation snaps through `.animation(_:value:)`; with an animation of its own it still animates
        let model = BarModel()
        let graph = Graph(ModifierBarScreen(model: model, animation: .linear(duration: 1)))
        graph.flush()
        var silenced = Transaction()
        silenced.disablesAnimations = true
        withTransaction(silenced) { model.wide = true }
        graph.flush()
        XCTAssertEqual(bar(graph)?.frame.width, 200, "no animation")

        let model2 = BarModel()
        let graph2 = Graph(BarScreen(model: model2))
        graph2.flush()
        var explicit = Transaction(animation: .linear(duration: 1))
        explicit.disablesAnimations = true
        withTransaction(explicit) { model2.wide = true }
        graph2.flush()
        graph2.tick(now: 0)
        graph2.tick(now: 0.5)
        XCTAssertEqual(p(graph2), 0.5, accuracy: 1e-9, "the explicit animation still runs")
    }

    func testTheModifierOnlyAppliesWhenItsValueChanged() {
        // a change of something else under the same modifier is not animated by it
        let model = BarModel()
        let graph = Graph(ModifierBarScreen(model: model, animation: .linear(duration: 1)))
        graph.flush()
        model.wide = true
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 2)
        XCTAssertEqual(bar(graph)?.frame.width, 200)
        model.wide = false
        graph.flush()
        XCTAssertEqual(bar(graph)?.frame.width, 200, "the next tick begins the motion back")
        graph.tick(now: 2)
        graph.tick(now: 2.5)
        XCTAssertEqual(p(graph), 0.5, accuracy: 1e-9)
    }

    // MARK: transitions

    func testInsertionFadesInWithTheAnimationByDefault() {
        let model = BarModel()
        let graph = Graph(TransitionScreen(model: model, transition: nil))
        graph.flush()
        withAnimation(.linear(duration: 1)) { model.shown = true }
        graph.flush()
        XCTAssertEqual(bar(graph)?.opacity, 0)
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(bar(graph)?.opacity ?? -1, 0.5, accuracy: 1e-9, "measured: alpha equals the animation's progress")
        graph.tick(now: 1.2)
        XCTAssertEqual(bar(graph)?.opacity, 1)
    }

    func testOpacityTransitionIsTheDefault() {
        let model = BarModel()
        let graph = Graph(TransitionScreen(model: model, transition: .opacity))
        graph.flush()
        withAnimation(.linear(duration: 1)) { model.shown = true }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.25)
        XCTAssertEqual(bar(graph)?.opacity ?? -1, 0.25, accuracy: 1e-9)
    }

    func testMoveTransitionStartsOneViewWidthBeyondTheEdge() {
        // measured (Color 120 x 40 in a 200 x 60 VStack, linear 1 s, move(edge: .leading)): x = final - 120 * (1 - progress), opacity untouched
        let model = BarModel()
        let graph = Graph(TransitionScreen(model: model, transition: .move(edge: .leading)))
        graph.flush()
        withAnimation(.linear(duration: 1)) { model.shown = true }
        graph.flush()
        let final = 40.0   // (200 - 120) / 2
        XCTAssertEqual(bar(graph)?.opacity, 1, "a move transition does not fade")
        graph.tick(now: 0)
        XCTAssertEqual(Double(bar(graph)?.frame.minX ?? 0), final - 120, accuracy: 1e-9)
        graph.tick(now: 0.25)
        XCTAssertEqual(Double(bar(graph)?.frame.minX ?? 0), final - 90, accuracy: 1e-9)
        graph.tick(now: 0.5)
        XCTAssertEqual(Double(bar(graph)?.frame.minX ?? 0), final - 60, accuracy: 1e-9)
        graph.tick(now: 1.5)
        XCTAssertEqual(Double(bar(graph)?.frame.minX ?? 0), final, accuracy: 1e-9)
    }

    func testIdentityTransitionDoesNotAnimateTheInsertion() {
        let model = BarModel()
        let graph = Graph(TransitionScreen(model: model, transition: .identity))
        graph.flush()
        withAnimation(.linear(duration: 1)) { model.shown = true }
        graph.flush()
        XCTAssertEqual(bar(graph)?.opacity, 1)
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(bar(graph)?.opacity, 1)
    }

    func testInsertionWithoutAnAnimationAppearsAtOnce() {
        let model = BarModel()
        let graph = Graph(TransitionScreen(model: model, transition: .move(edge: .leading)))
        graph.flush()
        let before = bar(graph)
        XCTAssertNil(before)
        model.shown = true
        graph.flush()
        XCTAssertEqual(bar(graph)?.opacity, 1)
        let x = bar(graph)?.frame.minX
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(bar(graph)?.frame.minX, x)
    }

    func testStaticOpacityModifierScalesTheLeaf() {
        struct S: View { var body: some View { Color.blue.frame(width: 120, height: 40).opacity(0.5) } }
        let graph = Graph(S())
        graph.flush()
        XCTAssertEqual(bar(graph)?.opacity, 0.5)
    }
}
