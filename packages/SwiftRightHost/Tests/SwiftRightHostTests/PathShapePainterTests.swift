import XCTest
import SwiftRightHost

/// F-path P2: which shapes the host sends to the path rasteriser, and that the raster is registered like the continuous route.
@MainActor
final class PathShapePainterTests: XCTestCase {
    private func shapeNode<V: View>(_ view: V, w: CGFloat = 100, h: CGFloat = 100, scale: CGFloat = 2.5) throws -> ResolvedNode {
        let graph = Graph(view, scale: scale)
        graph.rootProposal = ProposedViewSize(width: w, height: h)
        graph.flush()
        return try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.shape != nil })
    }

    private let frame = Rect(x: 100, y: 100, w: 150, h: 150)

    private func plan<V: View>(_ view: V, bounds: Rect? = nil) throws -> ShapePaintPlan {
        try ShapePainter.plan(try shapeNode(view), bounds: bounds ?? frame, scale: 2.5)
    }

    private func request<V: View>(_ view: V, file: StaticString = #filePath, line: UInt = #line) throws -> PathShapeRequest {
        guard case .path(let request) = try plan(view) else { XCTFail("path route expected", file: file, line: line); throw XCTSkip("not a path plan") }
        return request
    }

    private func isPrimitive(_ p: ShapePaintPlan) -> Bool { if case .primitive = p { return true }; return false }
    private func isContinuous(_ p: ShapePaintPlan) -> Bool { if case .continuous = p { return true }; return false }
    private func isPath(_ p: ShapePaintPlan) -> Bool { if case .path = p { return true }; return false }

    // MARK: Routing

    // Issue #74: a one-point column divider (Rectangle().strokeBorder, 2 or 3 device pixels wide at 2.5) must paint, not collapse to nothing.
    func testAOnePointInsetRectangleStrokeStillPaintsItsLine() throws {
        for widthPX: Float in [2, 3] {
            let node = try shapeNode(Rectangle().strokeBorder(Color.red, lineWidth: 1).frame(width: 1, height: 40))
            guard case .path(let request) = try ShapePainter.plan(node, bounds: Rect(x: 100, y: 100, w: widthPX, h: 100), scale: 2.5) else { return XCTFail("path route expected") }
            let result = try XCTUnwrap(try PathShapeRaster.render(request), "width \(widthPX) px")
            let painted = stride(from: 3, to: result.image.rgba.count, by: 4).filter { result.image.rgba[$0] > 0 }.count
            XCTAssertGreaterThan(painted, 100, "width \(widthPX) px painted \(painted) pixels")
        }
    }

    func testATrimmedStrokeTakesThePathRouteWithItsGeometryAndStyle() throws {
        let style = StrokeStyle(lineWidth: 6, lineCap: .round)
        let r = try request(Circle().inset(by: 3).trim(from: 0, to: 0.62).stroke(Color.blue, style: style).frame(width: 60, height: 60))
        XCTAssertEqual(r.geometry, .trimmed(.inset(.circle, by: 3), from: 0, to: 0.62))
        XCTAssertEqual(r.strokeStyle, style)
        XCTAssertEqual(r.strokeRGBA, 0x0088ffff); XCTAssertNil(r.fillRGBA)
        XCTAssertEqual(r.scale, 2.5); XCTAssertEqual(r.bounds, frame)
    }

    func testDashedShapesTakeThePathRouteEvenWhenPlain() throws {
        let dashed = StrokeStyle(lineWidth: 6, dash: [4, 2])
        XCTAssertTrue(isPath(try plan(Circle().stroke(Color.blue, style: dashed))))
        XCTAssertTrue(isPath(try plan(Rectangle().stroke(Color.blue, style: dashed))))
        XCTAssertTrue(isPath(try plan(RoundedRectangle(cornerRadius: 6, style: .circular).stroke(Color.blue, style: dashed))))
        let r = try request(Circle().stroke(Color.blue.opacity(0.7), style: dashed))
        XCTAssertEqual(r.geometry, .circle)
        XCTAssertEqual(try XCTUnwrap(r.strokeRGBA) >> 8, 0x0088ff)
        XCTAssertTrue((178...179).contains(try XCTUnwrap(r.strokeRGBA) & 255), "opacity 0.7 is baked into the colour alpha")
    }

    func testUndashedPlainShapesStayOnTodaysRoute() throws {
        XCTAssertTrue(isPrimitive(try plan(Circle().stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round)))))
        XCTAssertTrue(isPrimitive(try plan(Circle().fill(Color.blue))))
        XCTAssertTrue(isPrimitive(try plan(Rectangle().stroke(Color.blue, lineWidth: 2))))
        XCTAssertTrue(isPrimitive(try plan(Rectangle().stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineJoin: .miter)))))
        XCTAssertTrue(isPrimitive(try plan(RoundedRectangle(cornerRadius: 6, style: .circular).stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineJoin: .bevel)))))
        XCTAssertTrue(isContinuous(try plan(RoundedRectangle(cornerRadius: 6).stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round)))))
        // a dash with no usable on-length draws a plain line
        XCTAssertTrue(isPrimitive(try plan(Circle().stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [0, 0])))))
        XCTAssertTrue(isPrimitive(try plan(Circle().stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [4, -1])))))
    }

    func testARectangleStrokeWithANonMiterJoinOrLowMiterLimitNeedsThePath() throws {
        XCTAssertTrue(isPath(try plan(Rectangle().stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineJoin: .round)))))
        XCTAssertTrue(isPath(try plan(Rectangle().stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineJoin: .bevel)))))
        XCTAssertTrue(isPath(try plan(Rectangle().stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineJoin: .miter, miterLimit: 1.2)))))
    }

    func testInsetCustomAndPathShapesTakeThePathRoute() throws {
        let inset = try request(Circle().inset(by: 4).fill(Color.red, style: FillStyle(eoFill: true)))
        XCTAssertEqual(inset.geometry, .inset(.circle, by: 4))
        XCTAssertEqual(inset.fillRGBA, 0xff383cff); XCTAssertNil(inset.strokeRGBA)
        XCTAssertTrue(inset.fillStyle.isEOFilled)
        XCTAssertTrue(isPath(try plan(Path(CGRect(x: 0, y: 0, width: 10, height: 10)).fill(Color.red))))
        XCTAssertTrue(isPath(try plan(Rectangle().inset(by: 2).stroke(Color.red))))
    }

    func testCapsuleRoutes() throws {
        let wide = Rect(x: 10, y: 10, w: 200, h: 80)
        guard case .primitive(.rect(let rect, _, let radius, _, _)) = try plan(Capsule(style: .circular).fill(Color.red), bounds: wide) else { return XCTFail("circular capsule is a plain rect") }
        XCTAssertEqual(rect, wide); XCTAssertEqual(radius, 40)
        guard case .continuous(let continuous) = try plan(Capsule().fill(Color.red), bounds: wide) else { return XCTFail("default capsule is continuous") }
        XCTAssertEqual(continuous.cornerRadiusPX, 40); XCTAssertEqual(continuous.fillRGBA, 0xff383cff)
        XCTAssertTrue(isPath(try plan(Capsule().trim(from: 0, to: 0.5).stroke(Color.red, lineWidth: 2))))
    }

    // MARK: Raster

    func testARingRasterFitsItsFrameAndPlacesTheBitmapOnAnIntegerOrigin() throws {
        let ringRequest = PathShapeRequest(bounds: frame, scale: 2.5, geometry: .inset(.circle, by: 3), fillRGBA: nil, strokeRGBA: 0x0088ffff,
                                           strokeStyle: StrokeStyle(lineWidth: 6, dash: [4, 2]))
        let result = try XCTUnwrap(try PathShapeRaster.render(ringRequest))
        XCTAssertGreaterThanOrEqual(result.placement.x, 99); XCTAssertLessThanOrEqual(result.placement.x + result.placement.w, 251.1)
        XCTAssertGreaterThanOrEqual(result.placement.y, 99); XCTAssertLessThanOrEqual(result.placement.y + result.placement.h, 251.1)
        XCTAssertEqual(result.placement.x.truncatingRemainder(dividingBy: 1), 1.0 / 64, accuracy: 1e-6)
        XCTAssertEqual(result.placement.w, Float(result.image.width) - 2.0 / 64, accuracy: 1e-5)
        XCTAssertEqual(result.image.rgba.count, result.image.width * result.image.height * 4)
        XCTAssertTrue(result.image.rgba.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 })
        // the middle of the ring is empty
        let cx = Int(frame.x + frame.w / 2 - result.placement.x), cy = Int(frame.y + frame.h / 2 - result.placement.y)
        XCTAssertEqual(result.image.rgba[(cy * result.image.width + cx) * 4 + 3], 0)
    }

    func testAFilledPathCoversItsRectExactly() throws {
        let fill = PathShapeRequest(bounds: Rect(x: 10, y: 20, w: 100, h: 50), scale: 2.5, geometry: .inset(.rectangle, by: 4), fillRGBA: 0xff0000ff, strokeRGBA: nil)
        let result = try XCTUnwrap(try PathShapeRaster.render(fill))
        // inset by 4 pt = 10 px: a 80 x 30 px rectangle at (20, 30)
        XCTAssertEqual(result.image.width, 80); XCTAssertEqual(result.image.height, 30)
        XCTAssertEqual(result.placement.x, 20 + 1.0 / 64, accuracy: 1e-6); XCTAssertEqual(result.placement.y, 30 + 1.0 / 64, accuracy: 1e-6)
        XCTAssertTrue(stride(from: 0, to: result.image.rgba.count, by: 4).allSatisfy { Array(result.image.rgba[$0..<($0 + 4)]) == [255, 0, 0, 255] })
    }

    func testNothingToDrawGivesNilAndRegistersNothing() throws {
        let images = FakeImages()
        let zero = PathShapeRequest(bounds: frame, scale: 2.5, geometry: .trimmed(.inset(.circle, by: 3), from: 0, to: 0), fillRGBA: nil, strokeRGBA: 0x0088ffff,
                                    strokeStyle: StrokeStyle(lineWidth: 6, lineCap: .round))
        XCTAssertNil(try PathShapeRaster.render(zero))
        XCTAssertNil(try PathShapeRaster.primitive(images, zero))
        XCTAssertTrue(images.live.isEmpty)
        let noArea = PathShapeRequest(bounds: Rect(x: 0, y: 0, w: 0, h: 10), scale: 2.5, geometry: .circle, fillRGBA: 1, strokeRGBA: nil)
        XCTAssertNil(try PathShapeRaster.render(noArea))
    }

    func testInvalidInputsFailVisibly() {
        XCTAssertThrowsError(try PathShapeRaster.render(PathShapeRequest(bounds: Rect(x: 0, y: 0, w: .nan, h: 10), scale: 2.5, geometry: .circle, fillRGBA: 1, strokeRGBA: nil)))
        XCTAssertThrowsError(try PathShapeRaster.render(PathShapeRequest(bounds: frame, scale: 0, geometry: .circle, fillRGBA: 1, strokeRGBA: nil)))
    }

    func testRegisteringKeepsTheHandleForTheCaller() throws {
        let images = FakeImages()
        let request = PathShapeRequest(bounds: frame, scale: 2.5, geometry: .trimmed(.inset(.circle, by: 3), from: 0, to: 0.62), fillRGBA: nil,
                                       strokeRGBA: 0x0088ffff, strokeStyle: StrokeStyle(lineWidth: 6, lineCap: .round))
        let (primitive, handle) = try XCTUnwrap(try PathShapeRaster.primitive(images, request))
        guard case .image(let h, _, _) = primitive else { return XCTFail() }
        XCTAssertEqual(h, handle); XCTAssertEqual(images.live, [handle.raw])
    }

    // MARK: Through the painter

    private func emitRing(_ painter: ResolvedNodePainter, trimTo: CGFloat, id: UInt64) throws -> NodeEmission {
        let node = try shapeNode(Circle().inset(by: 3).trim(from: 0, to: trimTo).stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).frame(width: 60, height: 60))
        return try painter.emit(node, id: id, bounds: frame)
    }

    func testAnAnimatedRingReleasesItsPreviousImageAndReleaseAllEmptiesTheRegistry() throws {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: nil, systemImages: nil, log: { _ in })
        var seen: [UInt64] = []
        for trim in [0.1, 0.3, 0.62] as [CGFloat] {
            painter.beginCommit()
            let emission = try emitRing(painter, trimTo: trim, id: 7)
            guard case .image(let handle, _, _) = try XCTUnwrap(emission.primitives.first) else { return XCTFail("a ring is one image primitive") }
            XCTAssertEqual(emission.primitives.count, 1)
            painter.endCommit(committed: true)
            seen.append(handle.raw)
            XCTAssertEqual(images.live, [handle.raw], "exactly the current frame's image stays registered")
        }
        XCTAssertEqual(Set(seen).count, 3)
        // a frame that draws nothing (zero trim) leaves no image behind for the node
        painter.beginCommit()
        let empty = try emitRing(painter, trimTo: 0, id: 7)
        XCTAssertTrue(empty.primitives.isEmpty)
        painter.endCommit(committed: true)
        XCTAssertTrue(images.live.isEmpty)
        painter.beginCommit(); _ = try emitRing(painter, trimTo: 0.5, id: 7); painter.endCommit(committed: true)
        painter.releaseAll()
        XCTAssertTrue(images.live.isEmpty)
    }

    func testAFailedCommitReleasesThePathImageItCreated() throws {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: nil, systemImages: nil, log: { _ in })
        painter.beginCommit(); _ = try emitRing(painter, trimTo: 0.3, id: 1); painter.endCommit(committed: true)
        let first = images.live
        painter.beginCommit(); _ = try emitRing(painter, trimTo: 0.4, id: 1); painter.endCommit(committed: false)
        XCTAssertEqual(images.live, first, "the previous image is kept, the failed commit's is released")
    }
}
