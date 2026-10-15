import SwiftRightRuntime
import XCTest

// Round 5, block swiftui.layout-priority. Expected sizes are measured on macOS 27 SwiftUI (factory/pipeline/blocks-26-34/swiftui.layout-priority, widths in points).
// The flexible view is `frame(minWidth: 20, idealWidth: 100, maxWidth: 150)`; the stacks are 200 pt wide.

@MainActor private func flex(_ priority: Double? = nil) -> some View {
    let base = Rectangle().fill(Color.red).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20)
    return Group2(base, priority)
}

private struct Group2<V: View>: View {
    let v: V; let p: Double?
    init(_ v: V, _ p: Double?) { self.v = v; self.p = p }
    var body: some View { if let p { v.layoutPriority(p) } else { v } }
}

private struct LPRow: View {
    let items: [(Double?, Bool)]   // (priority, isSpacer)
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { i in
                if items[i].1 { Spacer() } else { flex(items[i].0) }
            }
        }.frame(width: 200, height: 20)
    }
}

@MainActor
final class LayoutPriorityBlockTests: XCTestCase {
    private func sizes(_ items: [(Double?, Bool)]) -> [CGFloat] {
        let g = Graph(LPRow(items: items), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        g.rootProposal = ProposedViewSize(width: 240, height: 100)
        g.flush()
        let nodes = everyNode(g.snapshot())
        return nodes.filter { $0.kind == "Spacer" || $0.kind.contains("Shape") || $0.kind == "Rectangle" || $0.kind == "Color" }.map(\.frame.size.width)
    }

    func testEqualPrioritiesShareEqually() {
        let s = sizes([(nil, false), (nil, false)])
        XCTAssertEqual(s, [100, 100])
    }

    func testHigherPriorityGetsItsMaximumAndTheOtherTheRest() {
        XCTAssertEqual(sizes([(nil, false), (1, false)]), [50, 150])
        XCTAssertEqual(sizes([(1, false), (nil, false)]), [150, 50])
        XCTAssertEqual(sizes([(1, false), (1, false)]), [100, 100])
        XCTAssertEqual(sizes([(-1, false), (nil, false)]), [50, 150])
    }

    func testThreeLevelsKeepTheMinimumOfEachLowerLevel() {
        for width in sizes([(nil, false), (nil, false), (nil, false)]) { XCTAssertEqual(Double(width), 66.67, accuracy: 1) }
        XCTAssertEqual(sizes([(2, false), (1, false), (nil, false)]), [150, 30, 20])
        XCTAssertEqual(sizes([(nil, false), (2, false), (1, false)]), [20, 150, 30])
        XCTAssertEqual(sizes([(1, false), (nil, false), (1, false), (nil, false)]), [80, 20, 80, 20])
    }

    func testASpacerKeepsItsMinimumAndTakesWhatIsLeft() {
        XCTAssertEqual(sizes([(nil, false), (nil, true), (nil, false)]), [96, 8, 96])
        XCTAssertEqual(sizes([(nil, false), (nil, true), (1, false)]), [42, 8, 150])
        XCTAssertEqual(sizes([(1, false), (nil, true), (nil, false)]), [150, 8, 42])
        XCTAssertEqual(sizes([(nil, false), (nil, true), (1, false), (1, false)]), [20, 8, 86, 86])
    }
}
