import Foundation
import Observation
@testable import SwiftRightRuntime
import XCTest

// SR2 block R4 (#39): `.scaleEffect`. Layout is unchanged; the resolved node carries the presented factors and anchor for the host; animated like a frame.

@Observable
@MainActor
final class ScaleModel {
    var big = false
}

struct ScaleScreen: View {
    @Bindable var model: ScaleModel
    var body: some View {
        VStack(spacing: 0) {
            Color.red.frame(width: 50, height: 20).scaleEffect(model.big ? 1.5 : 1, anchor: .topLeading)
            Color.blue.frame(width: 50, height: 20)
        }
    }
}

@MainActor
final class ScaleEffectTests: XCTestCase {
    private func nodes(_ g: Graph) throws -> [ResolvedNode] {
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return walk(try XCTUnwrap(g.snapshot()))
    }
    private func scale(_ g: Graph) throws -> ResolvedScale {
        try XCTUnwrap(try nodes(g).first { $0.kind == "modifier.scaleEffect" }?.scaleEffect)
    }

    func testScaleEffectKeepsLayoutAndPublishesFactorsAndAnchor() throws {
        let g = Graph(VStack(spacing: 0) {
            Color.red.frame(width: 50, height: 20).scaleEffect(x: 2, y: 0.5, anchor: .bottomTrailing)
            Color.blue.frame(width: 50, height: 20)
        })
        g.rootProposal = ProposedViewSize(width: 200, height: 200)
        g.flush()
        let all = try nodes(g)
        let s = try XCTUnwrap(all.first { $0.kind == "modifier.scaleEffect" })
        XCTAssertEqual(s.scaleEffect, ResolvedScale(x: 2, y: 0.5, anchor: .bottomTrailing))
        let colors = all.filter { $0.kind == "Color" }
        XCTAssertEqual(colors.map(\.frame.height), [20, 20])
        XCTAssertEqual(colors[1].frame.minY - colors[0].frame.minY, 20, "the next row is where it would be unscaled")
        XCTAssertEqual(s.frame, colors[0].frame, "the modifier takes its child's frame")
        XCTAssertEqual(Color.red.scaleEffect(CGSize(width: 3, height: 4)) is any View, true)
    }

    func testAScaleChangeAnimatesLikeAFrameAndSnapsWithoutAnimation() throws {
        let model = ScaleModel()
        let g = Graph(ScaleScreen(model: model))
        g.flush()
        XCTAssertEqual(try scale(g).x, 1)
        withAnimation(.linear(duration: 1)) { model.big = true }
        g.flush()
        XCTAssertEqual(try scale(g).x, 1, "nothing moves before the first tick")
        g.tick(now: 0)
        g.tick(now: 0.5)
        XCTAssertEqual(try scale(g).x, 1.25, accuracy: 1e-9)
        XCTAssertEqual(try scale(g).y, 1.25, accuracy: 1e-9)
        XCTAssertEqual(try scale(g).anchor, .topLeading)
        g.tick(now: 1)
        XCTAssertEqual(try scale(g).x, 1.5)
        model.big = false
        g.flush()
        XCTAssertEqual(try scale(g).x, 1, "no animation: snaps")
    }

    func testABouncyScaleOvershootsAndSettles() throws {
        let model = ScaleModel()
        let g = Graph(ScaleScreen(model: model), scale: 2.5)
        g.flush()
        var removed = false
        withAnimation(.bouncy, completionCriteria: .removed) { model.big = true } completion: { removed = true }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.315)
        XCTAssertGreaterThan(try scale(g).x, 1.5)
        g.tick(now: 3)
        XCTAssertEqual(try scale(g).x, 1.5)
        XCTAssertTrue(removed)
    }
}

// SR2 R4 (#39): `.tint` resolves through the environment's tint, else the accent colour.
@MainActor
final class TintTests: XCTestCase {
    private func nodes<V: View>(_ view: V) throws -> [ResolvedNode] {
        let g = Graph(view)
        g.rootProposal = ProposedViewSize(width: 200, height: 200)
        g.flush()
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return walk(try XCTUnwrap(g.snapshot()))
    }

    func testTintStyleResolvesToTheEnvironmentTintElseAccent() throws {
        let tinted = try nodes(VStack {
            Circle().fill(.tint).frame(width: 10, height: 10)
            Text("A").foregroundStyle(.tint)
        }.tint(.red))
        XCTAssertEqual(tinted.compactMap(\.shape).first?.paint?.color, Color.red.resolvedColor)
        XCTAssertEqual(tinted.first { $0.kind == "Text" }?.style.foreground, Color.red.resolvedColor)
        let plain = try nodes(Circle().fill(.tint).frame(width: 10, height: 10))
        XCTAssertEqual(plain.compactMap(\.shape).first?.paint?.color, .semantic("accentColor"))
    }

    func testBrightnessIsPublishedOnItsModifierNode() throws {
        let all = try nodes(Color.red.frame(width: 10, height: 10).brightness(0.3))
        XCTAssertEqual(all.first { $0.kind == "modifier.brightness" }?.brightness, 0.3)
    }
}
