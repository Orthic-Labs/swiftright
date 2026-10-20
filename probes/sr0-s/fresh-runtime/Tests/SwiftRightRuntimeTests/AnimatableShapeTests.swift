import Foundation
import Observation
@testable import SwiftRightRuntime
import XCTest

// SR2 block R2 (#37): Animatable shapes. A shape's geometry is presented like its frame: an animated change interpolates the shape's animatable data
// with the layer's progress; the presented shape is the new value with only that data interpolated.

@Observable
@MainActor
final class RingModel {
    var progress: CGFloat = 0.2
    var radius: CGFloat = 4
    var amount: Double = 0
    var tag = "a"
}

/// A user shape whose bar width is animatable; `tag` is not part of its animatable data.
struct GrowBar: Shape {
    var amount: Double
    var tag: String
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func path(in rect: CGRect) -> Path { Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * amount, height: rect.height)) }
}

/// A user shape with no animatable data: it switches at once.
struct PlainBar: Shape {
    var amount: Double
    func path(in rect: CGRect) -> Path { Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * amount, height: rect.height)) }
}

struct RingScreen: View {
    @Bindable var model: RingModel
    var body: some View {
        VStack(spacing: 0) {
            Circle().trim(from: 0, to: model.progress).stroke(Color.blue, lineWidth: 4).frame(width: 40, height: 40)
            RoundedRectangle(cornerRadius: model.radius).fill(Color.red).frame(width: 40, height: 20)
            GrowBar(amount: model.amount, tag: model.tag).fill(Color.green).frame(width: 100, height: 10)
            PlainBar(amount: model.amount).fill(Color.green).frame(width: 100, height: 10)
            Rectangle().fill(Color.gray).frame(width: 40, height: 10)
        }
    }
}

@MainActor
final class AnimatableShapeTests: XCTestCase {
    private func shapes(_ g: Graph) throws -> [ResolvedShape] {
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return walk(try XCTUnwrap(g.snapshot())).compactMap(\.shape)
    }
    private func trimEnd(_ g: Graph) throws -> CGFloat {
        guard case .trimmed(.circle, let from, let to) = try shapes(g)[0].geometry else { XCTFail("trimmed circle"); return -1 }
        XCTAssertEqual(from, 0)
        return to
    }
    private func radius(_ g: Graph) throws -> CGFloat {
        guard case .roundedRectangle(let r, _) = try shapes(g)[1].geometry else { XCTFail("rounded rectangle"); return -1 }
        return r
    }
    private func barWidth(_ g: Graph, _ index: Int) throws -> CGFloat {
        guard case .custom(let custom) = try shapes(g)[index].geometry else { XCTFail("custom shape"); return -1 }
        return custom.path(in: CGRect(x: 0, y: 0, width: 100, height: 10)).boundingRect.width
    }

    func testVectorArithmeticOfPairsAndScalars() {
        var p = AnimatablePair(CGFloat(1), AnimatablePair(2.0, Float(3)))
        p.scale(by: 2)
        XCTAssertEqual(p.first, 2); XCTAssertEqual(p.second.first, 4); XCTAssertEqual(p.second.second, 6)
        let q = p - AnimatablePair(CGFloat(1), AnimatablePair(1.0, Float(1)))
        XCTAssertEqual(q.first, 1); XCTAssertEqual(q.second.first, 3); XCTAssertEqual(q.second.second, 5)
        XCTAssertEqual(AnimatablePair(3.0, 4.0).magnitudeSquared, 25)
        XCTAssertEqual(EmptyAnimatableData().magnitudeSquared, 0)
        XCTAssertEqual(Circle().trim(from: 0.25, to: 0.75).animatableData, AnimatablePair(CGFloat(0.25), CGFloat(0.75)))
    }

    func testTrimCornerRadiusAndCustomDataInterpolateWithTheLayer() throws {
        let model = RingModel()
        let g = Graph(RingScreen(model: model))
        g.flush()
        XCTAssertEqual(try trimEnd(g), 0.2)
        withAnimation(.linear(duration: 1)) {
            model.progress = 0.8
            model.radius = 12
            model.amount = 1
        }
        g.flush()
        XCTAssertEqual(try trimEnd(g), 0.2, "nothing moves before the first tick")
        g.tick(now: 0)
        g.tick(now: 0.5)
        XCTAssertEqual(try trimEnd(g), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try radius(g), 8, accuracy: 1e-9)
        XCTAssertEqual(try barWidth(g, 2), 50, accuracy: 1e-9, "animatableData halfway")
        XCTAssertEqual(try barWidth(g, 3), 100, "a shape with no animatable data switches at once")
        g.tick(now: 1)
        XCTAssertEqual(try trimEnd(g), 0.8)
        XCTAssertEqual(try radius(g), 12)
        XCTAssertEqual(try barWidth(g, 2), 100)
    }

    func testAShapeChangeWithoutAnimationSnaps() throws {
        let model = RingModel()
        let g = Graph(RingScreen(model: model))
        g.flush()
        model.progress = 0.9
        g.flush()
        XCTAssertEqual(try trimEnd(g), 0.9)
    }

    func testPropertiesOutsideAnimatableDataTakeTheirNewValueAtOnce() throws {
        let model = RingModel()
        let g = Graph(RingScreen(model: model))
        g.flush()
        withAnimation(.linear(duration: 1)) {
            model.amount = 1
            model.tag = "b"
        }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.25)
        guard case .custom(let custom) = try shapes(g)[2].geometry else { return XCTFail() }
        XCTAssertTrue(custom.identity.contains("tag: \"b\""), "the presented shape is the new value: \(custom.identity)")
        XCTAssertTrue(custom.identity.contains("amount: 0.25"), custom.identity)
    }

    func testAnInterruptedTrimBlendsFromThePresentedValue() throws {
        let model = RingModel()
        let g = Graph(RingScreen(model: model))
        g.flush()
        withAnimation(.linear(duration: 1)) { model.progress = 1 }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.5)
        XCTAssertEqual(try trimEnd(g), 0.6, accuracy: 1e-9)
        withAnimation(.linear(duration: 1)) { model.progress = 0 }
        g.flush()
        g.tick(now: 0.5)   // the new layer begins here
        g.tick(now: 1.0)   // the first layer ends (presents 1); the second is halfway from it to 0
        XCTAssertEqual(try trimEnd(g), 0.5, accuracy: 1e-9, "additive: lerp(1, 0, 0.5)")
        g.tick(now: 1.5)
        XCTAssertEqual(try trimEnd(g), 0)
    }

    func testASpringOnAShapeOnlyChangeRunsAndCompletesAfterItSettles() throws {
        let model = RingModel()
        let g = Graph(RingScreen(model: model), scale: 2.5)
        g.flush()
        var removed = false
        withAnimation(.default, completionCriteria: .removed) { model.progress = 0.8 } completion: { removed = true }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.3)
        XCTAssertEqual(try trimEnd(g), 0.2 + 0.6 * CGFloat(SpringModel.value(elapsed: 0.3, duration: 0.5)), accuracy: 1e-9)
        g.tick(now: 0.6)
        XCTAssertFalse(removed, "a geometry change is not removed at once")
        XCTAssertNotEqual(try trimEnd(g), 0.8)
        g.tick(now: 1.2)
        XCTAssertEqual(try trimEnd(g), 0.8)
        XCTAssertTrue(removed)
    }

    // Oracle R2: a spring that interrupts a spring on a shape-only change continues smoothly instead of jumping to its target.
    func testASpringInterruptingASpringOnAShapeContinues() throws {
        let model = RingModel()
        let g = Graph(RingScreen(model: model), scale: 2.5)
        g.flush()
        withAnimation(.default) { model.progress = 0.5 }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.1)
        let mid = try trimEnd(g)
        XCTAssertGreaterThan(mid, 0.2); XCTAssertLessThan(mid, 0.5)
        withAnimation(.default) { model.progress = 0.9 }
        g.flush()
        g.tick(now: 0.1)
        g.tick(now: 0.15)
        let after = try trimEnd(g)
        XCTAssertGreaterThan(after, mid, "keeps moving")
        XCTAssertLessThan(after, 0.8, "no jump to the target")
        g.tick(now: 0.4)
        XCTAssertLessThan(try trimEnd(g), 0.9)
        g.tickSteps(from: 0.4, to: 2)
        XCTAssertEqual(try trimEnd(g), 0.9)
    }

    func testAnUnchangedShapeStartsNoMotion() throws {
        let model = RingModel()
        let g = Graph(RingScreen(model: model))
        g.flush()
        withAnimation(.linear(duration: 1)) { model.progress = 0.2 }
        g.flush()
        XCTAssertEqual(try trimEnd(g), 0.2)
        g.tick(now: 0)
        XCTAssertTrue(g.animating.isEmpty, "an unchanged shape starts no motion")
    }
}

// SR2 R6 (#41): `.clipShape` with an animatable shape animates the clip like a shape (the Pulse notch clips its content to its animating silhouette).
@MainActor
final class ClipShapeTests: XCTestCase {
    struct ClippedScreen: View {
        @Bindable var model: RingModel
        var body: some View {
            Color.red.frame(width: 100, height: 20).clipShape(GrowBar(amount: model.amount, tag: "clip"))
        }
    }

    private func clipWidth(_ g: Graph) throws -> CGFloat {
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        let clip = try XCTUnwrap(walk(try XCTUnwrap(g.snapshot())).compactMap(\.clipShape).first)
        guard case .custom(let custom) = clip.geometry else { XCTFail("custom clip"); return -1 }
        return custom.path(in: CGRect(x: 0, y: 0, width: 100, height: 20)).boundingRect.width
    }

    func testAnAnimatableClipShapeAnimatesAndLayoutIsUnchanged() throws {
        let model = RingModel()
        let g = Graph(ClippedScreen(model: model))
        g.flush()
        XCTAssertEqual(try clipWidth(g), 0)
        withAnimation(.linear(duration: 1)) { model.amount = 1 }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.5)
        XCTAssertEqual(try clipWidth(g), 50, accuracy: 1e-9)
        g.tick(now: 1)
        XCTAssertEqual(try clipWidth(g), 100)
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        let all = walk(try XCTUnwrap(g.snapshot()))
        XCTAssertEqual(all.first { $0.kind == "modifier.clipShape" }?.frame.size, all.first { $0.kind == "Color" }?.frame.size, "layout unchanged")
    }
}
