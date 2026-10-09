import Foundation
import Observation
import SwiftUI

/// Chrome for SR1 screens: focus logging, programmatic focus requests, and root appearance for the launcher.
struct SR1Scaffold<Content: View>: View {
    @Bindable var model: SR1Model
    let content: (FocusState<String?>.Binding) -> Content
    @FocusState private var focus: String?

    init(model: SR1Model, @ViewBuilder content: @escaping (FocusState<String?>.Binding) -> Content) {
        self.model = model
        self.content = content
    }

    var body: some View {
        content($focus)
            .onChange(of: focus) { _, newValue in
                model.log.emit("focus", node: "focus", payload: ["focused": newValue ?? "none"])
            }
            .onChange(of: model.focusRequestSeq) { _, _ in
                focus = model.focusRequest
            }
            .onAppear {
                model.log.emit("lifecycle", node: "window", payload: ["phase": "root-appear"])
            }
            .onDisappear {
                model.log.emit("lifecycle", node: "window", payload: ["phase": "root-disappear"])
            }
            .padding()
    }
}

// G1: Toggle. Binding write, keyboard Space, AX role and value.
struct G1Screen: View {
    @Bindable var model: SR1Model

    var body: some View {
        SR1Scaffold(model: model) { focus in
            Toggle("Sync enabled", isOn: $model.toggleOn)
                .focused(focus, equals: "g1/toggle")
                .accessibilityIdentifier("g1/toggle")
                .onChange(of: model.toggleOn) { _, value in
                    model.log.emit("state", node: "g1/toggle", payload: ["op": "binding-write", "value": value])
                }
        }
    }
}

// G2: TextEditor multi-line. Typing, Return, selection by AX range and Cmd-A.
struct G2Screen: View {
    @Bindable var model: SR1Model

    var body: some View {
        SR1Scaffold(model: model) { focus in
            TextEditor(text: $model.note)
                .focused(focus, equals: "g2/editor")
                .accessibilityIdentifier("g2/editor")
                .frame(width: 400, height: 180)
        }
    }
}

// G3: List(selection:) single and multiple side by side.
struct G3Screen: View {
    @Bindable var model: SR1Model

    var body: some View {
        SR1Scaffold(model: model) { _ in
            HStack(alignment: .top, spacing: 16) {
                List(selection: $model.singleSelection) {
                    ForEach(model.g3Rows) { row in
                        Text(row.title).tag(Optional(row.id))
                    }
                }
                .accessibilityIdentifier("g3/single")
                .frame(width: 190, height: 220)
                .onChange(of: model.singleSelection) { _, value in
                    model.log.emit("state", node: "g3/single", payload: ["op": "binding-write", "value": value?.uuidString ?? "nil"])
                }

                List(selection: $model.multiSelection) {
                    ForEach(model.g3Rows) { row in
                        Text(row.title).tag(row.id)
                    }
                }
                .accessibilityIdentifier("g3/multi")
                .frame(width: 190, height: 220)
                .onChange(of: model.multiSelection) { _, value in
                    model.log.emit("state", node: "g3/multi", payload: [
                        "op": "binding-write", "ids": value.map(\.uuidString).sorted(),
                    ])
                }
            }
        }
    }
}

// G4: List with .onDelete. Delete key on a selected row, and the model deletion command.
struct G4Screen: View {
    @Bindable var model: SR1Model

    var body: some View {
        SR1Scaffold(model: model) { focus in
            List(selection: $model.g4Selection) {
                ForEach(model.g4Items) { item in
                    Text(item.title)
                        .tag(Optional(item.id))
                        .accessibilityIdentifier("g4/row/\(item.id.uuidString)")
                        .onAppear {
                            model.log.emit("lifecycle", node: item.id.uuidString, payload: ["phase": "appear"])
                        }
                        .onDisappear {
                            model.log.emit("lifecycle", node: item.id.uuidString, payload: ["phase": "disappear"])
                        }
                }
                .onDelete { offsets in
                    model.log.emit("state", node: "g4/list", payload: ["op": "onDelete-handler", "offsets": Array(offsets)])
                    model.deleteG4(offsets, source: "onDelete")
                }
            }
            .accessibilityIdentifier("g4/list")
            .focused(focus, equals: "g4/list")
            .frame(width: 300, height: 220)
        }
    }
}

// G5: contextMenu on a target and a Menu with an enabled and a disabled item.
struct G5Screen: View {
    @Bindable var model: SR1Model

    var body: some View {
        SR1Scaffold(model: model) { _ in
            VStack(spacing: 24) {
                Text("Context target")
                    .padding(12)
                    .background(Color.gray.opacity(0.2))
                    .accessibilityIdentifier("g5/target")
                    .contextMenu {
                        Button("Rename") { model.menuAction("rename") }
                        Button("Duplicate") { model.menuAction("duplicate") }
                        Button("Locked action") { model.menuAction("locked") }
                            .disabled(true)
                    }
                Menu("More actions") {
                    Button("Archive") { model.menuAction("archive") }
                    Button("Pin") { model.menuAction("pin") }
                        .disabled(true)
                }
                .accessibilityIdentifier("g5/menu")
            }
        }
    }
}

// G6: alert and confirmationDialog. Presentation is driven by buttons; bindings are observed for reset.
struct G6Screen: View {
    @Bindable var model: SR1Model

    var body: some View {
        SR1Scaffold(model: model) { _ in
            VStack(spacing: 16) {
                Button("Open alert") { model.alertShown = true }
                    .accessibilityIdentifier("g6/open-alert")
                Button("Open dialog") { model.dialogShown = true }
                    .accessibilityIdentifier("g6/open-dialog")
            }
            .alert("Delete project?", isPresented: $model.alertShown) {
                Button("Delete", role: .destructive) {
                    model.log.emit("state", node: "g6/alert", payload: ["op": "action", "action": "delete"])
                }
                Button("Cancel", role: .cancel) {
                    model.log.emit("state", node: "g6/alert", payload: ["op": "action", "action": "cancel"])
                }
            } message: {
                Text("This cannot be undone.")
            }
            .confirmationDialog("Choose an action", isPresented: $model.dialogShown, titleVisibility: .visible) {
                Button("Archive") {
                    model.log.emit("state", node: "g6/dialog", payload: ["op": "action", "action": "archive"])
                }
                Button("Duplicate") {
                    model.log.emit("state", node: "g6/dialog", payload: ["op": "action", "action": "duplicate"])
                }
                Button("Cancel", role: .cancel) {
                    model.log.emit("state", node: "g6/dialog", payload: ["op": "action", "action": "cancel"])
                }
            }
            .onChange(of: model.alertShown) { _, value in
                model.log.emit("state", node: "g6/alert", payload: ["op": "binding", "presented": value])
            }
            .onChange(of: model.dialogShown) { _, value in
                model.log.emit("state", node: "g6/dialog", payload: ["op": "binding", "presented": value])
            }
        }
    }
}

// G7: keyboardShortcut on view buttons. The menu command set (SR1Commands) adds a second Cmd-S handler.
struct G7Screen: View {
    @Bindable var model: SR1Model

    var body: some View {
        SR1Scaffold(model: model) { _ in
            VStack(spacing: 12) {
                Button("Save") { model.log.emit("effect", node: "g7/view-save", payload: ["phase": "fired", "handler": "view-save"]) }
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityIdentifier("g7/save")
                Button("Export") { model.log.emit("effect", node: "g7/view-export", payload: ["phase": "fired", "handler": "view-export"]) }
                    .keyboardShortcut("e", modifiers: .command)
                    .accessibilityIdentifier("g7/export")
                Button("Locked") { model.log.emit("effect", node: "g7/view-locked", payload: ["phase": "fired", "handler": "view-locked"]) }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(true)
                    .accessibilityIdentifier("g7/locked")
            }
        }
    }
}

// G8: Image, Label, Divider and .disabled exposure.
struct G8Screen: View {
    @Bindable var model: SR1Model

    var body: some View {
        SR1Scaffold(model: model) { _ in
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "star.fill")
                    .accessibilityLabel("Starred item")
                    .accessibilityIdentifier("g8/image")
                Label("Save draft", systemImage: "square.and.arrow.down")
                    .accessibilityIdentifier("g8/label")
                Divider()
                    .accessibilityIdentifier("g8/divider")
                Button("Enabled action") { model.log.emit("effect", node: "g8/enabled", payload: ["phase": "fired"]) }
                    .accessibilityIdentifier("g8/enabled")
                Button("Disabled action") { model.log.emit("effect", node: "g8/disabled", payload: ["phase": "fired"]) }
                    .disabled(model.controlsLocked)
                    .accessibilityIdentifier("g8/disabled")
            }
        }
    }
}

/// App-level command set for G7. Attached to the Window scene in FixtureApp; it only records, never mutates the screen.
@MainActor
public struct SR1Commands: Commands {
    let session: FixtureSession

    public init(session: FixtureSession) {
        self.session = session
    }

    public var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save Document") {
                session.sr1.log.emit("effect", node: "g7/menu-save", payload: ["phase": "fired", "handler": "menu-save"])
            }
            .keyboardShortcut("s", modifiers: .command)
        }
        CommandGroup(after: .saveItem) {
            Button("Save Copy") {
                session.sr1.log.emit("effect", node: "g7/menu-save-copy", payload: ["phase": "fired", "handler": "menu-save-copy"])
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
