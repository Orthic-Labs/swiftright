import Foundation
import SwiftRightRuntime

// Scripted self-test for one gallery screen. One stage runs per display tick (after the previous stage's
// commit has been flushed and two ticks have passed). Stages drive the runtime through Graph and read back the
// resolved tree and what the backend committed to the renderer (GalleryBackend.committed).
//
// Native popups and task dialogs are never opened here (no --live-modal). Their answers are fed through
// GalleryBackend.modalResult with the arguments the renderer would send, so the item-id mapping is checked without a
// human. The display itself is BLOCKED: it needs a person (or a UIA driver) on the desktop.
// BLOCKED means a behaviour this run cannot verify. It is not a pass.

typealias GalleryStage = (name: String, run: () -> Void)

@MainActor
final class GallerySelfTest {
    let backend: GalleryBackend
    let model: GalleryModel
    let screen: String
    var requestQuit: (() -> Void)?
    private(set) var finished = false
    private(set) var closedSeen = false
    private var checks = 0
    private var passes = 0
    private var failures: [String] = []
    private var blockers: [String] = []
    private var stages: [GalleryStage] = []
    private var index = 0
    private var waitTicks = 0
    private var stageName = "start"

    init(backend: GalleryBackend, model: GalleryModel, screen: String) {
        self.backend = backend
        self.model = model
        self.screen = screen
        self.stages = [(name: "renderer-accepts-commits", run: { [self] in
            self.check("renderer accepted commits", self.backend.commitCount > 0 && self.backend.commitErrors.isEmpty)
            self.check("no measurement failures", self.backend.measureFailures == 0)
            self.check("two test patterns registered", self.backend.registeredPatternCount == 2)
        })] + stagesFor(screen)
    }

    var exitCode: Int32 {
        if !failures.isEmpty { return 1 }
        if !blockers.isEmpty { return 3 }
        return 0
    }

    /// Runs the next stage. Called from every bridge event and every display tick.
    func advance() {
        guard !finished, backend.isReady, backend.graph != nil else { return }
        if waitTicks > 0 {
            waitTicks -= 1
            return
        }
        if index >= stages.count {
            finish()
            return
        }
        let stage = stages[index]
        index += 1
        stageName = stage.name
        stage.run()
        backend.flushNow()
        waitTicks = 2
    }

    func windowClosed() {
        closedSeen = true
    }

    func finishAfterRun() {}

    private func finish() {
        finished = true
        let verdict = !failures.isEmpty ? "FAIL" : (!blockers.isEmpty ? "BLOCKED" : "PASS")
        for (key, count) in backend.abiUses.sorted(by: { $0.key < $1.key }) {
            log("ABI-06 USE \(key): \(count)")
        }
        log("SELFTEST SR1 \(screen): \(verdict) (\(passes)/\(checks) checks, \(blockers.count) blocked, \(failures.count) failed)")
        requestQuit?()
    }

    private func log(_ line: String) {
        print(line)
        fflush(stdout)
    }

    func check(_ name: String, _ ok: Bool) {
        checks += 1
        if ok {
            passes += 1
            log("CHECK [\(stageName)] \(name): ok")
        } else {
            failures.append(name)
            log("CHECK [\(stageName)] \(name): FAIL")
        }
    }

    func block(_ name: String, _ reason: String) {
        blockers.append("\(name): \(reason)")
        log("BLOCKED [\(stageName)] \(name): \(reason)")
    }

    // MARK: queries on the resolved tree

    private var graph: Graph { backend.graph! }

    private func flatten(_ node: ResolvedNode?) -> [ResolvedNode] {
        guard let node else { return [] }
        return [node] + node.children.flatMap { flatten($0) }
    }

    private func all() -> [ResolvedNode] { flatten(graph.snapshot()) }

    private func nodes(_ kind: String) -> [ResolvedNode] { all().filter { $0.kind == kind } }

    /// First node of `kind` whose descendant text equals `text`.
    private func node(_ kind: String, _ text: String) -> ResolvedNode? {
        nodes(kind).first { galleryText($0) == text }
    }

    private func rowID(_ text: String) -> String? {
        all().first { $0.accessibility.role == "list-item" && galleryText($0) == text }?.id
    }

    private func listID() -> String? { graph.ids(ofKind: "List").first }

    private func presented() -> ResolvedPresentation? {
        all().compactMap(\.presentation).first
    }

    private func presentedHost() -> String? {
        all().first { $0.presentation != nil }?.id
    }

    private func documentHost() -> ResolvedNode? {
        all().first { $0.menu != nil && galleryText($0) == "Document" }
    }

    /// What the backend committed for a runtime node in the latest commit.
    private func sent(_ runtimeNode: ResolvedNode?) -> CommittedSemantic? {
        runtimeNode.flatMap { backend.committed[$0.id] }
    }

    // MARK: stages per screen

    private func stagesFor(_ screen: String) -> [GalleryStage] {
        switch screen {
        case "toggle": return toggleStages()
        case "image": return imageStages()
        case "editor": return editorStages()
        case "label": return labelStages()
        case "list-single": return singleListStages()
        case "list-multi": return multiListStages()
        case "list-delete": return deleteListStages()
        case "menu": return menuStages()
        case "alert": return alertStages()
        case "dialog": return dialogStages()
        case "shortcut": return shortcutStages()
        default: return disabledStages()
        }
    }

    private func toggleStages() -> [GalleryStage] {
        [
            (name: "toggle-role-and-value", run: { [self] in
                let t = self.node("Toggle", "Wi-Fi")
                self.check("Wi-Fi toggle present", t != nil)
                self.check("Wi-Fi toggle reports checkbox role to the runtime", t?.accessibility.role == "checkbox")
                self.check("Wi-Fi toggle value is 0 when off", t?.accessibility.value == "0")
                self.check("renderer gets checkbox role, toggled off", self.sent(t)?.role == .checkbox && self.sent(t)?.toggled == .off)
            }),
            (name: "toggle-activate", run: { [self] in
                guard let t = self.node("Toggle", "Wi-Fi") else { return self.check("activate: toggle present", false) }
                self.check("activateToggle accepted", self.graph.activateToggle(t.id))
            }),
            (name: "toggle-state-after-activate", run: { [self] in
                let t = self.node("Toggle", "Wi-Fi")
                self.check("binding set by toggle", self.model.wifi)
                self.check("Wi-Fi toggle value is 1 when on", t?.accessibility.value == "1")
                self.check("renderer gets toggled on", self.sent(t)?.toggled == .on)
                self.check("Wi-Fi caption follows", self.all().contains { $0.text == "Wi-Fi on" })
            }),
            (name: "toggle-disabled-ignores", run: { [self] in
                guard let t = self.node("Toggle", "Locked") else { return self.check("locked toggle present", false) }
                self.check("disabled toggle reports disabled", !t.accessibility.isEnabled)
                self.check("disabled toggle sent with the disabled flag", self.sent(t)?.disabled == true)
                self.check("disabled toggle refuses activation", !self.graph.activateToggle(t.id))
                self.check("disabled toggle binding unchanged", !self.model.locked)
            }),
            (name: "toggle-native-display", run: { [self] in
                self.block("checkbox rendered and toggled by a click or UIA TogglePattern",
                           "needs the desktop (run with a person or UIA driver); the commit carries role checkbox and toggled state")
            }),
        ]
    }

    private func imageStages() -> [GalleryStage] {
        [
            (name: "image-nodes", run: { [self] in
                let images = self.nodes("Image")
                self.check("two image nodes", images.count == 2)
                self.check("symbol image labelled by its name", images.first?.accessibility.label == "star.fill")
                self.check("asset image uses accessibilityLabel", images.last?.accessibility.label == "Company logo")
            }),
            (name: "image-primitives", run: { [self] in
                self.check("backend drew an image primitive for both images", self.backend.abiUses["image primitive (SWR_PRIM_IMAGE)"] == 2)
                let images = self.nodes("Image")
                self.check("renderer gets role image for both", images.allSatisfy { self.sent($0)?.role == .image })
                self.check("renderer gets the image labels", self.sent(images.last)?.label == "Company logo")
            }),
            (name: "image-pixels-native", run: { [self] in
                self.block("image pixels on screen",
                           "the commit carries SWR_PRIM_IMAGE with generated RGBA patterns; the display needs the desktop")
            }),
        ]
    }

    private func editorStages() -> [GalleryStage] {
        [
            (name: "editor-node", run: { [self] in
                let editor = self.nodes("TextEditor").first
                self.check("TextEditor present", editor != nil)
                self.check("TextEditor reports text-area role to the runtime", editor?.accessibility.role == "text-area")
                self.check("TextEditor value is the note", editor?.accessibility.value == self.model.note)
                self.check("renderer gets a multiline text field", self.sent(editor)?.role == .textField)
            }),
            (name: "editor-single-node", run: { [self] in
                let editor = self.nodes("TextEditor").first
                self.check("both paragraphs measured in one text node", self.backend.editorLines >= 2)
                self.check("one AX text run per visual line, at least two", self.backend.editorRuns >= 2)
                let runs = self.sent(editor)?.runTexts ?? []
                self.check("first paragraph run ends with its newline", runs.first?.hasSuffix("\n") == true)
                self.check("AX runs partition the note", runs.joined() == self.model.note)
            }),
            (name: "editor-type", run: { [self] in
                guard let editor = self.nodes("TextEditor").first, let state = self.graph.textInput(editor.id) else {
                    return self.check("editor text state present", false)
                }
                _ = state.setSelection(UTF16Range(location: state.display.utf16.count, length: 0))
                self.check("replace accepted in editor", state.replace(range: nil, text: "!"))
                self.check("model note ends with typed text", self.model.note.hasSuffix("!"))
            }),
            (name: "editor-runs-follow-typing", run: { [self] in
                let editor = self.nodes("TextEditor").first
                let runs = self.sent(editor)?.runTexts ?? []
                self.check("AX runs follow the typed text", runs.joined() == self.model.note)
            }),
            (name: "title-field-type", run: { [self] in
                guard let field = self.nodes("TextField").first, let state = self.graph.textInput(field.id) else {
                    return self.check("title field text state present", false)
                }
                self.check("replace accepted in title field", state.replace(range: nil, text: "A"))
                self.check("model title holds typed text", self.model.title == "A")
            }),
            (name: "editor-native-caret", run: { [self] in
                self.block("caret and IME on screen",
                           "the single-node editor is committed with line-break cells; typing on the desktop needs a person or UIA")
            }),
        ]
    }

    private func labelStages() -> [GalleryStage] {
        [
            (name: "label-and-divider-nodes", run: { [self] in
                self.check("Label present", self.nodes("Label").count >= 1)
                self.check("Label icon drawn as an image node", self.nodes("Image").count == 1)
                self.check("Label icon uses an image primitive", self.backend.abiUses["image primitive (SWR_PRIM_IMAGE)"] == 1)
                self.check("two dividers present", self.nodes("Divider").count == 2)
            }),
            (name: "style-environment", run: { [self] in
                let styled = self.node("Text", "Styled")
                self.check("styled text present", styled != nil)
                self.check("font environment reaches text", styled?.style.font?.id == "textStyle.title")
                self.check("foreground reaches text", styled?.style.foreground == .semantic("system.red"))
            }),
        ]
    }

    private func singleListStages() -> [GalleryStage] {
        [
            (name: "list-rows", run: { [self] in
                self.check("one List node", self.graph.ids(ofKind: "List").count == 1)
                self.check("four list-item rows", self.all().filter { $0.accessibility.role == "list-item" }.count == 4)
                self.check("every row sent with the selectable flag", self.backend.abiUses["list selectable + selected flags"] == 4)
            }),
            (name: "select-row-2", run: { [self] in
                guard let row = self.rowID("Row 2") else { return self.check("Row 2 present", false) }
                self.check("selectRow accepted", self.graph.selectRow(row))
                self.check("binding holds tag 2", self.model.single == 2)
            }),
            (name: "navigate-down", run: { [self] in
                guard let list = self.listID() else { return self.check("list id present", false) }
                self.check("navigateList down accepted", self.graph.navigateList(list, .down))
                self.check("binding holds tag 3", self.model.single == 3)
            }),
            (name: "row-selected-state", run: { [self] in
                let row3 = self.all().first { galleryText($0) == "Row 3" && $0.accessibility.role == "list-item" }
                self.check("Row 3 reports selected to the runtime", row3?.accessibility.isSelected == true)
                self.check("renderer gets Row 3 selected", self.sent(row3)?.selected == true)
                let row2 = self.all().first { galleryText($0) == "Row 2" && $0.accessibility.role == "list-item" }
                self.check("renderer gets Row 2 not selected", self.sent(row2)?.selected == false)
            }),
        ]
    }

    private func multiListStages() -> [GalleryStage] {
        [
            (name: "multi-command-select", run: { [self] in
                guard let r1 = self.rowID("Row 1"), let r3 = self.rowID("Row 3") else { return self.check("rows present", false) }
                self.check("select Row 1", self.graph.selectRow(r1))
                self.check("command-select Row 3", self.graph.selectRow(r3, modifiers: .command))
                self.check("selection is {1, 3}", self.model.multi == [1, 3])
            }),
            (name: "multi-shift-range", run: { [self] in
                guard let r4 = self.rowID("Row 4") else { return self.check("Row 4 present", false) }
                self.check("shift-select Row 4", self.graph.selectRow(r4, modifiers: .shift))
                self.check("range from anchor 3 to 4", self.model.multi == [3, 4])
            }),
            (name: "multi-select-all", run: { [self] in
                guard let list = self.listID() else { return self.check("list id present", false) }
                self.check("select all accepted", self.graph.navigateList(list, .selectAll))
                self.check("selection is all four rows", self.model.multi == [1, 2, 3, 4])
            }),
            (name: "multi-selected-flags", run: { [self] in
                let rows = self.all().filter { $0.accessibility.role == "list-item" }
                self.check("four rows sent", rows.count == 4)
                self.check("every row sent as selected", rows.allSatisfy { self.sent($0)?.selected == true })
            }),
        ]
    }

    private func deleteListStages() -> [GalleryStage] {
        [
            (name: "select-row-2", run: { [self] in
                guard let r2 = self.rowID("Row 2") else { return self.check("Row 2 present", false) }
                self.check("selectRow Row 2", self.graph.selectRow(r2))
                self.check("selection is {2}", self.model.multi == [2])
            }),
            (name: "delete-selection", run: { [self] in
                guard let list = self.listID() else { return self.check("list id present", false) }
                self.check("deleteSelection accepted", self.graph.deleteSelection(in: list))
                self.check("rows are 1, 3, 4", self.model.rows == [1, 3, 4])
                self.check("onDelete received offset 1", self.model.deletes == [1])
            }),
            (name: "delete-row", run: { [self] in
                guard let r4 = self.rowID("Row 4") else { return self.check("Row 4 present", false) }
                self.check("deleteRow Row 4", self.graph.deleteRow(r4))
                self.check("rows are 1, 3", self.model.rows == [1, 3])
            }),
            (name: "delete-missing-row", run: { [self] in
                self.check("Row 4 no longer present", self.rowID("Row 4") == nil)
            }),
        ]
    }

    private func menuStages() -> [GalleryStage] {
        [
            (name: "menu-hosts", run: { [self] in
                let doc = self.documentHost()
                self.check("context menu host present", doc != nil)
                self.check("context menu has three items", doc?.menu?.count == 3)
                let more = self.nodes("Menu").first
                self.check("Menu node present", more != nil)
                self.check("Menu has one item", more?.menu?.count == 1)
            }),
            (name: "menu-native-items", run: { [self] in
                guard let doc = self.documentHost() else { return self.check("context menu host present", false) }
                let items = self.backend.nativeMenuItems(host: doc.id)
                self.check("native popup gets three items", items.count == 3)
                self.check("item ids are entry index + 1", items.map(\.id) == [1, 2, 3])
                self.check("item texts follow the menu", items.map(\.text) == ["Copy", "Delete", "Share"])
                self.check("Share is sent disabled", items.map(\.disabled) == [false, false, true])
            }),
            (name: "menu-enabled-item", run: { [self] in
                guard let doc = self.documentHost() else { return self.check("context menu host present", false) }
                self.check("Copy runs", self.graph.performMenuItem(doc.id, path: [0]))
                self.check("picks record copy", self.model.menuPicks == ["copy"])
            }),
            (name: "menu-destructive-item", run: { [self] in
                guard let doc = self.documentHost() else { return self.check("context menu host present", false) }
                self.check("Delete runs", self.graph.performMenuItem(doc.id, path: [1]))
                self.check("picks record delete", self.model.menuPicks.last == "delete")
            }),
            (name: "menu-disabled-item", run: { [self] in
                guard let doc = self.documentHost() else { return self.check("context menu host present", false) }
                self.check("disabled Share refuses", !self.graph.performMenuItem(doc.id, path: [2]))
                self.check("picks unchanged by disabled item", self.model.menuPicks.count == 2)
            }),
            (name: "menu-submenu-host", run: { [self] in
                guard let more = self.nodes("Menu").first else { return self.check("Menu node present", false) }
                self.check("Menu item runs", self.graph.performMenuItem(more.id, path: [0]))
                self.check("picks record export", self.model.menuPicks.last == "export")
            }),
            (name: "menu-overlay-fallback", run: { [self] in
                guard let doc = self.documentHost() else { return self.check("context menu host present", false) }
                self.backend.openMenu(hostRuntimeID: doc.id)
                self.check("no native popup without --live-modal", self.backend.modalRequests == 0)
                self.check("in-window overlay opened as the stand-in", self.backend.openMenuHost == doc.id)
            }),
            (name: "menu-overlay-rows", run: { [self] in
                self.check("overlay drew three rows", self.backend.overlayRowsCommitted == 3)
                guard let doc = self.documentHost() else { return self.check("context menu host present", false) }
                let rows = (0..<3).compactMap { self.backend.committed["overlay/\(doc.id)/\($0)"] }
                self.check("overlay rows sent as menu items", rows.count == 3 && rows.allSatisfy { $0.role == .menuItem })
                self.check("overlay Share row sent disabled", rows.last?.disabled == true)
                self.check("overlay container sent as a menu", self.backend.committed["overlay-menu/\(doc.id)"]?.role == .menu)
            }),
            (name: "menu-native-display", run: { [self] in
                self.block("native popup shown and an item picked",
                           "TrackPopupMenu opens only with --live-modal; a person or UIA must pick the item")
            }),
        ]
    }

    private func alertStages() -> [GalleryStage] {
        [
            (name: "alert-open", run: { [self] in
                guard let b = self.node("Button", "Delete item") else { return self.check("Delete item button present", false) }
                self.check("tapButton accepted", self.graph.tapButton(b.id))
                self.check("binding set by tap", self.model.showAlert)
            }),
            (name: "alert-presented", run: { [self] in
                let p = self.presented()
                self.check("alert presented", p != nil)
                self.check("alert kind and title", p?.kind == "alert" && p?.title == "Delete item?")
                self.check("alert has two actions", p?.actions.count == 2)
                self.check("alert plan is two custom buttons", self.backend.modalPlans.last == "alert:buttons-2")
                self.check("alert buttons are Cancel (id 1) and Delete (id 2)",
                           self.backend.activePlan?.buttons.map { "\($0.id):\($0.text)" } == ["1:Cancel", "2:Delete"])
                self.check("renderer gets an alert role for the presentation",
                           self.backend.committed["presentation/\(self.presentedHost() ?? "")"]?.role == .alert)
                self.check("no native dialog without --live-modal", self.backend.liveModal || self.backend.modalRequests == 0)
            }),
            (name: "alert-answer-delete", run: { [self] in
                guard let requestID = self.backend.activeDialogRequestID else {
                    return self.check("dialog request id present", false)
                }
                self.backend.modalResult(requestID: requestID, kind: 3, itemID: 2, index: 1)
                self.check("answer for item 2 runs the Delete action", self.model.outcome == "delete")
            }),
            (name: "alert-dismissed", run: { [self] in
                self.check("alert gone after the answer", self.presented() == nil)
                self.check("binding cleared", !self.model.showAlert)
            }),
            (name: "alert-native-display", run: { [self] in
                self.block("native alert shown and answered",
                           "TaskDialogIndirect opens only with --live-modal; a person or UIA must press a button")
            }),
        ]
    }

    private func dialogStages() -> [GalleryStage] {
        [
            (name: "dialog-open", run: { [self] in
                guard let b = self.node("Button", "Archive options") else { return self.check("Archive options button present", false) }
                self.check("tapButton accepted", self.graph.tapButton(b.id))
            }),
            (name: "dialog-presented", run: { [self] in
                let p = self.presented()
                self.check("dialog presented", p != nil)
                self.check("dialog kind and visibility", p?.kind == "confirmationDialog" && p?.titleVisibility == .visible)
                self.check("dialog has three actions", p?.actions.count == 3)
                self.check("dialog plan is three custom buttons", self.backend.modalPlans.last == "confirmationDialog:buttons-3")
                self.check("dialog buttons are Archive, Delete, Cancel (ids 1 to 3)",
                           self.backend.activePlan?.buttons.map { "\($0.id):\($0.text)" } == ["1:Archive", "2:Delete", "3:Cancel"])
                self.check("renderer gets a dialog role for the presentation",
                           self.backend.committed["presentation/\(self.presentedHost() ?? "")"]?.role == .dialog)
            }),
            (name: "dialog-action", run: { [self] in
                guard let requestID = self.backend.activeDialogRequestID else {
                    return self.check("dialog request id present", false)
                }
                self.backend.modalResult(requestID: requestID, kind: 3, itemID: 1, index: 0)
                self.check("answer for item 1 runs Archive", self.model.outcome == "archive")
                self.check("dialog gone after the answer", self.presented() == nil)
            }),
            (name: "dialog-native-display", run: { [self] in
                self.block("native three-button dialog shown and answered",
                           "TaskDialogIndirect opens only with --live-modal; a person or UIA must press a button")
            }),
        ]
    }

    private func shortcutStages() -> [GalleryStage] {
        [
            (name: "shortcut-registry", run: { [self] in
                let entries = self.graph.keyboardShortcuts()
                self.check("three shortcuts registered", entries.count == 3)
                let logical = entries.compactMap { $0.shortcut.logical }
                self.check("undo and redo resolved for Windows", logical.contains(.undo) && logical.contains(.redo))
            }),
            (name: "shortcut-runtime-dispatch", run: { [self] in
                self.check("Ctrl+S dispatches to Save", self.graph.performKeyboardShortcut("s", modifiers: .command))
                self.check("saves is 1", self.model.saves == 1)
                self.check("Ctrl+Y dispatches to Redo", self.graph.performKeyboardShortcut("y", modifiers: .command))
                self.check("redos is 1", self.model.redos == 1)
            }),
            (name: "shortcut-mac-redo-rejected", run: { [self] in
                self.check("Shift+Ctrl+Z is not Windows redo", !self.graph.performKeyboardShortcut("z", modifiers: [.command, .shift]))
                self.check("undos unchanged", self.model.undos == 0)
            }),
            (name: "shortcut-bridge-ctrl", run: { [self] in
                // Bridge modifier bit 0x1 is Ctrl; the backend maps it to the primary modifier on Windows.
                self.backend.keyDown(name: "s", modifiers: 0x1)
                self.check("renderer key event reaches Save", self.model.saves == 2)
            }),
        ]
    }

    private func disabledStages() -> [GalleryStage] {
        [
            (name: "disabled-flags", run: { [self] in
                let enabled = self.node("Button", "Enabled")
                let disabled = self.node("Button", "Disabled")
                self.check("enabled button reports enabled", enabled?.accessibility.isEnabled == true)
                self.check("disabled button reports disabled", disabled?.accessibility.isEnabled == false)
                self.check("renderer gets the disabled flag on the disabled button", self.sent(disabled)?.disabled == true)
                self.check("renderer gets no disabled flag on the enabled button", self.sent(enabled)?.disabled == false)
            }),
            (name: "disabled-tap-refused", run: { [self] in
                guard let d = self.node("Button", "Disabled") else { return self.check("disabled button present", false) }
                self.check("tapButton refuses disabled", !self.graph.tapButton(d.id))
                self.check("clicks unchanged", self.model.clicks == 0)
            }),
            (name: "enabled-tap-runs", run: { [self] in
                guard let e = self.node("Button", "Enabled") else { return self.check("enabled button present", false) }
                self.check("tapButton runs enabled", self.graph.tapButton(e.id))
                self.check("clicks is 1", self.model.clicks == 1)
            }),
            (name: "disabled-toggle-refused", run: { [self] in
                guard let t = self.node("Toggle", "Locked toggle") else { return self.check("locked toggle present", false) }
                self.check("disabled toggle refuses", !self.graph.activateToggle(t.id))
                self.check("binding unchanged", !self.model.locked)
                self.check("renderer gets the disabled flag on the toggle", self.sent(t)?.disabled == true)
            }),
            (name: "disabled-flag-count", run: { [self] in
                self.check("two disabled nodes sent (button and toggle)", self.backend.disabledNodes == 2)
            }),
            (name: "disabled-input-native", run: { [self] in
                self.block("renderer refuses a click on the disabled button",
                           "the flag is committed; swallowed presses and UIA IsEnabled need the desktop")
            }),
        ]
    }
}
