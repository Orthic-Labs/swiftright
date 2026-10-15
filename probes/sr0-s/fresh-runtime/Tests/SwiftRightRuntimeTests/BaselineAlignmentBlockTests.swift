import SwiftRightRuntime
import XCTest

// Round 5, block swiftui.baseline-alignment. FixedAdvanceTextMeasurer: 16 pt lines, baseline at 12 pt (0.75 of the line), 8 pt per character.
// The rules are measured on macOS 27 (factory/pipeline/blocks-26-34/swiftui.baseline-alignment): a view with no text counts its bottom edge, padding and frames carry the baseline,
// a nested stack passes its first text baseline up, and `lastTextBaseline` uses the last line of a wrapped text.

private struct BARect: View {
    let h: CGFloat
    var body: some View { Rectangle().fill(Color.red).frame(width: 10, height: h) }
}

@MainActor
private func frames(_ view: some View, kinds: [String] = ["Text", "Shape", "Rectangle"]) -> [(String, LayoutRect)] {
    let g = Graph(view, measurer: FixedAdvanceTextMeasurer(), scale: 1)
    g.rootProposal = ProposedViewSize(width: 400, height: 200)
    g.flush()
    return everyNode(g.snapshot()).filter { kinds.contains($0.kind) }.map { ($0.kind, $0.frame) }
}

@MainActor
final class BaselineAlignmentBlockTests: XCTestCase {
    func testATextAndAShapeShareTheTextBaselineAndTheShapesBottom() {
        let f = frames(HStack(alignment: .firstTextBaseline, spacing: 0) { Text("a"); BARect(h: 30) })
        XCTAssertEqual(f[0].1.minY, 18, "baseline 12 aligned to the shape's bottom 30")
        XCTAssertEqual(f[1].1.minY, 0)
        XCTAssertEqual(f[0].1.maxY, 34, "the row is as tall as the lowest descent")
    }

    func testTextsOfDifferentHeightsAlignByBaseline() {
        let f = frames(HStack(alignment: .firstTextBaseline, spacing: 0) { Text("a"); Text("b").padding(.top, 10); Text("c").frame(height: 40, alignment: .bottom) }, kinds: ["Text"])
        // the padded text's baseline is 22, the framed text's 12 + 24 = 36
        XCTAssertEqual(f.map { $0.1.minY + 12 }, [36, 36, 36])
    }

    func testANestedStackPassesItsFirstBaselineUp() {
        let f = frames(HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("a")
            VStack(alignment: .leading, spacing: 4) { Text("b"); Text("c") }
        }, kinds: ["Text"])
        XCTAssertEqual(f[0].1.minY, f[1].1.minY, "the VStack's first baseline is its first text's")
    }

    func testTheLastBaselineOfAWrappedText() {
        let f = frames(HStack(alignment: .lastTextBaseline, spacing: 0) { Text("aaaa bbbb cccc dddd").frame(width: 40); Text("x") }, kinds: ["Text"])
        // 4 words of 4 characters at 8 pt: 32 pt each, one per line in 40 pt -> 4 lines of 16 pt, last baseline 48 + 12 = 60
        XCTAssertEqual(f[0].1.height, 64)
        XCTAssertEqual(f[1].1.minY + 12, f[0].1.minY + 60, accuracy: 0.001)
    }

    func testTheOtherAlignmentsAreUnchanged() {
        let f = frames(HStack(alignment: .top, spacing: 0) { Text("a"); BARect(h: 30) })
        XCTAssertEqual(f[0].1.minY, 0)
        let c = frames(HStack(alignment: .center, spacing: 0) { Text("a"); BARect(h: 30) })
        XCTAssertEqual(c[0].1.minY, 7)
    }
}
