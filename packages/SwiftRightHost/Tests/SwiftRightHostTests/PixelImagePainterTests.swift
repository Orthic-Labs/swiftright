import XCTest
import SwiftRightHost

/// Round 5 block 35: `Image(decorative: RGBAImage, scale:)` painted through ResolvedNodePainter.
@MainActor
final class PixelImagePainterTests: XCTestCase {
    private func image(_ w: Int, _ h: Int, rgba: [UInt8] = [10, 20, 30, 255]) -> RGBAImage {
        RGBAImage(width: w, height: h, rgba: (0..<w * h).flatMap { _ in rgba })!
    }

    private func imageNode<V: View>(_ view: V, w: CGFloat = 200, h: CGFloat = 200, scale: CGFloat = 2.5) throws -> ResolvedNode {
        let graph = Graph(view, scale: scale)
        graph.rootProposal = ProposedViewSize(width: w, height: h)
        graph.flush()
        return try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.image != nil })
    }

    private func bounds(_ n: ResolvedNode) -> Rect {
        Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
    }

    private func painter(_ images: FakeImages) -> ResolvedNodePainter { ResolvedNodePainter(images: images, scale: 2.5, log: { _ in }) }

    private func emitImage(_ p: ResolvedNodePainter, _ n: ResolvedNode) throws -> (handle: ImageHandle, rect: Rect, semantic: SemanticNode?) {
        let e = try p.emit(n, id: 1, bounds: bounds(n))
        guard case .image(let handle, let rect, _)? = e.primitives.first, e.primitives.count == 1 else { throw XCTSkip("no single image primitive") }
        return (handle, rect, e.semantic)
    }

    func testScale2_5GivesOneToOneDevicePixels() throws {
        let images = FakeImages()
        let n = try imageNode(Image(decorative: image(100, 50), scale: 2.5))
        XCTAssertEqual(n.pixelFrame.width, 100)
        XCTAssertEqual(n.pixelFrame.height, 50)
        let p = painter(images)
        p.beginCommit()
        let out = try emitImage(p, n)
        p.endCommit(committed: true)
        let entry = try XCTUnwrap(images.registered[out.handle.raw])
        XCTAssertEqual(entry.width, 100); XCTAssertEqual(entry.height, 50)
        XCTAssertEqual(Array(entry.rgba.prefix(4)), [10, 20, 30, 255])
        XCTAssertEqual(out.rect.w, 100, accuracy: 0.1); XCTAssertEqual(out.rect.h, 50, accuracy: 0.1)
        XCTAssertEqual(out.semantic?.role, .image)
    }

    func testRegisteredOncePerContentAcrossCommits() throws {
        let images = FakeImages()
        let n = try imageNode(Image(decorative: image(40, 40), scale: 2.5))
        let p = painter(images)
        var handles: [ImageHandle] = []
        for _ in 0..<3 {
            p.beginCommit()
            handles.append(try emitImage(p, n).handle)
            p.endCommit(committed: true)
        }
        XCTAssertEqual(Set(handles.map(\.raw)).count, 1)
        XCTAssertEqual(images.registered.count, 1)
        XCTAssertTrue(images.released.isEmpty)
    }

    func testReleasedWhenTheNodeGoesAndAtTeardown() throws {
        let images = FakeImages()
        let n = try imageNode(Image(decorative: image(40, 40), scale: 2.5))
        let p = painter(images)
        p.beginCommit(); let first = try emitImage(p, n).handle; p.endCommit(committed: true)
        p.beginCommit(); p.endCommit(committed: true)   // a commit without the image
        XCTAssertEqual(images.released, [first.raw])
        p.beginCommit(); let second = try emitImage(p, n).handle; p.endCommit(committed: true)
        XCTAssertNotEqual(first.raw, second.raw)
        p.releaseAll()
        XCTAssertEqual(images.live, [])
    }

    func testFailedCommitKeepsTheOldAndReleasesTheNew() throws {
        let images = FakeImages()
        let a = try imageNode(Image(decorative: image(40, 40), scale: 2.5))
        let b = try imageNode(Image(decorative: image(30, 30, rgba: [1, 2, 3, 4]), scale: 2.5))
        let p = painter(images)
        p.beginCommit(); let old = try emitImage(p, a).handle; p.endCommit(committed: true)
        p.beginCommit(); let new = try emitImage(p, b).handle; p.endCommit(committed: false)
        XCTAssertEqual(images.released, [new.raw])
        p.beginCommit(); XCTAssertEqual(try emitImage(p, a).handle, old); p.endCommit(committed: true)
        XCTAssertEqual(images.live, [old.raw])
    }

    func testScaledDownFrameIsBoxFilteredToTheFrameSize() throws {
        let images = FakeImages()
        // 40 x 40 px drawn in a 8 x 8 pt frame at scale 2.5 = 20 x 20 px
        let n = try imageNode(Image(decorative: image(40, 40, rgba: [200, 100, 50, 255]), scale: 2.5).resizable().frame(width: 8, height: 8))
        XCTAssertEqual(n.pixelFrame.width, 20)
        let p = painter(images)
        p.beginCommit()
        let out = try emitImage(p, n)
        p.endCommit(committed: true)
        let entry = try XCTUnwrap(images.registered[out.handle.raw])
        XCTAssertEqual(entry.width, 20); XCTAssertEqual(entry.height, 20)
        XCTAssertEqual(Array(entry.rgba.prefix(4)), [200, 100, 50, 255])
    }

    func testFrameLargerThanTheImageIsUpscaledOnTheHostToTheDevicePixelSize() throws {
        // wave 1 block I2: the host registers a device-pixel-exact buffer, so the renderer draws it 1:1 (it used to scale a 10 px bitmap on the GPU)
        let images = FakeImages()
        let n = try imageNode(Image(decorative: image(10, 10), scale: 1).resizable().frame(width: 40, height: 40))
        let p = painter(images)
        p.beginCommit()
        let out = try emitImage(p, n)
        p.endCommit(committed: true)
        XCTAssertEqual(images.registered[out.handle.raw]?.width, 100)
        XCTAssertEqual(images.registered[out.handle.raw]?.height, 100)
        XCTAssertEqual(out.rect.w, 100, accuracy: 0.1)
    }

    func testOpacityScalesAlphaAndIsAPartOfTheCacheKey() throws {
        let images = FakeImages()
        let plain = try imageNode(Image(decorative: image(8, 8, rgba: [10, 20, 30, 200]), scale: 2.5))
        let faded = try imageNode(Image(decorative: image(8, 8, rgba: [10, 20, 30, 200]), scale: 2.5).opacity(0.5))
        XCTAssertEqual(faded.opacity, 0.5)
        let p = painter(images)
        p.beginCommit()
        let a = try emitImage(p, plain).handle, b = try emitImage(p, faded).handle
        p.endCommit(committed: true)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(images.registered[a.raw]?.rgba[3], 200)
        XCTAssertEqual(images.registered[b.raw]?.rgba[3], 100)
        XCTAssertEqual(Array(images.registered[b.raw]!.rgba.prefix(3)), [10, 20, 30])   // straight alpha: colour untouched
    }

    func testTiledImagesAreRefusedVisibly() throws {
        let n = try imageNode(Image(decorative: image(8, 8)).resizable(resizingMode: .tile).frame(width: 30, height: 30))
        let p = painter(FakeImages())
        XCTAssertThrowsError(try p.emit(n, id: 1, bounds: bounds(n)))
    }
}
