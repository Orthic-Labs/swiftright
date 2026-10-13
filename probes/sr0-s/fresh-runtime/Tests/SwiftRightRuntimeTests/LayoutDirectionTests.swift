import SwiftRightRuntime
import XCTest

private struct LayoutDirectionProbe: View {
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        Text(direction == .leftToRight ? "ltr" : "rtl")
    }
}

@MainActor
final class LayoutDirectionTests: XCTestCase {
    func testLayoutDirectionRoundTripAndEnvironmentReader() {
        var values = EnvironmentValues()
        XCTAssertEqual(values.layoutDirection, .leftToRight)

        values.layoutDirection = .rightToLeft
        XCTAssertEqual(values.layoutDirection, .rightToLeft)

        let graph = Graph(LayoutDirectionProbe().environment(\.layoutDirection, .rightToLeft))
        graph.flush()
        XCTAssertEqual(allTexts(graph, kind: "Text"), ["rtl"])
    }

    private func frames(_ graph: Graph, _ path: Int...) throws -> [LayoutRect] {
        var current = try XCTUnwrap(graph.snapshot())
        for index in path { current = current.children[index] }
        return current.children.map(\.frame)
    }

    private func flushed<V: View>(_ view: V, width: CGFloat = 200) -> Graph {
        let graph = Graph(view)
        graph.rootProposal = ProposedViewSize(width: width, height: nil)
        graph.flush()
        return graph
    }

    private struct TwoBlocks: View {
        var body: some View {
            DirectionProbeLayout(spacing: 4) {
                Color.red.frame(width: 12, height: 10)
                Color.red.frame(width: 16, height: 14)
            }
            .frame(width: 48, height: 32)
        }
    }

    func testCustomLayoutMirrorsChildrenWithinBoundsUnderRightToLeft() throws {
        let ltr = flushed(TwoBlocks())
        let rtl = flushed(TwoBlocks().environment(\.layoutDirection, .rightToLeft))
        func layoutFrames(_ g: Graph) throws -> [LayoutRect] {
            // env modifier / frame / layout are single-child wrappers; find the Layout node.
            let nodes = everyNode(g.snapshot())
            let layout = try XCTUnwrap(nodes.first { $0.kind == "Layout" })
            return layout.children.map(\.frame)
        }
        let a = try layoutFrames(ltr)
        let b = try layoutFrames(rtl)
        XCTAssertEqual(a.map(\.minX), [a[0].minX, a[0].minX + 16])
        XCTAssertEqual(a.map(\.width), [12, 16])
        // Mirror within the layout's bounds [lo, lo + 32]: 16-wide child first, 12-wide child last.
        let lo = a[0].minX
        XCTAssertEqual(b.map(\.width), [12, 16])
        XCTAssertEqual(b.map(\.minX), [lo + 32 - 12, lo])
        XCTAssertEqual(b.map(\.minY), a.map(\.minY))
    }

    func testHStackMirrorsUnderRightToLeftAndLeavesLeftToRightUnchanged() throws {
        struct Row: View {
            var body: some View {
                HStack(spacing: 5) {
                    Color.red.frame(width: 10, height: 10)
                    Color.blue.frame(width: 20, height: 10)
                    Color.green.frame(width: 30, height: 10)
                }
            }
        }
        let ltr = try frames(flushed(Row()), 0)
        XCTAssertEqual(ltr.map(\.minX), [0, 15, 40])
        let rtl = try frames(flushed(Row().environment(\.layoutDirection, .rightToLeft)), 0, 0)
        XCTAssertEqual(rtl.map(\.minX), [60, 35, 0])
        XCTAssertEqual(rtl.map(\.width), [10, 20, 30])
    }

    func testLeadingAlignmentFollowsRightToLeft() throws {
        struct Column: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Color.red.frame(width: 50, height: 10)
                    Color.blue.frame(width: 20, height: 10)
                }
            }
        }
        let ltr = try frames(flushed(Column()), 0)
        XCTAssertEqual(ltr.map(\.minX), [0, 0])
        let rtl = try frames(flushed(Column().environment(\.layoutDirection, .rightToLeft)), 0, 0)
        XCTAssertEqual(rtl.map(\.minX), [0, 30], "leading edge is the right edge")
    }

    func testNestedLeftToRightOverrideUnflipsSubtree() throws {
        struct Row: View {
            var body: some View {
                HStack(spacing: 0) {
                    Color.red.frame(width: 10, height: 10)
                    Color.blue.frame(width: 20, height: 10)
                }
            }
        }
        struct Outer: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Row()
                    Row().environment(\.layoutDirection, .leftToRight)
                    Color.gray.frame(width: 60, height: 10)
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
        let graph = flushed(Outer())
        let stacks = everyNode(graph.snapshot()).filter { $0.kind == "HStack" }
        XCTAssertEqual(stacks.count, 2)
        XCTAssertEqual(stacks[0].children.map(\.frame.minX), [50, 30], "RTL row sits at the right edge; its 10-wide child is rightmost")
        XCTAssertEqual(stacks[1].children.map(\.frame.minX), [30, 40], "LTR override keeps child order; the row itself sits at the leading (right) edge of the RTL column")
    }
}


private struct DirectionProbeLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> LayoutSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return LayoutSize(width: sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)),
                          height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(at: LayoutPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}
