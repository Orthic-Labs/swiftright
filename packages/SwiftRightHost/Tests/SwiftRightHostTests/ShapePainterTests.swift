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
        XCTAssertEqual(color, 0); XCTAssertEqual(border, 0x0088ffff); XCTAssertEqual(width, 5)
        XCTAssertEqual(r, Rect(x: 97.5, y: 97.5, w: 105, h: 55))      // grown by half the 5 px line on every side
        XCTAssertEqual(radius, 15 + 2.5)
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
        XCTAssertThrowsError(try ContinuousShapeRaster.render(ContinuousShapeRequest(bounds: Rect(x: 0, y: 0, w: 10, h: 10), cornerRadiusPX: 100, fillRGBA: 1, strokeRGBA: nil, strokeWidthPX: 0)))
    }

    func testRegisteringKeepsTheHandleForTheCaller() throws {
        let images = FakeImages()
        let (primitive, handle) = try ContinuousShapeRaster.primitive(images, ContinuousShapeRequest(bounds: Rect(x: 4, y: 4, w: 40, h: 20), cornerRadiusPX: 5, fillRGBA: 0xff0000ff, strokeRGBA: nil, strokeWidthPX: 0))
        guard case .image(let h, _, _) = primitive else { return XCTFail() }
        XCTAssertEqual(h, handle); XCTAssertEqual(images.live, [handle.raw])
    }
}
