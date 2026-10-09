#if os(macOS)
import AppKit
import Foundation

/// Step vocabulary for the SR1 fixtures (G1..G8).
/// Every action records exactly one `observe` event (the recorded Mac outcome, hashed by normalize-hash.py),
/// or a driver error. Reads happen in-process through AX; keys are posted to this pid. The outcome is the oracle.
@MainActor
enum SR1Steps {
    /// Returns false when `name` is not an SR1 step, so the caller can report it as unknown.
    static func perform(_ name: String, _ step: [String: Any], model: SR1Model) async -> Bool {
        let log = model.log
        let label = step["label"] as? String ?? name
        // Unique step names keep the canonical hash ordering meaningful across repeated actions.
        log.setStep("\(name):\(label)")
        let pauseMs = step["ms"] as? Int ?? 300
        let id = step["id"] as? String ?? ""

        switch name {
        case "g-activate":
            activate()
            await pause(pauseMs)
            observe(log, node: "window", phase: label, ["responder": responder(), "key-window": NSApp.keyWindow != nil])

        case "g-focus":
            activate()
            model.requestFocus(id)
            await pause(pauseMs)
            observe(log, node: id, phase: label, ["responder": responder(), "requested": id])

        case "g-snap":
            snapshot(log, id: id, label: label)

        case "g-table":
            tableSnapshot(log, index: step["table"] as? Int ?? 0, label: label)

        case "g-key":
            guard let key = keyFromName(step["key"] as? String ?? "") else { return false }
            let flags = flagsFrom(step["flags"] as? [String] ?? [])
            activate()
            SR1AX.tap(key, flags: flags)
            await pause(pauseMs)
            observe(log, node: "key", phase: label, [
                "key": step["key"] as? String ?? "", "flags": (step["flags"] as? [String] ?? []).sorted(), "responder": responder(),
            ])

        case "g-text":
            SR1AX.typeText(step["text"] as? String ?? "")
            await pause(pauseMs)
            observe(log, node: "text", phase: label, ["typed": step["text"] as? String ?? "", "responder": responder()])

        case "g-press":
            let element = SR1AX.find(identifier: id)
            let status = element.map { SR1AX.press($0).rawValue } ?? -1
            await pause(pauseMs)
            observe(log, node: id, phase: label, ["found": element != nil, "ax-status": Int(status)])

        case "g-showmenu":
            let element = SR1AX.find(identifier: id)
            let status = element.map { SR1AX.showMenu($0).rawValue } ?? -1
            await pause(pauseMs)
            observe(log, node: id, phase: label, ["found": element != nil, "ax-status": Int(status)])

        case "g-press-title":
            let title = step["title"] as? String ?? ""
            let role = step["role"] as? String
            let element = SR1AX.find(title: title, role: role)
            let status = element.map { SR1AX.press($0).rawValue } ?? -1
            await pause(pauseMs)
            observe(log, node: "title/\(title)", phase: label, ["found": element != nil, "role": role ?? "any", "ax-status": Int(status)])

        case "g-record":
            // Records a recorder-side status that cannot be observed by an action (for example, an AX action that
            // is advertised but deliberately not invoked in-process). Every field is supplied by the case.
            var fields: [String: Any] = [:]
            for (key, value) in step where !["step", "label", "ms"].contains(key) {
                fields[key] = value
            }
            observe(log, node: id, phase: label, fields)

        case "g-sheet":
            let sheets = SR1AX.everything().filter { ["AXSheet", "AXDialog"].contains(SR1AX.role($0) ?? "") }
            let buttons = sheets.flatMap { buttonTitles(in: $0) }
            observe(log, node: "sheet", phase: label, [
                "sheets": sheets.count, "roles": sheets.map { SR1AX.role($0) ?? "nil" }, "buttons": buttons,
            ])

        case "g-ax-focus":
            let tables = SR1AX.tables()
            let index = step["table"] as? Int ?? 0
            let status = tables.indices.contains(index) ? SR1AX.setFocused(tables[index]).rawValue : -1
            await pause(pauseMs)
            observe(log, node: "table/\(index)", phase: label, ["ax-status": Int(status), "responder": responder()])

        case "g-select-rows":
            let tables = SR1AX.tables()
            let index = step["table"] as? Int ?? 0
            let requested = step["rows"] as? [Int] ?? []
            var status: Int = -1
            if tables.indices.contains(index) {
                let rows = SR1AX.children(tables[index], "AXRows")
                let chosen = requested.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
                status = Int(SR1AX.setSelectedRows(tables[index], rows: chosen).rawValue)
            }
            await pause(pauseMs)
            observe(log, node: "table/\(index)", phase: label, ["requested": requested, "ax-status": status])

        case "g-range":
            let element = SR1AX.find(identifier: id).flatMap { SR1AX.textElement(in: $0) }
            let location = step["location"] as? Int ?? 0
            let length = step["length"] as? Int ?? 0
            let status = element.map { Int(SR1AX.setSelectedRange($0, location: location, length: length).rawValue) } ?? -1
            await pause(pauseMs)
            let readBack = element.flatMap { SR1AX.selectedRange($0) }.map { "(\($0.location),\($0.length))" } ?? "nil"
            observe(log, node: id, phase: label, ["found": element != nil, "ax-status": status, "read-back": readBack])

        case "g-tables":
            let tables = SR1AX.tables()
            observe(log, node: "tables", phase: label, [
                "count": tables.count,
                "roles": tables.map { SR1AX.role($0) ?? "nil" },
                "identifiers": tables.map { SR1AX.identifier($0) ?? "" },
            ])

        case "g-model":
            modelWrite(model, step: step, label: label)
            await pause(pauseMs)

        case "g-dump":
            dump(model, label: label)

        case "g-wait":
            await pause(pauseMs)

        default:
            return false
        }
        return true
    }

    // MARK: Helpers

    static func activate() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        appWindow()?.makeKeyAndOrderFront(nil)
    }

    static func appWindow() -> NSWindow? {
        NSApplication.shared.windows.first { $0.title.hasPrefix("SR0 Fixture") }
    }

    static func responder() -> String {
        guard let first = NSApplication.shared.keyWindow?.firstResponder else { return "nil" }
        return String(describing: type(of: first))
    }

    static func pause(_ ms: Int) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }

    static func observe(_ log: EventLog, node: String, phase: String, _ payload: [String: Any]) {
        var fields = payload
        fields["phase"] = phase
        log.emit("observe", node: node, payload: fields)
    }

    static func snapshot(_ log: EventLog, id: String, label: String) {
        let element = SR1AX.find(identifier: id)
        var fields: [String: Any] = ["found": element != nil, "identifier": id]
        if let element {
            fields["role"] = SR1AX.role(element) ?? "nil"
            fields["title"] = SR1AX.string(element, "AXTitle") ?? ""
            fields["description"] = SR1AX.string(element, "AXDescription") ?? ""
            fields["value"] = SR1AX.describe(SR1AX.copy(element, "AXValue"))
            fields["enabled"] = SR1AX.describe(SR1AX.copy(element, "AXEnabled"))
            fields["focused"] = SR1AX.describe(SR1AX.copy(element, "AXFocused"))
            fields["actions"] = SR1AX.actions(element).sorted()
            if let text = SR1AX.textElement(in: element) {
                fields["text-role"] = SR1AX.role(text) ?? "nil"
                fields["text-value"] = SR1AX.describe(SR1AX.copy(text, "AXValue"))
                fields["text-selection"] = SR1AX.selectedRange(text).map { "(\($0.location),\($0.length))" } ?? "nil"
            }
        }
        observe(log, node: id, phase: label, fields)
    }

    static func tableSnapshot(_ log: EventLog, index: Int, label: String) {
        let tables = SR1AX.tables()
        guard tables.indices.contains(index) else {
            observe(log, node: "table/\(index)", phase: label, ["found": false, "count": tables.count])
            return
        }
        let table = tables[index]
        observe(log, node: "table/\(index)", phase: label, [
            "found": true,
            "role": SR1AX.role(table) ?? "nil",
            "identifier": SR1AX.identifier(table) ?? "",
            "rows": SR1AX.children(table, "AXRows").count,
            "selected": SR1AX.selectedRowIndices(table),
        ])
    }

    /// Titles (or descriptions) of every AXButton under a sheet, in tree order.
    static func buttonTitles(in root: AXUIElement) -> [String] {
        var titles: [String] = []
        var stack = [root]
        var visited = 0
        while let element = stack.popLast(), visited < 500 {
            visited += 1
            if SR1AX.role(element) == "AXButton" {
                let title = SR1AX.string(element, "AXTitle") ?? ""
                titles.append(title.isEmpty ? (SR1AX.string(element, "AXDescription") ?? "") : title)
            }
            stack.append(contentsOf: SR1AX.children(element).reversed())
        }
        return titles
    }

    static func keyFromName(_ name: String) -> SR1AX.Key? {
        switch name {
        case "space": .space
        case "return": .returnKey
        case "delete": .delete
        case "escape": .escape
        case "a": .a
        case "e": .e
        case "l": .l
        case "s": .s
        default: nil
        }
    }

    static func flagsFrom(_ names: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for name in names {
            switch name {
            case "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option": flags.insert(.maskAlternate)
            default: break
            }
        }
        return flags
    }

    static func modelWrite(_ model: SR1Model, step: [String: Any], label: String) {
        let op = step["op"] as? String ?? ""
        switch op {
        case "toggle":
            model.toggleOn = step["value"] as? Bool ?? false
        case "note":
            model.note = step["text"] as? String ?? ""
        case "single":
            let row = step["row"] as? Int ?? 0
            model.singleSelection = row == 0 ? nil : SR1Model.sid(3, row)
        case "multi":
            let rows = step["rows"] as? [Int] ?? []
            model.multiSelection = Set(rows.map { SR1Model.sid(3, $0) })
        case "g4-select":
            model.g4Selection = SR1Model.sid(4, step["row"] as? Int ?? 1)
        case "g4-delete":
            model.deleteG4(IndexSet(step["offsets"] as? [Int] ?? []), source: "model-command")
        case "alert":
            model.alertShown = step["value"] as? Bool ?? false
        case "dialog":
            model.dialogShown = step["value"] as? Bool ?? false
        case "locked":
            model.controlsLocked = step["value"] as? Bool ?? false
        default:
            observe(model.log, node: "model", phase: label, ["unknown-op": op])
            return
        }
        observe(model.log, node: "model", phase: label, ["op": op])
    }

    static func dump(_ model: SR1Model, label: String) {
        let singleSlot = model.singleSelection.flatMap { id in model.g3Rows.firstIndex { $0.id == id } }
        let multiSlots = model.g3Rows.enumerated().filter { model.multiSelection.contains($0.element.id) }.map(\.offset)
        observe(model.log, node: "model", phase: label, [
            "toggle": model.toggleOn,
            "note": model.note,
            "single": singleSlot ?? -1,
            "multi": multiSlots,
            "g4-count": model.g4Items.count,
            "alert": model.alertShown,
            "dialog": model.dialogShown,
            "locked": model.controlsLocked,
        ])
    }
}
#endif
