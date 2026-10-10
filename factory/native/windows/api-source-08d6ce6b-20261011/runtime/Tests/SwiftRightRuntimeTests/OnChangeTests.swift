import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// `.onChange(of:)` and its previous-value baseline across row reinsertion (SR0-O F3, runtime defect D1).
//
// Mac oracle (probes/sr0-o/f1-cross/CROSS-ALL.md section D1, cross-evidence/F3*/mac-ev-n{1,2,3}.jsonl): the row's
// `.onChange(of: row.text)` saw `Row 4x`; the row is removed and reinserted with the same identity and text `Row 4`.
//   List       @State preserved (appear local 1), then the action runs once more (`Row 4x` -> `Row 4`): local 2.
//   VStack     fresh state (appear local 0), no action: local 0.
//   LazyVStack fresh state (appear local 0), no action: local 0.
// The baseline is part of the retained row state: it travels with @State where the container keeps state, and is
// recorded afresh where the container does not. A reinsertion with the text the preserved view last saw runs nothing.

/// Counts its own `.onChange` runs in @State, the way the F3 fixture row does. `onChange` is applied before `onAppear`, so
/// the node order is onAppear (outer), onChange: the appear line shows the state as it was before any reinsertion change.
struct ChangeRowView: View {
    let row: Binding<Row>
    let store: Store
    @State var edits = 0

    var body: some View {
        HStack {
            TextField("text", text: row.text)
            Text("local \(edits)")
        }
        .onChange(of: row.wrappedValue.text) { old, new in
            edits += 1
            store.log.append("change \(old)>\(new) local=\(edits)")
        }
        .onAppear {
            store.log.append("appear local=\(edits)")
        }
    }
}

struct ChangeVStackScreen: View {
    @Bindable var store: Store
    var body: some View {
        VStack {
            ForEach($store.rows) { $row in ChangeRowView(row: $row, store: store) }
        }
    }
}

struct ChangeListScreen: View {
    @Bindable var store: Store
    var body: some View {
        List {
            ForEach($store.rows) { $row in ChangeRowView(row: $row, store: store) }
        }
    }
}

struct ChangeLazyScreen: View {
    @Bindable var store: Store
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach($store.rows) { $row in ChangeRowView(row: $row, store: store) }
            }
        }
    }
}

/// `onChange(of:initial:)` and the argument-less action, outside any row.
struct ChangeOptionsScreen: View {
    @Bindable var store: Store
    var body: some View {
        VStack {
            Text("t")
                .onChange(of: store.results.count, initial: true) { old, new in
                    store.log.append("initial \(old)>\(new)")
                }
                .onChange(of: store.results.count) {
                    store.log.append("plain")
                }
        }
    }
}

@MainActor
private func changeRowID(_ graph: Graph, _ uuid: UUID) -> String {
    graph.ids(ofKind: "ChangeRowView").first { $0.contains("[\(uuid)]") } ?? "missing"
}

/// The row's "local N" label.
@MainActor
private func localLabel(_ graph: Graph, _ uuid: UUID) -> String? {
    descendants(graph, under: changeRowID(graph, uuid), kind: "Text").first?.text
}

@MainActor
final class OnChangeTests: XCTestCase {
    private func make(_ container: String) -> (Graph, Store) {
        let store = makeStore()
        let graph: Graph
        switch container {
        case "List": graph = Graph(ChangeListScreen(store: store))
        case "LazyVStack": graph = Graph(ChangeLazyScreen(store: store))
        default: graph = Graph(ChangeVStackScreen(store: store))
        }
        graph.flush()
        return (graph, store)
    }

    /// Edits row 3 to `r3x`, removes it, then reinserts it with `text` after a flush in between (a removal and an insertion in
    /// one flush is no change). Returns the log lines written by the reinsertion flush and the removed row.
    private func removeAndReinsert(_ graph: Graph, _ store: Store, text: String) -> (lines: [String], row: Row) {
        let id = store.rows[3].id
        store.rows[3].text = "r3x"
        graph.flush()
        store.rows.remove(at: 3)
        graph.flush()
        let mark = store.log.count
        let reinserted = Row(id: id, text: text)
        store.rows.insert(reinserted, at: 3)
        graph.flush()
        return (Array(store.log[mark...]), reinserted)
    }

    // MARK: Basics

    func testActionRunsOncePerValueChangeWithOldAndNew() {
        let (graph, store) = make("VStack")
        let id = store.rows[3].id
        XCTAssertEqual(store.log.filter { $0.hasPrefix("change") }, [], "first evaluation records the baseline only")
        XCTAssertEqual(localLabel(graph, id), "local 0")

        store.rows[3].text = "r3x"
        graph.flush()
        XCTAssertEqual(store.log.filter { $0.hasPrefix("change") }, ["change r3>r3x local=1"])
        graph.flush()
        store.rows[5].text = "other row"
        graph.flush()
        XCTAssertEqual(store.log.filter { $0.hasPrefix("change") }, ["change r3>r3x local=1", "change r5>other row local=1"],
                       "an unrelated flush and an edit of another row do not run row 3's action again")
        store.rows[3].text = "r3xy"
        graph.flush()
        XCTAssertEqual(store.log.last, "change r3x>r3xy local=2")
        XCTAssertEqual(localLabel(graph, id), "local 2")
    }

    func testInitialAndArgumentlessActions() {
        let store = makeStore()
        let graph = Graph(ChangeOptionsScreen(store: store))
        graph.flush()
        XCTAssertEqual(store.log, ["initial 0>0"], "initial runs once with the value as old and new; the plain one waits")
        store.results.append("a")
        graph.flush()
        XCTAssertEqual(store.log.sorted(), ["initial 0>0", "initial 0>1", "plain"], "both run once for the change (node order is not pinned)")
        graph.flush()
        XCTAssertEqual(store.log.count, 3, "no change, no run")
    }

    // MARK: Reinsertion (D1)

    // List: the baseline comes back with the preserved @State. The reinserted text differs from the last value the
    // preserved view saw: exactly one more run, after appear, with the preserved state.
    func testListReinsertWithChangedValueRunsOnceWithPreservedState() {
        let (graph, store) = make("List")
        let (lines, row) = removeAndReinsert(graph, store, text: "r3")
        XCTAssertEqual(lines, ["appear local=1", "change r3x>r3 local=2"], "state preserved at appear; one run after it")
        XCTAssertEqual(localLabel(graph, row.id), "local 2")
        graph.flush()
        XCTAssertEqual(store.log.filter { $0.hasPrefix("change") }.count, 2, "typing r3x, then the reinsertion run; nothing more")
    }

    // List, the reinserted value equals the last value the preserved view saw: nothing runs.
    func testListReinsertWithUnchangedValueRunsNothing() {
        let (graph, store) = make("List")
        let (lines, row) = removeAndReinsert(graph, store, text: "r3x")
        XCTAssertEqual(lines, ["appear local=1"])
        XCTAssertEqual(localLabel(graph, row.id), "local 1")
    }

    // List, the baseline keeps working after the reinsertion: the next edit compares with the reinserted value.
    func testListEditAfterReinsertCompareWithReinsertedValue() {
        let (graph, store) = make("List")
        let (_, row) = removeAndReinsert(graph, store, text: "r3")
        store.rows[3].text = "r3z"
        graph.flush()
        XCTAssertEqual(store.log.last, "change r3>r3z local=3")
        XCTAssertEqual(localLabel(graph, row.id), "local 3")
    }

    // VStack and LazyVStack: the reinserted row is a fresh view. State is fresh and nothing runs.
    func testVStackAndLazyReinsertAreFreshAndRunNothing() {
        for container in ["VStack", "LazyVStack"] {
            let (graph, store) = make(container)
            let (lines, row) = removeAndReinsert(graph, store, text: "r3")
            XCTAssertEqual(lines, ["appear local=0"], "\(container): fresh state, no action")
            XCTAssertEqual(localLabel(graph, row.id), "local 0", container)
            store.rows[3].text = "r3q"
            graph.flush()
            XCTAssertEqual(store.log.last, "change r3>r3q local=1", "\(container): the fresh baseline is the reinserted value")
        }
    }

    // The unchanged-value rule holds for the fresh containers as well (no baseline to differ from).
    func testVStackAndLazyReinsertWithPreviousValueRunNothing() {
        for container in ["VStack", "LazyVStack"] {
            let (graph, store) = make(container)
            let (lines, _) = removeAndReinsert(graph, store, text: "r3x")
            XCTAssertEqual(lines, ["appear local=0"], container)
        }
    }

    // The baseline is bounded with the @State it belongs to (RowStateCache.limit, oldest retired first). 65 rows retire in one
    // pass: the most recently retired one comes back with state and baseline (one run), the oldest has lost both (fresh, no run).
    func testListEvictedRowLosesItsBaselineWithItsState() {
        let store = makeStore(70)
        let graph = Graph(ChangeListScreen(store: store))
        graph.flush()
        let oldest = store.rows[0].id
        let newest = store.rows[64].id
        store.rows[0].text = "r0x"
        store.rows[64].text = "r64x"
        graph.flush()
        store.rows.removeFirst(65)
        graph.flush()

        var mark = store.log.count
        store.rows.insert(Row(id: newest, text: "r64"), at: 0)
        graph.flush()
        XCTAssertEqual(Array(store.log[mark...]), ["appear local=1", "change r64x>r64 local=2"], "retained: baseline kept")

        mark = store.log.count
        store.rows.insert(Row(id: oldest, text: "r0"), at: 0)
        graph.flush()
        XCTAssertEqual(Array(store.log[mark...]), ["appear local=0"], "evicted: fresh state, baseline recorded, no run")
    }
}
