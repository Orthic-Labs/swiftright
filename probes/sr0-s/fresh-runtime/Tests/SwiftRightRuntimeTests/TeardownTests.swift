import Foundation
import Observation
@testable import SwiftRightRuntime
import XCTest

// Tree release after teardown (SR0-O F9: the closed window's tree must not stay alive). Each kind of
// retained object is checked through a weak reference after `tearDown()`: the graph, every node, the
// @State value, an environment value, and the state captured by a running task.

/// A probe object whose lifetime is observed through weak references.
final class Marker {}

struct MarkerKey: EnvironmentKey {
    static var defaultValue: Marker? { nil }
}

extension EnvironmentValues {
    var marker: Marker? {
        get { self[MarkerKey.self] }
        set { self[MarkerKey.self] = newValue }
    }
}

@Observable
@MainActor
final class Feed {
    var value = 0
}

/// Holds a `@State` marker, an environment marker, a task that captures the state marker, and an
/// observation read of `feed`.
struct ReleaseScreen: View {
    @Bindable var feed: Feed
    @State var marker = Marker()

    var body: some View {
        VStack {
            Text("value \(feed.value)")
            Text("held")
        }
        .environment(\.marker, marker)
        .task {
            // Captures the state marker. Teardown cancels the sleep, and the task then ends.
            _ = marker
            try? await Task.sleep(for: .seconds(3600))
        }
    }
}

/// Weak handles to every object a torn-down graph could keep alive.
final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T?) { self.value = value }
}

struct ReleaseCheck {
    let graph: WeakBox<Graph>
    let nodes: [WeakBox<Node>]
    let state: WeakBox<Marker>
}

@MainActor
func buildFeedGraphAndTearDown(feed: Feed) -> ReleaseCheck {
    let graph = Graph(ReleaseScreen(feed: feed))
    graph.flush()
    let stateMarker = (graph.root?.storage["marker"] as? StateBox<Marker>)?.value
    feed.value += 1
    graph.flush()
    let nodes = graph.nodes.values.map { WeakBox<Node>($0) }
    graph.tearDown()
    return ReleaseCheck(graph: WeakBox<Graph>(graph), nodes: nodes, state: WeakBox<Marker>(stateMarker))
}

struct ReleaseListScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?

    var body: some View {
        List {
            ForEach($store.rows) { $row in
                RowView(name: row.text, row: $row, focus: $focus, store: store)
            }
        }
    }
}

/// Disappear and task cancellation at teardown.
struct TeardownLogScreen: View {
    let log: KeyLog

    var body: some View {
        Text("logged")
            .onDisappear { log.events.append("disappear") }
            .task {
                do {
                    try await Task.sleep(for: .seconds(3600))
                } catch {
                    log.events.append("cancelled")
                }
            }
    }
}

@MainActor
final class TeardownTests: XCTestCase {

    // After teardown, nothing the graph held is alive: no retain cycle through observation tracking
    // (StateBox registrar -> onChange), the task (its captured state), the commit sink, or node storage.
    func testTearDownReleasesGraphNodesStateAndTaskCaptures() async throws {
        let feed = Feed()
        let check = buildFeedGraphAndTearDown(feed: feed)
        try await settle()
        XCTAssertNil(check.graph.value, "graph released")
        XCTAssertFalse(check.nodes.isEmpty)
        XCTAssertTrue(check.nodes.allSatisfy { $0.value == nil }, "every node released")
        XCTAssertNil(check.state.value, "@State value released")
    }

    // The same release holds for a List: its row cache and row @State go with the graph.
    func testTearDownReleasesListRowsAndRowCache() async throws {
        func build() -> ReleaseCheck {
            let store = makeStore(4)
            let graph = Graph(ReleaseListScreen(store: store))
            graph.flush()
            // Retire a row so the List row cache holds retained state, then tear down.
            store.rows.remove(at: 1)
            graph.flush()
            let nodes = graph.nodes.values.map { WeakBox<Node>($0) }
            graph.tearDown()
            return ReleaseCheck(graph: WeakBox<Graph>(graph), nodes: nodes, state: WeakBox<Marker>(nil))
        }
        let check = build()
        try await settle()
        XCTAssertNil(check.graph.value, "graph released")
        XCTAssertTrue(check.nodes.allSatisfy { $0.value == nil }, "every row node released")
    }

    // Teardown runs onDisappear, cancels running tasks, and emits one final record with no root.
    func testTearDownRunsDisappearCancelsTasksAndEmitsFinalRecord() async throws {
        let log = KeyLog()
        let graph = Graph(TeardownLogScreen(log: log))
        var records: [CommitRecord] = []
        graph.commitSink = { records.append($0) }
        graph.flush()

        graph.tearDown()
        try await settle(until: { log.events.filter { $0 == "cancelled" }.count == 1 && log.events.filter { $0 == "disappear" }.count == 1 })
        XCTAssertEqual(log.events.filter { $0 == "disappear" }.count, 1)
        XCTAssertEqual(log.events.filter { $0 == "cancelled" }.count, 1)
        XCTAssertEqual(records.count, 2)
        XCTAssertNil(records.last?.root, "final record has no root")
        XCTAssertNil(graph.snapshot())
    }

    // After teardown the graph commits nothing: flush and tick are inert.
    func testNothingCommitsAfterTearDown() {
        let feed = Feed()
        let graph = Graph(ReleaseScreen(feed: feed))
        var records: [CommitRecord] = []
        graph.commitSink = { records.append($0) }
        graph.flush()
        graph.tearDown()
        let count = records.count

        feed.value += 1
        graph.flush()
        graph.tick(now: 1)
        XCTAssertEqual(records.count, count, "no commits after teardown")
    }
}
