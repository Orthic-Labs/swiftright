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
