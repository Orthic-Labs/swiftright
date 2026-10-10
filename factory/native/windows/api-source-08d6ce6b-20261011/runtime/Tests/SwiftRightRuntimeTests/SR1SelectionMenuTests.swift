import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// SR1 selection, deletion, menus, alerts and dialogs, and keyboard shortcuts.

@Observable
@MainActor
final class SR1Picker {
    var one: Int? = nil
    var many: Set<Int> = []
    var rows = [1, 2, 3, 4]
    var deleted: [Int] = []
}

struct SR1SingleListScreen: View {
    @Bindable var model: SR1Picker

    var body: some View {
        List(selection: $model.one) {
            ForEach(model.rows, id: \.self) { row in
                Text("Row \(row)").tag(row)
            }
        }
    }
}

struct SR1MultiListScreen: View {
    @Bindable var model: SR1Picker

    var body: some View {
        List(selection: $model.many) {
            ForEach(model.rows, id: \.self) { row in
                Text("Row \(row)").tag(row)
            }
        }
    }
}

struct SR1DeletableListScreen: View {
    @Bindable var model: SR1Picker

    var body: some View {
        List(selection: $model.many) {
            ForEach(model.rows, id: \.self) { row in
                Text("Row \(row)").tag(row)
            }
            .onDelete { offsets in
                for offset in offsets.reversed() {
                    model.rows.remove(at: offset)
                }
                model.deleted = Array(offsets)
            }
        }
    }
}

struct SR1MenuScreen: View {
    @Bindable var model: SR1Counter

    var body: some View {
        VStack {
            Text("Doc")
                .contextMenu {
                    Button("Open") { model.a += 1 }
                    Divider()
                    Button("Delete", role: .destructive) { model.b += 1 }
                        .disabled(true)
                    Menu("More") {
                        Button("Copy") { model.c += 1 }
                    }
                }
            Menu("Share") {
                Button("Mail") { model.d += 1 }
            }
        }
    }
}

@Observable
@MainActor
final class SR1Dialog {
    var presented = false
    var outcome = ""
}

struct SR1AlertScreen: View {
    @Bindable var model: SR1Dialog

    var body: some View {
        Text("Body")
            .alert(
                "Delete file?",
                isPresented: $model.presented,
                actions: {
                    Button("Cancel", role: .cancel) { model.outcome = "cancel" }
                    Button("Delete", role: .destructive) { model.outcome = "delete" }
                },
                message: { Text("This cannot be undone.") }
            )
    }
}

struct SR1ConfirmationScreen: View {
    @Bindable var model: SR1Dialog

    var body: some View {
        Text("Body")
            .confirmationDialog(
                "Sign out?",
                isPresented: $model.presented,
                titleVisibility: .visible,
                actions: {
                    Button("Sign Out", role: .destructive) { model.outcome = "out" }
                    Button("Stay") { model.outcome = "stay" }.disabled(true)
                },
                message: { Text("You will be logged out.") }
            )
    }
}

struct SR1ShortcutScreen: View {
    @Bindable var model: SR1Counter

    var body: some View {
        VStack {
            Button("Save") { model.a += 1 }
                .keyboardShortcut("s")
            Button("Undo") { model.b += 1 }
                .keyboardShortcut("z")
            Button("Redo") { model.c += 1 }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button("Hidden") { model.d += 1 }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(true)
        }
    }
}

/// The id of the list row whose subtree contains `text`.
@MainActor
func sr1RowID(_ graph: Graph, containing text: String) -> String? {
    sr1All(graph.snapshot()).first { row in
        row.accessibility.role == "list-item" && sr1All(row).contains { $0.text == text }
    }?.id
}

@MainActor
final class SR1SelectionMenuTests: XCTestCase {

    // Single selection writes the binding on click, follows the cursor with up and down (clamped at the ends),
    // and rejects select-all. Rows report list-item and isSelected from the binding.
    // https://developer.apple.com/documentation/swiftui/list/init(selection:content:)
    func testSingleSelectionClickAndKeyboardNavigation() {
        let model = SR1Picker()
        let graph = Graph(SR1SingleListScreen(model: model))
        graph.flush()
        let list = graph.ids(ofKind: "List")[0]
        XCTAssertEqual(sr1Node(graph, list)?.accessibility.role, "list")

        XCTAssertTrue(graph.selectRow(sr1RowID(graph, containing: "Row 3")!))
        XCTAssertEqual(model.one, 3)
        graph.flush()
        XCTAssertEqual(sr1Node(graph, sr1RowID(graph, containing: "Row 3")!)?.accessibility.isSelected, true)
        XCTAssertEqual(sr1Node(graph, sr1RowID(graph, containing: "Row 2")!)?.accessibility.isSelected, false)
        XCTAssertEqual(sr1Node(graph, sr1RowID(graph, containing: "Row 3")!)?.accessibility.role, "list-item")

        XCTAssertTrue(graph.navigateList(list, .down))
        XCTAssertEqual(model.one, 4)
        XCTAssertTrue(graph.navigateList(list, .down))
        XCTAssertEqual(model.one, 4, "clamped at the last row")
        XCTAssertTrue(graph.navigateList(list, .up))
        XCTAssertEqual(model.one, 3)
        XCTAssertFalse(graph.navigateList(list, .selectAll), "select all needs multiple selection")
    }

    // Multiple selection: click replaces, command toggles, shift extends from the anchor, select all takes every
    // row, and extending with up grows the range from the anchor to the cursor.
    // https://developer.apple.com/documentation/swiftui/list/init(selection:content:)
    func testMultipleSelectionModifiersAndRanges() {
        let model = SR1Picker()
        let graph = Graph(SR1MultiListScreen(model: model))
        graph.flush()
        let list = graph.ids(ofKind: "List")[0]

        XCTAssertTrue(graph.selectRow(sr1RowID(graph, containing: "Row 1")!))
        XCTAssertEqual(model.many, [1])
        XCTAssertTrue(graph.selectRow(sr1RowID(graph, containing: "Row 3")!, modifiers: .command))
        XCTAssertEqual(model.many, [1, 3])
        XCTAssertTrue(graph.selectRow(sr1RowID(graph, containing: "Row 4")!, modifiers: .shift))
        XCTAssertEqual(model.many, [3, 4], "shift extends from the last clicked anchor (row 3)")

        XCTAssertTrue(graph.navigateList(list, .selectAll))
        XCTAssertEqual(model.many, [1, 2, 3, 4])

        XCTAssertTrue(graph.navigateList(list, .up, extending: true))
        XCTAssertEqual(model.many, [1, 2, 3])
    }

    // Delete through onDelete: the handler gets the offsets of the rows, runs once per handler, and the
    // selection-based delete targets selected rows only.
    // https://developer.apple.com/documentation/swiftui/dynamicviewcontent/ondelete(perform:)
    func testOnDeleteRunsWithRowOffsets() {
        let model = SR1Picker()
        let graph = Graph(SR1DeletableListScreen(model: model))
        graph.flush()

        XCTAssertTrue(graph.deleteRow(sr1RowID(graph, containing: "Row 2")!))
        XCTAssertEqual(model.deleted, [1])
        XCTAssertEqual(model.rows, [1, 3, 4])
        graph.flush()
        XCTAssertNil(sr1RowID(graph, containing: "Row 2"))

        model.many = [3, 4]
        graph.flush()
        XCTAssertTrue(graph.deleteSelection(in: graph.ids(ofKind: "List")[0]))
        XCTAssertEqual(model.deleted, [1, 2])
        XCTAssertEqual(model.rows, [1])
    }

    func testDeleteWithoutHandlerReturnsFalse() {
        let model = SR1Picker()
        let graph = Graph(SR1MultiListScreen(model: model))
        graph.flush()
        XCTAssertFalse(graph.deleteRow(sr1RowID(graph, containing: "Row 1")!))
        XCTAssertEqual(model.rows, [1, 2, 3, 4])
    }

    // contextMenu and Menu are model nodes: their items carry titles, dividers, submenus and disabled state.
    // Enabled actions run through performMenuItem; disabled ones do not.
    // https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:)
    // https://developer.apple.com/documentation/swiftui/menu
    func testContextMenuAndMenuItemsDispatch() {
        let model = SR1Counter()
        let graph = Graph(SR1MenuScreen(model: model))
        graph.flush()

        let context = sr1Kind(graph, "modifier.contextMenu")
        XCTAssertEqual(context.count, 1)
        let items = context[0].menu ?? []
        XCTAssertEqual(items.map(\.title), ["Open", "", "Delete", "More"])
        XCTAssertEqual(items.map(\.kind), [.action, .divider, .action, .submenu])
        XCTAssertEqual(items[2].isDisabled, true)
        XCTAssertEqual(items[3].children.map(\.title), ["Copy"])

        XCTAssertTrue(graph.performMenuItem(context[0].id, path: [0]))
        XCTAssertEqual(model.a, 1)
        XCTAssertFalse(graph.performMenuItem(context[0].id, path: [2]), "disabled item does not run")
        XCTAssertEqual(model.b, 0)
        XCTAssertTrue(graph.performMenuItem(context[0].id, path: [3, 0]), "submenu item runs")
        XCTAssertEqual(model.c, 1)
        XCTAssertFalse(graph.performMenuItem(context[0].id, path: [9]))

        // Only the top-level Menu is a graph node; "More" is a submenu entry of the context menu model.
        let share = sr1Kind(graph, "Menu")
        XCTAssertEqual(share.count, 1)
        XCTAssertEqual(share.first?.menu?.map(\.title), ["Mail"])
        XCTAssertTrue(graph.performMenuItem(share[0].id, path: [0]))
        XCTAssertEqual(model.d, 1)
    }

    // alert is presented while its binding is true. The runtime lists the actions with roles, dispatches the
    // chosen action and dismisses, and cancel dismisses without an action.
    // https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:)
    func testAlertPresentationAndActionDispatch() {
        let model = SR1Dialog()
        let graph = Graph(SR1AlertScreen(model: model))
        graph.flush()
        XCTAssertTrue(sr1Kind(graph, "modifier.alert").first?.presentation == nil)

        model.presented = true
        graph.flush()
        let alertNode = sr1Kind(graph, "modifier.alert").first
        let presentation = alertNode?.presentation
        XCTAssertEqual(presentation?.kind, "alert")
        XCTAssertEqual(presentation?.title, "Delete file?")
        XCTAssertEqual(presentation?.message, "This cannot be undone.")
        XCTAssertEqual(presentation?.actions.map(\.title), ["Cancel", "Delete"])
        XCTAssertEqual(presentation?.actions.map(\.role), [.cancel, .destructive])
        XCTAssertEqual(alertNode?.accessibility.role, "alert")

        XCTAssertTrue(graph.performPresentationAction(alertNode!.id, index: 1))
        XCTAssertEqual(model.outcome, "delete")
        XCTAssertFalse(model.presented, "an action dismisses the alert")
        graph.flush()
        XCTAssertNil(sr1Kind(graph, "modifier.alert").first?.presentation)

        model.presented = true
        graph.flush()
        let again = sr1Kind(graph, "modifier.alert").first!.id
        XCTAssertTrue(graph.dismissPresentation(again))
        XCTAssertFalse(model.presented)
        XCTAssertEqual(model.outcome, "delete", "dismissal runs no action")
    }

    // confirmationDialog reports its title visibility and dialog role. A disabled action does not run and does not
    // dismiss.
    // https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:message:)
    func testConfirmationDialogVisibilityAndDisabledAction() {
        let model = SR1Dialog()
        let graph = Graph(SR1ConfirmationScreen(model: model))
        model.presented = true
        graph.flush()
        let node = sr1Kind(graph, "modifier.confirmationDialog").first
        XCTAssertEqual(node?.presentation?.kind, "confirmationDialog")
        XCTAssertEqual(node?.presentation?.titleVisibility, .visible)
        XCTAssertEqual(node?.presentation?.actions.map(\.role), [.destructive, nil])
        XCTAssertEqual(node?.accessibility.role, "dialog")

        XCTAssertFalse(graph.performPresentationAction(node!.id, index: 1), "disabled action")
        XCTAssertTrue(model.presented)
        XCTAssertEqual(model.outcome, "")
    }

    // Keyboard shortcuts are a registry. Logical commands map per CONTRACT section 4: redo differs between Mac
    // and Windows. Dispatch runs the named button when enabled. Disabled shortcuts do not dispatch.
    // https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:modifiers:)
    func testKeyboardRegistryLogicalMappingAndDispatch() {
        let model = SR1Counter()
        let graph = Graph(SR1ShortcutScreen(model: model))
        graph.flush()

        let entries = graph.keyboardShortcuts()
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].shortcut.logical, nil, "save is not a CONTRACT command")
        XCTAssertEqual(entries[1].shortcut.logical, .undo)
        XCTAssertEqual(entries[2].shortcut.logical, .redo, "Mac redo is Shift-Cmd-Z")
        XCTAssertFalse(entries[3].isEnabled)

        graph.keyboardPlatform = .windows
        XCTAssertNil(graph.keyboardShortcuts()[2].shortcut.logical, "Shift-Cmd-Z is not redo on Windows")
        XCTAssertEqual(KeyboardChords.chord(for: .redo, on: .windows), KeyboardChord(key: "y", modifiers: .command))
        XCTAssertEqual(KeyboardChords.command(for: KeyboardChord(key: "y", modifiers: .command), on: .windows), .redo)
        XCTAssertEqual(KeyboardChords.chord(for: .copy, on: .mac), KeyboardChords.chord(for: .copy, on: .windows))

        XCTAssertTrue(graph.performKeyboardShortcut("s", modifiers: .command))
        XCTAssertEqual(model.a, 1)
        XCTAssertTrue(graph.performKeyboardShortcut("z", modifiers: .command))
        XCTAssertEqual(model.b, 1)
        XCTAssertFalse(graph.performKeyboardShortcut(.escape, modifiers: []), "disabled shortcut")
        XCTAssertEqual(model.d, 0)
        XCTAssertFalse(graph.performKeyboardShortcut("q", modifiers: .command))
    }
}
