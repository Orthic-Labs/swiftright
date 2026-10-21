import Foundation
import Observation
@testable import SwiftRightRuntime
import XCTest

// Issue #54 (SR2): paint interpolation (colour, foreground, line width), the spring removal rule for interrupted springs, and the control tint carried to the host.

@Observable
@MainActor
final class PaintModel {
    var on = false
}

private let paintRed = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
private let paintBlue = Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)

struct PaintScreen: View {
    @Bindable var model: PaintModel
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(model.on ? paintBlue : paintRed).frame(width: 40, height: 10)
            Circle().stroke(Color.green, lineWidth: model.on ? 8 : 2).frame(width: 40, height: 40)
            Text("A").foregroundStyle(model.on ? paintBlue : paintRed)
            (model.on ? paintBlue : paintRed).frame(width: 40, height: 10)
        }
    }
}

@MainActor
final class PaintInterpolationTests: XCTestCase {
    private func nodes(_ g: Graph) throws -> [ResolvedNode] {
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return walk(try XCTUnwrap(g.snapshot()))
    }
    private func fill(_ g: Graph) throws -> ResolvedColor { try XCTUnwrap(try nodes(g).compactMap(\.shape).first?.paint?.color) }
    private func lineWidth(_ g: Graph) throws -> CGFloat { try XCTUnwrap(try nodes(g).compactMap(\.shape).last?.paint?.lineWidth) }
    private func foreground(_ g: Graph) throws -> ResolvedColor { try XCTUnwrap(try nodes(g).first { $0.kind == "Text" }?.style.foreground) }
    private func colorView(_ g: Graph) throws -> ResolvedColor { try XCTUnwrap(try nodes(g).first { $0.kind == "Color" }?.color) }

    private func components(_ c: ResolvedColor) throws -> [Double] {
        guard case .rgba(let r, let g, let b, let a) = c else { XCTFail("not an rgba colour: \(c)"); return [] }
        return [r, g, b, a]
    }

    /// CI 39579395357, macOS 27: red 255/51/51 to blue 51/102/255 reads 212/90/119, 167/106/167, 118/109/212 at 0.25, 0.5, 0.75 of a linear animation.
    func testDefaultColourSpaceIsOklabAsMeasuredOnTheMac() throws {
        XCTAssertEqual(ColorInterpolation.space, .oklab)
        let from = ResolvedColor.rgba(1, 51.0 / 255, 51.0 / 255, 1), to = ResolvedColor.rgba(51.0 / 255, 102.0 / 255, 1, 1)
        for (t, want) in [(0.25, [212, 90, 119]), (0.5, [167, 106, 167]), (0.75, [118, 109, 212])] as [(Double, [Double])] {
            let c = try components(ResolvedColor.interpolated(from, to, t))
            for k in 0..<3 { XCTAssertEqual((c[k] * 255).rounded(), want[k], "t \(t) channel \(k)") }
        }
        XCTAssertEqual(try components(ResolvedColor.interpolated(from, to, 0)).prefix(3).map { ($0 * 255).rounded() }, [255, 51, 51])
    }

    func testColourInterpolationIsPerComponentAndClamped() throws {
        let mid = try components(ResolvedColor.interpolated(paintRed.resolvedColor, paintBlue.resolvedColor, 0.5, in: .sRGB))
        XCTAssertEqual(mid, [0.5, 0, 0.5, 1])
        let linear = try components(ResolvedColor.interpolated(paintRed.resolvedColor, paintBlue.resolvedColor, 0.5, in: .linear))
        XCTAssertEqual(linear[0], 0.7353569830524495, accuracy: 1e-9, "encode(0.5) of linear light")
        XCTAssertEqual(linear[2], linear[0], accuracy: 1e-12)
        // a spring that overshoots stays inside 0...1 where it is drawn
        let over = try components(ResolvedColor.interpolated(paintRed.resolvedColor, paintBlue.resolvedColor, 1.2, in: .sRGB))
        XCTAssertEqual(over, [0, 0, 1, 1])
        let under = try components(ResolvedColor.interpolated(paintRed.resolvedColor, paintBlue.resolvedColor, -0.2, in: .sRGB))
        XCTAssertEqual(under, [1, 0, 0, 1])
        // alpha is interpolated on its own (straight alpha)
        let faded = try components(ResolvedColor.interpolated(.rgba(1, 0, 0, 0), .rgba(1, 0, 0, 1), 0.25))
        XCTAssertEqual(faded[3], 0.25)
        for k in 0..<3 { XCTAssertEqual(faded[k], [1, 0, 0][k], accuracy: 1e-9) }
        // the same semantic colour fades its alpha; other pairs take the new colour
        XCTAssertEqual(ResolvedColor.interpolated(.semantic("label"), .semanticAlpha("label", 0.5), 0.5), .semanticAlpha("label", 0.75))
        XCTAssertEqual(ResolvedColor.interpolated(.semantic("label"), .semantic("accentColor"), 0.5), .semantic("accentColor"))
        XCTAssertEqual(ResolvedColor.distance(paintRed.resolvedColor, paintBlue.resolvedColor), 1)
        XCTAssertEqual(ResolvedColor.distance(.semantic("label"), .semantic("accentColor")), 0, "a switch is not a movement")
    }

    func testAnimatedColourLineWidthAndForegroundFollowTheLayer() throws {
        let model = PaintModel()
        let g = Graph(PaintScreen(model: model), scale: 2.5)
        g.flush()
        XCTAssertEqual(try fill(g), paintRed.resolvedColor)
        withAnimation(.linear(duration: 1)) { model.on = true }
        g.flush()
        g.tick(now: 0)
        XCTAssertEqual(try fill(g), paintRed.resolvedColor, "nothing moves at progress 0")
        g.tick(now: 0.5)
        // Oklab midpoint of red and blue (the measured space, see PaintInterpolation.swift)
        let mid = [0.5504410670996633, 0.32562068470935013, 0.6365006535344367, 1]
        for (got, what) in [(try fill(g), "a shape fill"), (try foreground(g), "a foreground style"), (try colorView(g), "a Color view")] {
            let c = try components(got)
            for k in 0..<4 { XCTAssertEqual(c[k], mid[k], accuracy: 1e-6, "\(what) animates in Oklab, channel \(k)") }
        }
        XCTAssertEqual(try lineWidth(g), 5, accuracy: 1e-9)
        let stroke = try XCTUnwrap(try nodes(g).compactMap(\.shape).last?.paint)
        XCTAssertEqual(stroke.strokeStyle?.lineWidth ?? stroke.lineWidth, 5, "the stroke style follows the width")
        g.tick(now: 1)
        XCTAssertEqual(try fill(g), paintBlue.resolvedColor)
        XCTAssertEqual(try lineWidth(g), 8)
        XCTAssertEqual(try foreground(g), paintBlue.resolvedColor)
    }

    func testAChangeWithoutAnimationSnaps() throws {
        let model = PaintModel()
        let g = Graph(PaintScreen(model: model), scale: 2.5)
        g.flush()
        model.on = true
        g.flush()
        XCTAssertEqual(try fill(g), paintBlue.resolvedColor)
        XCTAssertEqual(try lineWidth(g), 8)
        XCTAssertEqual(try foreground(g), paintBlue.resolvedColor)
    }

    func testABouncyColourOvershootsIntoTheClampAndIsRemovedOnTheTarget() throws {
        let model = PaintModel()
        let g = Graph(PaintScreen(model: model), scale: 2.5)
        g.flush()
        var removed = false
        withAnimation(.bouncy, completionCriteria: .removed) { model.on = true } completion: { removed = true }
        g.flush()
        g.tick(now: 0)
        g.tick(now: 0.315)
        let c = try components(try fill(g))
        XCTAssertTrue(c.allSatisfy { $0 >= 0 && $0 <= 1 }, "never outside 0...1: \(c)")
        XCTAssertGreaterThan(c[2], 0.9, "most of the way to blue at 0.315 s")
        XCTAssertGreaterThan(try lineWidth(g), 7, "the width overshoots or is close to 8")
        XCTAssertFalse(removed)
        g.tickSteps(from: 0.315, to: 4)
        XCTAssertEqual(try fill(g), paintBlue.resolvedColor)
        XCTAssertEqual(try lineWidth(g), 8)
        XCTAssertTrue(removed)
    }

    func testASpringSettlesOnAColourChangeLikeAnOpacityLikeValue() throws {
        guard case .integratedSpring(let k, let c) = Animation.bouncy.curve else { return XCTFail() }
        let colour = SpringMath.integratedSettle(k: k, c: c, displacement: [0, 0, 0, 0, 1], scale: 2.5)
        let tiny = SpringMath.integratedSettle(k: k, c: c, displacement: [0, 0, 0, 0, 0.0005], scale: 2.5)
        XCTAssertGreaterThan(colour, 0.5)
        XCTAssertEqual(tiny, 0, "a change under the opacity tolerance is removed at once")
    }
}

@MainActor
final class SpringRemovalRuleTests: XCTestCase {
    private func width(_ g: Graph) throws -> CGFloat {
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return try XCTUnwrap(walk(try XCTUnwrap(g.snapshot())).first { $0.kind == "Color" }).frame.width
    }

    // Issue #54: an interrupted spring is removed by the same rule as a fresh one, the one-device-pixel tolerance (1.05 / 2.5 = 0.42 pt of width at scale 2.5),
    // not a percentage of its distance (1 % of 200 pt, 2.1 pt, removed it up to 5 times too early).
    func testAnInterruptedSpringIsRemovedOnlyWhenItStaysWithinThePixelTolerance() throws {
        for animation in [Animation.bouncy, Animation.snappy, Animation.spring(duration: 0.6, bounce: -0.2), Animation.default] {
            let model = SpringBarModel()
            let g = Graph(SpringBarScreen(model: model), scale: 2.5)
            g.flush()
            withAnimation(animation) { model.wide = true }
            g.flush()
            g.tick(now: 0)
            g.tick(now: 0.1)
            var removedAt: Double?
            var now = 0.1
            withAnimation(animation, completionCriteria: .removed) { model.wide = false } completion: { removedAt = now }
            g.flush()
            g.tick(now: now)
            var before = try width(g)
            while removedAt == nil, now < 8 {
                before = try width(g)
                now += 0.01
                g.tick(now: now)
            }
            XCTAssertNotNil(removedAt, "\(animation.name) is removed")
            XCTAssertEqual(try width(g), 100, "\(animation.name) lands on the target")
            XCTAssertLessThan(abs(before - 100), 0.6, "\(animation.name): the tick before its removal was already within the pixel tolerance (\(before))")
        }
    }
}

@MainActor
final class ControlTintCarryTests: XCTestCase {
    private func nodes<V: View>(_ view: V) throws -> [ResolvedNode] {
        let g = Graph(view)
        g.rootProposal = ProposedViewSize(width: 300, height: 200)
        g.flush()
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return walk(try XCTUnwrap(g.snapshot()))
    }

    func testButtonToggleAndSliderCarryTheEnvironmentTint() throws {
        let view = VStack {
            Button("Go") {}.buttonStyle(.borderedProminent)
            Toggle("On", isOn: .constant(true))
            Slider(value: .constant(0.4), in: 0...1)
        }.tint(.red)
        let all = try nodes(view)
        for kind in ["Button", "Toggle", "SliderControl"] {
            XCTAssertEqual(all.first { $0.kind == kind }?.tint, Color.red.resolvedColor, kind)
        }
        XCTAssertNil(try nodes(Button("Go") {}).first { $0.kind == "Button" }?.tint, "no tint set: the accent applies")
    }

    func testAProgressViewFillsInTheTint() throws {
        let tinted = try nodes(ProgressView(value: 0.5).tint(.red).frame(width: 100))
        let fills = tinted.compactMap(\.shape).compactMap(\.paint).map(\.color)
        XCTAssertTrue(fills.contains(Color.red.resolvedColor), "the fill capsule is red: \(fills)")
        let plain = try nodes(ProgressView(value: 0.5).frame(width: 100))
        XCTAssertTrue(plain.compactMap(\.shape).compactMap(\.paint).map(\.color).contains(.semantic("accentColor")))
    }
}
