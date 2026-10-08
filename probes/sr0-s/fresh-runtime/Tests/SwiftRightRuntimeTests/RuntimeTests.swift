import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// Headless semantics tests. Only the public SwiftRightRuntime API is used.

struct Row: Identifiable, Equatable {
    let id: UUID
    var text: String
}

@Observable
@MainActor
final class Store {
    var rows: [Row]
    var results: [String] = []
    var log: [String] = []
    init(rows: [Row]) { self.rows = rows }
}

@MainActor
enum Serial {
    private static var last = 0
    static func take() -> Int {
        last += 1
        return last
    }
}

struct RowView: View {
    let name: String
    let row: Binding<Row>
    let focus: FocusState<UUID?>.Binding
    let store: Store
    @State var serial = Serial.take()

    var body: some View {
        VStack {
            TextField("text", text: row.text)
            Text("serial \(serial)")
            Button("focus") { focus.wrappedValue = row.wrappedValue.id }
        }
        .focused(focus, equals: row.wrappedValue.id)
        .task(RowTask(name: name, store: store).run)
        .onDisappear(perform: RowTask(name: name, store: store).disappear)
    }
}

/// Task and teardown bodies live outside the view builder so no closure locals are created there.
@MainActor
struct RowTask {
    let name: String
    let store: Store

    func run() async {
        do {
            try await Task.sleep(for: .milliseconds(30))
        } catch {
            store.log.append("cancelled \(name)")
        }
        let accepted = TaskOwner.current?.commit { store.results.append(name) } ?? false
        store.log.append("commit=\(accepted) \(name)")
    }

    func disappear() {
        store.log.append("disappear \(name)")
    }
}

struct Screen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?

    var body: some View {
        VStack {
            ForEach($store.rows) { $row in
                RowView(name: row.text, row: $row, focus: $focus, store: store)
            }
        }
    }
}

/// Writes through a row binding. Kept as a free function so the ForEach closure holds no nested closure.
@MainActor
func setRowText(_ row: Binding<Row>) -> () -> Void {
    { row.text.wrappedValue = "set" }
}

struct WriteBackScreen: View {
    @Bindable var store: Store

    var body: some View {
        VStack {
            ForEach($store.rows) { row in
                Button("set", action: setRowText(row))
            }
        }
    }
}

struct Theme: EnvironmentKey {
    static var defaultValue: String { "light" }
}

extension EnvironmentValues {
    var theme: String {
        get { self[Theme.self] }
        set { self[Theme.self] = newValue }
    }
}

struct ThemeProbe: View {
    @Environment(\.theme) var theme
    var body: some View { Text("theme \(theme)") }
}

struct EnvScreen: View {
    var body: some View {
        VStack {
            ThemeProbe()
            ThemeProbe().environment(\.theme, "dark")
        }
    }
}

@Observable
@MainActor
final class Model {
    var a = 0
    var b = 0
}

@MainActor
final class EvalCounter {
    var a = 0
    var b = 0
    func tickA() -> String { a += 1; return "" }
    func tickB() -> String { b += 1; return "" }
}

struct ProbeA: View {
    let model: Model
    let counter: EvalCounter
    var body: some View { Text("a \(model.a)\(counter.tickA())") }
}

struct ProbeB: View {
    let model: Model
    let counter: EvalCounter
    var body: some View { Text("b \(model.b)\(counter.tickB())") }
}

struct ObsScreen: View {
    let model: Model
    let counter: EvalCounter
    var body: some View {
        VStack {
            ProbeA(model: model, counter: counter)
            ProbeB(model: model, counter: counter)
        }
    }
}

@Observable
@MainActor
final class AnimModel {
    var rows: [Row] = []
}

struct AnimScreen: View {
    @Bindable var model: AnimModel
    var body: some View {
        VStack {
            Text("count \(model.rows.count)")
                .animation(.default, value: model.rows.count)
        }
    }
}

// MARK: - Helpers

@MainActor
func makeStore(_ count: Int = 7) -> Store {
    Store(rows: (0..<count).map { Row(id: UUID(), text: "r\($0)") })
}

@MainActor
func rowNodeID(_ graph: Graph, _ uuid: UUID) -> String {
    graph.ids(ofKind: "RowView").first { $0.contains("[\(uuid)]") } ?? "missing"
}

@MainActor
func collect(_ node: ResolvedNode?, into out: inout [ResolvedNode], where keep: (ResolvedNode) -> Bool) {
    guard let node else { return }
    if keep(node) { out.append(node) }
    for child in node.children { collect(child, into: &out, where: keep) }
}

@MainActor
func descendants(_ graph: Graph, under id: String, kind: String) -> [ResolvedNode] {
    var out: [ResolvedNode] = []
    collect(graph.snapshot(), into: &out) { $0.id.hasPrefix(id + "/") && $0.kind == kind }
    return out
}

@MainActor
func allTexts(_ graph: Graph, kind: String) -> [String] {
    var nodes: [ResolvedNode] = []
    collect(graph.snapshot(), into: &nodes) { $0.kind == kind && $0.text != nil }
    return nodes.compactMap(\.text)
}

@MainActor
func serialText(_ graph: Graph, _ uuid: UUID) -> String? {
    descendants(graph, under: rowNodeID(graph, uuid), kind: "Text").first?.text
}

@MainActor
func fieldText(_ graph: Graph, _ uuid: UUID) -> String? {
    descendants(graph, under: rowNodeID(graph, uuid), kind: "TextField").first?.text
}

@MainActor
func settle() async throws {
    for _ in 0..<3 { await Task.yield() }
    try await Task.sleep(for: .milliseconds(120))
}

// MARK: - Tests

@MainActor
final class RuntimeTests: XCTestCase {

    // F1: a surviving row keeps node identity, @State, and focus when a row is inserted above it.
    func testF1_SurvivingRowIdentityAcrossInsertAbove() {
        let store = makeStore()
        let graph = Graph(Screen(store: store))
        var records: [CommitRecord] = []
        graph.commitSink = { records.append($0) }
        graph.flush()

        let target = store.rows[4]
        let before = rowNodeID(graph, target.id)
        let tokenBefore = graph.nodeInstance(before)
        let serialBefore = serialText(graph, target.id)
        XCTAssertNotNil(graph.snapshot())

        graph.tapButton(descendants(graph, under: before, kind: "Button")[0].id)
        graph.flush()
        XCTAssertTrue(records.last?.focused?.hasPrefix(before + "/") == true, "focus should land on row 5")

        store.rows[4].text += "abc"
        graph.flush()
        store.rows.insert(Row(id: UUID(), text: "new"), at: 0)
        graph.flush()
        store.rows[5].text += "d"
        graph.flush()

        XCTAssertEqual(fieldText(graph, target.id), "r4abcd")
        XCTAssertEqual(rowNodeID(graph, target.id), before, "identity path unchanged")
        XCTAssertEqual(graph.nodeInstance(before), tokenBefore, "same node instance survives")
        XCTAssertEqual(serialText(graph, target.id), serialBefore, "@State survives")
        XCTAssertTrue(records.last?.focused?.hasPrefix(before + "/") == true, "focus stays on row 5")
    }

    // F2: a move keeps identity, @State and focus for the moved row.
    func testF2_ReorderPreservesStateAndFocus() {
        let store = makeStore()
        let graph = Graph(Screen(store: store))
        var records: [CommitRecord] = []
        graph.commitSink = { records.append($0) }
        graph.flush()

        let target = store.rows[2]
        let before = rowNodeID(graph, target.id)
        let token = graph.nodeInstance(before)
        let serial = serialText(graph, target.id)
        graph.tapButton(descendants(graph, under: before, kind: "Button")[0].id)
        graph.flush()

        store.rows.move(fromOffsets: IndexSet(integer: 2), toOffset: 7)
        graph.flush()

        XCTAssertEqual(graph.ids(ofKind: "RowView").last, rowNodeID(graph, target.id), "row moved to end")
        XCTAssertEqual(graph.nodeInstance(rowNodeID(graph, target.id)), token, "same node after move")
        XCTAssertEqual(serialText(graph, target.id), serial)
        XCTAssertTrue(records.last?.focused?.hasPrefix(rowNodeID(graph, target.id) + "/") == true)
    }

    // F3: removal tears the row down (onDisappear, then task cancellation); reinsertion gets fresh state.
    func testF3_RemovalTearsDownAndReinsertionGetsFreshState() async throws {
        let store = makeStore()
        let graph = Graph(Screen(store: store))
        graph.flush()

        let removed = store.rows[3]
        let before = rowNodeID(graph, removed.id)
        let tokenBefore = graph.nodeInstance(before)
        let serialBefore = serialText(graph, removed.id)

        store.rows.remove(at: 3)
        graph.flush()
        try await settle()
        XCTAssertNil(graph.nodeInstance(before), "removed node is gone")
        XCTAssertEqual(store.log.filter { $0.contains("r3") }, ["disappear r3", "cancelled r3", "commit=false r3"])

        store.rows.insert(removed, at: 3)
        graph.flush()
        XCTAssertNotEqual(graph.nodeInstance(rowNodeID(graph, removed.id)), tokenBefore, "reinsertion is a new node")
        XCTAssertNotEqual(serialText(graph, removed.id), serialBefore, "reinserted row gets fresh @State")
    }

    // F4: a stale async result is cancelled and rejected; cleanup still runs and is observable.
    func testF4_StaleAsyncResultIsRejectedAfterRemoval() async throws {
        let store = makeStore(3)
        let graph = Graph(Screen(store: store))
        graph.flush()

        let removed = store.rows[2]
        store.rows.remove(at: 2)
        graph.flush()
        try await settle()

        XCTAssertFalse(store.results.contains("r2"), "stale result must not commit")
        XCTAssertTrue(store.log.contains("cancelled r2"), "cancellation delivered")
        XCTAssertTrue(store.log.contains("commit=false r2"), "guarded commit rejected")
        XCTAssertTrue(store.results.contains("r0"), "live row still commits (control)")
        _ = removed
    }

    // Environment: an override applies to its subtree only.
    func testEnvironmentOverridePropagation() {
        let graph = Graph(EnvScreen())
        graph.flush()
        XCTAssertEqual(allTexts(graph, kind: "Text"), ["theme light", "theme dark"])
    }

    // Observation: a body re-evaluates only when a property it read changes.
    func testObservationFineGrainedInvalidation() {
        let model = Model()
        let counter = EvalCounter()
        let graph = Graph(ObsScreen(model: model, counter: counter))
        graph.flush()
        XCTAssertEqual(counter.a, 1)
        XCTAssertEqual(counter.b, 1)

        model.b += 1
        graph.flush()
        XCTAssertEqual(counter.a, 1, "ProbeA did not read b")
        XCTAssertEqual(counter.b, 2, "ProbeB re-evaluated")
        XCTAssertEqual(allTexts(graph, kind: "Text"), ["a 0", "b 1"])

        model.a += 1
        graph.flush()
        XCTAssertEqual(counter.a, 2)
        XCTAssertEqual(counter.b, 2)
    }

    // Binding write-back through ForEach($rows) { $row in }.
    func testBindingWriteBackThroughForEach() {
        let store = makeStore(3)
        let graph = Graph(WriteBackScreen(store: store))
        graph.flush()
        let buttons = graph.ids(ofKind: "Button")
        XCTAssertEqual(buttons.count, 3)

        graph.tapButton(buttons[1])
        graph.flush()
        XCTAssertEqual(store.rows.map(\.text), ["r0", "set", "r2"])
    }

    // Transactions: withAnimation and .animation(value:) tag the invalidation/flush.
    func testTransactionAnimationTagRecorded() {
        let model = AnimModel()
        let graph = Graph(AnimScreen(model: model))
        var records: [CommitRecord] = []
        graph.commitSink = { records.append($0) }
        graph.flush()

        withAnimation(Animation(name: "spring")) {
            model.rows.append(Row(id: UUID(), text: "x"))
        }
        graph.flush()
        XCTAssertTrue(records.last?.animation?.contains("spring") == true, "transaction tag recorded")

        model.rows.removeLast()
        graph.flush()
        XCTAssertEqual(records.last?.animation, "default", ".animation(value:) tag recorded on value change")
    }

    // Commit sink: one record per flush, with resolved kinds and text.
    func testCommitSinkReceivesResolvedTree() {
        let graph = Graph(EnvScreen())
        var records: [CommitRecord] = []
        graph.commitSink = { records.append($0) }
        graph.flush()
        graph.flush()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.root?.kind, "EnvScreen")
        XCTAssertTrue(records.last?.root?.children.isEmpty == false)
    }
}

