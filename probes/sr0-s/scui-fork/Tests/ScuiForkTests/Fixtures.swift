import Foundation
import Observation
import TestSinkBackend
import XCTest

@testable @_spi(Backends) import SwiftCrossUI

// Source-identical port of probes/sr0-s/fresh-runtime/Tests/SwiftRightRuntimeTests/RuntimeTests.swift
// fixtures. Differences are marked PORT and are API differences of SwiftCrossUI, not test changes.

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
        .onAppear(perform: RowTask(name: name, store: store).appear)
        .task(RowTask(name: name, store: store).run)
        .onDisappear(perform: RowTask(name: name, store: store).disappear)
    }
}

/// Task and teardown bodies live outside the view builder (same as the fresh-runtime test).
@MainActor
struct RowTask {
    let name: String
    let store: Store

    func run() async {
        do {
            // PORT: 30 ms in the fresh suite. SCUI updates are not deterministic (assessment B1), so the
            // harness settles by polling; the task must outlive a settle window.
            try await Task.sleep(for: .milliseconds(150))
        } catch {
            store.log.append("cancelled \(name)")
        }
        // PORT: fresh runtime guards with `TaskOwner.current?.commit { }`, a runtime-specific API.
        // SwiftUI has no equivalent, so the SCUI port commits through `guardedCommit` (see Overrides).
        let accepted = commitIfOwnerAlive { store.results.append(name) }
        store.log.append("commit=\(accepted) \(name)")
    }

    func appear() {
        store.log.append("appear \(name)")
    }

    func disappear() {
        store.log.append("disappear \(name)")
    }
}

#if SCUI_STOCK_FOREACHBINDING || SCUI_STOCK_LIST
/// Stock SCUI has no `ForEach(Binding<[T]>)` and no `$row in`; row bindings are built by id.
@MainActor
func rowBinding(_ store: Store, _ id: UUID) -> Binding<Row> {
    Binding(
        get: { store.rows.first(where: { $0.id == id }) ?? Row(id: id, text: "") },
        set: { new in
            if let i = store.rows.firstIndex(where: { $0.id == id }) { store.rows[i] = new }
        }
    )
}
#endif

struct Screen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?

    var body: some View {
        VStack {
            #if SCUI_STOCK_FOREACHBINDING
            ForEach(store.rows, id: \.id) { row in
                RowView(name: row.text, row: rowBinding(store, row.id), focus: $focus, store: store)
            }
            #else
            ForEach($store.rows) { $row in
                RowView(name: row.text, row: $row, focus: $focus, store: store)
            }
            #endif
        }
    }
}

/// Same rows as `Screen`, inside a `List` (SR0-O F3: List retains removed-row state).
struct ListScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?

    var body: some View {
        #if SCUI_STOCK_LIST
        // Stock `List` takes data and a row builder, with index-based row identity.
        List(store.rows, id: \.id, selection: Binding<UUID?>(get: { nil }, set: { _ in })) { row in
            RowView(name: row.text, row: rowBinding(store, row.id), focus: $focus, store: store)
        }
        #else
        List {
            ForEach($store.rows) { $row in
                RowView(name: row.text, row: $row, focus: $focus, store: store)
            }
        }
        #endif
    }
}

/// Writes through a row binding.
// PORT: SCUI `Button` actions are `@MainActor @Sendable` and `Binding` is not `Sendable`, so a
// function value capturing a Binding needs an explicit unchecked capture in Swift 6 mode.
@MainActor
func setRowText(_ row: Binding<Row>) -> @MainActor @Sendable () -> Void {
    nonisolated(unsafe) let row = row
    return { row.text.wrappedValue = "set" }
}

struct WriteBackScreen: View {
    @Bindable var store: Store

    var body: some View {
        VStack {
            #if SCUI_STOCK_FOREACHBINDING
            ForEach(store.rows, id: \.id) { row in
                Button("set", action: setRowText(rowBinding(store, row.id)))
            }
            #else
            ForEach($store.rows) { row in
                Button("set", action: setRowText(row))
            }
            #endif
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

struct KeyedScreen: View {
    @Bindable var store: Store

    var body: some View {
        VStack {
            #if SCUI_STOCK_FOREACHBINDING
            ForEach(store.rows, id: \.id) { row in
                Text(row.text)
            }
            #else
            ForEach($store.rows, id: \.id) { row in
                Text(row.wrappedValue.text)
            }
            #endif
        }
    }
}

// MARK: - Helpers

@MainActor
func makeStore(_ count: Int = 7) -> Store {
    Store(rows: (0..<count).map { Row(id: UUID(), text: "r\($0)") })
}

extension SinkNode {
    /// RowView subtrees in tree order (ForEach order).
    var rowViews: [SinkNode] { find(kind: "RowView") }
    var texts: [String] { find(kind: "Text").compactMap(\.text) }
}

@MainActor
func rowLog(_ store: Store, from mark: Int) -> [String] {
    store.log[mark...].filter { $0.hasSuffix(" r3") }
}

func serialText(_ row: SinkNode) -> String? {
    row.find(kind: "Text").first?.text
}

func fieldText(_ row: SinkNode) -> String? {
    row.find(kind: "TextField").first?.text
}

/// F4 guarded commit. Stock SCUI has no liveness guard (assessment B3); the fork adds `TaskOwner`.
@MainActor
func commitIfOwnerAlive(_ commit: () -> Void) -> Bool {
    #if SCUI_STOCK_TASKGUARD
    commit()
    return true
    #else
    return TaskOwner.current?.commit(commit) ?? false
    #endif
}

/// `move(fromOffsets:toOffset:)` (stock SCUI lacks it; the fork adds it as override O1).
func moveRows(_ rows: inout [Row], from: Int, to: Int) {
    #if SCUI_STOCK_MOVE
    let item = rows.remove(at: from)
    rows.insert(item, at: to > from ? to - 1 : to)
    #else
    rows.move(fromOffsets: IndexSet(integer: from), toOffset: to)
    #endif
}
