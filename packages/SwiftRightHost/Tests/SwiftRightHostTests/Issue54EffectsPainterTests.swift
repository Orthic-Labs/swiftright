import XCTest
@testable import SwiftRightHost
import SwiftRightBridge

// Issue #54 (SR2): brightness on bitmaps, non-uniform scale on shapes, and tinted controls.

@MainActor
final class Issue54EffectsPainterTests: XCTestCase {
    private func commit<V: View>(_ view: V, renderer: Bool = false) throws -> (upserts: [NodeUpsert], images: FakeImages, painter: ResolvedNodePainter) {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: FakeRuns(), log: { _ in })
        painter.usesRendererPaths = renderer
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        return (upserts, images, painter)
    }

    private func pixels(_ e: FakeImages.Entry) -> [[UInt8]] {
        stride(from: 0, to: e.rgba.count, by: 4).map { Array(e.rgba[$0..<$0 + 4]) }
    }

    // MARK: brightness on bitmaps

    private func bitmap(_ rgba: [UInt8]) -> RGBAImage { RGBAImage(width: 2, height: 2, rgba: (0..<4).flatMap { _ in rgba })! }

    func testBrightnessAddsToEachChannelOfABitmapAndKeepsItsAlpha() throws {
        // measured for colours on macOS 27 (BrightnessPainterTests): (0.2, 0.4, 0.6) + 0.2 = (102, 153, 204)
        let lit = try commit(Image(decorative: bitmap([51, 102, 153, 255]), scale: 2.5).brightness(0.2))
        XCTAssertEqual(try XCTUnwrap(lit.images.registered.values.first).rgba.prefix(4).map { $0 }, [102, 153, 204, 255])
        let dim = try commit(Image(decorative: bitmap([51, 102, 153, 128]), scale: 2.5).brightness(-0.2))
        XCTAssertEqual(try XCTUnwrap(dim.images.registered.values.first).rgba.prefix(4).map { $0 }, [0, 51, 102, 128], "alpha unchanged")
        let plain = try commit(Image(decorative: bitmap([51, 102, 153, 255]), scale: 2.5))
        XCTAssertEqual(try XCTUnwrap(plain.images.registered.values.first).rgba.prefix(4).map { $0 }, [51, 102, 153, 255])
        XCTAssertEqual(lit.painter.brightnessImageLimitationCount, 0, "a bitmap is adjusted, not reported as a limitation")
    }

    func testNestedBrightnessClampsInnermostFirstAndWholeSubtreeOnly() throws {
        let both = try commit(VStack(spacing: 0) {
            Image(decorative: bitmap([200, 100, 0, 255]), scale: 2.5).brightness(0.3).brightness(-0.5)
            Image(decorative: bitmap([200, 100, 0, 255]), scale: 2.5)
        })
        let adjusted = both.images.registered.values.compactMap { e -> [UInt8]? in e.rgba.prefix(4).map { $0 } == [200, 100, 0, 255] ? nil : e.rgba.prefix(4).map { $0 } }
        // innermost first: 200 + 0.3 clamps to 255, then -0.5 -> 128 (127.5 rounds up); 100 + 0.3 = 176.5 -> 0.5 less 0.5 = 49; 0 + 0.3 -> 77 - 127.5 -> 0
        XCTAssertEqual(adjusted.count, 1)
        XCTAssertEqual(adjusted[0][0], 128)
        XCTAssertEqual(adjusted[0][2], 0)
        XCTAssertEqual(both.images.registered.count, 2, "the sibling outside the modifier is a different image")
    }

    func testBrightenedTableIsTheColourArithmetic() {
        let out = ResolvedNodePainter.brightened([0, 128, 255, 77], by: [0.5])
        XCTAssertEqual(out, [128, 255, 255, 77])
        let down = ResolvedNodePainter.brightened([0, 128, 255, 77], by: [-0.4])
        XCTAssertEqual(down, [0, 26, 153, 77])
    }

    // MARK: non-uniform scale

    private func pathCommands(_ upserts: [NodeUpsert]) -> [[PathCommand]] {
        upserts.flatMap { $0.primitives }.compactMap { if case .pathShape(let spec, _, _, _) = $0 { return spec.commands } else { return nil } }
    }

    private func onCurvePoints(_ commands: [PathCommand]) -> [(Double, Double)] {
        commands.compactMap {
            switch $0 {
            case .move(let x, let y), .line(let x, let y): return (Double(x), Double(y))
            case .quad(_, _, let x, let y): return (Double(x), Double(y))
            case .cubic(_, _, _, _, let x, let y): return (Double(x), Double(y))
            case .close: return nil
            }
        }
    }

    func testACircleUnderANonUniformScaleBecomesAnEllipse() throws {
        let out = try commit(Circle().fill(Color.red).frame(width: 20, height: 20).scaleEffect(x: 3, y: 1), renderer: true)
        let paths = pathCommands(out.upserts)
        XCTAssertEqual(paths.count, 1, "one path shape, not a rect")
        let points = onCurvePoints(try XCTUnwrap(paths.first))
        let xs = points.map(\.0), ys = points.map(\.1)
        let w = (xs.max() ?? 0) - (xs.min() ?? 0), h = (ys.max() ?? 0) - (ys.min() ?? 0)
        XCTAssertEqual(w, 20 * 3 * 2.5, accuracy: 0.5)
        XCTAssertEqual(h, 20 * 2.5, accuracy: 0.5)
        let cx = ((xs.max() ?? 0) + (xs.min() ?? 0)) / 2, cy = ((ys.max() ?? 0) + (ys.min() ?? 0)) / 2
        for (x, y) in points {
            let r = ((x - cx) / (w / 2)) * ((x - cx) / (w / 2)) + ((y - cy) / (h / 2)) * ((y - cy) / (h / 2))
            XCTAssertEqual(r, 1, accuracy: 0.02, "every anchor lies on the ellipse")
        }
    }

    func testACapsuleKeepsItsStraightEdgeAndGetsEllipticalEnds() throws {
        // 40 x 20 pt capsule (ends of radius 10), x2 y0.5: 80 x 10 pt, ends 20 pt wide and 5 pt high. The old route drew a pill of radius 5 pt.
        let out = try commit(Capsule(style: .circular).fill(Color.blue).frame(width: 40, height: 20).scaleEffect(x: 2, y: 0.5), renderer: true)
        let points = onCurvePoints(try XCTUnwrap(pathCommands(out.upserts).first))
        let xs = points.map(\.0)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        XCTAssertEqual(maxX - minX, 80 * 2.5, accuracy: 0.5)
        let minY = points.map(\.1).min() ?? 0
        let top = points.filter { abs($0.1 - minY) < 0.01 }       // the anchors on the top edge: where the straight edge starts and ends
        // The straight edge ends 20 pt in from each side (the cap is 20 pt wide), not 5 pt as for a radius-5 pill.
        let topXs = top.map(\.0)
        XCTAssertEqual((topXs.min() ?? 0) - minX, 20 * 2.5, accuracy: 1.0)
        XCTAssertEqual(maxX - (topXs.max() ?? 0), 20 * 2.5, accuracy: 1.0)
    }

    func testAUniformScaleStillDrawsTheRectPrimitive() throws {
        // factor 2 keeps the bounds on whole device pixels; a factor such as 1.5 lands off the grid and legitimately takes the unsnapped path route (SR2 R4), stretch or not
        let out = try commit(Circle().fill(Color.red).frame(width: 20, height: 20).scaleEffect(2), renderer: true)
        XCTAssertEqual(pathCommands(out.upserts).count, 0)
    }

    func testAStretchedBarOfSolidColourIsStillOneRect() throws {
        let out = try commit(Color.red.frame(width: 20, height: 20).scaleEffect(x: 3, y: 1))
        let rects = out.upserts.flatMap { $0.primitives }.compactMap { p -> Rect? in if case .rect(let r, _, _, _, _) = p { return r } else { return nil } }
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects[0].w, 150, accuracy: 0.6)
        XCTAssertEqual(rects[0].h, 50, accuracy: 0.6)
    }

    func testPaintScaleStretch() {
        XCTAssertFalse(PaintScale(sx: 1.5, sy: 1.5).isStretched)
        let s = PaintScale(sx: 4, sy: 1)
        XCTAssertTrue(s.isStretched)
        XCTAssertEqual(s.uniform, 2, accuracy: 1e-6)
        XCTAssertEqual(s.stretch.x, 2, accuracy: 1e-6)
        XCTAssertEqual(s.stretch.y, 0.5, accuracy: 1e-6)
        XCTAssertTrue(PaintScale(sx: -1, sy: 1).isStretched, "a flip is a stretch of -1")
    }

    // MARK: tinted controls

    func testAccentRemapKeepsTheMixTowardWhiteAndBlackAndLeavesOtherColours() {
        let accent: UInt32 = 0x007bff, red: UInt32 = 0xff0000
        XCTAssertEqual(AccentTint.remap(accent, accent: accent, to: red), red)
        // the disabled prominent fill (0x4fa3ff) is the accent mixed 31 % toward white: the tint mixed by the same share
        let disabled = AccentTint.remap(0x4fa3ff, accent: accent, to: red)
        XCTAssertEqual(disabled >> 16 & 255, 255)
        XCTAssertEqual(Double(disabled >> 8 & 255), 255 * 0.305, accuracy: 4)
        XCTAssertEqual(AccentTint.remap(0xffffff, accent: accent, to: red), 0xffffff)
        XCTAssertEqual(AccentTint.remap(0x000000, accent: accent, to: red), 0x000000)
        XCTAssertEqual(AccentTint.remap(0xe6e6e6, accent: accent, to: red), 0xe6e6e6, "a grey track is not accent")
        XCTAssertEqual(AccentTint.apply(0xe6e6e6, accent: accent, tint: nil), 0xe6e6e6)
    }

    private func hasPixel(_ e: FakeImages.Entry, near rgb: UInt32, within d: Int = 2) -> Bool {
        let want = [Int(rgb >> 16 & 255), Int(rgb >> 8 & 255), Int(rgb & 255)]
        return pixels(e).contains { p in p[3] == 255 && (0..<3).allSatisfy { abs(Int(p[$0]) - want[$0]) <= d } }
    }

    func testAProminentButtonFillsInTheTintWithTheLabelStillWhite() throws {
        let plain = try commit(Button("Run") {}.buttonStyle(.borderedProminent))
        let tinted = try commit(Button("Run") {}.buttonStyle(.borderedProminent).tint(.red))
        let plainImage = try XCTUnwrap(plain.images.registered.values.max { $0.rgba.count < $1.rgba.count })
        let tintedImage = try XCTUnwrap(tinted.images.registered.values.max { $0.rgba.count < $1.rgba.count })
        XCTAssertTrue(hasPixel(plainImage, near: 0x007bff, within: 0))
        XCTAssertFalse(hasPixel(tintedImage, near: 0x007bff, within: 8), "no accent left")
        let red = try XCTUnwrap(HostPaint.rgba(Color.red.resolvedColor, opacity: 1)) >> 8
        XCTAssertTrue(hasPixel(tintedImage, near: red, within: 0))
        let bordered = try commit(Button("Run") {}.tint(.red))
        let borderedImage = try XCTUnwrap(bordered.images.registered.values.max { $0.rgba.count < $1.rgba.count })
        XCTAssertFalse(hasPixel(borderedImage, near: red, within: 8), "a bordered button has no accent fill to tint")
    }

    /// `.tint(.red)` = 0xff383c: a switch track, checkbox box and slider fill measured 249/55/59 on macOS 27 (CI 39579395357), the accent artwork's own 2.35 % shade.
    private let shadedRed: UInt32 = 0xf9373b

    func testTheShadeOfTheArtworkAccentCarriesToTheTint() {
        XCTAssertEqual(AccentTint.shaded(tint: 0xff383c, artworkAccent: 0x0078f9, dark: false), shadedRed)
        XCTAssertEqual(AccentTint.shaded(tint: 0xff383c, artworkAccent: 0x007bff, dark: false), 0xff383c, "the accent itself (a prominent Button) takes the tint as it is")
        // dark: 0x067eff is the accent lightened 2.3 %
        let dark = AccentTint.shaded(tint: 0xff383c, artworkAccent: 0x067eff, dark: true)
        XCTAssertEqual(dark >> 16 & 255, 255)
        XCTAssertEqual(Double(dark >> 8 & 255), 56 + (255 - 56) * 0.0231, accuracy: 1.5)
        XCTAssertEqual(AccentTint.shaded(tint: 0xff383c, artworkAccent: 0xe6e6e6, dark: false), 0xff383c, "not an accent shade: the tint unchanged")
    }

    func testASwitchTracksInTheTintOnlyWhenOn() throws {
        let red = try XCTUnwrap(HostPaint.rgba(Color.red.resolvedColor, opacity: 1)) >> 8
        let on = try commit(Toggle("Enabled", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).tint(.red))
        let onImage = try XCTUnwrap(on.images.registered.values.first)
        XCTAssertTrue(hasPixel(onImage, near: shadedRed, within: 0), "the on track is the tint darkened 2.35 % (measured on the Mac: 249/55/59)")
        XCTAssertFalse(hasPixel(onImage, near: 0x0078f9, within: 8))
        let off = try commit(Toggle("Enabled", isOn: .constant(false)).labelsHidden().toggleStyle(.switch).tint(.red))
        XCTAssertFalse(hasPixel(try XCTUnwrap(off.images.registered.values.first), near: red, within: 8), "the off track keeps its grey")
        let box = try commit(Toggle("Enabled", isOn: .constant(true)).toggleStyle(.checkbox).tint(.red))
        XCTAssertTrue(box.images.registered.values.contains { hasPixel($0, near: shadedRed, within: 0) }, "the checked box is the shaded tint")
    }

    func testASliderFillsInTheTint() throws {
        let tinted = try commit(Slider(value: .constant(0.6), in: 0...1).frame(width: 200).tint(.red))
        let image = try XCTUnwrap(tinted.images.registered.values.max { $0.rgba.count < $1.rgba.count })
        XCTAssertTrue(hasPixel(image, near: shadedRed, within: 2), "the fill is the shaded tint (249/55/59 on the Mac)")
        XCTAssertFalse(hasPixel(image, near: 0x0078f9, within: 6))
    }
}
