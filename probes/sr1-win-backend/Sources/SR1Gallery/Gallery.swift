import Foundation
import Observation
import SwiftRightRuntime

// SR1 gallery: one screen per SR1 control. A run shows exactly one screen (chosen by --screen), so each
// self-test covers one control. Views follow the shapes exercised by the SR1 runtime tests
// (probes/sr0-s/fresh-runtime/Tests/SwiftRightRuntimeTests/SR1*.swift).

@Observable
@MainActor
final class GalleryModel {
    var wifi = false
    var locked = false
    var note = "First paragraph\nSecond paragraph"
    var title = ""
    var single: Int? = nil
    var multi: Set<Int> = []
    var rows = [1, 2, 3, 4]
    var deletes: [Int] = []
    var menuPicks: [String] = []
    var showAlert = false
    var showDialog = false
    var outcome = "none"
    var saves = 0
    var undos = 0
    var redos = 0
    var clicks = 0
}

/// Screen names accepted by --screen, in the order the self-test list follows.
let gallerySceneNames = [
    "toggle", "image", "editor", "label", "list-single", "list-multi", "list-delete",
    "menu", "alert", "dialog", "shortcut", "disabled",
]

struct GalleryRoot: View {
    @Bindable var model: GalleryModel
    let screen: String

    var body: some View {
        if screen == "toggle" {
            ToggleScreen(model: model)
        } else if screen == "image" {
            ImageScreen()
        } else if screen == "editor" {
            EditorScreen(model: model)
        } else if screen == "label" {
            LabelScreen()
        } else if screen == "list-single" {
            SingleListScreen(model: model)
        } else if screen == "list-multi" {
            MultiListScreen(model: model)
        } else if screen == "list-delete" {
            DeletableListScreen(model: model)
        } else if screen == "menu" {
            MenuScreen(model: model)
        } else if screen == "alert" {
            AlertScreen(model: model)
        } else if screen == "dialog" {
            DialogScreen(model: model)
        } else if screen == "shortcut" {
            ShortcutScreen(model: model)
        } else {
            DisabledScreen(model: model)
        }
    }
}

// MARK: - Toggle

struct ToggleScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        VStack {
            Toggle("Wi-Fi", isOn: $model.wifi)
            Toggle(isOn: $model.locked) { Text("Locked") }
                .disabled(true)
            Text(model.wifi ? "Wi-Fi on" : "Wi-Fi off")
        }
    }
}

// MARK: - Image

struct ImageScreen: View {
    var body: some View {
        VStack {
            Image(systemName: "star.fill")
            Image("logo").accessibilityLabel("Company logo")
            Text("Images")
        }
    }
}

// MARK: - TextEditor

struct EditorScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        VStack {
            TextEditor(text: $model.note)
            TextField("Title", text: $model.title)
        }
    }
}

// MARK: - Label, Divider, style environment

struct LabelScreen: View {
    var body: some View {
        VStack {
            Label("Inbox", systemImage: "tray")
            Divider()
            Text("Styled")
                .font(.title)
                .foregroundStyle(.red)
            Divider()
        }
    }
}

// MARK: - List selection and deletion

struct SingleListScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        List(selection: $model.single) {
            ForEach(model.rows, id: \.self) { row in
                Text("Row \(row)").tag(row)
            }
        }
    }
}

struct MultiListScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        List(selection: $model.multi) {
            ForEach(model.rows, id: \.self) { row in
                Text("Row \(row)").tag(row)
            }
        }
    }
}

struct DeletableListScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        List(selection: $model.multi) {
            ForEach(model.rows, id: \.self) { row in
                Text("Row \(row)").tag(row)
            }
            .onDelete { offsets in
                for offset in offsets.reversed() {
                    model.rows.remove(at: offset)
                }
                model.deletes.append(contentsOf: offsets)
            }
        }
    }
}

// MARK: - Menu and context menu

struct MenuScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        VStack {
            Text("Document")
                .contextMenu {
                    Button("Copy") { model.menuPicks.append("copy") }
                    Button("Delete", role: .destructive) { model.menuPicks.append("delete") }
                    Button("Share") { model.menuPicks.append("share") }
                        .disabled(true)
                }
            Menu("More") {
                Button("Export") { model.menuPicks.append("export") }
            }
        }
    }
}

// MARK: - Alert and confirmation dialog

struct AlertScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        VStack {
            Button("Delete item") { model.showAlert = true }
            Text("Outcome: \(model.outcome)")
        }
        .alert("Delete item?", isPresented: $model.showAlert, actions: {
            Button("Cancel", role: .cancel) { model.outcome = "cancel" }
            Button("Delete", role: .destructive) { model.outcome = "delete" }
        }, message: {
            Text("This cannot be undone.")
        })
    }
}

struct DialogScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        VStack {
            Button("Archive options") { model.showDialog = true }
            Text("Outcome: \(model.outcome)")
        }
        .confirmationDialog("Choose an action", isPresented: $model.showDialog, titleVisibility: .visible, actions: {
            Button("Archive") { model.outcome = "archive" }
            Button("Delete", role: .destructive) { model.outcome = "delete" }
            Button("Cancel", role: .cancel) { model.outcome = "cancel" }
        }, message: {
            Text("Pick one.")
        })
    }
}

// MARK: - Keyboard shortcuts (CONTRACT section 4: Ctrl maps to the primary modifier on Windows)

struct ShortcutScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        VStack {
            Button("Save") { model.saves += 1 }
                .keyboardShortcut("s")
            Button("Undo") { model.undos += 1 }
                .keyboardShortcut("z")
            Button("Redo") { model.redos += 1 }
                .keyboardShortcut("y")
            Text("saves \(model.saves) undos \(model.undos) redos \(model.redos)")
        }
    }
}

// MARK: - Disabled

struct DisabledScreen: View {
    @Bindable var model: GalleryModel

    var body: some View {
        VStack {
            Button("Enabled") { model.clicks += 1 }
            Button("Disabled") { model.clicks += 100 }
                .disabled(true)
            Toggle("Locked toggle", isOn: $model.locked)
                .disabled(true)
            Text("clicks \(model.clicks)")
        }
    }
}
