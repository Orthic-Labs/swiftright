import Foundation
import Observation
@testable import SwiftRightRuntime
import XCTest

// A change to one element of a ForEach($rows) re-evaluates that row only. The rows read their element through a per-row box
// that the node expanding the ForEach refreshes, so the owner re-expands (new rows, removed rows, order) and the unchanged
// rows beneath it are left alone. These tests pin what that must not break: the values rows show, event-handler reads, a
// parent that changes what the rows are built from, and elements that cannot be compared.

@MainActor
enum BodyCounter {
    static var cells = 0
}

struct CountedCell: View {
    let row: Binding<PerfRow>
    let flag: String

    var body: some View {
        let _ = { BodyCounter.cells += 1 }()
        HStack {
            Text("\(flag)\(row.wrappedValue.text)")
            Text(row.wrappedValue.detail)
        }
    }
}

struct CountedList: View {
    @Bindable var store: PerfStore

    var body: some View {
        // `flag` is read here, so a change of it re-evaluates this body and rebuilds the ForEach with a new capture.
        let flag = store.other % 2 == 0 ? "a:" : "b:"
        VStack {
            ForEach($store.rows, id: \.id) { row in
                CountedCell(row: row, flag: flag)
            }
        }
    }
}

struct Opaque: Identifiable {
    let id: Int
    var text: String
}

@Observable
@MainActor
final class OpaqueStore {
    var items: [Opaque] = (0..<5).map { Opaque(id: $0, text: "o\($0)") }
}

struct OpaqueList: View {
    @Bindable var store: OpaqueStore

    var body: some View {
        VStack {
            ForEach($store.items, id: \.id) { item in
                Text(item.wrappedValue.text)
            }
        }
    }
}

@MainActor
private func texts(_ graph: Graph) -> [String] {
    everyNode(graph.snapshot()).filter { $0.kind == "Text" }.compactMap(\.text)
}

@MainActor
final class RowRefreshTests: XCTestCase {
    private func make(rows: Int = 40) -> (Graph, PerfStore) {
        let store = PerfStore(rows: rows)
        let graph = Graph(CountedList(store: store), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        graph.rootProposal = ProposedViewSize(width: 600, height: 400)
        graph.flush()
        return (graph, store)
    }

    func testEditingOneRowEvaluatesThatRowOnly() {
        let (graph, store) = make()
        BodyCounter.cells = 0
        graph.profile = GraphProfile()
        store.rows[7].text = "edited"
        graph.flush()
        XCTAssertEqual(BodyCounter.cells, 1, "only the edited row's body runs")
        XCTAssertLessThanOrEqual(graph.profile!.evaluations, 12, "the owner and one row's nodes, not 40 rows")
        XCTAssertTrue(texts(graph).contains("a:edited"))
        XCTAssertEqual(texts(graph).filter { $0.hasPrefix("a:Row") }.count, 39)
    }

    func testInsertRemoveAndReorderEvaluateOnlyNewRows() {
        let (graph, store) = make()
        BodyCounter.cells = 0
        let moved = store.rows.remove(at: 3)
        store.rows.insert(moved, at: 30)
        graph.flush()
        XCTAssertEqual(BodyCounter.cells, 0, "a reorder changes no row's element")
        XCTAssertEqual(texts(graph).filter { $0.hasPrefix("a:Row") }.map { $0 }.count, 40)
        let order = texts(graph).filter { $0.hasPrefix("a:Row") }
        XCTAssertEqual(order[30], "a:Row 3", "the moved row is in its new place")

        BodyCounter.cells = 0
        store.rows.insert(PerfRow(id: UUID(), slot: 99, text: "fresh", detail: "d"), at: 0)
        store.rows.remove(at: 20)
        graph.flush()
        XCTAssertEqual(BodyCounter.cells, 1, "only the inserted row is evaluated")
        XCTAssertEqual(texts(graph).first, "a:fresh")
        XCTAssertEqual(texts(graph).filter { $0.hasPrefix("a:") }.count, 40)
    }

    /// A parent whose body builds the ForEach from something other than the data must still reach every row.
    func testParentChangeReachesRowsWhoseElementsDidNotChange() {
        let (graph, store) = make(rows: 12)
        BodyCounter.cells = 0
        store.other += 1
        graph.flush()
        XCTAssertEqual(BodyCounter.cells, 12, "every row is rebuilt with the new capture")
        XCTAssertEqual(texts(graph).filter { $0.hasPrefix("b:Row") }.count, 12)
        // data and parent in one flush
        store.other += 1
        store.rows[2].text = "both"
        graph.flush()
        XCTAssertTrue(texts(graph).contains("a:both"))
        XCTAssertEqual(texts(graph).filter { $0.hasPrefix("a:") }.count, 12)
    }

    /// Outside a node's evaluation a row binding reads the live collection, so an event handler never sees a stale element.
    func testRowBindingReadsAndWritesLiveOutsideEvaluation() {
        var rows = [PerfRow(id: UUID(), slot: 1, text: "one", detail: "d")]
        let source = Binding<[PerfRow]>(get: { rows }, set: { rows = $0 })
        var captured: Binding<PerfRow>?
        let each = ForEach(source, id: \.id) { row in
            captured = row
            return Text(row.wrappedValue.text)
        }
        _ = each.parts()
        XCTAssertEqual(captured?.wrappedValue.text, "one")
        rows[0].text = "two"
        XCTAssertEqual(captured?.wrappedValue.text, "two", "no refresh has run, the read still sees the model")
        captured?.wrappedValue = PerfRow(id: rows[0].id, slot: 1, text: "three", detail: "d")
        XCTAssertEqual(rows[0].text, "three")
    }

    func testTypingIntoARowFieldUpdatesModelAndDisplay() {
        let store = PerfStore(rows: 5)
        let graph = Graph(PerfScreen(store: store), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        graph.rootProposal = ProposedViewSize(width: 600, height: 400)
        graph.flush()
        let field = graph.ids(ofKind: "TextField")[2]
        let state = graph.textInput(field)!
        XCTAssertTrue(state.replace(range: nil, text: "typed"))
        graph.flush()
        let shown = everyNode(graph.snapshot()).first { $0.id == field }?.text
        XCTAssertEqual(shown, store.rows[1].text)
        XCTAssertTrue(store.rows[1].text.contains("typed"), "the edit reached the model: \(store.rows[1].text)")
    }

    /// An element that is not Equatable cannot be compared, so it counts as changed; the rows still show the right values.
    func testNonEquatableElementsStillUpdate() {
        let store = OpaqueStore()
        let graph = Graph(OpaqueList(store: store), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        graph.flush()
        store.items[2].text = "changed"
        graph.flush()
        XCTAssertEqual(texts(graph), ["o0", "o1", "changed", "o3", "o4"])
        store.items.remove(at: 0)
        store.items.append(Opaque(id: 9, text: "nine"))
        graph.flush()
        XCTAssertEqual(texts(graph), ["o1", "changed", "o3", "o4", "nine"])
    }

    /// Row registrations are retired with the rows: after removing everything, a data change wakes nothing.
    func testRemovedRowsStopObserving() {
        let (graph, store) = make(rows: 10)
        store.rows.removeAll()
        graph.flush()
        let before = graph.observationCallbacks
        store.rows.append(PerfRow(id: UUID(), slot: 1, text: "again", detail: "d"))
        graph.flush()
        XCTAssertLessThanOrEqual(graph.observationCallbacks - before, 2)
        XCTAssertEqual(texts(graph).filter { $0.hasPrefix("a:") }, ["a:again"])
    }
}
