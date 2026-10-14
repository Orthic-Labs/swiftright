import SwiftRightRuntime
import XCTest

// `.listRowSeparator(_:)` and `.listRowBackground(_:)` reach the resolved tree as `ResolvedNode.rowStyle` on their modifier nodes (the host reads them from the row's subtree).

private struct Rows: View {
    var body: some View {
        List { ForEach(0..<3, id: \.self) { i in
            Text("r\(i)").listRowSeparator(i == 1 ? .hidden : .visible).listRowBackground(i == 0 ? Color.red : nil)
        } }
    }
}

@MainActor
final class ListRowStyleBlockTests: XCTestCase {
    func testRowModifiersAreResolved() throws {
        let graph = Graph(Rows(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 200, height: 160)
        graph.flush()
        let styles = everyNode(graph.snapshot()).compactMap(\.rowStyle)
        XCTAssertEqual(styles.compactMap(\.separatorHidden), [false, true, false])
        XCTAssertEqual(styles.filter(\.setsBackground).map(\.background), [Color.red.resolvedColor, nil, nil])
    }

    func testListRowSeparatorAcceptsEdges() {
        _ = Text("x").listRowSeparator(.hidden, edges: .bottom)
        _ = Text("x").listRowSeparator(.visible, edges: .all)
    }
}
