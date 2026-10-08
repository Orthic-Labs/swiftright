import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// Scripted F1 self-test. The Mac fixture's steps (focus row 5, type "abc", release insert-above,
// type "d") become: AX focus on row 5, VK "a" "b" "c" from the driver, AX invoke of "Insert above",
// the fake engine release (in process, as the Mac `release` step), VK "d" from the driver.
// Each stage advances only on observed state (bridge events, commits, model), never on a timer.

@MainActor
final class SelfTest {
    struct Check {
        let name: String
        let ok: Bool
        let detail: String
    }

    private let bridge: Bridge
    private let backend: BridgeBackend
    private let model: RowModel
    private let log: EventLog
    private let engine: FakeEngine
    private let started = Date()
    private let timeoutSeconds: TimeInterval = 90
    private let row5: UUID

    private(set) var stage = 0
    private var ticks = 0
    private var gatherUntilTick = Int.max
    private(set) var finished = false
    private(set) var passed = false
    private var focusBeforeInsert: UInt64?
    private var focusAfterInsert: UInt64?
    private var instanceBefore: Int?
    private var instanceAfter: Int?
    private var commitsAtRelease = 0
    private var checks: [Check] = []
    private var stageLog: [String] = []

    var requestQuit: (() -> Void)?

    init(bridge: Bridge, backend: BridgeBackend, model: RowModel, log: EventLog, engine: FakeEngine) {
        self.bridge = bridge
        self.backend = backend
        self.model = model
        self.log = log
        self.engine = engine
        self.row5 = model.rowID(5)
        log.emit("lifecycle", node: "selftest", payload: ["phase": "start", "row5": row5.uuidString])
    }

    private func enter(_ next: Int, _ note: String) {
        stage = next
        stageLog.append("\(next):\(note)@\(String(format: "%.2f", Date().timeIntervalSince(started)))s")
        log.emit("lifecycle", node: "selftest", payload: ["phase": "stage", "stage": next, "note": note])
    }

    /// Stage advancement. Called after each bridge event and each tick.
    func advance() {
        guard !finished else { return }
        switch stage {
        case 0:
            if backend.focusedRow == row5 {
                focusBeforeInsert = backend.textFieldBridgeID(row5)
                enter(1, "row5 focused by AX")
            }
        case 1:
            if model.row(row5)?.text == "Row 5abc" {
                enter(2, "typed abc")
            }
        case 2:
            if backend.axInvokes >= 1 {
                instanceBefore = backend.instanceNumber(kind: "EditableRowView", row: row5)
                enter(3, "insert above invoked")
            }
        case 3:
            if engine.pendingKeys.contains("insert-above") {
                commitsAtRelease = backend.commitCount
                engine.release("insert-above", value: 0)
                enter(4, "engine released")
            }
        case 4:
            if model.rows.first?.text == "Engine 0", backend.commitCount > commitsAtRelease {
                instanceAfter = backend.instanceNumber(kind: "EditableRowView", row: row5)
                focusAfterInsert = backend.focusTarget
                enter(5, "insert committed")
            }
        case 5:
            if model.row(row5)?.text == "Row 5abcd" {
                gatherUntilTick = ticks + 240
                enter(6, "typed d; gathering frames")
            }
        default:
            break
        }
    }

    /// Display tick (UI thread). Ends the run once the frame-gathering window has elapsed.
    func tick() {
        guard !finished else { return }
        ticks += 1
        advance()
        if stage == 6, ticks >= gatherUntilTick {
            finish()
        } else if Date().timeIntervalSince(started) > timeoutSeconds {
            checks.append(Check(name: "timeout", ok: false, detail: "stage \(stage) after \(timeoutSeconds)s"))
            finish()
        }
    }

    private func lastLocalEdit(_ id: UUID) -> Int? {
        for event in log.events().reversed() {
            guard event["kind"] as? String == "lifecycle", event["node_id"] as? String == id.uuidString,
                  let payload = event["payload"] as? [String: Any], payload["phase"] as? String == "local-edit"
            else { continue }
            return payload["local"] as? Int
        }
        return nil
    }

    private func add(_ name: String, _ ok: Bool, _ detail: String = "") {
        checks.append(Check(name: name, ok: ok, detail: detail))
    }

    private func finish() {
        finished = true
        let rowText = model.row(row5)?.text
        let index = model.index(of: row5)
        let local = lastLocalEdit(row5)
        let appears = log.count(node: row5.uuidString, phase: "appear")
        let disappears = log.count(node: row5.uuidString, phase: "disappear")
        let rejected = log.count(kind: "effect", phase: "rejected")
        let noWaiter = log.count(kind: "effect", phase: "release-no-waiter")
        let focusedInModel = model.focusBinding.map { $0.wrappedValue } ?? nil

        add("insert-committed-at-top", model.rows.first?.text == "Engine 0",
            "top=\(model.rows.first?.text ?? "nil")")
        add("row5-text", rowText == "Row 5abcd", "text=\(rowText ?? "nil")")
        add("row5-identity-index-shift", index == 5, "index=\(index.map(String.init) ?? "nil")")
        add("row5-not-torn-down", disappears == 0 && appears == 1,
            "appear=\(appears) disappear=\(disappears)")
        add("row5-node-instance-kept", instanceBefore != nil && instanceBefore == instanceAfter,
            "instance before=\(instanceBefore.map(String.init) ?? "nil") after=\(instanceAfter.map(String.init) ?? "nil")")
        add("row5-state-continuous", local == 4,
            "local=\(local.map(String.init) ?? "nil") (edits a,b,c,d since start; a reset would read 1)")
        add("focus-stays-row5",
            focusedInModel == row5 && backend.focusedRow == row5
                && focusBeforeInsert != nil && focusBeforeInsert != 0 && focusAfterInsert == focusBeforeInsert,
            "model=\(focusedInModel?.uuidString ?? "nil") runtime=\(backend.focusedRow?.uuidString ?? "nil") bridge-target before=\(focusBeforeInsert.map(String.init) ?? "nil") after=\(focusAfterInsert.map(String.init) ?? "nil")")
        let caretEnd = backend.caretOffset(row5)
        add("caret-follows-typing", caretEnd == UInt32("Row 5abcd".utf16.count),
            "caret=\(caretEnd.map(String.init) ?? "nil") expected=\("Row 5abcd".utf16.count) (end of text)")
        add("no-rejected-effects", rejected == 0 && noWaiter == 0,
            "rejected=\(rejected) release-no-waiter=\(noWaiter)")
        add("ax-focus-delivered", backend.axFocusEvents >= 1, "ax-focus=\(backend.axFocusEvents)")
        add("ax-invoke-delivered", backend.axInvokes == 1, "ax-invoke=\(backend.axInvokes)")
        add("text-store-keystrokes", backend.keystrokes == ["a", "b", "c", "d"],
            "replace calls=\(backend.keystrokes.joined(separator: ","))")
        add("commits-accepted", backend.commitErrors.isEmpty && backend.commitCount >= 4,
            "commits=\(backend.commitCount) errors=\(backend.commitErrors.count)")
        add("no-measure-or-draw-failures", backend.measurerFailures() == 0 && backend.drawFailures == 0,
            "measure=\(backend.measurerFailures()) draw=\(backend.drawFailures) \(backend.measurerError())\(backend.lastDrawError)")

        let st = bridge.stats()
        add("renderer-no-violations", st.thread_violations == 0 && st.host_panics == 0,
            "thread_violations=\(st.thread_violations) host_panics=\(st.host_panics)")

        print("OBSERVE F1 stages: \(stageLog.joined(separator: " | "))")
        print("OBSERVE F1 ticks=\(ticks) pointer-downs=\(backend.pointerDowns) key-events=\(backend.keyEvents) ax-set-values=\(backend.axSetValues) scale-changes=\(backend.scaleChanges)")
        print("OBSERVE F1 renderer paints=\(st.paints) commits_accepted=\(st.commits_accepted) commits_rejected=\(st.commits_rejected) commits_deferred=\(st.commits_deferred) measure_calls=\(st.measure_calls) cache_hits=\(st.measure_cache_hits) reentry_refused=\(st.reentry_refused) events_pushed=\(st.events_pushed) ime_calls=\(st.ime_calls) ime_busy=\(st.ime_busy_rejected)")
        print("OBSERVE F1 runtime measure_calls=\(backend.measurerCalls()) commits=\(backend.commitCount)")
        for check in checks {
            print("ASSERT F1 \(check.name): \(check.ok ? "PASS" : "FAIL") \(check.detail)")
        }
        let ok = checks.filter(\.ok).count
        passed = ok == checks.count
        print("SELFTEST F1-bridge: \(passed ? "PASS" : "FAIL") (\(ok)/\(checks.count))")
        fflush(stdout)
        requestQuit?()
    }
}
