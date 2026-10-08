import Foundation
import Observation
#if os(macOS)
import SwiftUI
#endif

// F1: surviving-row identity. Engine-driven insert above the active edit.
struct F1Screen: View {
    @Bindable var model: RowModel

    var body: some View {
        FixtureScaffold(model: model) { focus in
            RowList(model: model, focus: focus)
        }
        .task { await model.runInsertAbove(key: "insert-above", slot: 99) }
    }
}

// F2: reorder via onMove, identity and caret-owning row preserved.
struct F2Screen: View {
    @Bindable var model: RowModel

    var body: some View {
        FixtureScaffold(model: model) { focus in
            RowList(model: model, focus: focus)
        }
    }
}

// F3: removal tears rows down; reinsertion with the same UUID starts fresh @State.
struct F3Screen: View {
    @Bindable var model: RowModel

    var body: some View {
        FixtureScaffold(model: model) { focus in
            RowList(model: model, focus: focus, rowTasks: true)
        }
    }
}

// F4: each row runs a guarded engine task; removal happens before the engine completes.
struct F4Screen: View {
    @Bindable var model: RowModel

    var body: some View {
        FixtureScaffold(model: model) { focus in
            RowList(model: model, focus: focus, rowTasks: true)
        }
    }
}

// F6: interrupted animation. Overlapping animated inserts; reduced-motion policy from the environment.
struct F6Screen: View {
    @Bindable var model: RowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FixtureScaffold(model: model) { focus in
            RowList(model: model, focus: focus)
        }
        .animation(model.animationEnabled ? .linear(duration: 0.6) : nil, value: model.rows.count)
        .onAppear { model.setReducedMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, newValue in model.setReducedMotion(newValue) }
    }
}

// F7: IME placeholder. Composition is out-of-process; the screen provides the active row and insert trigger.
struct F7Screen: View {
    @Bindable var model: RowModel

    var body: some View {
        FixtureScaffold(model: model) { focus in
            VStack(alignment: .leading) {
                Text("IME placeholder: composition is driven out-of-process")
                RowList(model: model, focus: focus)
            }
        }
        .task { await model.runInsertAbove(key: "insert-above", slot: 99) }
    }
}

// F8: accessibility surface. Every row exposes a text field and a labelled Delete button.
struct F8Screen: View {
    @Bindable var model: RowModel

    var body: some View {
        FixtureScaffold(model: model) { focus in
            RowList(model: model, focus: focus, showDelete: true)
        }
    }
}

// F9: window teardown with live row tasks and a screen-level task.
struct F9Screen: View {
    @Bindable var model: RowModel
    @State private var probe: TreeProbe?

    var body: some View {
        FixtureScaffold(model: model) { focus in
            RowList(model: model, focus: focus, rowTasks: true)
        }
        .task { await model.runScreenSync() }
        .onAppear {
            if probe == nil { probe = TreeProbe(log: model.log) }
        }
    }
}
