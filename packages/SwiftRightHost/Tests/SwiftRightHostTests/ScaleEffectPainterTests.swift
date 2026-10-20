import XCTest
import SwiftRightHost
import SwiftRightBridge

// SR2 R4 (#39): `.scaleEffect` scales the painting of its subtree about the anchor of its frame: rect bounds, corner radii and stroke widths;
// layout and the siblings' painting are unchanged.

@MainActor
final class ScaleEffectPainterTests: XCTestCase {
    /// The rect primitives committed for the view, in tree order.
    private func rects<V: View>(_ view: V) throws -> [(rect: Rect, radius: Float, border: Float)] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        return upserts.flatMap { $0.primitives }.compactMap {
            if case .rect(let r, _, let radius, _, let border) = $0 { return (r, radius, border) }
            return nil
        }
    }

    func testAUniformScaleAboutTheCentreScalesBoundsAndRadius() throws {
        let plain = try rects(RoundedRectangle(cornerRadius: 4, style: .circular).fill(Color.red).frame(width: 40, height: 20))
        let scaled = try rects(RoundedRectangle(cornerRadius: 4, style: .circular).fill(Color.red).frame(width: 40, height: 20).scaleEffect(2))
        XCTAssertEqual(plain.count, 1); XCTAssertEqual(scaled.count, 1)
        let a = plain[0].rect, b = scaled[0].rect
        XCTAssertEqual(b.w, a.w * 2, accuracy: 1e-3); XCTAssertEqual(b.h, a.h * 2, accuracy: 1e-3)
        XCTAssertEqual(b.x + b.w / 2, a.x + a.w / 2, accuracy: 1e-3, "about the centre")
        XCTAssertEqual(b.y + b.h / 2, a.y + a.h / 2, accuracy: 1e-3)
        XCTAssertEqual(scaled[0].radius, plain[0].radius * 2, accuracy: 1e-3)
    }

    func testATopLeadingAnchorKeepsTheCornerAndSiblingsStayPut() throws {
        let view = VStack(spacing: 0) {
            Color.red.frame(width: 40, height: 20).scaleEffect(1.5, anchor: .topLeading)
            Color.blue.frame(width: 40, height: 20)
        }
        let plain = try rects(VStack(spacing: 0) { Color.red.frame(width: 40, height: 20); Color.blue.frame(width: 40, height: 20) })
        let scaled = try rects(view)
        XCTAssertEqual(scaled[0].rect.x, plain[0].rect.x, accuracy: 1e-3)
        XCTAssertEqual(scaled[0].rect.y, plain[0].rect.y, accuracy: 1e-3)
        XCTAssertEqual(scaled[0].rect.w, plain[0].rect.w * 1.5, accuracy: 1e-3)
        XCTAssertEqual(scaled[1].rect.x, plain[1].rect.x, accuracy: 1e-3, "layout is unchanged")
        XCTAssertEqual(scaled[1].rect.y, plain[1].rect.y, accuracy: 1e-3)
        XCTAssertEqual(scaled[1].rect.w, plain[1].rect.w, accuracy: 1e-3)
    }

    func testNestedScalesCompose() throws {
        let once = try rects(Color.red.frame(width: 40, height: 20).scaleEffect(3))
        let twice = try rects(Color.red.frame(width: 40, height: 20).scaleEffect(1.5).scaleEffect(2))
        XCTAssertEqual(twice[0].rect.w, once[0].rect.w, accuracy: 1e-3)
        XCTAssertEqual(twice[0].rect.x, once[0].rect.x, accuracy: 1e-3)
    }

    func testStrokeWidthScales() throws {
        let plain = try rects(RoundedRectangle(cornerRadius: 6, style: .circular).stroke(Color.red, lineWidth: 2).frame(width: 40, height: 20))
        let scaled = try rects(RoundedRectangle(cornerRadius: 6, style: .circular).stroke(Color.red, lineWidth: 2).frame(width: 40, height: 20).scaleEffect(2))
        XCTAssertEqual(scaled.count, plain.count)
        if let p = plain.first, let s = scaled.first { XCTAssertEqual(s.border, p.border * 2, accuracy: 1e-3) }
    }
}
