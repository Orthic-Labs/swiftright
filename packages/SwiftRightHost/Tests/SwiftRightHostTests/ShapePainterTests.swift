import XCTest
import SwiftRightHost

@MainActor
final class ShapePainterTests: XCTestCase {
    private func shapeNode<V: View>(_ view: V, w: CGFloat, h: CGFloat, scale: CGFloat = 2.5) throws -> ResolvedNode {
        let graph = Graph(view, scale: scale)
        graph.rootProposal = ProposedViewSize(width: w, height: h)
        graph.flush()
        return try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.shape != nil })
    }
    private func bounds(_ n: ResolvedNode) -> Rect {
        Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
    }

    func testRectangleFillIsAPlainRect() throws {
        let n = try shapeNode(Rectangle().fill(Color.blue).frame(width: 48, height: 32), w: 100, h: 100)
        guard case .primitive(.rect(let r, let color, let radius, _, _)) = try ShapePainter.plan(n, bounds: bounds(n), scale: 2.5) else { return XCTFail() }
        XCTAssertEqual(r.w, 120); XCTAssertEqual(r.h, 80)
        XCTAssertEqual(color, 0x0088ffff)
        XCTAssertEqual(radius, 0)
    }

    // SR2 R1 (#36): a shape with no .fill/.stroke fills with the inherited foreground style (here set on a Group), else .primary.
    func testBareShapeFillsWithInheritedForegroundStyleElsePrimary() throws {
        let styled = try shapeNode(Group { Rectangle().frame(width: 48, height: 32) }.foregroundStyle(Color.blue), w: 100, h: 100)
        guard case .primitive(.rect(_, let color, _, _, _)) = try ShapePainter.plan(styled, bounds: bounds(styled), scale: 2.5) else { return XCTFail() }
        XCTAssertEqual(color, 0x0088ffff)
        let bare = try shapeNode(Rectangle().frame(width: 48, height: 32), w: 100, h: 100)
        let primary = try shapeNode(Rectangle().fill(Color.primary).frame(width: 48, height: 32), w: 100, h: 100)
        guard case .primitive(.rect(_, let c1, _, _, _)) = try ShapePainter.plan(bare, bounds: bounds(bare), scale: 2.5),
              case .primitive(.rect(_, let c2, _, _, _)) = try ShapePainter.plan(primary, bounds: bounds(primary), scale: 2.5) else { return XCTFail() }
        XCTAssertEqual(c1, c2)
    }

    func testCircleIsTheCentredSquare() throws {
        let n = try shapeNode(Circle().fill(Color.red), w: 40, h: 20)
        let b = bounds(n)
        guard case .primitive(.rect(let r, _, let radius, _, _)) = try ShapePainter.plan(n, bounds: Rect(x: 10, y: 5, w: 100, h: 50), scale: 2.5) else { return XCTFail() }
        XCTAssertEqual(r, Rect(x: 35, y: 5, w: 50, h: 50)); XCTAssertEqual(radius, 25)
        _ = b
    }

    func testCircularRoundedStrokeIsCentredOnThePath() throws {
        let n = try shapeNode(RoundedRectangle(cornerRadius: 6, style: .circular).stroke(Color.blue, lineWidth: 2).frame(width: 40, height: 20), w: 100, h: 100)
        guard case .primitive(.rect(let r, let color, let radius, let border, let width)) = try ShapePainter.plan(n, bounds: Rect(x: 100, y: 100, w: 100, h: 50), scale: 2.5) else { return XCTFail() }
        XCTAssertEqual(color, 0x0088ff00, "stroke background is the border RGB at alpha 0 (#71)"); XCTAssertEqual(border, 0x0088ffff); XCTAssertEqual(width, 5)
        XCTAssertEqual(r, Rect(x: 97.5, y: 97.5, w: 105, h: 55))      // grown by half the 5 px line on every side
        XCTAssertEqual(radius, 15 + 2.5)
    }

    /// #71: models gpui's quad_fragment edge pixel (lerp of straight background toward over(background, border) by inner coverage t, times outer coverage in alpha,
    /// then SRC_ALPHA / INV_SRC_ALPHA over white) and checks the planned stroke yields straight-alpha red: R stays 255, G = B = 255 (1 - a).
    func testStrokeEdgePixelIsStraightAlphaNotSquaredCoverage() throws {
        let n = try shapeNode(RoundedRectangle(cornerRadius: 6, style: .circular).stroke(Color(red: 1, green: 0.2, blue: 0.2), lineWidth: 2).frame(width: 40, height: 20), w: 100, h: 100)
        guard case .primitive(.rect(_, let bg, _, let border, _)) = try ShapePainter.plan(n, bounds: Rect(x: 100, y: 100, w: 100, h: 50), scale: 1.25) else { return XCTFail() }
        func v(_ c: UInt32) -> [Double] { [24, 16, 8, 0].map { Double((c >> UInt32($0)) & 255) / 255 } }
        let b = v(bg), e = v(border), t = 0.25
        // over(background, border): alpha = ea + ba (1 - ea); rgb = (e.rgb ea + b.rgb ba (1 - ea)) / alpha
        let alpha = e[3] + b[3] * (1 - e[3])
        let over = (0..<3).map { (e[$0] * e[3] + b[$0] * b[3] * (1 - e[3])) / alpha }
        let src = (0..<3).map { b[$0] + (over[$0] - b[$0]) * t }
        let a = (b[3] + (alpha - b[3]) * t)         // outer coverage 1
        let out = src.map { UInt8(((($0 * a) + (1 - a)) * 255).rounded()) }
        XCTAssertEqual(out[0], 255, "red keeps full R at partial coverage")
        XCTAssertEqual(out[1], UInt8(((e[1] * 0.25 + 0.75) * 255).rounded()), "G = straight-alpha blend at 25 % coverage, not coverage squared")
        XCTAssertEqual(out[1], out[2])
    }

    func testRectangleStrokeKeepsSharpCorners() throws {
        let n = try shapeNode(Rectangle().stroke(Color.blue, lineWidth: 2), w: 40, h: 20)
        guard case .primitive(.rect(_, _, let radius, _, _)) = try ShapePainter.plan(n, bounds: Rect(x: 10, y: 10, w: 100, h: 50), scale: 2.5) else { return XCTFail() }
        XCTAssertEqual(radius, 0)
    }

    func testDefaultRoundedRectangleIsContinuousAndRoutesToTheRasterizer() throws {
        let n = try shapeNode(RoundedRectangle(cornerRadius: 6).stroke(Color.blue, lineWidth: 2).frame(width: 40, height: 20), w: 100, h: 100)
        guard case .continuous(let request) = try ShapePainter.plan(n, bounds: Rect(x: 100, y: 100, w: 100, h: 50), scale: 2.5) else { return XCTFail("continuous expected") }
        XCTAssertEqual(request.cornerRadiusPX, 15); XCTAssertEqual(request.strokeWidthPX, 5)
        XCTAssertEqual(request.strokeRGBA, 0x0088ffff); XCTAssertNil(request.fillRGBA)
    }

    func testContinuousFillRequest() throws {
        let n = try shapeNode(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.red).frame(width: 40, height: 20), w: 100, h: 100)
        guard case .continuous(let request) = try ShapePainter.plan(n, bounds: Rect(x: 0, y: 0, w: 100, h: 50), scale: 2.5) else { return XCTFail() }
        XCTAssertEqual(request.fillRGBA, 0xff383cff); XCTAssertNil(request.strokeRGBA); XCTAssertEqual(request.strokeWidthPX, 0)
    }

    func testContinuousRasterPlacementBakesTheFractionalOriginIntoTheBitmap() throws {
        // 100x50 px frame at (100.4, 100.6), 5 px stroke: snapped to (100, 101) 100x50; outer edge 97.5/98.5 -> bitmap origin 97/98 with 0.5 baked in.
        let r = try ContinuousShapeRaster.render(ContinuousShapeRequest(bounds: Rect(x: 100.4, y: 100.6, w: 100, h: 50), cornerRadiusPX: 15,
                                                                         fillRGBA: nil, strokeRGBA: 0x0088ffff, strokeWidthPX: 5))
        XCTAssertEqual(r.image.width, 106); XCTAssertEqual(r.image.height, 56)
        XCTAssertEqual(r.placement.x, 97 + 1.0 / 64, accuracy: 1e-6); XCTAssertEqual(r.placement.y, 98 + 1.0 / 64, accuracy: 1e-6)
        XCTAssertEqual(r.placement.w, 106 - 2.0 / 64, accuracy: 1e-6)
        XCTAssertEqual(r.image.rgba.count, 106 * 56 * 4)
        XCTAssertTrue(r.image.rgba.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 })
        // The centre of a stroke-only shape is empty.
        let centre = (28 * 106 + 53) * 4
        XCTAssertEqual(r.image.rgba[centre + 3], 0)
    }

    func testInvalidInputsFailVisibly() {
        XCTAssertThrowsError(try ContinuousShapeRaster.render(ContinuousShapeRequest(bounds: Rect(x: 0, y: 0, w: 0, h: 10), cornerRadiusPX: 1, fillRGBA: 1, strokeRGBA: nil, strokeWidthPX: 0)))
        XCTAssertThrowsError(try ContinuousShapeRaster.render(ContinuousShapeRequest(bounds: Rect(x: 0, y: 0, w: 10, h: 10), cornerRadiusPX: .nan, fillRGBA: 1, strokeRGBA: nil, strokeWidthPX: 0)))
        // a radius past half the short side is no longer refused (round 5 block 30): it is clamped as SwiftUI clamps it
        XCTAssertNoThrow(try ContinuousShapeRaster.render(ContinuousShapeRequest(bounds: Rect(x: 0, y: 0, w: 10, h: 10), cornerRadiusPX: 100, fillRGBA: 1, strokeRGBA: nil, strokeWidthPX: 0)))
    }

    func testRegisteringKeepsTheHandleForTheCaller() throws {
        let images = FakeImages()
        let (primitive, handle) = try ContinuousShapeRaster.primitive(images, ContinuousShapeRequest(bounds: Rect(x: 4, y: 4, w: 40, h: 20), cornerRadiusPX: 5, fillRGBA: 0xff0000ff, strokeRGBA: nil, strokeWidthPX: 0))
        guard case .image(let h, _, _) = primitive else { return XCTFail() }
        XCTAssertEqual(h, handle); XCTAssertEqual(images.live, [handle.raw])
    }
}

/// Round 5 block 30 (hub gaps R7/R8): continuous shapes over the rasteriser's work limit are drawn as bands that abut exactly; a pill radius is accepted.
final class ContinuousShapeBandTests: XCTestCase {
    func testABandedShapeEqualsTheWholeShapeRaster() throws {
        // 800 x 400 px at scale 1 is 320 000 px: under the limit, so rasterise it whole AND by hand in bands to prove the bands are windows onto one path
        let request = ContinuousShapeRequest(bounds: Rect(x: 10, y: 10, w: 800, h: 400), cornerRadiusPX: 99, fillRGBA: 0x336699ff, strokeRGBA: nil, strokeWidthPX: 0, scale: 1)
        let whole = try ContinuousShapeRaster.render(request)
        XCTAssertEqual(whole.image.width, 800)
        var stitched: [UInt8] = []
        var top = 0
        while top < whole.image.height {
            let rows = min(130, whole.image.height - top)
            let band = try ContinuousShapeRaster.render(request, band: (top, rows))
            XCTAssertEqual(band.image.width, 800)
            XCTAssertEqual(band.placement.y, whole.placement.y + Float(top) + (imageGuardBandForTests - imageGuardBandForTests))
            stitched += band.image.rgba
            top += rows
        }
        XCTAssertEqual(stitched, whole.image.rgba, "bands are windows onto the same path")
    }

    func testAShapeOverTheWorkLimitIsSplitIntoBands() throws {
        let request = ContinuousShapeRequest(bounds: Rect(x: 0, y: 0, w: 2250, h: 1500), cornerRadiusPX: 30, fillRGBA: 0xffffffff, strokeRGBA: nil, strokeWidthPX: 0, scale: 2.5)
        XCTAssertThrowsError(try ContinuousShapeRaster.render(request), "a whole 3.4 Mpx raster is over the work limit")
        let bands = try ContinuousShapeRaster.renderBands(request)
        XCTAssertGreaterThan(bands.count, 1)
        XCTAssertEqual(bands.reduce(0) { $0 + $1.image.height }, 1500)
        for b in bands { XCTAssertLessThanOrEqual(b.image.width * b.image.height, 2_000_000) }
        // corners are transparent, the middle is opaque
        XCTAssertEqual(bands[0].image.rgba[3], 0)
        XCTAssertEqual(bands[bands.count / 2].image.rgba[(10 * 2250 + 1000) * 4 + 3], 255)
    }

    func testAPillRadiusIsAcceptedAndAZeroSizeShapeIsRefusedVisibly() throws {
        let pill = ContinuousShapeRequest(bounds: Rect(x: 0, y: 0, w: 200, h: 24), cornerRadiusPX: 99 * 2.5, fillRGBA: 0xff0000ff, strokeRGBA: nil, strokeWidthPX: 0, scale: 2.5)
        let result = try ContinuousShapeRaster.render(pill)
        XCTAssertEqual(result.image.rgba[3], 0, "the pill's corner is transparent")
        XCTAssertEqual(result.image.rgba[((12 * 200) + 100) * 4 + 3], 255)
        let empty = ContinuousShapeRequest(bounds: Rect(x: 0, y: 0, w: 0, h: 10), cornerRadiusPX: 5, fillRGBA: 0xff0000ff, strokeRGBA: nil, strokeWidthPX: 0, scale: 2.5)
        XCTAssertThrowsError(try ContinuousShapeRaster.render(empty))
    }
}
private let imageGuardBandForTests: Float = 0

private struct Witness_ZeroBar: View {
    var body: some View { VStack { RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.red).frame(width: 0, height: 8); Text("x") } }
}
private struct Witness_Pill: View {
    var body: some View { RoundedRectangle(cornerRadius: 99, style: .continuous).fill(Color.blue).frame(width: 80, height: 10) }
}

@MainActor
final class ContinuousShapeEmitTests: XCTestCase {
    private func emit<V: View>(_ view: V) throws -> [(String, NodeEmission)] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        painter.beginCommit()
        defer { painter.endCommit(committed: true) }
        return try flatten(try XCTUnwrap(graph.snapshot())).map { n in
            let b = Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
            return (n.kind, try painter.emit(n, id: UInt64(n.instance + 1), bounds: b))
        }
    }
    func testAZeroSizeContinuousShapePaintsNothing() throws {
        let nodes = try emit(Witness_ZeroBar())
        XCTAssertTrue(try XCTUnwrap(nodes.first { $0.0 == "RoundedRectangle" }).1.primitives.isEmpty)
    }
    func testAPillPaintsOneImage() throws {
        let nodes = try emit(Witness_Pill())
        XCTAssertEqual(try XCTUnwrap(nodes.first { $0.0 == "RoundedRectangle" }).1.primitives.count, 1)
    }
}
