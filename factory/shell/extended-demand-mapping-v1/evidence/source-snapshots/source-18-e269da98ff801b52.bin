import Foundation
import Observation
#if os(macOS)
import SwiftUI
#else
import SwiftRightRuntime
#endif

// The reorderable editor screen: one source, compiled against SwiftUI on macOS and against the SwiftRight
// runtime on Windows. Only the subset the Windows runtime supports is used: List + ForEach with onMove,
// TextField, Button, Text, Spacer, FocusState, Binding(get:set:), padding. Up/Down buttons give keyboard
// reordering on both platforms; onMove adds drag reordering where the platform supplies it.

struct EditorScreen: View {
    @Bindable var model: EditorModel
    @FocusState private var focus: UUID?

    var body: some View {
        let focusBinding = $focus
        let _ = model.registerFocus { focusBinding.wrappedValue = $0 }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Insert above", action: { model.insertAbove(focusedID: focusBinding.wrappedValue) })
                Spacer()
                Text("\(model.rows.count) rows")
            }
            if let message = model.lastError {
                Text(message)
            }
            List {
                ForEach($model.rows, id: \.id) { row in
                    EditorRowView(row: row, model: model, focus: focusBinding)
                }
                .onMove { offsets, destination in
                    model.moveRow(from: offsets, to: destination)
                }
            }
        }
        .padding(.all, 16)
    }
}

/// One editable row. The text binding writes through the model so every edit is persisted.
struct EditorRowView: View {
    let row: Binding<EditorRow>
    let model: EditorModel
    let focus: FocusState<UUID?>.Binding

    var body: some View {
        let id = row.wrappedValue.id
        let text = row.text
        HStack {
            TextField("Row", text: Binding(get: { text.wrappedValue }, set: { model.editText(id, $0) }))
                .focused(focus, equals: id)
            Button("Up", action: { model.nudgeRow(id, by: -1) })
            Button("Down", action: { model.nudgeRow(id, by: 1) })
            Button("Delete", action: { model.removeRow(id) })
        }
    }
}
