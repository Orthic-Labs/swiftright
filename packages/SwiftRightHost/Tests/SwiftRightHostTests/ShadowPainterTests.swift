import XCTest
import SwiftRightHost
import SwiftRightBridge

// #82: `.shadow` is a Gaussian blur (sigma = radius) of the subtree's shape alpha. Expected alpha measured on macOS 27 (ImageRenderer at 1x, black shadow, a 40 x 40 white
// rectangle at x 40..80, y 30..70): radius 8 -> alpha 122 / 37 / 3 at x = 80 / 88 / 96 on the centre row; with y = 6 the same profile appears 6 rows lower; radius 4 x = y = 3
// -> 186 / 21 at x = 80 / 88 (row 50).

@MainActor
final class ShadowPainterTests: XCTestCase {
    private func shadowAlpha<V: View>(_ view: V, at x: Int, y: Int) throws -> Int {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 1, text: FakeRuns(), log: { _ in })
        let graph = Graph(view, scale: 1)
        graph.rootProposal = ProposedViewSize(width: 120, height: 100)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        for u in upserts { for case .image(let handle, let rect, _) in u.primitives {
            guard let e = images.registered[handle.raw] else { continue }
            let lx = x - Int(rect.x), ly = y - Int(rect.y)
            guard lx >= 0, ly >= 0, lx < Int(e.width), ly < Int(e.height) else { return 0 }
            let width = Int(e.width)
            let index: Int = (ly * width + lx) * 4 + 3
            return Int(e.rgba[index])
        } }
        return 0
    }

    private func box(radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        Rectangle().fill(Color.white).frame(width: 40, height: 40).shadow(color: .black, radius: radius, x: x, y: y)
            .frame(width: 120, height: 100)
    }

    func testRadius8ProfileMatchesTheMac() throws {
        for (px, want) in [(80, 122), (88, 37), (96, 3)] {
            XCTAssertEqual(Double(try shadowAlpha(box(radius: 8), at: px, y: 50)), Double(want), accuracy: 8, "x=\(px)")
        }
    }

    func testOffsetMovesTheShadow() throws {
        // below the rectangle (bottom edge y = 70): with y = 6 the shadow reaches further down than without
        let plain = try shadowAlpha(box(radius: 8), at: 60, y: 76), moved = try shadowAlpha(box(radius: 8, y: 6), at: 60, y: 76)
        XCTAssertGreaterThan(moved, plain + 30)
    }

    func testRadius4WithOffset() throws {
        for (px, want) in [(80, 186), (88, 21)] {
            XCTAssertEqual(Double(try shadowAlpha(box(radius: 4, x: 3, y: 3), at: px, y: 50)), Double(want), accuracy: 10, "x=\(px)")
        }
    }
}
