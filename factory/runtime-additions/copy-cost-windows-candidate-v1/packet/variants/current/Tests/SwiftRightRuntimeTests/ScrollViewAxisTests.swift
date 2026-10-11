import Foundation
import Observation
import SwiftRightRuntime
import XCTest

@Observable
@MainActor
final class ScrollAxisModel {
    var isHorizontal = true
}

@MainActor
final class ScrollViewAxisTests: XCTestCase {
    struct HorizontalContent: View {
        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Text("1234567890")
                    Text("abcdefghij")
                }
            }
        }
    }

    struct VerticalContent: View {
        var body: some View {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    Text("line 0")
                    Text("line 1")
                    Text("line 2")
                    Text("line 3")
                    Text("line 4")
                }
            }
        }
    }

    private func text(_ graph: Graph, _ value: String) -> ResolvedNode? {
        var nodes: [ResolvedNode] = []
        collect(graph.snapshot(), into: &nodes) { $0.kind == "Text" && $0.text == value }
        return nodes.first
    }

    func testConfiguredHorizontalScrollUsesWidthForContentAndClamping() throws {
        let graph = Graph(HorizontalContent())
        graph.rootProposal = ProposedViewSize(width: 40, height: 20)
        graph.flush()
        let id = try XCTUnwrap(graph.ids(ofKind: "ScrollView").first)
        let first = try XCTUnwrap(text(graph, "1234567890"))
        let second = try XCTUnwrap(text(graph, "abcdefghij"))

        XCTAssertEqual(graph.snapshot()?.frame.width, 40)
        XCTAssertGreaterThan(second.frame.minX, first.frame.minX)
        XCTAssertEqual(first.frame.minX, 0)

        graph.scroll(id, to: 24)
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(id), 24)
        XCTAssertEqual(text(graph, "1234567890")?.frame.minX, -24)

        graph.scroll(id, to: 999)
        graph.flush()
        XCTAssertGreaterThan(graph.scrollOffset(id) ?? 0, 24)
        XCTAssertLessThan(text(graph, "1234567890")?.frame.minX ?? 0, -24)
    }

    func testConfiguredVerticalScrollUsesHeightForContentAndClamping() throws {
        let graph = Graph(VerticalContent())
        graph.rootProposal = ProposedViewSize(width: 100, height: 40)
        graph.flush()
        let id = try XCTUnwrap(graph.ids(ofKind: "ScrollView").first)

        XCTAssertEqual(text(graph, "line 4")?.frame.minY, 64)
        graph.scroll(id, to: 24)
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(id), 24)
        XCTAssertEqual(text(graph, "line 0")?.frame.minY, -24)
        XCTAssertEqual(text(graph, "line 4")?.frame.minY, 40)

        graph.scroll(id, to: 999)
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(id), 40)
        XCTAssertEqual(text(graph, "line 0")?.frame.minY, -40)
    }

    func testConfiguredTwoAxisOffsetsClampIndependently() throws {
        struct BothAxes: View {
            var body: some View {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("1234567890")
                            Text("abcdefghij")
                        }
                        Text("lower")
                        Text("lowest")
                        Text("extra 0")
                        Text("extra 1")
                        Text("extra 2")
                        Text("extra 3")
                    }
                }
            }
        }
        let graph = Graph(BothAxes())
        graph.rootProposal = ProposedViewSize(width: 40, height: 40)
        graph.flush()
        let id = try XCTUnwrap(graph.ids(ofKind: "ScrollView").first)
        graph.scroll(id, to: LayoutPoint(x: 20, y: 20))
        graph.flush()

        XCTAssertEqual(graph.scrollOffsets(id)?.x, 20)
        XCTAssertEqual(graph.scrollOffsets(id)?.y, 20)
        XCTAssertEqual(text(graph, "1234567890")?.frame.minX, -20)
        XCTAssertEqual(text(graph, "1234567890")?.frame.minY, -20)
    }

    func testChangingAxesOnSameScrollViewInvalidatesWrappedContentSize() throws {
        struct AxisChangingScreen: View {
            @Bindable var model: ScrollAxisModel

            var body: some View {
                ScrollView(model.isHorizontal ? .horizontal : .vertical) {
                    Text(String(repeating: "wrap ", count: 16))
                }
            }
        }
        let model = ScrollAxisModel()
        let graph = Graph(AxisChangingScreen(model: model))
        graph.rootProposal = ProposedViewSize(width: 40, height: nil)
        graph.flush()
        let id = try XCTUnwrap(graph.ids(ofKind: "ScrollView").first)
        let instance = try XCTUnwrap(graph.nodeInstance(id))
        let horizontalHeight = try XCTUnwrap(everyNode(graph.snapshot()).first { $0.kind == "ScrollView" }?.frame.height)

        model.isHorizontal = false
        graph.flush()

        XCTAssertEqual(graph.nodeInstance(id), instance, "axis update keeps same ScrollView node")
        let verticalHeight = try XCTUnwrap(everyNode(graph.snapshot()).first { $0.kind == "ScrollView" }?.frame.height)
        XCTAssertGreaterThan(verticalHeight, horizontalHeight, "finite-width vertical content wraps into more height")
    }
}
