import XCTest
import SwiftRightHost
import SwiftRightBridge

/// ABI 0.12 (#52): a vector path shape is handed to the renderer as `Primitive.pathShape` when the host says the renderer supports it
/// (`ResolvedNodePainter.usesRendererPaths`, set from `Bridge.supportsPaths`); otherwise, and under a clip mask or for a dashed stroke, it stays the host bitmap.
@MainActor
final class PathShapeRendererTests: XCTestCase {
    private let line = PathShapeRequestFactory.line

    func testALineBecomesTwoCommandsInWindowPixelsWithTheStrokeInPixels() throws {
        let d = try XCTUnwrap(try PathShapeRaster.rendererPath(line(.identity)))
        XCTAssertEqual(d.spec.commands, [.move(10, 50), .line(90, 50)])
        XCTAssertEqual(d.fill, 0)
        XCTAssertEqual(d.strokeColor, 0x0000ffff)
        XCTAssertEqual(d.strokeWidthPX, 2, accuracy: 1e-6)
        XCTAssertEqual(d.spec.cap, .butt)
        XCTAssertEqual(d.spec.join, .miter)
        XCTAssertFalse(d.spec.evenOdd)
    }

    func testRotationAndScaleAreFoldedIntoThePoints() throws {
        let turned = try XCTUnwrap(try PathShapeRaster.rendererPath(line(ShapeRotation(radians: .pi / 2, anchorX: 50, anchorY: 50).transform)))
        guard case .move(let x0, let y0) = turned.spec.commands[0], case .line(let x1, let y1) = turned.spec.commands[1] else { return XCTFail("move, line") }
        // +90 degrees about (50, 50): (10, 50) -> (50, 10), (90, 50) -> (50, 90)
        XCTAssertEqual([x0, y0, x1, y1].map { ($0 * 1000).rounded() / 1000 }, [50, 10, 50, 90])
        XCTAssertEqual(turned.strokeWidthPX, 2, accuracy: 1e-5, "a rotation does not change the width")
        var scaled = line(.identity)
        scaled.scale = 2
        let d = try XCTUnwrap(try PathShapeRaster.rendererPath(scaled))
        XCTAssertEqual(d.spec.commands, [.move(20, 100), .line(180, 100)], "points are in points, the device point is p * scale")
        XCTAssertEqual(d.strokeWidthPX, 4, accuracy: 1e-5)
    }

    func testFillOnlyEvenOddCapAndJoinCarryThrough() throws {
        var path = Path()
        path.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
        path.addRect(CGRect(x: 2, y: 2, width: 6, height: 6))
        let fill = PathShapeRequest(bounds: Rect(x: 4, y: 6, w: 10, h: 10), scale: 1, geometry: .path(path), fillRGBA: 0xff0000ff, strokeRGBA: nil,
                                    strokeStyle: StrokeStyle(), fillStyle: FillStyle(eoFill: true))
        let d = try XCTUnwrap(try PathShapeRaster.rendererPath(fill))
        XCTAssertTrue(d.spec.evenOdd)
        XCTAssertEqual(d.fill, 0xff0000ff)
        XCTAssertEqual(d.strokeWidthPX, 0)
        XCTAssertEqual(d.strokeColor, 0)
        guard case .move(let x, let y) = d.spec.commands[0] else { return XCTFail("move first") }
        XCTAssertEqual([x, y], [4, 6], "placed at the snapped origin of its bounds")
        var stroke = fill
        stroke.fillRGBA = nil; stroke.strokeRGBA = 0x00ff00ff
        stroke.strokeStyle = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .bevel, miterLimit: 5)
        let s = try XCTUnwrap(try PathShapeRaster.rendererPath(stroke))
        XCTAssertEqual(s.spec.cap, .round)
        XCTAssertEqual(s.spec.join, .bevel)
        XCTAssertEqual(s.spec.miterLimit, 5)
        XCTAssertEqual(s.strokeWidthPX, 3, accuracy: 1e-6)
    }

    func testDashedAndEmptyAndInvisibleHaveNoRendererPath() throws {
        var dashed = line(.identity)
        dashed.strokeStyle = StrokeStyle(lineWidth: 2, dash: [4, 2])
        XCTAssertNil(try PathShapeRaster.rendererPath(dashed), "the renderer has no dash: the host bitmap draws it")
        var clear = line(.identity)
        clear.strokeRGBA = 0x0000ff00
        XCTAssertNil(try PathShapeRaster.rendererPath(clear), "alpha 0 paints nothing")
        var none = line(.identity)
        none.strokeStyle = StrokeStyle(lineWidth: 0)
        XCTAssertNil(try PathShapeRaster.rendererPath(none))
        var empty = line(.identity)
        empty.geometry = .path(Path())
        XCTAssertNil(try PathShapeRaster.rendererPath(empty))
    }

    // MARK: Through the painter

    private func tree<V: View>(_ view: V) throws -> ResolvedNode {
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 200, height: 200)
        graph.flush()
        return try XCTUnwrap(graph.snapshot())
    }

    private func commit(_ root: ResolvedNode, paths: Bool) throws -> (nodes: [NodeUpsert], painter: ResolvedNodePainter) {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: nil, systemImages: nil)
        painter.usesRendererPaths = paths
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: root, version: 1, previousLive: []) { upserts = $0.upserts }
        return (upserts, painter)
    }

    private func counts(_ nodes: [NodeUpsert]) -> (images: Int, paths: Int) {
        var i = 0, p = 0
        for n in nodes { for prim in n.primitives { if case .image = prim { i += 1 }; if case .pathShape = prim { p += 1 } } }
        return (i, p)
    }

    private func ring() -> some View { Circle().trim(from: 0, to: 0.5).stroke(Color.blue, lineWidth: 4).frame(width: 60, height: 60) }

    func testTheGateSelectsTheRendererPathOrTheBitmap() throws {
        let off = try commit(try tree(ring()), paths: false)
        XCTAssertEqual(counts(off.nodes).images, 1)
        XCTAssertEqual(counts(off.nodes).paths, 0)
        XCTAssertEqual(off.painter.rendererPathCount, 0)
        let on = try commit(try tree(ring()), paths: true)
        XCTAssertEqual(counts(on.nodes).images, 0, "no host bitmap on a 0.12 renderer")
        XCTAssertEqual(counts(on.nodes).paths, 1)
        XCTAssertEqual(on.painter.rendererPathCount, 1)
        XCTAssertFalse(ResolvedNodePainter(images: FakeImages(), scale: 1, text: nil, systemImages: nil).usesRendererPaths, "off by default")
    }

    func testTheEmittedStrokeIsTheRingInPixels() throws {
        let on = try commit(try tree(ring()), paths: true)
        for n in on.nodes { for case .pathShape(let spec, let fill, let strokeColor, let width) in n.primitives {
            XCTAssertEqual(fill, 0)
            XCTAssertNotEqual(strokeColor & 255, 0)
            XCTAssertEqual(width, 4 * 2.5, accuracy: 1e-4, "4 pt at scale 2.5")
            XCTAssertTrue(spec.commands.contains { if case .cubic = $0 { return true }; return false }, "an arc is cubics, not a flattened polygon")
            return
        } }
        XCTFail("no path primitive")
    }

    func testAShapeUnderAClipMaskStaysAMaskedBitmap() throws {
        let clipped = try commit(try tree(ring().clipShape(Circle())), paths: true)
        XCTAssertEqual(counts(clipped.nodes).paths, 0, "the renderer clips by bands; only the shape's own mask has the soft edge")
        XCTAssertEqual(counts(clipped.nodes).images, 1)
    }

    // MARK: Path clip (text and bitmaps under `.clipShape`)

    private func prims<V: View>(_ view: V, paths: Bool) throws -> [Primitive] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        painter.usesRendererPaths = paths
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        return upserts.flatMap { $0.primitives }
    }

    func testTextAcrossACurvedClipIsOneDrawUnderAPathClipOnARendererPathHost() throws {
        let view = Text("Hello").frame(width: 60, height: 40).clipShape(Circle())
        let banded = try prims(view, paths: false)
        XCTAssertGreaterThan(banded.filter { if case .text = $0 { return true } else { return false } }.count, 2, "the earlier host bands (#43) are unchanged")
        XCTAssertFalse(banded.contains { if case .clipPath = $0 { return true } else { return false } })
        let p = try prims(view, paths: true)
        XCTAssertEqual(p.filter { if case .text = $0 { return true } else { return false } }.count, 1)
        var clips = 0, pops = 0
        for prim in p {
            if case .clipPath(let r, let spec) = prim {
                clips += 1
                XCTAssertGreaterThan(r.w, 0)
                XCTAssertTrue(spec.commands.contains { if case .cubic = $0 { return true }; return false }, "a circle is cubics")
            }
            if case .clipPop = prim { pops += 1 }
        }
        XCTAssertEqual(clips, 1)
        XCTAssertGreaterThanOrEqual(pops, clips, "every path clip is closed")
    }

    func testTextWhollyInsideTheClipNeedsNoClipOnARendererPathHost() throws {
        let p = try prims(Text("Hi").frame(width: 20, height: 10).frame(width: 100, height: 100).clipShape(Circle()), paths: true)
        XCTAssertFalse(p.contains { if case .clipPath = $0 { return true } else { return false } })
    }
}
