import Foundation
import Observation
import SwiftRightRuntime

// Port of probes/sr0-o/fixtures Screens F1Screen, Common/SharedViews.swift (EditableRowView, RowList,
// FixtureScaffold toolbar and focus). Runtime-supported API only: no onChange, no animation.
// Local edit counting moves from onChange to the text write path (see EditableRowView).

struct F1Root: View {
    @Bindable var model: RowModel
    @FocusState private var focus: UUID?

    var body: some View {
        let _ = model.registerFocus($focus)
        VStack(alignment: .leading, spacing: 8) {
            Button("Insert above", action: { model.requestInsertAboveFromButton() })
            RowList(model: model, focus: $focus)
        }
        .padding(.all, 16)
    }
}

struct RowList: View {
    @Bindable var model: RowModel
    let focus: FocusState<UUID?>.Binding

    var body: some View {
        List {
            ForEach($model.rows, id: \.id) { row in
                EditableRowView(row: row, model: model, focus: focus)
            }
        }
    }
}

/// One editable row. Its @State is per identity, so a row keeps its counter across an insert above.
struct EditableRowView: View {
    let row: Binding<Row>
    let model: RowModel
    let focus: FocusState<UUID?>.Binding
    @State private var localEdits = 0

    var body: some View {
        let id = row.wrappedValue.id
        let text = row.text
        let edits = $localEdits
        let _ = model.registerTextInput(id) { newValue in
            text.wrappedValue = newValue
            edits.wrappedValue += 1
            model.log.emit("state", node: id.uuidString, payload: ["op": "edit", "text": newValue])
            model.log.emit("lifecycle", node: id.uuidString, payload: ["phase": "local-edit", "local": edits.wrappedValue])
        }
        HStack {
            TextField("Row", text: Binding(get: { text.wrappedValue }, set: { model.editText(id, $0) }))
                .focused(focus, equals: id)
            Text("local \(localEdits)")
        }
        .onAppear {
            model.log.emit("lifecycle", node: id.uuidString, payload: [
                "phase": "appear", "local": edits.wrappedValue, "controls": ["field"],
            ])
        }
        .onDisappear {
            model.log.emit("lifecycle", node: id.uuidString, payload: ["phase": "disappear", "local": edits.wrappedValue])
        }
    }
}
