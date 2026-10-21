import XCTest
import SwiftRightHost
import SwiftRightBridge

// SR2 R6 (#41): `.clipShape` masks the subtree's host-rasterised shapes and solid rects to the shape; content fully inside is untouched; text is rect-clipped.

@MainActor
final class ClipShapePainterTests: XCTestCase {
    private func commit<V: View>(_ view: V) throws -> (prims: [Primitive], images: FakeImages, upserts: [NodeUpsert]) {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        return (upserts.flatMap { $0.primitives }.filter {
            switch $0 { case .clipPush, .clipPop: return false; default: return true }
        }, images, upserts)
    }

    func testAColourUnderACircleClipIsMaskedToTheCircle() throws {
        let (prims, images, _) = try commit(Color.red.frame(width: 40, height: 40).clipShape(Circle()))
        guard case .image(let handle, let placement, _) = try XCTUnwrap(prims.first) else { return XCTFail("masked raster expected: \(prims)") }
        let entry = try XCTUnwrap(images.registered[handle.raw])
        let w = Int(entry.width), h = Int(entry.height)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { entry.rgba[(y * w + x) * 4 + 3] }
        XCTAssertEqual(alpha(w / 2, h / 2), 255, "centre inside")
        XCTAssertEqual(alpha(2, 2), 0, "corner outside the circle")
        XCTAssertEqual(Int(placement.w.rounded()), 100)
    }

    func testContentFullyInsideTheClipIsUntouched() throws {
        let (prims, _, _) = try commit(Color.red.frame(width: 10, height: 10).frame(width: 40, height: 40).clipShape(Circle()))
        XCTAssertEqual(prims.count, 1)
        guard case .rect = prims[0] else { return XCTFail("a rect wholly inside stays a rect: \(prims)") }
    }

    func testAShapeUnderTheClipIsMaskedAndARectClipBoundsItsSubtree() throws {
        let (prims, images, upserts) = try commit(
            ZStack { Circle().stroke(Color.blue, lineWidth: 4).frame(width: 60, height: 60) }.frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10, style: .circular)))
        XCTAssertFalse(prims.isEmpty)
        XCTAssertTrue(upserts.contains { u in u.primitives.contains { if case .clipPush = $0 { return true } else { return false } } }, "the subtree is clipped to the clip's bounds")
        XCTAssertFalse(images.registered.isEmpty)
    }

    func testARectangleClipIsAPlainRectClip() throws {
        let (prims, _, _) = try commit(Color.red.frame(width: 60, height: 60).frame(width: 40, height: 40).clipShape(Rectangle()))
        XCTAssertTrue(prims.contains { if case .rect = $0 { return true } else { return false } }, "no mask for a rectangle: \(prims)")
    }
}

// #43: text under a non-rectangular clip is drawn once per band of the clip's inside, each band a rect clip.
@MainActor
final class ClipShapeTextTests: XCTestCase {
    private func prims<V: View>(_ view: V) throws -> [Primitive] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        return upserts.flatMap { $0.primitives }
    }
    private func textCount(_ p: [Primitive]) -> Int { p.filter { if case .text = $0 { return true } else { return false } }.count }

    func testTextAcrossACurvedClipEdgeIsDrawnInBandsInsideTheClip() throws {
        let p = try prims(Text("Hello").frame(width: 60, height: 40).clipShape(Circle()))
        XCTAssertGreaterThan(textCount(p), 2, "one draw per band: \(p.count) primitives")
        var bands: [Rect] = []
        var depth = 0
        for prim in p {
            if case .clipPush(let r) = prim { depth += 1; if depth == 2 { bands.append(r) } }
            if case .clipPop = prim { depth -= 1 }
        }
        XCTAssertFalse(bands.isEmpty)
        // a 40 pt circle in a 60 x 40 pt frame: 100 px across, centred at x 75 px; every band lies inside its bounding square
        for b in bands { XCTAssertGreaterThanOrEqual(b.x, 24); XCTAssertLessThanOrEqual(b.x + b.w, 126) }
        let widest = bands.map(\.w).max() ?? 0
        let narrowest = bands.map(\.w).min() ?? 0
        XCTAssertGreaterThan(widest, narrowest, "the bands follow the curve")
    }

    func testTextWhollyInsideTheClipIsOneDraw() throws {
        let p = try prims(Text("Hi").frame(width: 20, height: 10).frame(width: 100, height: 100).clipShape(Circle()))
        XCTAssertEqual(textCount(p), 1)
    }

    func testTextWhollyOutsideTheClipIsNotDrawn() throws {
        let p = try prims(Text("Hi").frame(width: 20, height: 10).offset(x: -48, y: -48).frame(width: 100, height: 100).clipShape(Circle()))
        // The frame's nearest corner is 57 pt from the circle's centre (radius 50); its 0.25 em ink margin (3.25 pt) still leaves it outside (about 53 pt). At -45 the
        // frame was 53 pt out and the margin reached the circle (#53): ink could genuinely overhang that far, so that placement draws.
        XCTAssertEqual(textCount(p), 0)
    }

    // Issue #76: a text run under a curved clip is filled from its outline with the clip's anti-aliased coverage, as a bitmap, instead of the renderer's band or path clip.
    @MainActor
    func testTextUnderACurvedClipIsAnAntialiasedBitmapWhenOutlinesExist() throws {
        let fake = StyledFake(); fake.squareOutlines = true
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: fake, log: { _ in })
        painter.usesRendererPaths = true
        let graph = Graph(Text("Hello").frame(width: 60, height: 40).clipShape(Circle()), measurer: fake, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        let prims = upserts.flatMap { $0.primitives }
        XCTAssertFalse(prims.contains { if case .text = $0 { return true } else { return false } }, "the run is drawn as a bitmap")
        XCTAssertFalse(prims.contains { if case .clipPath = $0 { return true } else { return false } }, "no renderer clip around it")
        let bitmaps = prims.compactMap { p -> ImageHandle? in if case .image(let h, _, _) = p { return h } else { return nil } }
        XCTAssertEqual(bitmaps.count, 1)
        let entry = try XCTUnwrap(images.registered[bitmaps[0].raw])
        let partial = stride(from: 3, to: entry.rgba.count, by: 4).filter { entry.rgba[$0] > 0 && entry.rgba[$0] < 255 }.count
        XCTAssertGreaterThan(partial, 0, "an anti-aliased edge has partial coverage")
    }
}
