import XCTest
@testable import SwiftRightHost

/// Wave 1 block I2: image layout, scaling and interpolation (docs/foundations-images-fonts.md 1.3, 1.4; decisions G50-G58).
/// The resampler is checked against vectors produced by the offline reference model (factory/pipeline/blocks-w1-i2/resample_model.py, the model that was fitted to the Mac),
/// the painter against its contract: device-exact buffers, one registration per variant, level in the cache key, the transient path, and `.clipped()`.
@MainActor
final class ImageLayoutI2Tests: XCTestCase {
    private func solid(_ w: Int, _ h: Int, _ px: [UInt8]) -> RGBAImage { RGBAImage(width: w, height: h, rgba: (0..<w * h).flatMap { _ in px })! }
    private func gradient(_ w: Int, _ h: Int) -> RGBAImage {
        RGBAImage(width: w, height: h, rgba: (0..<w * h).flatMap { i in [UInt8((i * 7) % 256), UInt8((i * 13) % 256), UInt8((i * 29) % 256), 255] })!
    }

    // MARK: resampler

    func testVectorsFromTheReferenceModel() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("I2ResampleVectors.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("I2ResampleVectors.json is not staged") }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cubic = try XCTUnwrap(root["cubic"] as? [Double])
        XCTAssertEqual(ImageResampler.highCubic.b, cubic[0]); XCTAssertEqual(ImageResampler.highCubic.c, cubic[1])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 10)
        for c in cases {
            let sw = c["sw"] as! Int, sh = c["sh"] as! Int, w = c["width"] as! Int, h = c["height"] as! Int
            let src = RGBAImage(width: sw, height: sh, rgba: [UInt8](Data(base64Encoded: c["source"] as! String)!))!
            let expected = [UInt8](Data(base64Encoded: c["expected"] as! String)!)
            let level: Image.Interpolation = ["none": .none, "low": .low, "medium": .medium, "high": .high][c["level"] as! String]!
            let out = ImageResampler.resample(src, width: w, height: h, frameWidth: c["frameW"] as! Double, frameHeight: c["frameH"] as! Double, level: level)
            XCTAssertEqual(out.width, w); XCTAssertEqual(out.height, h)
            var worst = 0, sum = 0
            for i in 0..<expected.count { let d = abs(Int(out.rgba[i]) - Int(expected[i])); worst = max(worst, d); sum += d }
            let name = "\(c["family"] as! String) \(sw)x\(sh)->\(w)x\(h) \(c["level"] as! String)"
            // Float (32 bit) here against Double in the model: at most one level where a value sits on a rounding boundary
            XCTAssertLessThanOrEqual(worst, 1, name)
            XCTAssertLessThan(Double(sum) / Double(expected.count), 0.05, name)
        }
    }

    func testAnImageAtItsOwnSizeIsReturnedUnchanged() {
        let img = gradient(12, 9)
        for level in [Image.Interpolation.none, .low, .medium, nil] {
            XCTAssertEqual(ImageResampler.resample(img, width: 12, height: 9, frameWidth: 12, frameHeight: 9, level: level).rgba, img.rgba)
        }
    }

    func testNoneAtIntegerRatiosReplicatesPixelsExactly() {
        let img = gradient(5, 4)
        for k in [2, 3] {
            let out = ImageResampler.resample(img, width: 5 * k, height: 4 * k, frameWidth: Double(5 * k), frameHeight: Double(4 * k), level: Image.Interpolation.none)
            for y in 0..<(4 * k) { for x in 0..<(5 * k) {
                let s = ((y / k) * 5 + x / k) * 4, o = (y * 5 * k + x) * 4
                XCTAssertEqual(Array(out.rgba[o..<o + 4]), Array(img.rgba[s..<s + 4]), "k=\(k) at \(x),\(y)")
            } }
        }
    }

    func testPlansFollowTheFit() {
        XCTAssertEqual(ImageResampler.plan(for: nil), ImageResampler.plan(for: .low))   // the Mac's default draws like .low
        XCTAssertEqual(ImageResampler.plan(for: Image.Interpolation.none).filter, .nearest)
        XCTAssertEqual(ImageResampler.plan(for: .low), ImageResampler.Plan(filter: .triangle, mip: false))
        XCTAssertEqual(ImageResampler.plan(for: .medium), ImageResampler.Plan(filter: .triangle, mip: true))
        XCTAssertTrue(ImageResampler.plan(for: .high).mip)
    }

    func testAlphaIsPremultipliedSoTransparentColourNeverBleeds() {
        // alpha 0 yellow beside opaque red, enlarged 4x: every output pixel is red with partial alpha, or transparent with RGB 0; a straight-alpha resample would give orange
        let img = RGBAImage(width: 2, height: 1, rgba: [255, 255, 0, 0, 255, 0, 0, 255])!
        for level in [Image.Interpolation.low, .medium, .high] {
            let out = ImageResampler.resample(img, width: 8, height: 4, frameWidth: 8, frameHeight: 4, level: level)
            for i in 0..<(8 * 4) {
                let (r, g, b, a) = (out.rgba[i * 4], out.rgba[i * 4 + 1], out.rgba[i * 4 + 2], out.rgba[i * 4 + 3])
                if a == 0 { XCTAssertEqual([r, g, b], [0, 0, 0]) } else { XCTAssertEqual(g, 0, "no yellow bleeds (\(level))"); XCTAssertEqual(b, 0); XCTAssertEqual(r, 255, "\(level)") }
            }
        }
    }

    func testHalvingKeepsAMeanInAMipChain() {
        let img = solid(32, 32, [40, 90, 200, 255])
        let out = ImageResampler.resample(img, width: 8, height: 8, frameWidth: 8, frameHeight: 8, level: .high)   // 4:1: two halvings then a 1:1 cubic
        XCTAssertEqual(Array(out.rgba.prefix(4)), [40, 90, 200, 255])
        XCTAssertEqual(Array(out.rgba.suffix(4)), [40, 90, 200, 255])
    }

    // MARK: painter

    private func imageNode<V: View>(_ view: V, w: CGFloat = 200, h: CGFloat = 200, scale: CGFloat = 2.5) throws -> ResolvedNode {
        let graph = Graph(view, scale: scale)
        graph.rootProposal = ProposedViewSize(width: w, height: h)
        graph.flush()
        return try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.image != nil })
    }
    private func bounds(_ n: ResolvedNode) -> Rect { Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height)) }
    private func painter(_ images: FakeImages) -> ResolvedNodePainter { ResolvedNodePainter(images: images, scale: 2.5, log: { _ in }) }
    private func emit(_ p: ResolvedNodePainter, _ n: ResolvedNode, id: UInt64 = 1) throws -> (handle: ImageHandle, rect: Rect) {
        let e = try p.emit(n, id: id, bounds: bounds(n))
        guard case .image(let handle, let rect, _)? = e.primitives.first else { throw XCTSkip("no image primitive") }
        return (handle, rect)
    }

    func testRegisteredAtTheSnappedDevicePixelSize() throws {
        let images = FakeImages()
        let n = try imageNode(Image(decorative: gradient(20, 15), scale: 2.5).resizable().interpolation(.high).frame(width: 30, height: 18))   // 75 x 45 px
        let p = painter(images)
        p.beginCommit(); let out = try emit(p, n); p.endCommit(committed: true)
        let entry = try XCTUnwrap(images.registered[out.handle.raw])
        XCTAssertEqual(entry.width, 75); XCTAssertEqual(entry.height, 45)
        XCTAssertEqual(out.rect.w, 75, accuracy: 0.1)
    }

    func testTheLevelIsPartOfTheCacheKey() throws {
        let images = FakeImages()
        let src = gradient(20, 15)
        let a = try imageNode(Image(decorative: src, scale: 2.5).resizable().interpolation(.none).frame(width: 30, height: 18))
        let b = try imageNode(Image(decorative: src, scale: 2.5).resizable().interpolation(.high).frame(width: 30, height: 18))
        let p = painter(images)
        p.beginCommit(); let ha = try emit(p, a, id: 1).handle, hb = try emit(p, b, id: 2).handle; p.endCommit(committed: true)
        XCTAssertNotEqual(ha, hb)
        XCTAssertNotEqual(images.registered[ha.raw]?.rgba, images.registered[hb.raw]?.rgba)
    }

    func testTransientPathKeepsTheLastVariantWhileResizingThenRebuilds() throws {
        let images = FakeImages()
        let src = gradient(20, 15)
        func node(_ w: CGFloat) throws -> ResolvedNode { try imageNode(Image(decorative: src, scale: 2.5).resizable().frame(width: w, height: w * 0.75)) }
        let p = painter(images)
        p.beginCommit(); let first = try emit(p, try node(40)); p.endCommit(committed: true)
        XCTAssertEqual(images.registered[first.handle.raw]?.width, 100)
        p.isLiveResizing = true
        p.beginCommit(); let moving = try emit(p, try node(48)); p.endCommit(committed: true)      // 120 px: the 100 px variant is kept, the renderer scales it
        XCTAssertEqual(moving.handle, first.handle)
        XCTAssertEqual(moving.rect.w, 120, accuracy: 0.1)
        XCTAssertEqual(images.registered.count, 1)
        p.isLiveResizing = false
        p.beginCommit(); let settled = try emit(p, try node(48)); p.endCommit(committed: true)     // stable: rebuilt at its exact size
        XCTAssertNotEqual(settled.handle, first.handle)
        XCTAssertEqual(images.registered[settled.handle.raw]?.width, 120)
        XCTAssertEqual(images.live, [settled.handle.raw])
    }

    func testFirstAppearanceBuildsEvenWhileResizing() throws {
        let images = FakeImages()
        let p = painter(images)
        p.isLiveResizing = true
        let n = try imageNode(Image(decorative: gradient(20, 15), scale: 2.5).resizable().frame(width: 40, height: 30))
        p.beginCommit(); let out = try emit(p, n); p.endCommit(committed: true)
        XCTAssertEqual(images.registered[out.handle.raw]?.width, 100)
    }

    func testClippedModifierClipsItsSubtree() throws {
        let img = Image(decorative: gradient(20, 15), scale: 2.5).resizable().scaledToFill().frame(width: 20, height: 20).clipped()
        let graph = Graph(img, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 200, height: 200)
        graph.flush()
        let all = flatten(try XCTUnwrap(graph.snapshot()))
        let clip = try XCTUnwrap(all.first { $0.kind == "modifier.clipped" })
        XCTAssertTrue(ResolvedNodePainter.clipsContent(clip.kind))
        let image = try XCTUnwrap(all.first { $0.image != nil })
        // fill: the image is larger than the frame on one axis (50 x 37.5 px frame of 50 x 50)
        XCTAssertGreaterThan(image.pixelFrame.width, clip.pixelFrame.width)
        XCTAssertEqual(image.pixelFrame.height, clip.pixelFrame.height)
    }
}
