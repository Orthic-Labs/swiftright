import XCTest
import SwiftRightHost
import SwiftRightBridge

// SR2 R4 (#39): `.brightness` adds its amount to each sRGB channel of the subtree's colours, clamped, alpha unchanged. Expected values measured on
// macOS 27 with ImageRenderer into an sRGB context: (0.2, 0.4, 0.6) + 0.2 = (102, 153, 204); black + 0.5 = 128; white - 0.2 = 204.

@MainActor
final class BrightnessPainterTests: XCTestCase {
    private func colors<V: View>(_ view: V) throws -> [UInt32] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        return upserts.flatMap { $0.primitives }.compactMap { if case .rect(_, let c, _, _, _) = $0 { return c } else { return nil } }
    }

    func testBrightnessAddsToEachChannelAndClamps() throws {
        let base = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 1)
        XCTAssertEqual(try colors(base.frame(width: 10, height: 10).brightness(0.2)), [0x6699ccff])
        XCTAssertEqual(try colors(base.frame(width: 10, height: 10).brightness(-0.2)), [0x003366ff])
        XCTAssertEqual(try colors(Color.black.frame(width: 10, height: 10).brightness(0.5)), [0x808080ff])
        XCTAssertEqual(try colors(Color.white.frame(width: 10, height: 10).brightness(-0.2)), [0xccccccff])
        XCTAssertEqual(try colors(base.opacity(0.5).frame(width: 10, height: 10).brightness(0.2)).map { $0 & 0xffffff00 }, [0x6699cc00], "alpha unchanged")
    }

    func testBrightnessCoversTheSubtreeOnlyAndNests() throws {
        let view = VStack(spacing: 0) {
            Color.black.frame(width: 10, height: 10).brightness(0.1).brightness(0.1)
            Color.black.frame(width: 10, height: 10)
        }
        XCTAssertEqual(try colors(view), [0x333333ff, 0x000000ff])
    }
}
