import Foundation
import SwiftRightRuntime
import XCTest

/// swiftui.padding-frame: sizes measured on macOS (ImageRenderer, scale 2.5) in
/// factory/pipeline/blocks-6-10/padding-frame/flexible-frame-v1 and padding-edges-v1.
@MainActor
final class PaddingFrameTests: XCTestCase {
    private func root<V: View>(_ view: V, width: CGFloat?, height: CGFloat?) -> ResolvedNode? {
        let graph = Graph(view)
        graph.rootProposal = ProposedViewSize(width: width, height: height)
        graph.flush()
        return graph.snapshot()
    }

    private func color(_ node: ResolvedNode?) -> ResolvedNode? {
        guard let node else { return nil }
        if node.kind == "Color" { return node }
        for child in node.children { if let found = color(child) { return found } }
        return nil
    }

    func testMinimumAloneKeepsChildSizeInsteadOfFillingTheOffer() {
        // Mac: Color.red.frame(width: 30, height: 8).frame(minWidth: 70, minHeight: 14, alignment: .trailing) in a 200 x 20 row is 70 x 14.
        struct Witness: View {
            var body: some View {
                Color.red.frame(width: 30, height: 8).frame(minWidth: 70, minHeight: 14, alignment: .trailing)
            }
        }
        let node = root(Witness(), width: 200, height: 20)
        XCTAssertEqual(node?.frame.width, 70)
        XCTAssertEqual(node?.frame.height, 14)
        let red = color(node)
        XCTAssertEqual(red?.frame.width, 30)
        XCTAssertEqual(red?.frame.minX, 40, "trailing alignment inside the 70 pt frame")
    }

    func testMaximumFillsTheOfferUpToTheMaximum() {
        struct Fill: View { var body: some View { Color.red.frame(width: 40, height: 10).frame(maxWidth: .infinity) } }
        struct Capped: View { var body: some View { Color.red.frame(width: 40, height: 10).frame(maxWidth: 100) } }
        XCTAssertEqual(root(Fill(), width: 200, height: 20)?.frame.width, 200, "maxWidth .infinity takes the offer")
        XCTAssertEqual(root(Fill(), width: 200, height: 20)?.frame.height, 10, "the other axis keeps the child")
        XCTAssertEqual(root(Capped(), width: 200, height: 20)?.frame.width, 100)
        XCTAssertEqual(root(Capped(), width: 60, height: 20)?.frame.width, 60, "an offer below the maximum is taken as offered")
    }

    func testOversizedChildUnderMaximumIsCappedAndCentred() {
        // Mac: a 300 pt child under frame(maxWidth: 100) leaves a 100 pt frame with the child centred on it.
        struct Witness: View { var body: some View { Color.red.frame(width: 300, height: 10).frame(maxWidth: 100) } }
        let node = root(Witness(), width: 200, height: 20)
        XCTAssertEqual(node?.frame.width, 100)
        XCTAssertEqual(color(node)?.frame.minX, -100)
    }

    func testBothBoundsOnBothAxesClampTheOffer() {
        // Mac rows: frame(minWidth: 80, maxWidth: 120, minHeight: 10, maxHeight: 16) in rows 200, 100 and 60 wide.
        struct Witness: View { var body: some View { Color.red.frame(minWidth: 80, maxWidth: 120, minHeight: 10, maxHeight: 16) } }
        for (offer, expected) in [(CGFloat(200), CGFloat(120)), (100, 100), (60, 80)] {
            let node = root(Witness(), width: offer, height: 20)
            XCTAssertEqual(node?.frame.width, expected, "offer \(offer)")
            XCTAssertEqual(node?.frame.height, 16)
        }
        XCTAssertEqual(root(Witness(), width: 200, height: 12)?.frame.height, 12)
        XCTAssertEqual(root(Witness(), width: 200, height: 4)?.frame.height, 10)
    }

    func testIdealLengthStandsInForAnUnspecifiedProposal() {
        struct Witness: View { var body: some View { Color.red.frame(idealWidth: 50, maxWidth: .infinity, idealHeight: 12, maxHeight: .infinity) } }
        let ideal = root(Witness(), width: nil, height: nil)
        XCTAssertEqual(ideal?.frame.width, 50)
        XCTAssertEqual(ideal?.frame.height, 12)
        XCTAssertEqual(root(Witness(), width: 80, height: 30)?.frame.width, 80, "a proposal wins over the ideal")
    }

    func testEdgeInsetsPaddingSizesTheViewAndInsetsTheChild() {
        // Mac padding-edges-v1: padding(EdgeInsets(top: 2, leading: 12, bottom: 6, trailing: 4)) inside a 56 x 36 base.
        struct Witness: View {
            var body: some View { Color.red.padding(EdgeInsets(top: 2, leading: 12, bottom: 6, trailing: 4)) }
        }
        let node = root(Witness(), width: 56, height: 36)
        let red = color(node)
        XCTAssertEqual(red?.frame.minX, 12)
        XCTAssertEqual(red?.frame.minY, 2)
        XCTAssertEqual(red?.frame.width, 40)
        XCTAssertEqual(red?.frame.height, 28)

        struct Sized: View {
            var body: some View { Color.red.frame(width: 20, height: 20).padding(EdgeInsets(top: 1, leading: 6, bottom: 3, trailing: 8)) }
        }
        XCTAssertEqual(root(Sized(), width: 100, height: 100)?.frame.width, 34)
        XCTAssertEqual(root(Sized(), width: 100, height: 100)?.frame.height, 24)
    }

    func testEdgeSetPaddingAndDefaultAmount() {
        struct Witness: View { var body: some View { Color.red.padding([.top, .leading], 10).padding(.trailing, 4) } }
        let node = root(Witness(), width: 56, height: 36)
        XCTAssertEqual(color(node)?.frame.minX, 10)
        XCTAssertEqual(color(node)?.frame.minY, 10)
        XCTAssertEqual(color(node)?.frame.width, 56 - 10 - 4)
        XCTAssertEqual(color(node)?.frame.height, 26)
        struct Default: View { var body: some View { Color.red.padding() } }
        XCTAssertEqual(color(root(Default(), width: 56, height: 36))?.frame.width, 24, "the default padding is 16 pt a side (Mac: 56 - 2 x 16)")
    }
}

@MainActor
final class FlexibleFrameStackTests: XCTestCase {
    func testInfiniteMaximumFramesShareWhatFixedSiblingsLeave() {
        // Mac flexible-frame-v1, last row: a 200 pt HStack of red (min 20, max infinity), green 40, red (min 30, max infinity), orange 20
        // gives each red frame (200 - 60) / 2 = 70 pt.
        struct Witness: View {
            var body: some View {
                HStack(spacing: 0) {
                    Color.red.frame(minWidth: 20, maxWidth: .infinity)
                    Color.green.frame(width: 40, height: 20)
                    Color.red.frame(minWidth: 30, maxWidth: .infinity)
                    Color.orange.frame(width: 20, height: 20)
                }.frame(width: 200, height: 20)
            }
        }
        let graph = Graph(Witness())
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var widths: [CGFloat] = []
        func walk(_ n: ResolvedNode) { if n.kind == "Color" { widths.append(n.frame.width) }; n.children.forEach(walk) }
        walk(graph.snapshot()!)
        XCTAssertEqual(widths, [70, 40, 70, 20])
        XCTAssertEqual(graph.snapshot()?.frame.width, 200)
    }

    func testFiniteMaximumFrameIsMeasuredAtItsMaximumForTheInfiniteProposal() {
        struct Capped: View { var body: some View { Color.red.frame(maxWidth: 120) } }
        let graph = Graph(Capped())
        graph.rootProposal = ProposedViewSize(width: .infinity, height: 10)
        graph.flush()
        XCTAssertEqual(graph.snapshot()?.frame.width, 120)
    }
}
