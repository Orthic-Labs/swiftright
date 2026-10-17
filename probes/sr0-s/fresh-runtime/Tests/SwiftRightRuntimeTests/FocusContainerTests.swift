import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// Focus clearing on removal (all containers), focus restore on reinsertion (List only), LazyVStack
// reinsertion (state resets), and ScrollView layout. Mac oracle: SR0-O F3 (probes/sr0-o/fixtures/RESULT.md),
// focus trace in out/F3-*-1s-run1.jsonl: removal focused=none in every container; reinsertion focused
// in List only.

struct LazyScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?

    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach($store.rows) { $row in
                    RowView(name: row.text, row: $row, focus: $focus, store: store)
                }
            }
        }
    }
}

/// Focuses a row through its own Button (the same path a user takes).
@MainActor
func focusRow(_ graph: Graph, _ uuid: UUID) {
    let before = rowNodeID(graph, uuid)
    graph.tapButton(descendants(graph, under: before, kind: "Button")[0].id)
    graph.flush()
}

@MainActor
final class FocusContainerTests: XCTestCase {

    // F3 focus, every container: removing the focused row clears focus.
    func testRemovingFocusedRowClearsFocusInEveryContainer() {
        for kind in ["VStack", "List", "LazyVStack"] {
            let store = makeStore()
            var records: [CommitRecord] = []
            let graph: Graph
            switch kind {
            case "List": graph = Graph(ListScreen(store: store))
            case "LazyVStack": graph = Graph(LazyScreen(store: store))
            default: graph = Graph(Screen(store: store))
            }
            graph.commitSink = { records.append($0) }
            graph.flush()

            let target = store.rows[3]
            focusRow(graph, target.id)
            XCTAssertTrue(records.last?.focused?.hasPrefix(rowNodeID(graph, target.id) + "/") == true, "\(kind): focused before removal")

            store.rows.remove(at: 3)
            graph.flush()
            XCTAssertNil(records.last?.focused, "\(kind): removing the focused row clears focus")
        }
    }

    // F3 focus, List: the reinserted row is focused again (oracle: "List reinsert focused").
    func testListReinsertRestoresFocus() {
        let store = makeStore()
        var records: [CommitRecord] = []
        let graph = Graph(ListScreen(store: store))
        graph.commitSink = { records.append($0) }
        graph.flush()

        let removed = store.rows[3]
        focusRow(graph, removed.id)
        store.rows.remove(at: 3)
        graph.flush()
        XCTAssertNil(records.last?.focused)

        store.rows.insert(removed, at: 3)
        graph.flush()
        XCTAssertTrue(records.last?.focused?.hasPrefix(rowNodeID(graph, removed.id) + "/") == true,
                      "List reinsert is focused (Mac oracle)")
    }

    // F3 focus, VStack and LazyVStack: the reinserted row is not focused (oracle: "not-focused").
    func testVStackAndLazyReinsertDoesNotRestoreFocus() {
        for kind in ["VStack", "LazyVStack"] {
            let store = makeStore()
            var records: [CommitRecord] = []
            let graph: Graph = kind == "LazyVStack" ? Graph(LazyScreen(store: store)) : Graph(Screen(store: store))
            graph.commitSink = { records.append($0) }
            graph.flush()

            let removed = store.rows[3]
            focusRow(graph, removed.id)
            store.rows.remove(at: 3)
            graph.flush()
            store.rows.insert(removed, at: 3)
            graph.flush()
            XCTAssertNil(records.last?.focused, "\(kind): reinserted row is not focused")
        }
    }

    // F3 focus, a focus that moved away before removal is left alone by the removal.
    func testRemovingUnfocusedRowKeepsFocus() {
        let store = makeStore()
        var records: [CommitRecord] = []
        let graph = Graph(Screen(store: store))
        graph.commitSink = { records.append($0) }
        graph.flush()

        focusRow(graph, store.rows[1].id)
        store.rows.remove(at: 4)
        graph.flush()
        XCTAssertTrue(records.last?.focused?.hasPrefix(rowNodeID(graph, store.rows[1].id) + "/") == true,
                      "focus on another row survives the removal")
    }
}

@MainActor
final class LazyContainerTests: XCTestCase {

    // F3 LazyVStack (oracle: LazyVStack in a ScrollView resets a reinserted row's @State, as VStack does).
    // Lifecycle still runs: onDisappear and task cancel on removal, onAppear and task restart on reinsert.
    func testLazyVStackReinsertResetsStateWhileLifecycleFires() async throws {
        let store = makeStore()
        let graph = Graph(LazyScreen(store: store))
        graph.flush()

        let removed = store.rows[3]
        let before = rowNodeID(graph, removed.id)
        let tokenBefore = graph.nodeInstance(before)
        let serialBefore = serialText(graph, removed.id)

        let markRemoved = store.log.count
        store.rows.remove(at: 3)
        graph.flush()
        try await settle(until: { rowLog(store, from: markRemoved) == ["disappear r3", "cancelled r3", "commit=false r3"] })
        XCTAssertNil(graph.nodeInstance(before), "removed node is gone")
        XCTAssertEqual(rowLog(store, from: markRemoved), ["disappear r3", "cancelled r3", "commit=false r3"])

        let markReinserted = store.log.count
        store.rows.insert(removed, at: 3)
        graph.flush()
        XCTAssertNotEqual(graph.nodeInstance(rowNodeID(graph, removed.id)), tokenBefore, "reinsertion is a new node")
        XCTAssertNotEqual(serialText(graph, removed.id), serialBefore, "LazyVStack resets reinserted row @State")
        try await settle(until: { rowLog(store, from: markReinserted) == ["appear r3", "commit=true r3"] })
        XCTAssertEqual(rowLog(store, from: markReinserted), ["appear r3", "commit=true r3"])
    }
}

@MainActor
final class ScrollViewTests: XCTestCase {

    struct Lines: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("line 0")
                    Text("line 1")
                    Text("line 2")
                    Text("line 3")
                    Text("line 4")
                }
            }
        }
    }

    @MainActor
    private func top(_ graph: Graph, _ text: String) -> CGFloat? {
        var nodes: [ResolvedNode] = []
        collect(graph.snapshot(), into: &nodes) { $0.kind == "Text" && $0.text == text }
        return nodes.first?.frame.minY
    }

    // A 40 pt viewport over 5 x 16 pt lines: the content is 80 pt, so the offset ranges 0...40.
    func testScrollOffsetShiftsContentAndClamps() {
        let graph = Graph(Lines())
        graph.rootProposal = ProposedViewSize(width: 100, height: 40)
        graph.flush()

        let scrollID = graph.ids(ofKind: "ScrollView").first
        XCTAssertNotNil(scrollID)
        XCTAssertEqual(top(graph, "line 4"), 64, "content laid out at its ideal height")
        XCTAssertEqual(graph.snapshot()?.children.first?.frame.height, 40, "ScrollView takes the viewport height")

        graph.scroll(scrollID!, to: 24)
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(scrollID!), 24)
        XCTAssertEqual(top(graph, "line 0"), -24)
        XCTAssertEqual(top(graph, "line 4"), 40)

        graph.scroll(scrollID!, to: 999)
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(scrollID!), 40, "clamped to content minus viewport")
        XCTAssertEqual(top(graph, "line 0"), -40)

        graph.scroll(scrollID!, to: -5)
        graph.flush()
        XCTAssertEqual(graph.scrollOffset(scrollID!), 0, "clamped at the top")
        XCTAssertEqual(top(graph, "line 0"), 0)
    }
}
