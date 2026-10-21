import SwiftRightRuntime
import XCTest

// Helpers shared by the issue #60 (SR1 backlog) test files.

@MainActor
func i60Graph(_ view: some View, width: CGFloat? = 300, height: CGFloat? = 200) -> Graph {
    let graph = Graph(view, scale: 1)
    graph.rootProposal = ProposedViewSize(width: width, height: height)
    graph.flush()
    graph.flush()   // a preference delivered by the first flush may write state that the second settles
    return graph
}

@MainActor
func i60Nodes(_ graph: Graph) -> [ResolvedNode] { everyNode(graph.snapshot()) }

@MainActor
func i60Texts(_ graph: Graph) -> [String] { i60Nodes(graph).compactMap { $0.kind == "Text" ? $0.text : nil } }

@MainActor
func i60Nodes(_ graph: Graph, kind: String) -> [ResolvedNode] { i60Nodes(graph).filter { $0.kind == kind } }

@MainActor
func i60Text(_ graph: Graph, _ text: String) -> ResolvedNode? { i60Nodes(graph).first { $0.kind == "Text" && $0.text == text } }

/// The Button node whose subtree holds `text`.
@MainActor
func i60Button(_ graph: Graph, _ text: String) -> ResolvedNode? {
    i60Nodes(graph).first { $0.kind == "Button" && everyNode($0).contains { $0.text == text } }
}

@MainActor
func i60Tap(_ graph: Graph, button text: String, file: StaticString = #filePath, line: UInt = #line) {
    guard let button = i60Button(graph, text) else { return XCTFail("no button \"\(text)\"", file: file, line: line) }
    XCTAssertTrue(graph.tapButton(button.id), file: file, line: line)
    graph.flush()
    graph.flush()
}

func i60Mid(_ frame: LayoutRect) -> (x: Double, y: Double) {
    (Double(frame.minX) + Double(frame.width) / 2, Double(frame.minY) + Double(frame.height) / 2)
}
