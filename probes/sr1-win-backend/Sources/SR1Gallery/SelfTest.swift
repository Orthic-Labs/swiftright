import Foundation
import SwiftRightRuntime

// Scripted self-test for one gallery screen. One stage runs per display tick (after the previous stage's
// commit has been flushed and two ticks have passed). Stages drive the runtime through Graph and read back the
// resolved tree; the backend counters show what reached the renderer.
//
// BLOCKED means a behaviour the ABI 0.5 path cannot verify or express (see the block reasons). It is not a pass.

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
        for (key, count) in backend.abiGapUses.sorted(by: { $0.key < $1.key }) {
            log("ABI-GAP \(key): \(count)")
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
                self.check("Wi-Fi toggle reports checkbox role", t?.accessibility.role == "checkbox")
                self.check("Wi-Fi toggle value is 0 when off", t?.accessibility.value == "0")
            }),
            (name: "toggle-activate", run: { [self] in
                guard let t = self.node("Toggle", "Wi-Fi") else { return self.check("activate: toggle present", false) }
                self.check("activateToggle accepted", self.graph.activateToggle(t.id))
            }),
            (name: "toggle-state-after-activate", run: { [self] in
                self.check("binding set by toggle", self.model.wifi)
                self.check("Wi-Fi toggle value is 1 when on", self.node("Toggle", "Wi-Fi")?.accessibility.value == "1")
                self.check("Wi-Fi caption follows", self.all().contains { $0.text == "Wi-Fi on" })
            }),
            (name: "toggle-disabled-ignores", run: { [self] in
                guard let t = self.node("Toggle", "Locked") else { return self.check("locked toggle present", false) }
                self.check("disabled toggle reports disabled", !t.accessibility.isEnabled)
                self.check("disabled toggle refuses activation", !self.graph.activateToggle(t.id))
                self.check("disabled toggle binding unchanged", !self.model.locked)
            }),
            (name: "toggle-abi-role", run: { [self] in
                self.block("checkbox role and toggled state",
                           "ABI 0.5 has no checkbox role or checked flag; sent as a button with value 1/0")
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
            (name: "image-placeholders", run: { [self] in
                self.check("backend drew placeholders for both images", self.backend.abiGapUses["image-primitive (placeholder drawn)"] == 2)
            }),
            (name: "image-primitive", run: { [self] in
                self.block("image pixels", "SWR_PRIM_IMAGE is SWR_E_UNSUPPORTED in ABI 0.5; only placeholder rects are drawn")
            }),
        ]
    }

    private func editorStages() -> [GalleryStage] {
        [
            (name: "editor-node", run: { [self] in
                let editor = self.nodes("TextEditor").first
                self.check("TextEditor present", editor != nil)
                self.check("TextEditor reports text-area role", editor?.accessibility.role == "text-area")
                self.check("TextEditor value is the note", editor?.accessibility.value == self.model.note)
            }),
            (name: "editor-paragraphs", run: { [self] in
                self.check("both paragraphs drawn as runs", self.backend.abiGapUses["multi-paragraph text (per-paragraph runs, no AX runs)"] == 2)
            }),
            (name: "editor-type", run: { [self] in
                guard let editor = self.nodes("TextEditor").first, let state = self.graph.textInput(editor.id) else {
                    return self.check("editor text state present", false)
                }
                _ = state.setSelection(UTF16Range(location: state.display.utf16.count, length: 0))
                self.check("replace accepted in editor", state.replace(range: nil, text: "!"))
                self.check("model note ends with typed text", self.model.note.hasSuffix("!"))
            }),
            (name: "title-field-type", run: { [self] in
                guard let field = self.nodes("TextField").first, let state = self.graph.textInput(field.id) else {
                    return self.check("title field text state present", false)
                }
                self.check("replace accepted in title field", state.replace(range: nil, text: "A"))
                self.check("model title holds typed text", self.model.title == "A")
            }),
            (name: "editor-ax-runs", run: { [self] in
                self.block("multi-paragraph AX text runs",
                           "ABI 0.5 measures one paragraph per call (no newline); the editor publishes no AX text runs")
            }),
        ]
    }

    private func labelStages() -> [GalleryStage] {
        [
            (name: "label-and-divider-nodes", run: { [self] in
                self.check("Label present", self.nodes("Label").count >= 1)
                self.check("Label icon drawn as an image node", self.nodes("Image").count == 1)
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
                self.check("Row 3 reports selected", self.all().first { galleryText($0) == "Row 3" && $0.accessibility.role == "list-item" }?.accessibility.isSelected == true)
            }),
            (name: "list-selected-abi", run: { [self] in
                self.block("selected state on list items", "ABI 0.5 has no selected flag; the row highlight is drawn only")
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
            (name: "multi-selected-abi", run: { [self] in
                self.block("selected state on list items", "ABI 0.5 has no selected flag; the row highlight is drawn only")
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
                let doc = self.all().first { $0.menu != nil && galleryText($0) == "Document" }
                self.check("context menu host present", doc != nil)
                self.check("context menu has three items", doc?.menu?.count == 3)
                let more = self.nodes("Menu").first
                self.check("Menu node present", more != nil)
                self.check("Menu has one item", more?.menu?.count == 1)
            }),
            (name: "menu-enabled-item", run: { [self] in
                guard let doc = self.all().first(where: { $0.menu != nil && galleryText($0) == "Document" }) else {
                    return self.check("context menu host present", false)
                }
                self.check("Copy runs", self.graph.performMenuItem(doc.id, path: [0]))
                self.check("picks record copy", self.model.menuPicks == ["copy"])
            }),
            (name: "menu-destructive-item", run: { [self] in
                guard let doc = self.all().first(where: { $0.menu != nil && galleryText($0) == "Document" }) else {
                    return self.check("context menu host present", false)
                }
                self.check("Delete runs", self.graph.performMenuItem(doc.id, path: [1]))
                self.check("picks record delete", self.model.menuPicks.last == "delete")
            }),
            (name: "menu-disabled-item", run: { [self] in
                guard let doc = self.all().first(where: { $0.menu != nil && galleryText($0) == "Document" }) else {
                    return self.check("context menu host present", false)
                }
                self.check("disabled Share refuses", !self.graph.performMenuItem(doc.id, path: [2]))
                self.check("picks unchanged by disabled item", self.model.menuPicks.count == 2)
            }),
            (name: "menu-submenu-host", run: { [self] in
                guard let more = self.nodes("Menu").first else { return self.check("Menu node present", false) }
                self.check("Menu item runs", self.graph.performMenuItem(more.id, path: [0]))
                self.check("picks record export", self.model.menuPicks.last == "export")
            }),
            (name: "menu-overlay-open", run: { [self] in
                guard let doc = self.all().first(where: { $0.menu != nil && galleryText($0) == "Document" }) else {
                    return self.check("context menu host present", false)
                }
                self.backend.openMenu(hostRuntimeID: doc.id)
            }),
            (name: "menu-overlay-items", run: { [self] in
                self.check("overlay drew three rows", self.backend.abiGapUses["popup-menu kind (in-window overlay items)"] == 3)
                self.block("native popup menu", "ABI 0.5 has no popup-menu modal kind; the in-window overlay is used instead")
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
                self.check("alert plan is YES/NO", self.backend.modalPlans.last == "alert:yes-no")
                self.check("self-test opened no MessageBox", self.backend.modalRequests == 0)
            }),
            (name: "alert-action", run: { [self] in
                guard let host = self.presentedHost() else { return self.check("alert host present", false) }
                self.check("destructive action runs", self.graph.performPresentationAction(host, index: 1))
                self.check("outcome is delete", self.model.outcome == "delete")
            }),
            (name: "alert-dismissed", run: { [self] in
                self.check("alert gone after action", self.presented() == nil)
                self.check("binding cleared", !self.model.showAlert)
            }),
            (name: "alert-messagebox", run: { [self] in
                self.block("MessageBox answer path",
                           "YES/NO answer needs a human or a UIA driver; run with --live-modal interactively")
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
                self.check("dialog plan is unsupported", self.backend.modalPlans.last == "confirmationDialog:unsupported-3-actions")
            }),
            (name: "dialog-action", run: { [self] in
                guard let host = self.presentedHost() else { return self.check("dialog host present", false) }
                self.check("Archive runs", self.graph.performPresentationAction(host, index: 0))
                self.check("outcome is archive", self.model.outcome == "archive")
            }),
            (name: "dialog-abi-modal", run: { [self] in
                self.block("three-action dialog through the modal",
                           "ABI 0.5 modal offers OK, OK/Cancel and YES/NO only; custom actions need a new modal kind")
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
                self.check("enabled button reports enabled", self.node("Button", "Enabled")?.accessibility.isEnabled == true)
                self.check("disabled button reports disabled", self.node("Button", "Disabled")?.accessibility.isEnabled == false)
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
            }),
            (name: "disabled-abi-flag", run: { [self] in
                self.block("disabled state in the ABI",
                           "SWR_SEM_DISABLED exists in ABI 0.5 but the Swift bridge never sends it; UIA IsEnabled stays true")
            }),
        ]
    }
}
