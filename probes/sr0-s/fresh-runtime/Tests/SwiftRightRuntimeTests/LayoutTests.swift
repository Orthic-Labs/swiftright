import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// Layout semantics on the headless engine. Geometry is in logical points unless named "pixel".

/// Walks child indices from a snapshot root.
@MainActor
func node(_ root: ResolvedNode?, _ path: Int...) throws -> ResolvedNode {
    var current = try XCTUnwrap(root)
    for index in path {
        current = current.children[index]
    }
    return current
}

@MainActor
func everyNode(_ root: ResolvedNode?) -> [ResolvedNode] {
    guard let root else { return [] }
    return [root] + root.children.flatMap { everyNode($0) }
}

struct WrapProbe: View {
    var body: some View { Text("aaa bbb ccc ddd") }
}

struct SpacerRow: View {
    var body: some View {
        HStack {
            Text("A")
            Spacer()
            Text("B")
        }
    }
}

struct AlignProbe: View {
    let alignment: HorizontalAlignment
    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text("wide text")
            Text("hi")
        }
    }
}

struct PadProbe: View {
    var body: some View { Text("ab").padding(.all, 10) }
}

struct FixedFrameProbe: View {
    var body: some View { Text("x").frame(width: 100, height: 40, alignment: .bottomTrailing) }
}

struct FramedSpacerProbe: View {
    var body: some View {
        HStack {
            Text("A")
            Spacer().frame(width: 20)
            Text("B")
        }
    }
}

struct CrossAxisFramedHStackSpacerProbe: View {
    var body: some View {
        HStack {
            Text("A")
            Spacer().frame(height: 10)
            Text("B")
        }
    }
}

struct CrossAxisFramedVStackSpacerProbe: View {
    var body: some View {
        VStack {
            Text("A")
            Spacer().frame(width: 10)
            Text("B")
        }
    }
}

/// Two subviews side by side when the proposed width reaches the threshold, stacked otherwise.
struct SideBySide: Layout {
    let threshold: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        if (proposal.width ?? CGFloat.infinity) >= threshold {
            return LayoutSize(width: sizes.map(\.width).reduce(0, +), height: sizes.map(\.height).max() ?? 0)
        }
        return LayoutSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).reduce(0, +))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let wide = (proposal.width ?? CGFloat.infinity) >= threshold
        var x = bounds.minX
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(at: LayoutPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            if wide { x += size.width } else { y += size.height }
        }
    }
}

struct AdaptiveProbe: View {
    var body: some View {
        SideBySide(threshold: 200).callAsFunction {
            Text("one")
            Text("two")
        }
    }
}

struct PixelProbe: View {
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text("ab").padding(.all, 3)
            Text("wide text")
        }
    }
}

@Observable
@MainActor
final class LabelModel {
    var first = "one"
    var second = "two"
}

struct LabelProbe: View {
    let model: LabelModel
    var body: some View {
        VStack(spacing: 0) {
            Text(model.first)
            Text(model.second)
            Text("static")
        }
    }
}

@MainActor
final class LayoutTests: XCTestCase {

    func testFrameSetsDimensionsAndAlignsChild() throws {
        let graph = Graph(FixedFrameProbe(), measurer: FixedAdvanceTextMeasurer())
        graph.flush()
        let frame = try node(graph.snapshot(), 0)
        XCTAssertEqual(frame.kind, "modifier.frame")
        XCTAssertEqual(frame.frame, LayoutRect(x: 0, y: 0, width: 100, height: 40))
        XCTAssertEqual(frame.children[0].frame, LayoutRect(x: 92, y: 24, width: 8, height: 16))
    }

    func testFixedFrameStopsSpacerFromTakingRemainingStackSpace() throws {
        let graph = Graph(FramedSpacerProbe())
        graph.rootProposal = ProposedViewSize(width: 300, height: nil)
        graph.flush()
        let stack = try node(graph.snapshot(), 0)
        XCTAssertEqual(stack.children.map(\.frame.width), [8, 20, 8])
    }

    func testCrossAxisFramePreservesHStackSpacerFlexibilityAndHeight() throws {
        let graph = Graph(CrossAxisFramedHStackSpacerProbe())
        graph.rootProposal = ProposedViewSize(width: 300, height: nil)
        graph.flush()
        let spacerFrame = try node(graph.snapshot(), 0, 1)
        XCTAssertGreaterThan(spacerFrame.frame.width, 100)
        XCTAssertEqual(spacerFrame.frame.height, 10)
    }

    func testCrossAxisFramePreservesVStackSpacerFlexibilityAndWidth() throws {
        let graph = Graph(CrossAxisFramedVStackSpacerProbe())
        graph.rootProposal = ProposedViewSize(width: nil, height: 300)
        graph.flush()
        let spacerFrame = try node(graph.snapshot(), 0, 1)
        XCTAssertGreaterThan(spacerFrame.frame.height, 100)
        XCTAssertEqual(spacerFrame.frame.width, 10)
    }

    func testTextWrapsWhenProposedWidthShrinks() throws {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(WrapProbe(), measurer: measurer)
        graph.flush()
        XCTAssertEqual(try node(graph.snapshot()).frame.size, LayoutSize(width: 120, height: 16), "one line when unconstrained")

        graph.rootProposal = ProposedViewSize(width: 60, height: nil)
        graph.flush()
        let text = try node(graph.snapshot(), 0)
        XCTAssertEqual(text.frame.size, LayoutSize(width: 56, height: 32), "wraps to two lines at width 60")
        XCTAssertEqual(text.frame.minX, 0)
    }

    func testHStackDistributesWidthToSpacer() throws {
        let graph = Graph(SpacerRow())
        graph.rootProposal = ProposedViewSize(width: 300, height: nil)
        graph.flush()
        let stack = try node(graph.snapshot(), 0)
        XCTAssertEqual(stack.kind, "HStack")
        XCTAssertEqual(stack.frame.width, 300)
        XCTAssertEqual(stack.children.map(\.kind), ["Text", "Spacer", "Text"])
        XCTAssertEqual(stack.children.map(\.frame.width), [8, 268, 8])
        XCTAssertEqual(stack.children.map(\.frame.minX), [0, 16, 292])
    }

    func testVStackAlignmentLeadingCenterTrailing() throws {
        let expected: [(HorizontalAlignment, CGFloat)] = [(.leading, 0), (.center, 28), (.trailing, 56)]
        for (alignment, minX) in expected {
            let graph = Graph(AlignProbe(alignment: alignment))
            graph.flush()
            let stack = try node(graph.snapshot(), 0)
            XCTAssertEqual(stack.frame.width, 72)
            XCTAssertEqual(stack.children[0].frame.minX, 0, "wide line is at the leading edge")
            XCTAssertEqual(stack.children[1].frame.minX, minX, "short line for \(alignment)")
        }
    }

    func testPaddingInsetsChild() throws {
        let graph = Graph(PadProbe())
        graph.flush()
        let root = try XCTUnwrap(graph.snapshot())
        XCTAssertEqual(root.frame.size, LayoutSize(width: 36, height: 36))
        let padded = try node(graph.snapshot(), 0)
        XCTAssertEqual(padded.kind, "modifier.padding")
        XCTAssertEqual(padded.children[0].frame, LayoutRect(x: 10, y: 10, width: 16, height: 16))
    }

    func testCustomLayoutSwitchesAtWidthThreshold() throws {
        let graph = Graph(AdaptiveProbe())
        graph.rootProposal = ProposedViewSize(width: 300, height: nil)
        graph.flush()
        var layout = try node(graph.snapshot(), 0)
        XCTAssertEqual(layout.kind, "Layout")
        XCTAssertEqual(layout.children.map(\.frame.minX), [0, 24], "side by side when wide")
        XCTAssertEqual(layout.children.map(\.frame.minY), [0, 0])

        graph.rootProposal = ProposedViewSize(width: 150, height: nil)
        graph.flush()
        layout = try node(graph.snapshot(), 0)
        XCTAssertEqual(layout.children.map(\.frame.minX), [0, 0], "stacked when narrow")
        XCTAssertEqual(layout.children.map(\.frame.minY), [0, 16])

        graph.rootProposal = ProposedViewSize(width: 300, height: nil)
        graph.flush()
        layout = try node(graph.snapshot(), 0)
        XCTAssertEqual(layout.children.map(\.frame.minX), [0, 24], "crossing back restores side by side")
    }

    func testFramesArePixelAlignedAtScale2_5() throws {
        let graph = Graph(PixelProbe(), scale: 2.5)
        graph.flush()
        let stack = try node(graph.snapshot(), 0)
        let padded = stack.children[0]
        // Centered in 72 pt: (72 - 22) / 2 = 25 pt, which is 62.5 px and rounds to 63 px (25.2 pt).
        XCTAssertEqual(padded.frame.minX, 25.2, accuracy: 1e-9)
        XCTAssertEqual(padded.pixelFrame.x, 63)

        for item in everyNode(graph.snapshot()) {
            let x0 = item.frame.minX * 2.5
            let x1 = item.frame.maxX * 2.5
            let y0 = item.frame.minY * 2.5
            XCTAssertEqual(x0, x0.rounded(), accuracy: 1e-9, "\(item.id) left edge on pixel grid")
            XCTAssertEqual(y0, y0.rounded(), accuracy: 1e-9, "\(item.id) top edge on pixel grid")
            XCTAssertEqual(item.pixelFrame.x, Int(x0.rounded()), item.id)
            XCTAssertEqual(item.pixelFrame.width, Int(x1.rounded()) - Int(x0.rounded()), item.id)
        }
    }

    func testRelayoutRemeasuresOnlyChangedText() {
        let model = LabelModel()
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(LabelProbe(model: model), measurer: measurer)
        graph.flush()

        let baseline = measurer.requests.count
        model.first = "one!"
        graph.flush()

        let measured = measurer.requests.dropFirst(baseline).map(\.text)
        XCTAssertEqual(measured, ["one!"], "only the changed Text is measured; siblings hit the memo")
    }
}
