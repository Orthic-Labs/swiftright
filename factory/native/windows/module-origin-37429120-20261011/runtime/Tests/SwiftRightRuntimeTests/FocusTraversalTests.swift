import Foundation
import SwiftRightRuntime
import XCTest

// Tab / Shift-Tab traversal (CONTRACT section 4). Order is resolved tree order; disabled stops are skipped;
// traversal wraps; buttons are not tab stops unless tabFocusesAllControls (macOS default keyboard navigation).

struct DisablingScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?

    var body: some View {
        VStack {
            ForEach($store.rows) { $row in
                TextField("t", text: $row.text)
                    .focused($focus, equals: row.id)
                    .disabled(row.text == "off")
            }
        }
    }
}

struct ButtonStopsScreen: View {
    @FocusState var focus: Int?

    var body: some View {
        VStack {
            TextField("a", text: Binding(get: { "a" }, set: { _ in })).focused($focus, equals: 0)
            Button("b") {}.focused($focus, equals: 1)
            TextField("c", text: Binding(get: { "c" }, set: { _ in })).focused($focus, equals: 2)
        }
    }
}

@MainActor
final class FocusTraversalTests: XCTestCase {
    private func focusedIndex(_ store: Store, _ graph: Graph, _ records: [CommitRecord]) -> Int? {
        guard let focused = records.last?.focused else { return nil }
        return store.rows.firstIndex { focused.contains("[\($0.id)]") }
    }

    func testForwardFollowsTreeOrderAndWraps() {
        let store = makeStore(4)
        var records: [CommitRecord] = []
        let graph = Graph(Screen(store: store))
        graph.commitSink = { records.append($0) }
        graph.flush()
        XCTAssertNil(focusedIndex(store, graph, records))
        var seen: [Int] = []
        for _ in 0..<5 {
            XCTAssertTrue(graph.moveFocus(forward: true))
            seen.append(focusedIndex(store, graph, records) ?? -1)
        }
        XCTAssertEqual(seen, [0, 1, 2, 3, 0])
    }

    func testBackwardStartsAtLastAndWraps() {
        let store = makeStore(4)
        var records: [CommitRecord] = []
        let graph = Graph(Screen(store: store))
        graph.commitSink = { records.append($0) }
        graph.flush()
        var seen: [Int] = []
        for _ in 0..<5 {
            XCTAssertTrue(graph.moveFocus(forward: false))
            seen.append(focusedIndex(store, graph, records) ?? -1)
        }
        XCTAssertEqual(seen, [3, 2, 1, 0, 3])
    }

    func testTabContinuesFromPointerFocus() {
        let store = makeStore(5)
        var records: [CommitRecord] = []
        let graph = Graph(Screen(store: store))
        graph.commitSink = { records.append($0) }
        graph.flush()
        focusRow(graph, store.rows[2].id)
        XCTAssertEqual(focusedIndex(store, graph, records), 2)
        graph.moveFocus(forward: true)
        XCTAssertEqual(focusedIndex(store, graph, records), 3)
        graph.moveFocus(forward: false)
        graph.moveFocus(forward: false)
        XCTAssertEqual(focusedIndex(store, graph, records), 1)
    }

    func testOrderFollowsRowOrderAfterInsertAbove() {
        let store = makeStore(3)
        var records: [CommitRecord] = []
        let graph = Graph(Screen(store: store))
        graph.commitSink = { records.append($0) }
        graph.flush()
        store.rows.insert(Row(id: UUID(), text: "new"), at: 0)
        graph.flush()
        var seen: [Int] = []
        for _ in 0..<4 {
            graph.moveFocus(forward: true)
            seen.append(focusedIndex(store, graph, records) ?? -1)
        }
        XCTAssertEqual(seen, [0, 1, 2, 3])
    }

    func testDisabledStopsAreSkipped() {
        let store = makeStore(4)
        store.rows[1].text = "off"
        store.rows[3].text = "off"
        var records: [CommitRecord] = []
        let graph = Graph(DisablingScreen(store: store))
        graph.commitSink = { records.append($0) }
        graph.flush()
        XCTAssertEqual(graph.focusStops().count, 2)
        var seen: [Int] = []
        for _ in 0..<3 {
            graph.moveFocus(forward: true)
            seen.append(focusedIndex(store, graph, records) ?? -1)
        }
        XCTAssertEqual(seen, [0, 2, 0])
        graph.moveFocus(forward: false)
        XCTAssertEqual(focusedIndex(store, graph, records), 2)
    }

    func testNoStopsReturnsFalse() {
        let graph = Graph(Text("hi"))
        graph.flush()
        XCTAssertFalse(graph.moveFocus(forward: true))
        XCTAssertFalse(graph.moveFocus(forward: false))
    }

    func testButtonsAreStopsOnlyWhenAllControlsEnabled() {
        let graph = Graph(ButtonStopsScreen())
        graph.flush()
        XCTAssertEqual(graph.focusStops().count, 2)
        graph.tabFocusesAllControls = true
        XCTAssertEqual(graph.focusStops().count, 3)
    }

    func testKeyDispatchMapsTabAndShiftTab() {
        let store = makeStore(3)
        var records: [CommitRecord] = []
        let graph = Graph(Screen(store: store))
        graph.commitSink = { records.append($0) }
        graph.flush()
        XCTAssertTrue(graph.performFocusKey(.tab, modifiers: []))
        XCTAssertEqual(focusedIndex(store, graph, records), 0)
        XCTAssertTrue(graph.performFocusKey(.tab, modifiers: []))
        XCTAssertEqual(focusedIndex(store, graph, records), 1)
        XCTAssertTrue(graph.performFocusKey(.tab, modifiers: .shift))
        XCTAssertEqual(focusedIndex(store, graph, records), 0)
        XCTAssertFalse(graph.performFocusKey(.tab, modifiers: .command))
        XCTAssertFalse(graph.performFocusKey("a", modifiers: []))
    }
}
