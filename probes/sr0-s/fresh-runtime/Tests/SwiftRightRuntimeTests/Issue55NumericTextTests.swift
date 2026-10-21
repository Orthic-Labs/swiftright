import Foundation
import Observation
@testable import SwiftRightRuntime
import XCTest

// Issue #55: `.contentTransition(.numericText())` rolls changed digits inside an animation transaction (FixedAdvanceTextMeasurer: 8 pt per character, 16 pt line).

@Observable
@MainActor
final class CounterModel {
    var n = 41
    var x = 41.0
}

private struct CounterScreen: View {
    @Bindable var model: CounterModel
    let transition: ContentTransition
    var body: some View {
        Text("\(model.n)").contentTransition(transition)
    }
}

@MainActor
final class NumericTextTests: XCTestCase {
    private func textNode(_ g: Graph) throws -> ResolvedNode {
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return try XCTUnwrap(walk(try XCTUnwrap(g.snapshot())).first { $0.kind == "Text" })
    }

    private func start(_ transition: ContentTransition, n: Int = 41) -> (CounterModel, Graph) {
        let model = CounterModel()
        model.n = n
        let g = Graph(CounterScreen(model: model, transition: transition), scale: 2)
        g.flush()
        return (model, g)
    }

    func testChangedDigitRollsUpAndUnchangedDigitStays() throws {
        let (model, g) = start(.numericText())
        XCTAssertNil(try textNode(g).numericRoll)
        withAnimation(.linear(duration: 1)) { model.n = 42 }
        g.flush()
        g.tick(now: 0)
        let begin = try XCTUnwrap(try textNode(g).numericRoll)
        XCTAssertEqual(begin.glyphs.map(\.text), ["4", "1", "2"])
        XCTAssertEqual(begin.glyphs[1].y, 0, accuracy: 1e-9)
        XCTAssertEqual(begin.glyphs[2].y, 16, accuracy: 1e-9, "the new digit starts one line box below")
        g.tick(now: 0.5)
        let mid = try XCTUnwrap(try textNode(g).numericRoll)
        XCTAssertEqual(mid.progress, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mid.glyphs[0].y, 0); XCTAssertEqual(mid.glyphs[0].opacity, 1)
        XCTAssertEqual(mid.glyphs[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(mid.glyphs[1].y, -8, accuracy: 1e-9, "the old digit moves up")
        XCTAssertEqual(mid.glyphs[1].opacity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mid.glyphs[2].y, 8, accuracy: 1e-9, "the new digit comes from below")
        XCTAssertEqual(mid.glyphs[2].opacity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mid.glyphs[2].x, 8, accuracy: 1e-9)
        g.tick(now: 1)
        XCTAssertNil(try textNode(g).numericRoll, "done: the node is plain text again")
        XCTAssertEqual(try textNode(g).text, "42")
    }

    func testGrowingStringPairsPlaceValuesFromTheTrailingEnd() throws {
        let (model, g) = start(.numericText(), n: 9)
        withAnimation(.linear(duration: 1)) { model.n = 10 }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.5)
        let roll = try XCTUnwrap(try textNode(g).numericRoll)
        XCTAssertEqual(roll.glyphs.map(\.text), ["1", "9", "0"])
        XCTAssertEqual(roll.glyphs[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(roll.glyphs[0].opacity, 0.5, accuracy: 1e-9, "the new leading digit fades in")
        XCTAssertEqual(roll.glyphs[1].x, 4, accuracy: 1e-9, "the 9 slides right while it leaves")
        XCTAssertEqual(roll.glyphs[2].x, 4, accuracy: 1e-9)
        XCTAssertEqual(roll.glyphs[1].y, -8, accuracy: 1e-9)
        XCTAssertEqual(roll.glyphs[2].y, 8, accuracy: 1e-9)
    }

    func testCountsDownReversesTheDirection() throws {
        let (model, g) = start(.numericText(countsDown: true))
        withAnimation(.linear(duration: 1)) { model.n = 40 }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.5)
        let roll = try XCTUnwrap(try textNode(g).numericRoll)
        XCTAssertTrue(roll.countsDown)
        XCTAssertEqual(roll.glyphs[1].y, 8, accuracy: 1e-9, "the old digit moves down")
        XCTAssertEqual(roll.glyphs[2].y, -8, accuracy: 1e-9, "the new digit comes from above")
    }

    func testValueVariantCountsDownWhenTheValueFalls() throws {
        let model = CounterModel()
        struct S: View {
            @Bindable var model: CounterModel
            var body: some View { Text("\(model.n)").contentTransition(.numericText(value: model.x)) }
        }
        let g = Graph(S(model: model), scale: 2)
        g.flush()
        withAnimation(.linear(duration: 1)) { model.n = 40; model.x = 40 }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.5)
        XCTAssertEqual(try XCTUnwrap(try textNode(g).numericRoll).countsDown, true)
        g.tick(now: 1)
        withAnimation(.linear(duration: 1)) { model.n = 43; model.x = 43 }
        g.flush()
        g.tick(now: 2)
        g.tick(now: 2.5)
        XCTAssertEqual(try XCTUnwrap(try textNode(g).numericRoll).countsDown, false)
    }

    func testNoTransactionSwapsAtOnce() throws {
        let (model, g) = start(.numericText())
        model.n = 42
        g.flush()
        XCTAssertNil(try textNode(g).numericRoll)
        XCTAssertEqual(try textNode(g).text, "42")
    }

    func testOtherTransitionsSwapAtOnce() throws {
        let (model, g) = start(.opacity)
        withAnimation(.linear(duration: 1)) { model.n = 42 }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.5)
        XCTAssertNil(try textNode(g).numericRoll)
    }

    func testInterruptingChangeRestartsFromTheShownGlyphs() throws {
        let (model, g) = start(.numericText())
        withAnimation(.linear(duration: 1)) { model.n = 42 }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.5)
        withAnimation(.linear(duration: 1)) { model.n = 43 }
        g.flush()
        g.tick(now: 0.5)
        let roll = try XCTUnwrap(try textNode(g).numericRoll)
        XCTAssertEqual(roll.progress, 0, accuracy: 1e-9)
        XCTAssertEqual(roll.glyphs.map(\.text), ["4", "2", "3"])
        g.tick(now: 1.5)
        XCTAssertNil(try textNode(g).numericRoll)
    }
}
