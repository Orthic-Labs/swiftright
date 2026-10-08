import Foundation
import Observation
#if os(macOS)
import SwiftUI
#endif

/// One editable row. Its @State is per identity, so a reinserted row starts fresh.
struct EditableRowView: View {
    let row: Binding<Row>
    let model: RowModel
    let focus: FocusState<UUID?>.Binding
    var rowTask = false
    var showDelete = false
    @State private var localEdits = 0

    var body: some View {
        let id = row.wrappedValue.id
        HStack {
            TextField("Row", text: row.text)
                .focused(focus, equals: id)
                .accessibilityIdentifier("row/\(id.uuidString)/field")
            Text("local \(localEdits)")
            if showDelete {
                Button("Delete") { model.removeRow(id) }
                    .accessibilityIdentifier("row/\(id.uuidString)/delete")
            }
        }
        .onAppear {
            let controls: [String] = showDelete ? ["field", "delete"] : ["field"]
            let identifiers: [String] = controls.map { "row/\(id.uuidString)/\($0)" }
            model.log.emit("lifecycle", node: id.uuidString, payload: [
                "phase": "appear", "local": localEdits, "controls": controls, "identifiers": identifiers,
            ])
        }
        .onDisappear {
            model.log.emit("lifecycle", node: id.uuidString, payload: ["phase": "disappear", "local": localEdits])
        }
        .onChange(of: row.wrappedValue.text) { _, newText in
            localEdits += 1
            model.log.emit("state", node: id.uuidString, payload: ["op": "edit", "text": newText])
            model.log.emit("lifecycle", node: id.uuidString, payload: ["phase": "local-edit", "local": localEdits])
        }
        .task {
            guard rowTask else { return }
            await model.runRowLoad(id)
        }
    }
}

/// Lazy-free list of editable rows. Identity is the row UUID; the binding is projected by ForEach(_:id:).
struct RowList: View {
    @Bindable var model: RowModel
    let focus: FocusState<UUID?>.Binding
    var rowTasks = false
    var showDelete = false

    var body: some View {
        List {
            ForEach($model.rows, id: \.id) { row in
                EditableRowView(row: row, model: model, focus: focus, rowTask: rowTasks, showDelete: showDelete)
            }
            .onMove { offsets, destination in
                model.moveRow(from: offsets, to: destination)
            }
        }
    }
}

/// F3 container variants. `list` is the original fixture; `vstack` and `lazy` are oracle variants
/// that test whether the preserved-state outcome depends on List's cell reuse.
struct RowStack: View {
    @Bindable var model: RowModel
    let focus: FocusState<UUID?>.Binding
    let kind: FixtureConfig.F3Container
    var rowTasks = false

    var body: some View {
        switch kind {
        case .list:
            RowList(model: model, focus: focus, rowTasks: rowTasks)
        case .vstack:
            VStack(alignment: .leading) {
                ForEach($model.rows, id: \.id) { row in
                    EditableRowView(row: row, model: model, focus: focus, rowTask: rowTasks)
                }
            }
        case .lazy:
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach($model.rows, id: \.id) { row in
                        EditableRowView(row: row, model: model, focus: focus, rowTask: rowTasks)
                    }
                }
            }
        }
    }
}

/// Common chrome for every fixture: focus logging, programmatic focus requests, toolbar insert, window disappearance.
struct FixtureScaffold<Content: View>: View {
    @Bindable var model: RowModel
    let content: (FocusState<UUID?>.Binding) -> Content
    @FocusState private var focus: UUID?

    init(model: RowModel, @ViewBuilder content: @escaping (FocusState<UUID?>.Binding) -> Content) {
        self.model = model
        self.content = content
    }

    var body: some View {
        content($focus)
            .onChange(of: focus) { _, newValue in
                model.log.emit("focus", node: "focus", payload: ["focused": newValue?.uuidString ?? "none"])
            }
            .onChange(of: model.focusRequestSeq) { _, _ in
                focus = model.focusRequest
            }
            .toolbar {
                Button("Insert above") { model.requestInsert() }
                    .accessibilityIdentifier("toolbar/insert")
            }
            .task(id: model.insertRequestSeq) {
                await model.runToolbarInsert()
            }
            .onAppear {
                model.log.emit("lifecycle", node: "window", payload: ["phase": "root-appear"])
            }
            .onDisappear {
                model.markClosed()
            }
    }
}

/// Lifetime probe for the view state of a screen. Its deinit records that the tree was released.
final class TreeProbe {
    private let log: EventLog

    init(log: EventLog) {
        self.log = log
    }

    deinit {
        log.emit("lifecycle", node: "tree", payload: ["phase": "released"])
    }
}
