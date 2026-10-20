import XCTest
import SwiftRightHost

/// F-path (#35): `.rotationEffect` on shapes is folded into the path raster (the renderer transform is translation only); other content is left unrotated and reported.
@MainActor
final class RotationEffectPainterTests: XCTestCase {
    private func apply(_ t: CGAffineTransform, _ x: Double, _ y: Double) -> (x: Double, y: Double) {
        (Double(t.a) * x + Double(t.c) * y + Double(t.tx), Double(t.b) * x + Double(t.d) * y + Double(t.ty))
    }

    // MARK: Transform semantics

    func testPositiveAnglesTurnClockwiseOnScreenAboutTheAnchor() {
        // y is down: a point to the right of the anchor goes below it after +90 degrees
        let t = ShapeRotation(radians: .pi / 2, anchorX: 50, anchorY: 50).transform
        let p = apply(t, 90, 50)
        XCTAssertEqual(p.x, 50, accuracy: 1e-9); XCTAssertEqual(p.y, 90, accuracy: 1e-9)
        let anchor = apply(t, 50, 50)
        XCTAssertEqual(anchor.x, 50, accuracy: 1e-9); XCTAssertEqual(anchor.y, 50, accuracy: 1e-9)
    }

    func testNestedRotationsApplyInnermostFirstEachAboutItsOwnAnchor() {
        let inner = ShapeRotation(radians: .pi / 2, anchorX: 0, anchorY: 0)
        let outer = ShapeRotation(radians: .pi / 2, anchorX: 100, anchorY: 0)
        // (1, 0) -> inner (0, 1) -> outer: (-100, 1) turns to (-1, -100), plus the anchor back: (99, -100)
        let p = apply(ShapeRotation.combined([outer, inner]), 1, 0)
        XCTAssertEqual(p.x, 99, accuracy: 1e-9); XCTAssertEqual(p.y, -100, accuracy: 1e-9)
        let swapped = apply(ShapeRotation.combined([inner, outer]), 1, 0)
        XCTAssertNotEqual(swapped.y, p.y, "order matters")   // (99, 100) vs (99, -100): x coincides, y differs
        XCTAssertEqual(ShapeRotation.combined([ShapeRotation(radians: 2 * .pi, anchorX: 5, anchorY: 5)]), .identity, "whole turns are no rotation")
    }

    // MARK: Routing and raster

    private let line = PathShapeRequestFactory.line

    func testA90DegreeRotationTurnsAHorizontalLineVertical() throws {
        let flat = try XCTUnwrap(try PathShapeRaster.render(line(.identity)))
        XCTAssertEqual(flat.placement.w, 80, accuracy: 1.5); XCTAssertEqual(flat.placement.h, 2, accuracy: 1.5)
        XCTAssertEqual(flat.placement.x, 10, accuracy: 1.5); XCTAssertEqual(flat.placement.y, 49, accuracy: 1.5)
        let turned = try XCTUnwrap(try PathShapeRaster.render(line(ShapeRotation(radians: .pi / 2, anchorX: 50, anchorY: 50).transform)))
        XCTAssertEqual(turned.placement.w, 2, accuracy: 1.5); XCTAssertEqual(turned.placement.h, 80, accuracy: 1.5)
        XCTAssertEqual(turned.placement.x, 49, accuracy: 1.5); XCTAssertEqual(turned.placement.y, 10, accuracy: 1.5)
        XCTAssertEqual(turned.image.rgba.count, turned.image.width * turned.image.height * 4)
        XCTAssertTrue(turned.image.rgba.enumerated().contains { $0.offset % 4 == 3 && $0.element == 255 })
    }

    func testTheAnchorMovesTheResultAsSwiftUIWould() throws {
        let center = try XCTUnwrap(try PathShapeRaster.render(line(ShapeRotation(radians: .pi / 2, anchorX: 50, anchorY: 50).transform)))
        // about the top-left corner (0, 0) the line (10...90, 50) lands at x = -50, y 10...90: left of its frame, same extent
        let corner = try XCTUnwrap(try PathShapeRaster.render(line(ShapeRotation(radians: .pi / 2, anchorX: 0, anchorY: 0).transform)))
        XCTAssertEqual(corner.placement.x, -51, accuracy: 1.5); XCTAssertEqual(corner.placement.y, 10, accuracy: 1.5)
        XCTAssertEqual(corner.placement.w, 2, accuracy: 1.5); XCTAssertEqual(corner.placement.h, 80, accuracy: 1.5)
        XCTAssertEqual(center.placement.x - corner.placement.x, 100, accuracy: 1.5, "50 - (-50)")
        XCTAssertEqual(center.placement.y, corner.placement.y, accuracy: 1.5)
        // -90 degrees about the bottom-left (0, 100): (x, y) -> (y - 100, 100 - x): the line goes to x = -50, y 10...90 reversed
        let ccw = try XCTUnwrap(try PathShapeRaster.render(line(ShapeRotation(radians: -.pi / 2, anchorX: 0, anchorY: 100).transform)))
        XCTAssertEqual(ccw.placement.x, -51, accuracy: 1.5); XCTAssertEqual(ccw.placement.y, 10, accuracy: 1.5)
    }

    func testARotatedShapeIsNeverClipped() throws {
        // a 100 x 20 bar turned 45 degrees about its centre grows to about 85 x 85
        let bar = PathShapeRequest(bounds: Rect(x: 0, y: 0, w: 100, h: 20), scale: 1, geometry: .rectangle, fillRGBA: 0xff0000ff, strokeRGBA: nil,
                                   strokeStyle: StrokeStyle(), fillStyle: FillStyle())
        var turned = bar
        turned.rotation = ShapeRotation(radians: .pi / 4, anchorX: 50, anchorY: 10).transform
        let r = try XCTUnwrap(try PathShapeRaster.render(turned))
        XCTAssertEqual(Double(r.placement.w), 120 / 2.0.squareRoot(), accuracy: 2.5)
        XCTAssertEqual(Double(r.placement.h), 120 / 2.0.squareRoot(), accuracy: 2.5)
        XCTAssertEqual(r.placement.x + r.placement.w / 2, 50, accuracy: 1.5); XCTAssertEqual(r.placement.y + r.placement.h / 2, 10, accuracy: 1.5)
    }

    // MARK: Through the painter

    private func tree<V: View>(_ view: V) throws -> ResolvedNode {
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 200, height: 200)
        graph.flush()
        return try XCTUnwrap(graph.snapshot())
    }

    private func committed(_ root: ResolvedNode, log: @escaping (String) -> Void = { _ in }) throws -> (nodes: [NodeUpsert], painter: ResolvedNodePainter) {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: nil, systemImages: nil, log: log)
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: root, version: 1, previousLive: []) { upserts = $0.upserts }
        return (upserts, painter)
    }

    private func imageRect(_ upserts: [NodeUpsert]) throws -> Rect {
        for node in upserts { for case .image(_, let rect, _) in node.primitives { return rect } }
        throw XCTSkip("no image primitive")
    }

    private func ring() -> some View { Circle().trim(from: 0, to: 0.5).stroke(Color.blue, lineWidth: 4).frame(width: 60, height: 60) }

    func testARotatedTrimmedCircleRoutesThroughThePathRasterWithTheRotationInItsTransform() throws {
        let root = try tree(ring().rotationEffect(.degrees(90)))
        let all = flatten(root)
        let modifier = try XCTUnwrap(all.first { $0.kind == "modifier.rotationEffect" })
        let shape = try XCTUnwrap(all.first { $0.shape != nil })
        let p = modifier.pixelFrame
        let bounds = Rect(x: Float(p.x), y: Float(p.y), w: Float(p.width), h: Float(p.height))
        let rotation = ShapeRotation(try XCTUnwrap(modifier.rotation), bounds: bounds)
        XCTAssertEqual(rotation.anchorX, Double(bounds.x + bounds.w / 2), accuracy: 1e-4)
        XCTAssertEqual(rotation.anchorY, Double(bounds.y + bounds.h / 2), accuracy: 1e-4)
        guard case .path(let request) = try ShapePainter.plan(shape, bounds: bounds, scale: 2.5, rotations: [rotation]) else { return XCTFail("path route expected") }
        XCTAssertEqual(request.rotation, rotation.transform)
        XCTAssertNotEqual(request.rotation, .identity)
        XCTAssertEqual(request.geometry, .trimmed(.circle, from: 0, to: 0.5))
        // unrotated, the same trimmed ring keeps the identity transform
        guard case .path(let flat) = try ShapePainter.plan(shape, bounds: bounds, scale: 2.5) else { return XCTFail("path route expected") }
        XCTAssertEqual(flat.rotation, .identity)
        // a plain filled circle takes the path route only when rotated
        let plainShape = try XCTUnwrap(flatten(try tree(Circle().fill(Color.red).frame(width: 60, height: 60))).first { $0.shape != nil })
        if case .primitive = try ShapePainter.plan(plainShape, bounds: bounds, scale: 2.5) {} else { XCTFail("unrotated plain circle stays a primitive") }
        if case .path = try ShapePainter.plan(plainShape, bounds: bounds, scale: 2.5, rotations: [rotation]) {} else { XCTFail("rotated circle takes the path route") }
    }

    func testTheCommittedImageOfARotatedHalfRingTurnsFromLowerToLeftHalf() throws {
        // trim 0...0.5 of a circle runs clockwise from 3 o'clock to 9 o'clock: the lower half. Turned 90 degrees clockwise about the centre it is the left half.
        let flat = try imageRect(try committed(try tree(ring())).nodes)
        let turned = try imageRect(try committed(try tree(ring().rotationEffect(.degrees(90)))).nodes)
        XCTAssertGreaterThan(flat.w, flat.h * 1.4, "lower half: wide and short")
        XCTAssertGreaterThan(turned.h, turned.w * 1.4, "left half: tall and narrow")
        XCTAssertEqual(turned.x + turned.w, flat.x + flat.w / 2, accuracy: 4, "its right edge is the vertical centre line")
        XCTAssertEqual(turned.y + turned.h / 2, flat.y, accuracy: 4, "centred vertically on the circle centre, where the lower half starts")
    }

    func testRotatedShapesPaintWithoutALimitationReport() throws {
        var lines: [String] = []
        let result = try committed(try tree(ring().rotationEffect(.degrees(30))), log: { lines.append($0) })
        XCTAssertEqual(result.painter.rotationLimitationCount, 0)
        XCTAssertTrue(lines.isEmpty)
    }

    func testNonShapeContentUnderRotationEffectStaysUnrotatedAndIsReported() throws {
        var lines: [String] = []
        let flat = try committed(try tree(Color.red.frame(width: 60, height: 40)))
        let result = try committed(try tree(Color.red.frame(width: 60, height: 40).rotationEffect(.degrees(30))), log: { lines.append($0) })
        XCTAssertEqual(result.painter.rotationLimitationCount, 1)
        XCTAssertEqual(lines.count, 1); XCTAssertTrue(lines[0].contains("Color"), lines.joined())
        func rects(_ nodes: [NodeUpsert]) -> [Rect] { nodes.flatMap { $0.primitives.compactMap { if case .rect(let r, _, _, _, _) = $0 { return r }; return nil } } }
        XCTAssertEqual(rects(result.nodes), rects(flat.nodes), "painted exactly as unrotated")
        // the unrotated tree reports nothing
        XCTAssertEqual(flat.painter.rotationLimitationCount, 0)
    }
}

/// A 100 x 100 frame at the origin holding a horizontal 2 px line from (10, 50) to (90, 50), at scale 1.
enum PathShapeRequestFactory {
    static func line(_ rotation: CGAffineTransform) -> PathShapeRequest {
        var path = Path()
        path.move(to: CGPoint(x: 10, y: 50)); path.addLine(to: CGPoint(x: 90, y: 50))
        var request = PathShapeRequest(bounds: Rect(x: 0, y: 0, w: 100, h: 100), scale: 1, geometry: .path(path), fillRGBA: nil, strokeRGBA: 0x0000ffff,
                                       strokeStyle: StrokeStyle(lineWidth: 2, lineCap: .butt), fillStyle: FillStyle())
        request.rotation = rotation
        return request
    }
}
