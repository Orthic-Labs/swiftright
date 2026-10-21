import XCTest
@testable import SwiftRightHost
import SwiftRightBridge
import SwiftRightRuntime
import Observation

@Observable
@MainActor
final class NumericPainterModel { var n = 41 }

private struct NumericPainterScreen: View {
    @Bindable var model: NumericPainterModel
    var body: some View { Text("\(model.n)").contentTransition(.numericText()) }
}

// Issue #55: a Text mid numeric roll paints one natural-size run per glyph at its offset, faded by the glyph's opacity, clipped to the line box.
@MainActor
final class NumericTextPainterTests: XCTestCase {
    func testMidRollPaintsGlyphsAtTheirOffsetsAndAlphas() throws {
        let fake = StyledFake()
        let model = NumericPainterModel()
        let graph = Graph(NumericPainterScreen(model: model), measurer: fake, scale: 1)
        graph.rootProposal = ProposedViewSize(width: 400, height: 200)
        graph.flush()
        withAnimation(.linear(duration: 1)) { model.n = 42 }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 1, text: fake, log: { _ in })
        painter.beginCommit()
        var found: [NodeEmission] = []
        for n in flatten(try XCTUnwrap(graph.snapshot())) where n.kind == "Text" {
            let bounds = Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
            found.append(try painter.emit(n, id: UInt64(n.instance + 1), bounds: bounds))
        }
        painter.endCommit(committed: true)
        let emission = try XCTUnwrap(found.first)
        XCTAssertEqual(fake.fragments.map(\.text), ["4", "1", "2"])
        let at = emission.primitives.compactMap { p -> (x: Float, y: Float)? in if case .text(_, let x, let y) = p { return (x, y) } else { return nil } }
        XCTAssertEqual(at.count, 3)
        XCTAssertEqual(at[1].y - at[0].y, -8, "the old digit is half a line up")
        XCTAssertEqual(at[2].y - at[0].y, 8, "the new digit is half a line below")
        XCTAssertEqual(at[2].x - at[0].x, 8)
        // The default text colour is macOS label (alpha 0xd8 = 216); mid-roll glyphs are at half of it.
        XCTAssertEqual((fake.fragments[0].color ?? 0) & 255, 216)
        XCTAssertEqual((fake.fragments[1].color ?? 0) & 255, 108)
        XCTAssertEqual((fake.fragments[2].color ?? 0) & 255, 108)
        let clip = try XCTUnwrap(emission.clipTo)
        XCTAssertEqual(clip.h, 16)
        XCTAssertEqual(emission.semantic?.label, "42")
    }
}
