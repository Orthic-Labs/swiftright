import XCTest
@testable import SwiftRightHost
import SwiftRightBridge

// #53: text ink past its frame is cut by the mask, not the frame; band cover cache and early exits; renderer path clips replace host bands on rev 0.12.

final class ClipBandingTests53: XCTestCase {
    /// 200 x 100 px raster at the origin, 255 left of `edge`, 0 from it on (a vertical edge).
    private func halfPlane(edge: Int) -> ClipMask {
        var a = [UInt8](repeating: 0, count: 200 * 100)
        for y in 0..<100 { for x in 0..<edge { a[y * 200 + x] = 255 } }
        return ClipMask(x0: 0, y0: 0, width: 200, height: 100, alpha: a)
    }

    func testOverhangPastTheFrameIsCutByTheMaskNotTheFrame() {
        let m = halfPlane(edge: 80)
        let frame = Rect(x: 40, y: 10, w: 30, h: 20)
        // The frame is wholly inside the mask; a frame-only region says "all" and would leave overhang to the right unmasked.
        XCTAssertEqual(ClipMask.rectCover([m], region: frame), .all)
        let ink = ClipMask.inkRegion(frame, fontPx: 48)   // 12 px each side: reaches x 82 and y -2
        guard case .rects(let bands) = ClipMask.rectCover([m], region: ink) else { return XCTFail("the ink region crosses the edge") }
        XCTAssertEqual(bands.map { $0.x + $0.w }.max(), 80, "cut at the mask edge, past the frame's own right edge (70)")
        XCTAssertEqual(bands.map(\.x).min(), 28, "ink left of the frame is kept where the mask covers it")
    }

    func testCacheHitReturnsIdenticalBandsAndSurvivesARebuiltMask() {
        ClipMask.bandCache.reset()
        let region = Rect(x: 60, y: 5, w: 40, h: 30)
        let first = ClipMask.rectCover([halfPlane(edge: 80)], region: region)
        XCTAssertEqual(ClipMask.bandCache.hits, 0)
        let again = ClipMask.rectCover([halfPlane(edge: 80)], region: region)   // an equal mask built anew
        XCTAssertEqual(ClipMask.bandCache.hits, 1)
        XCTAssertEqual(first, again)
        XCTAssertEqual(first, .rects([Rect(x: 60, y: 5, w: 20, h: 30)]), "identical rows are one band")
        // A different mask is a miss and a different answer.
        XCTAssertNotEqual(ClipMask.rectCover([halfPlane(edge: 90)], region: region), first)
        XCTAssertEqual(ClipMask.bandCache.hits, 1)
    }

    func testCacheIsBounded() {
        ClipMask.bandCache.reset()
        let m = halfPlane(edge: 80)
        for i in 0..<100 { _ = ClipMask.rectCover([m], region: Rect(x: 60, y: Float(i % 50), w: 40 + Float(i / 50), h: 10 + Float(i % 7))) }
        XCTAssertLessThanOrEqual(ClipMask.bandCache.count, 64)
    }

    func testEarlyExits() {
        ClipMask.bandCache.reset()
        let m = halfPlane(edge: 80)
        XCTAssertEqual(ClipMask.rectCover([m], region: Rect(x: 300, y: 0, w: 20, h: 20)), .none, "apart from the mask's raster")
        XCTAssertEqual(ClipMask.rectCover([m], region: Rect(x: 0, y: 500, w: 20, h: 20)), .none)
        XCTAssertEqual(ClipMask.rectCover([m], region: Rect(x: 10, y: 10, w: 20, h: 20)), .all, "wholly covered")
        XCTAssertEqual(ClipMask.rectCover([m], region: Rect(x: 120, y: 10, w: 20, h: 20)), .none, "wholly outside inside the raster")
        XCTAssertEqual(ClipMask.bandCache.misses, 1, "only the last needed a scan; the others exited before the cache")
        XCTAssertEqual(ClipMask.rectCover([], region: Rect(x: 0, y: 0, w: 5, h: 5)), .all)
    }

    func testClassifyOnlySkipsBands() {
        let m = halfPlane(edge: 80)
        XCTAssertEqual(ClipMask.rectCover([m], region: Rect(x: 60, y: 5, w: 40, h: 30), needBands: false), .rects([]))
    }

    // MARK: painter

    @MainActor
    private func prims(renderer: Bool) throws -> [Primitive] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        painter.usesRendererPaths = renderer
        let graph = Graph(Text("Hello").frame(width: 60, height: 40).clipShape(Circle()), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        return upserts.flatMap { $0.primitives }
    }

    @MainActor
    func testRendererPathClipReplacesHostBandsOnRev012() throws {
        let p = try prims(renderer: true)
        var regions: [Rect] = []
        for prim in p { if case .clipPath(let r, _) = prim { regions.append(r) } }
        XCTAssertEqual(regions.count, 1, "one nested path clip around the single text draw: \(p.count) primitives")
        XCTAssertEqual(p.filter { if case .text = $0 { return true } else { return false } }.count, 1)
        // The text node is 100 x 40 px (not the 60 x 40 pt wrapper); grown by 0.25 em of the 13 pt body at 2.5 = 8.125 px each side.
        let r = try XCTUnwrap(regions.first)
        XCTAssertEqual(r.w, 100 + 2 * 8.125, accuracy: 0.01); XCTAssertEqual(r.h, 40 + 2 * 8.125, accuracy: 0.01)
    }

    @MainActor
    func testHostBandsAreTheFallbackWithoutRendererPaths() throws {
        let p = try prims(renderer: false)
        XCTAssertFalse(p.contains { if case .clipPath = $0 { return true } else { return false } })
        XCTAssertGreaterThan(p.filter { if case .text = $0 { return true } else { return false } }.count, 2)
    }
}
