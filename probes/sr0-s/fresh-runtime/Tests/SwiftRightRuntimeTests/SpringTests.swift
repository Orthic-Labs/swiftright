import Foundation
import Observation
@testable import SwiftRightRuntime
import XCTest

// SR2 block R3 (#38): parameterised springs. Every expected progress below was read from SwiftUI on macOS 27.0.1 (26A434) by the R3 spike sampler
// (factory/pipeline/sr2-r3-spike/samples.jsonl, 1 ms cadence, at 0.105 / 0.205 / 0.315 / 0.455 s: away from the 1/300 s step boundaries).

@Observable
@MainActor
final class SpringBarModel {
    var wide = false
}

struct SpringBarScreen: View {
    @Bindable var model: SpringBarModel
    var body: some View {
        Color.blue.frame(width: model.wide ? 300 : 100, height: 40)
            .frame(width: 400, height: 60, alignment: .leading)
    }
}

@MainActor
final class SpringTests: XCTestCase {
    private func width(_ g: Graph) throws -> CGFloat {
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return try XCTUnwrap(walk(try XCTUnwrap(g.snapshot())).first { $0.kind == "Color" }).frame.width
    }

    /// Animates the bar 100 -> 300 pt with `animation` and returns the progress at each time.
    private func progress(_ animation: Animation, at times: [Double]) throws -> [Double] {
        let model = SpringBarModel()
        let g = Graph(SpringBarScreen(model: model), scale: 2.5)
        g.flush()
        withAnimation(animation) { model.wide = true }
        g.flush()
        g.tick(now: 0)
        var out: [Double] = []
        for t in times {
            g.tick(now: t)
            out.append(Double(try width(g) - 100) / 200)
        }
        return out
    }

    private let times = [0.105, 0.205, 0.315, 0.455]

    private func assertMatches(_ animation: Animation, _ swiftUI: [Double], _ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let got = try progress(animation, at: times)
        for (g, e) in zip(got, swiftUI) { XCTAssertEqual(g, e, accuracy: 1e-6, "\(name): \(got)", file: file, line: line) }
    }

    func testParameterisedSpringsMatchSwiftUI() throws {
        try assertMatches(.snappy, [0.4189429, 0.8012315, 0.9656687, 1.0037941], "snappy")
        try assertMatches(.bouncy, [0.4576509, 0.8897288, 1.0367943, 1.0227174], "bouncy")
        try assertMatches(.spring(duration: 0.5, bounce: 0.3), [0.4576509, 0.8897288, 1.0367943, 1.0227174], "bounce 0.3 = bouncy")
        try assertMatches(.spring(duration: 0.35, bounce: 0), [0.5679928, 0.8796193, 0.9737913, 0.9964302], "duration 0.35")
        try assertMatches(.spring(duration: 0.5, bounce: -0.3), [0.3123386, 0.5827465, 0.7610417, 0.8825161], "bounce -0.3")
        try assertMatches(.spring(response: 0.4, dampingFraction: 0.7), [0.6011062, 0.9911402, 1.0360034, 1.0030853], "response 0.4")
        try assertMatches(.spring(response: 0.55, dampingFraction: 0.825), [0.3753365, 0.7619471, 0.9537637, 1.0067726], "response 0.55")
    }

    func testInterpolatingSpringIsTheClosedForm() throws {
        let got = try progress(.interpolatingSpring(stiffness: 170, damping: 15), at: times)
        // SwiftUI: [0.5137511, 1.0007162, 1.1062796, 1.0183384]; frames snap to the device pixel grid (1 / 2.5 pt of 200 pt = 0.002), so compare to that.
        for (g, e) in zip(got, [0.5137511, 1.0007162, 1.1062796, 1.0183384]) { XCTAssertEqual(g, e, accuracy: 0.002, "\(got)") }
    }

    func testDefaultSpringNamesStillUseTheMeasuredTable() throws {
        XCTAssertEqual(Animation.spring(duration: 0.5, bounce: 0).curve, .spring)
        XCTAssertEqual(Animation.smooth(duration: 0.5, extraBounce: 0).curve, .spring)
        XCTAssertEqual(Animation.snappy, Animation.snappy(duration: 0.5, extraBounce: 0))
        guard case .integratedSpring = Animation.bouncy(extraBounce: 0.1).curve else { return XCTFail() }
    }

    func testDelayHoldsTheStartThenRunsTheSameCurve() throws {
        let plain = try progress(.linear(duration: 1), at: [0.25, 0.5])
        let delayed = try progress(.linear(duration: 1).delay(0.25), at: [0.25, 0.5, 0.75])
        XCTAssertEqual(delayed[0], 0, accuracy: 1e-9, "still at the start when the delay ends")
        XCTAssertEqual(delayed[1], plain[0], accuracy: 1e-9)
        XCTAssertEqual(delayed[2], plain[1], accuracy: 1e-9)
    }

    func testABouncySpringOvershootsAndSettlesOnTheTarget() throws {
        let model = SpringBarModel()
        let g = Graph(SpringBarScreen(model: model), scale: 2.5)
        g.flush()
        var removed = false
        withAnimation(.bouncy, completionCriteria: .removed) { model.wide = true } completion: { removed = true }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.315)
        XCTAssertGreaterThan(try width(g), 300, "overshoots the target")
        g.tick(now: 0.5)
        XCTAssertFalse(removed)
        g.tick(now: 3)
        XCTAssertEqual(try width(g), 300)
        XCTAssertTrue(removed)
    }

    // Oracle R3: a parameterised spring interrupting one keeps its velocity (no restart from rest, no fling) at any tick alignment.
    func testABouncySpringInterruptedByABouncySpringKeepsItsVelocity() throws {
        for offset in [0.0, 0.0333, 0.00005, 0.0016666, 1.0 / 300, 2.0 / 300, -1e-12, 1e-12] {
            let model = SpringBarModel()
            let g = Graph(SpringBarScreen(model: model), scale: 2.5)
            g.flush()
            withAnimation(.bouncy) { model.wide = true }
            g.flush()
            g.tick(now: 0)
            let t0 = 0.1 + offset
            g.tick(now: t0 - 1.0 / 60)
            let before = try width(g)
            g.tick(now: t0)
            let at = try width(g)
            let rate = Double(at - before) * 60   // pt/s just before the interruption
            withAnimation(.bouncy) { model.wide = false }   // back to 100: the bar is still moving towards 300
            g.flush()
            g.tick(now: t0)
            g.tick(now: t0 + 1.0 / 60)
            let next = try width(g)
            let rateAfter = Double(next - at) * 60
            XCTAssertGreaterThan(rateAfter, 0.3 * rate, "offset \(offset): keeps moving the same way at first (\(rateAfter) vs \(rate))")
            XCTAssertLessThan(rateAfter, 1.5 * rate, "offset \(offset): no fling (\(rateAfter) vs \(rate))")
            g.tick(now: t0 + 3)
            XCTAssertEqual(try width(g), 100)
        }
    }

    func testSpringCallWithoutArgumentsIsTheDefaultSpring() {
        XCTAssertEqual(Animation.spring().curve, .spring)
        XCTAssertEqual(Animation.spring(response: 0.5, dampingFraction: 1).curve, .spring)
    }

    func testIntegratedSettleKeepsTheSpringUntilItStaysWithinTolerance() {
        guard case .integratedSpring(let k, let c) = Animation.bouncy.curve else { return XCTFail() }
        let t = SpringMath.integratedSettle(k: k, c: c, displacement: [0, 0, 200, 0, 0], scale: 2.5)
        XCTAssertGreaterThan(t, 0.5)
        var probe = t
        while probe < t + 1 {
            XCTAssertLessThanOrEqual(abs(1 - SpringMath.integrated(k: k, c: c, elapsed: probe + 1e-9)) * 200, 1.05 / 2.5 + 1e-9)
            probe += 0.01
        }
    }
}
