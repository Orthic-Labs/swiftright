import Foundation
@testable import SwiftRightRuntime
import XCTest

// Issue #75: a view's @State (or a model) read only inside the ForEach row closures. The closures run when the stack expands the
// ForEach, outside the view's body scope; the runtime attributes those reads to the expanding node, so a change re-runs the rows.
// Rows that read nothing that changed are not re-evaluated.

@MainActor
private enum RowCounter {
    static var bodies = 0
}

private struct CountedRow: View {
    let label: String
    var body: some View {
        let _ = { RowCounter.bodies += 1 }()
        Text(label)
    }
}

private struct StateInRows: View {
    @State private var suffix = "a"
    @State private var unrelated = 0

    var body: some View {
        VStack {
            Button("flip") { suffix = suffix == "a" ? "b" : "a" }
            Button("other") { unrelated += 1 }
            ForEach([1, 2, 3], id: \.self) { index in
                CountedRow(label: "row\(index)-\(suffix)")
            }
        }
    }
}

private struct StateInRowsOverBinding: View {
    @State private var rows = [PerfRow(id: UUID(), slot: 0, text: "x", detail: "d"), PerfRow(id: UUID(), slot: 1, text: "y", detail: "d")]
    @State private var prefix = "p"

    var body: some View {
        VStack {
            Button("flip") { prefix = "q" }
            ForEach($rows, id: \.id) { row in
                CountedRow(label: "\(prefix):\(row.wrappedValue.text)")
            }
        }
    }
}

@MainActor
final class ForEachRowStateTests: XCTestCase {
    private func labels(_ graph: Graph) -> [String] {
        everyNode(graph.snapshot()).filter { $0.kind == "Text" }.compactMap(\.text).filter { $0.hasPrefix("row") || $0.hasPrefix("p:") || $0.hasPrefix("q:") }
    }

    private func button(_ graph: Graph, _ title: String) -> String {
        everyNode(graph.snapshot()).first { $0.kind == "Button" && everyNode($0).contains { $0.text == title } }!.id
    }

    private func make<V: View>(_ view: V) -> Graph {
        let graph = Graph(view, measurer: FixedAdvanceTextMeasurer(), scale: 1)
        graph.rootProposal = ProposedViewSize(width: 400, height: 400)
        graph.flush()
        return graph
    }

    func testStateReadOnlyInRowClosureUpdatesRows() {
        let graph = make(StateInRows())
        XCTAssertEqual(labels(graph), ["row1-a", "row2-a", "row3-a"])
        XCTAssertTrue(graph.tapButton(button(graph, "flip")))
        graph.flush()
        XCTAssertEqual(labels(graph), ["row1-b", "row2-b", "row3-b"])
        XCTAssertTrue(graph.tapButton(button(graph, "flip")))
        graph.flush()
        XCTAssertEqual(labels(graph), ["row1-a", "row2-a", "row3-a"], "the registration is renewed by each expansion")
    }

    func testUnrelatedStateDoesNotEvaluateRows() {
        let graph = make(StateInRows())
        RowCounter.bodies = 0
        XCTAssertTrue(graph.tapButton(button(graph, "other")))
        graph.flush()
        XCTAssertEqual(RowCounter.bodies, 0, "a state the rows never read leaves them alone")
        XCTAssertTrue(graph.tapButton(button(graph, "flip")))
        graph.flush()
        XCTAssertEqual(RowCounter.bodies, 3, "the state they read re-runs each exactly once")
    }

    func testStateInBindingRowClosureUpdatesRowsAndDataChangeStaysPerRow() {
        let graph = make(StateInRowsOverBinding())
        XCTAssertEqual(labels(graph), ["p:x", "p:y"])
        XCTAssertTrue(graph.tapButton(button(graph, "flip")))
        graph.flush()
        XCTAssertEqual(labels(graph), ["q:x", "q:y"])
    }
}
