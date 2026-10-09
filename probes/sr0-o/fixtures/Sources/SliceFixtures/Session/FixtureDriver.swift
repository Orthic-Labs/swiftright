import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

/// Model-level stimuli: fake engine releases, structural edits, window resize and close.
/// Keyboard and pointer input is not performed here; the out-of-process recorder owns it.
/// `focus`, `type` and `set-text` are programmatic equivalents used only by the self-test.
@MainActor
final class FixtureDriver {
    let model: RowModel
    let engine: FakeEngine
    let log: EventLog
    let sr1: SR1Model

    init(model: RowModel, engine: FakeEngine, log: EventLog, sr1: SR1Model) {
        self.model = model
        self.engine = engine
        self.log = log
        self.sr1 = sr1
    }

    func handleLine(_ line: String) async {
        guard let data = line.data(using: .utf8),
              let step = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            log.emit("lifecycle", node: "driver", payload: ["phase": "rejected-line"])
            return
        }
        await perform(step)
    }

    func perform(_ step: [String: Any]) async {
        let name = step["step"] as? String ?? "unnamed"
        log.setStep(name)
        switch name {
        case "focus":
            if let id = resolveID(step) { model.requestFocus(id) }
        case "type":
            if let id = resolveID(step), let text = step["text"] as? String,
               let current = model.rows.first(where: { $0.id == id })?.text {
                model.setText(id, current + text)
            }
        case "set-text":
            if let id = resolveID(step), let text = step["text"] as? String {
                model.setText(id, text)
            }
        case "release":
            engine.release(step["key"] as? String ?? "", value: step["value"] as? Int ?? 0)
        case "release-all":
            engine.releaseAll()
        case "remove-row":
            if let id = resolveID(step) { model.removeRow(id) }
        case "insert-row":
            if let id = resolveID(step), let text = step["text"] as? String {
                model.insertRow(Row(id: id, text: text), at: step["index"] as? Int ?? 0)
            }
        case "move":
            if let from = step["from"] as? Int, let to = step["to"] as? Int {
                model.moveRow(from: IndexSet(integer: from), to: to)
            }
        case "toolbar-insert":
            model.requestInsert()
        case "burst-insert":
            model.burstInsert()
        case "burst-a":
            model.burstInsertOne(0)
        case "burst-b":
            model.burstInsertOne(1)
        case "resize":
            resizeWindow(width: step["width"] as? Int ?? 480, height: step["height"] as? Int ?? 560)
        case "close-window":
            appWindow()?.close()
        case "quit":
            exit(0)
        case "snapshot", "settle":
            break
        default:
            #if os(macOS)
            if await SR1Steps.perform(name, step, model: sr1) {
                break
            }
            #endif
            log.emit("lifecycle", node: "driver", payload: ["phase": "unknown-step", "name": name])
        }
        await settle(minimumMs: step["ms"] as? Int ?? 0)
        model.snapshot(name)
    }

    private func resolveID(_ step: [String: Any]) -> UUID? {
        if let text = step["id"] as? String { return UUID(uuidString: text) }
        if let slot = step["row"] as? Int { return model.rowID(slot) }
        return nil
    }

    private func appWindow() -> NSWindow? {
        NSApplication.shared.windows.first { $0.title.hasPrefix("SR0 Fixture") && $0.isVisible }
    }

    private func resizeWindow(width: Int, height: Int) {
        log.emit("lifecycle", node: "window", payload: ["phase": "resize-requested", "width": width, "height": height])
        appWindow()?.setContentSize(NSSize(width: width, height: height))
    }

    /// Waits for the optional minimum, then until the event count is stable for 150 ms.
    func settle(minimumMs: Int = 0) async {
        if minimumMs > 0 {
            try? await Task.sleep(for: .milliseconds(minimumMs))
        }
        var last = -1
        var stable = 0
        for _ in 0..<80 {
            try? await Task.sleep(for: .milliseconds(50))
            let count = log.count
            if count == last {
                stable += 1
                if stable >= 3 { return }
            } else {
                last = count
                stable = 0
            }
        }
    }
}
