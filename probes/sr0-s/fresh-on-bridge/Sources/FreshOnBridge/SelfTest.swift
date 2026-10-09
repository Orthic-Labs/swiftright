import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// Scripted self-test for one fixture (F1-F9 and variants). Mirrors probes/sr0-o/fixtures/Sources/SliceFixtures/
// Session/SelfTest.swift: the same steps where the runtime allows, the same check names, and the same
// oracle outcomes (recorded on Mac) asserted against Windows.
//
// Stage rule: each step advances only on observed state (bridge events, model, commit counts, engine keys),
// never on a timer, except the explicit `pause` steps that mirror the Mac driver's `ms` gap.
// Input (AX/UIA focus, VK keys, invoke, SetValue, window close) comes from scripts/drive-fixture.ps1.

enum CheckStatus: String {
    case pass = "PASS"
    case fail = "FAIL"
    case blocked = "BLOCKED"
    case observe = "OBSERVE"
}

struct Check {
    let name: String
    let status: CheckStatus
    let detail: String
}

enum Step {
    case wait(String, () -> Bool)
    case act(String, () -> Void)
    case pause(String, Int)
    case awaitClose
}

@MainActor
final class SelfTest {
    private let bridge: Bridge
    private let backend: BridgeBackend
    private let model: RowModel
    private let log: EventLog
    private let engine: FakeEngine
    private let options: FixtureOptions
    private let started = Date()
    private var steps: [Step] = []
    private var cursor = 0
    private var stepStarted = Date()
    private var stageLog: [String] = []
    private var reachedClose = false
    private var closeWaitStarted = Date()
    private var commitMark = 0
    private var instanceBefore: Int?
    private var instanceAfter: Int?
    private var closeCommitMark = 0
    private(set) var finished = false
    private(set) var exitCode: Int32 = 1
    var requestQuit: (() -> Void)?

    init(bridge: Bridge, backend: BridgeBackend, model: RowModel, log: EventLog, engine: FakeEngine, options: FixtureOptions) {
        self.bridge = bridge
        self.backend = backend
        self.model = model
        self.log = log
        self.engine = engine
        self.options = options
        log.emit("lifecycle", node: "selftest", payload: ["phase": "start", "fixture": options.label])
        steps = buildScript()
    }

    // MARK: F7 composition (programmatic, through the bridge text-store API)

    /// Text state of row 2 right after one programmatic text-store call (or after the insert).
    private struct ImeSnapshot {
        let committed: String
        let display: String
        let marked: UTF16Range?
        let viaStore: UTF16Span?
    }
    private var imeSnapshots: [String: ImeSnapshot] = [:]

    /// One composition step through `Bridge.textStore`, the object the renderer calls, on the UI thread.
    private func compose(_ text: String, key: String) {
        guard let node = backend.textFieldBridgeID(rid(2)) else { return }
        _ = bridge.textStore?.replaceAndMark(node: node, range: nil, text: Array(text.utf16), newSelection: nil)
        snapshot(key)
    }

    private func unmarkComposition() {
        guard let node = backend.textFieldBridgeID(rid(2)) else { return }
        _ = bridge.textStore?.unmark(node: node)
        snapshot("unmark")
    }

    private func snapshot(_ key: String) {
        guard let state = backend.textState(for: rid(2)) else { return }
        let node = backend.textFieldBridgeID(rid(2))
        let viaStore = node.flatMap { bridge.textStore?.markedRange(node: $0) }
        imeSnapshots[key] = ImeSnapshot(committed: state.committed, display: state.display,
                                        marked: state.markedRange, viaStore: viaStore)
    }

    // MARK: Evidence helpers (read-only over the event log)

    private func rid(_ slot: Int) -> UUID { model.rowID(slot) }

    private func text(_ id: UUID) -> String? { model.row(id)?.text }

    private func index(_ id: UUID) -> Int? { model.index(of: id) }

    private func payload(_ e: [String: Any]) -> [String: Any] { e["payload"] as? [String: Any] ?? [:] }

    private func phase(_ e: [String: Any]) -> String {
        let p = payload(e)
        return (p["phase"] as? String) ?? (p["op"] as? String) ?? ""
    }

    private func seq(_ e: [String: Any]) -> Int { e["seq"] as? Int ?? -1 }

    /// Evidence is read as of window close by default: the host teardown at close (disappear, task-cancel) is
    /// a separate phase and is read with `includeTeardown`.
    private func events(kind: String? = nil, node: String? = nil, phase wanted: String? = nil,
                        includeTeardown: Bool = false) -> [[String: Any]] {
        let all = log.events()
        let closedSeq = includeTeardown ? nil : all.first {
            ($0["node_id"] as? String) == "window" && phase($0) == "closed"
        }.map { seq($0) }
        return all.filter { e in
            if let closedSeq, seq(e) > closedSeq { return false }
            if let kind, e["kind"] as? String != kind { return false }
            if let node, e["node_id"] as? String != node { return false }
            if let wanted, phase(e) != wanted { return false }
            return true
        }
    }

    private func count(kind: String? = nil, node: String? = nil, phase wanted: String? = nil,
                       includeTeardown: Bool = false) -> Int {
        events(kind: kind, node: node, phase: wanted, includeTeardown: includeTeardown).count
    }

    private func lastFocusID() -> UUID? {
        guard let last = events(kind: "focus").last, let s = payload(last)["focused"] as? String else { return nil }
        return UUID(uuidString: s)
    }

    private func lastLocal(_ id: UUID) -> Int? {
        events(node: id.uuidString, phase: "local-edit").last.flatMap { payload($0)["local"] as? Int }
    }

    private func appearLocals(_ id: UUID) -> [Int] {
        events(node: id.uuidString, phase: "appear").compactMap { payload($0)["local"] as? Int }
    }

    private func appearControls(_ id: UUID) -> [String] {
        let last = events(node: id.uuidString, phase: "appear").last
        return (last.flatMap { payload($0)["controls"] as? [String] }) ?? []
    }

    private func layoutModes() -> [(seq: Int, mode: String)] {
        events(kind: "state", node: "layout").compactMap { e in
            guard let mode = payload(e)["mode"] as? String else { return nil }
            return (seq(e), mode)
        }
    }

    private func layoutEvents() -> [[String: Any]] {
        events(kind: "state", node: "layout")
    }

    private func millis(_ from: [String: Any], _ to: [String: Any]) -> Int {
        let a = from["mono_ns"] as? UInt64 ?? 0
        let b = to["mono_ns"] as? UInt64 ?? 0
        return Int((b &- a) / 1_000_000)
    }

    private func isSubsequence(_ needle: [String], of haystack: [String]) -> Bool {
        var position = 0
        for value in haystack where position < needle.count && value == needle[position] {
            position += 1
        }
        return position == needle.count
    }

    /// Diagnostic: prints the first resolved nodes (kind and id) when an instance lookup misses.
    private func dumpTree(_ label: String) {
        guard let root = backend.graph?.snapshot() else {
            print("DEBUG-TREE \(label): no snapshot")
            return
        }
        var lines: [String] = []
        func walk(_ node: ResolvedNode, _ depth: Int) {
            if lines.count < 80 { lines.append(String(repeating: " ", count: depth) + "\(node.kind) \(node.id)") }
            for child in node.children { walk(child, depth + 1) }
        }
        walk(root, 0)
        print("DEBUG-TREE \(label)")
        for line in lines { print(line) }
        fflush(stdout)
    }

    private func pendingHas(_ key: String) -> Bool { engine.pendingKeys.contains(key) }

    private func pendingCount() -> Int { engine.pendingKeys.count }

    // MARK: Script

    private func buildScript() -> [Step] {
        let f = options.fixture
        switch f {
        case .F1:
            return [
                .wait("row5 focused by AX") { self.lastFocusID() == self.rid(5) },
                .wait("typed abc") { self.text(self.rid(5)) == "Row 5abc" },
                .wait("insert-above pending") { self.pendingHas("insert-above") },
                .act("release insert-above") {
                    self.commitMark = self.backend.commitCount
                    self.instanceBefore = self.backend.instanceNumber(kind: "EditableRowView", row: self.rid(5))
                    if self.instanceBefore == nil { self.dumpTree("release-insert-above") }
                    self.engine.release("insert-above", value: 0)
                },
                .wait("insert committed") {
                    self.model.rows.first?.text == "Engine 0" && self.backend.commitCount > self.commitMark
                },
                .wait("typed d") { self.text(self.rid(5)) == "Row 5abcd" },
                .act("record row5 instance") {
                    self.instanceAfter = self.backend.instanceNumber(kind: "EditableRowView", row: self.rid(5))
                },
                .awaitClose,
            ]

        case .F2:
            return [
                .wait("row3 focused by AX") { self.lastFocusID() == self.rid(3) },
                .wait("typed -x") { self.text(self.rid(3)) == "Row 3-x" },
                .act("move offset 2 to 8") { self.model.moveRow(from: IndexSet(integer: 2), to: 8) },
                .wait("order matches move") { self.model.rows.map(\.id) == [1, 2, 4, 5, 6, 7, 8, 3, 9, 10].map { self.rid($0) } },
                .awaitClose,
            ]

        case .F3:
            let gap = options.f3GapMs
            return [
                .wait("row4 focused by AX") { self.lastFocusID() == self.rid(4) },
                .wait("typed x") { self.text(self.rid(4)) == "Row 4x" },
                .act("remove row4") {
                    self.commitMark = self.backend.commitCount
                    self.model.removeRow(self.rid(4))
                },
                // The Mac driver settles between steps; here the removal must be committed (teardown runs)
                // before the reinsert, or remove+insert in one turn is seen as no change at all.
                .wait("removal committed") { self.backend.commitCount > self.commitMark },
                .pause("settle gap", gap),
                .act("reinsert row4 at index 3") {
                    self.model.insertRow(Row(id: self.rid(4), text: "Row 4"), at: 3, tag: "reinsert")
                },
                .wait("reinserted task restarted") { self.count(kind: "lifecycle", node: self.rid(4).uuidString, phase: "task-start") == 2 },
                .act("release all") { self.engine.releaseAll() },
                .awaitClose,
            ]

        case .F4:
            return [
                .wait("row loads pending") { self.pendingHas("load-\(self.rid(1).uuidString)-g0") && self.pendingHas("load-\(self.rid(2).uuidString)-g0") },
                .act("remove row2") { self.model.removeRow(self.rid(2)) },
                .wait("row2 task cancelled") { self.count(kind: "lifecycle", node: self.rid(2).uuidString, phase: "task-cancel") >= 1 },
                .act("release row2 late") { self.engine.release("load-\(self.rid(2).uuidString)-g0", value: 42) },
                .act("release row1") { self.engine.release("load-\(self.rid(1).uuidString)-g0", value: 7) },
                .wait("row1 committed, row2 rejected") {
                    self.model.committedNotes[self.rid(1)] == 7 && self.count(kind: "effect", node: self.rid(2).uuidString, phase: "rejected") >= 1
                },
                .awaitClose,
            ]

        case .F5:
            return [
                .wait("narrow layout observed") { self.layoutModes().contains { $0.mode == "narrow" } },
                .act("release update-1") { self.engine.release("update-1", value: 0) },
                .act("release insert-1") { self.engine.release("insert-1", value: 0) },
                .wait("async update and insert committed") {
                    self.text(self.rid(1)) == "Row 1 updated 0" && self.model.rows.count == 11 && self.model.rows.first?.text == "Engine 0"
                },
                .wait("wide layout after narrow") {
                    guard let n = self.layoutModes().firstIndex(where: { $0.mode == "narrow" }) else { return false }
                    return self.layoutModes()[n...].contains { $0.mode == "wide" }
                },
                .awaitClose,
            ]

        case .F6:
            return [
                .wait("motion policy recorded") { self.count(kind: "lifecycle", node: "animation", phase: "policy") >= 1 },
                .act("burst insert (same turn)") { self.model.burstInsert() },
                .pause("animation window", 1500),
                .awaitClose,
            ]

        case .F7:
            return [
                .wait("insert-above pending") { self.pendingHas("insert-above") },
                .wait("row2 focused by AX") { self.lastFocusID() == self.rid(2) },
                .wait("typed ka") { self.text(self.rid(2)) == "Row 2ka" },
                .act("compose n (marked, uncommitted)") { self.compose("n", key: "mark1") },
                .wait("composition visible in runtime") { self.backend.textState(for: self.rid(2))?.composition == "n" },
                .act("release insert-above (composition open)") {
                    self.commitMark = self.backend.commitCount
                    self.engine.release("insert-above", value: 0)
                },
                .wait("insert committed") { self.model.rows.first?.text == "Engine 0" && self.backend.commitCount > self.commitMark },
                .act("record composition across insert") { self.snapshot("insert") },
                .act("compose na (replaces marked n)") { self.compose("na", key: "mark2") },
                .act("unmark (commit composition)") { self.unmarkComposition() },
                .wait("composition committed to model") { self.text(self.rid(2)) == "Row 2kana" },
                .awaitClose,
            ]

        case .F8:
            return [
                .wait("toolbar insert pending") { self.pendingHas("insert-toolbar-1") },
                .act("release toolbar insert") { self.engine.release("insert-toolbar-1", value: 0) },
                .wait("toolbar row committed") { self.model.rows.first?.text == "Toolbar 0" },
                .act("restart: press 2") { self.backend.pressInsertButton() },
                .wait("insert-toolbar-2 pending") { self.pendingHas("insert-toolbar-2") },
                .act("restart: press 3 (replaces run 2)") { self.backend.pressInsertButton() },
                .wait("insert-toolbar-3 pending") { self.pendingHas("insert-toolbar-3") },
                .act("release cancelled run 2") { self.engine.release("insert-toolbar-2", value: 0) },
                .wait("stale result rejected") { self.count(kind: "effect", node: "toolbar/insert", phase: "rejected") >= 1 },
                .wait("AX value applied") { self.text(self.rid(3)) == "AX value" },
                .wait("row3 focused by AX") { self.lastFocusID() == self.rid(3) },
                .wait("row6 deleted by AX") { self.index(self.rid(6)) == nil && self.model.rows.count == 10 },
                .awaitClose,
            ]

        case .F9:
            if options.f9NoTasks {
                return [.awaitClose]
            }
            return [
                .wait("row tasks and screen task pending") { self.pendingCount() >= 11 },
                .awaitClose,
            ]
        }
    }

    // MARK: Advancement

    /// Called after each bridge event and each display tick.
    func advance() {
        guard !finished else { return }
        while cursor < steps.count {
            switch steps[cursor] {
            case .act(let name, let body):
                body()
                enter(name)
            case .wait(let name, let condition):
                if condition() {
                    enter(name)
                } else {
                    if Date().timeIntervalSince(stepStarted) > 40 {
                        finish(reason: "timeout waiting for '\(name)'")
                    }
                    return
                }
            case .pause(let name, let ms):
                if Date().timeIntervalSince(stepStarted) * 1000 >= Double(ms) {
                    enter(name)
                } else {
                    return
                }
            case .awaitClose:
                if !reachedClose {
                    reachedClose = true
                    closeWaitStarted = Date()
                    stageLog.append("awaiting-driver-close")
                }
                return
            }
        }
    }

    private func enter(_ name: String) {
        cursor += 1
        stepStarted = Date()
        stageLog.append("\(name)@\(String(format: "%.2f", Date().timeIntervalSince(started)))s")
        log.emit("lifecycle", node: "selftest", payload: ["phase": "stage", "name": name])
    }

    func tick() {
        guard !finished else { return }
        advance()
        if Date().timeIntervalSince(started) > 150 {
            finish(reason: "watchdog: 150 s at step \(cursor)")
        } else if reachedClose, Date().timeIntervalSince(closeWaitStarted) > 60 {
            finish(reason: "driver did not close the window within 60 s")
        }
    }

    /// Host window-closed callback (the renderer shuts down after it returns).
    func windowClosed() {
        closeCommitMark = backend.commitCount
        if options.fixture == .F9 {
            // Cancelled tasks still wait on their engine continuation, which keeps the tree alive. Resume them,
            // then judge release after the post-close pump has run the unwinding tasks (ABI rev 0.5).
            engine.releaseAll()
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.finish(reason: "window-closed") } }
                }
            }
            return
        }
        finish(reason: "window-closed")
    }

    // MARK: Checks

    private func pass(_ name: String, _ ok: Bool, _ detail: String = "") -> Check {
        Check(name: name, status: ok ? .pass : .fail, detail: detail)
    }

    private func blocked(_ name: String, _ reason: String) -> Check {
        Check(name: name, status: .blocked, detail: reason)
    }

    private func observe(_ name: String, _ detail: String) -> Check {
        Check(name: name, status: .observe, detail: detail)
    }

    private func bridgeChecks() -> [Check] {
        let st = bridge.stats()
        return [
            pass("renderer-no-violations", st.thread_violations == 0 && st.host_panics == 0,
                 "thread_violations=\(st.thread_violations) host_panics=\(st.host_panics)"),
            pass("commits-accepted", backend.commitErrors.isEmpty && backend.commitCount >= 1,
                 "commits=\(backend.commitCount) errors=\(backend.commitErrors.count)"),
            pass("no-measure-or-draw-failures", backend.measurerFailures() == 0 && backend.drawFailures == 0,
                 "measure=\(backend.measurerFailures()) draw=\(backend.drawFailures) \(backend.measurerError())\(backend.lastDrawError)"),
        ]
    }

    private func buildChecks() -> [Check] {
        var checks: [Check] = [
            pass("script-completed", reachedClose, "stages=\(stageLog.joined(separator: " | "))"),
        ]
        switch options.fixture {
        case .F1:
            let r5 = rid(5)
            let local = lastLocal(r5)
            checks += [
                pass("insert-committed-at-top", model.rows.first?.text == "Engine 0", "top=\(model.rows.first?.text ?? "nil")"),
                pass("row5-text", text(r5) == "Row 5abcd", "text=\(text(r5) ?? "nil")"),
                pass("row5-identity-index-shift", index(r5) == 5, "index=\(index(r5).map(String.init) ?? "nil")"),
                pass("row5-not-torn-down", count(node: r5.uuidString, phase: "disappear") == 0 && count(node: r5.uuidString, phase: "appear") == 1,
                     "appear=\(count(node: r5.uuidString, phase: "appear")) disappear=\(count(node: r5.uuidString, phase: "disappear"))"),
                pass("row5-node-instance-kept", instanceBefore != nil && instanceBefore == instanceAfter,
                     "instance before=\(instanceBefore.map(String.init) ?? "nil") after=\(instanceAfter.map(String.init) ?? "nil")"),
                pass("row5-state-continuous", local == 4,
                     "local=\(local.map(String.init) ?? "nil") (keystrokes a,b,c,d; Mac oracle recorded local=2 for two programmatic steps; a reset would read 1)"),
                pass("focus-stays-row5", lastFocusID() == r5, "focus=\(lastFocusID()?.uuidString ?? "nil")"),
                pass("no-rejected-effects", count(kind: "effect", phase: "rejected") == 0),
                pass("caret-follows-typing", backend.caretOffset(r5) == UInt32("Row 5abcd".utf16.count),
                     "caret=\(backend.caretOffset(r5).map(String.init) ?? "nil")"),
                pass("text-store-keystrokes", backend.keystrokes == ["a", "b", "c", "d"], "replace calls=\(backend.keystrokes.joined(separator: ","))"),
                pass("ax-focus-delivered", backend.axFocusEvents >= 1, "ax-focus=\(backend.axFocusEvents)"),
            ]

        case .F2:
            let r3 = rid(3)
            let expected = [1, 2, 4, 5, 6, 7, 8, 3, 9, 10].map { rid($0) }
            let local = lastLocal(r3)
            checks += [
                pass("row3-moved-to-index7", index(r3) == 7, "index=\(index(r3).map(String.init) ?? "nil")"),
                pass("row3-text-preserved", text(r3) == "Row 3-x", "text=\(text(r3) ?? "nil")"),
                pass("order-matches-move", model.rows.map(\.id) == expected),
                pass("focus-stays-row3", lastFocusID() == r3, "focus=\(lastFocusID()?.uuidString ?? "nil")"),
                pass("no-teardown-on-move", count(node: r3.uuidString, phase: "disappear") == 0),
                pass("local-state-kept", local == 2,
                     "local=\(local.map(String.init) ?? "nil") (keystrokes '-','x'; Mac oracle recorded local=1 for one programmatic edit; a reset would read 0)"),
                pass("text-store-keystrokes", backend.keystrokes == ["-", "x"], "replace calls=\(backend.keystrokes.joined(separator: ","))"),
            ]

        case .F3:
            let r4 = rid(4)
            let disappear = events(node: r4.uuidString, phase: "disappear").first
            let cancel = events(node: r4.uuidString, phase: "task-cancel").first
            let rejected = events(kind: "effect", node: r4.uuidString, phase: "rejected")
            let reason = rejected.first.flatMap { payload($0)["reason"] as? String }
            let commits = events(kind: "effect", node: r4.uuidString, phase: "commit")
            let commitGen = commits.first.flatMap { payload($0)["gen"] as? Int }
            let taskStarts = count(node: r4.uuidString, phase: "task-start")
            let appears = appearLocals(r4)
            let secondLocal = appears.count == 2 ? appears[1] : nil
            let windowsState = secondLocal == 1 ? "preserved" : (secondLocal == 0 ? "fresh" : "other")
            let focusedAfter = backend.focusedRow == r4
            // Mac oracle (probes/sr0-o/fixtures/RESULT.md, F3 oracle table): List preserves, VStack and LazyVStack reset.
            let oracleState = options.f3Container == .list ? "preserved" : "fresh"
            let oracleFocus = options.f3Container == .list
            let gapMs = (events(node: r4.uuidString, phase: "disappear").first != nil && appears.count == 2)
                ? millis(events(node: r4.uuidString, phase: "disappear").first!, events(node: r4.uuidString, phase: "appear")[1]) : -1
            checks += [
                pass("teardown-disappear-before-cancel",
                     disappear != nil && cancel != nil && seq(disappear!) < seq(cancel!),
                     "disappear=\(disappear.map { String(seq($0)) } ?? "nil") cancel=\(cancel.map { String(seq($0)) } ?? "nil")"),
                pass("reinserted-index-and-text", index(r4) == 3 && text(r4) == "Row 4",
                     "index=\(index(r4).map(String.init) ?? "nil") text=\(text(r4) ?? "nil")"),
                pass("task-restarted-for-reinsert", taskStarts == 2, "task-starts=\(taskStarts)"),
                pass("old-result-rejected", rejected.count == 1 && reason == "task-cancelled",
                     "rejected=\(rejected.count) reason=\(reason ?? "nil")"),
                pass("only-new-instance-commits", commits.count == 1 && commitGen == 1,
                     "commits=\(commits.count) gen=\(commitGen.map(String.init) ?? "nil")"),
                pass("reinsert-state-matches-mac-oracle", windowsState == oracleState,
                     "windows=\(windowsState) (second-local=\(secondLocal.map(String.init) ?? "nil")) mac-oracle=\(oracleState) container=\(options.f3Container.rawValue)"),
                pass("reinsert-focus-matches-mac-oracle", focusedAfter == oracleFocus,
                     "windows-focused=\(focusedAfter) mac-oracle-focused=\(oracleFocus) (runtime clears focus on removal; List restores it on reinsert)"),
                observe("reinsert-gap-ms", "\(gapMs) (configured \(options.f3GapMs))"),
            ]

        case .F4:
            let r2 = rid(2)
            let cancelIndex = events(node: r2.uuidString, phase: "task-cancel").first
            let releaseIndex = events(node: r2.uuidString, phase: "engine-release").first
            let rejected = events(kind: "effect", node: r2.uuidString, phase: "rejected")
            let reason = rejected.first.flatMap { payload($0)["reason"] as? String }
            let trail = log.events().filter { ($0["node_id"] as? String) == r2.uuidString }.map { "\($0["kind"] as? String ?? "")/\(phase($0))" }
            checks += [
                pass("cancel-delivered-before-late-result",
                     cancelIndex != nil && releaseIndex != nil && seq(cancelIndex!) < seq(releaseIndex!)),
                pass("stale-result-rejected", rejected.count == 1 && reason == "task-cancelled",
                     "rejected=\(rejected.count) reason=\(reason ?? "nil")"),
                pass("result-not-committed", model.committedNotes[r2] == nil && events(kind: "effect", node: r2.uuidString, phase: "commit").isEmpty),
                pass("cleanup-observed-after-rejection", trail.last == "effect/cleanup", "trail-last=\(trail.last ?? "nil")"),
                pass("control-row-commits", model.committedNotes[rid(1)] == 7,
                     "row1-note=\(model.committedNotes[rid(1)].map(String.init) ?? "nil")"),
                pass("row-removed", model.rows.count == 9, "count=\(model.rows.count)"),
            ]

        case .F5:
            let modes = layoutModes().map(\.mode)
            let real = layoutEvents().filter { (payload($0)["degenerate"] as? Bool) != true }
            let degenerate = layoutEvents().filter { (payload($0)["degenerate"] as? Bool) == true }
            let offender = real.first { (payload($0)["contained"] as? Bool) != true }
            let offenderDetail = offender.map { e -> String in
                let p = payload(e)
                return "seq=\(seq(e)) width=\(p["width"] ?? "?") bounds=[\(p["bounds"] ?? "?")] outside=\(p["outside"] ?? [])"
            } ?? ""
            checks += [
                pass("wide-narrow-wide-transitions", isSubsequence(["wide", "narrow", "wide"], of: modes), "modes=\(modes.joined(separator: ">"))"),
                pass("all-placements-contained", !real.isEmpty && offender == nil,
                     "placements=\(real.count) offender: \(offenderDetail)"),
                observe("zero-width-placement-passes", "\(degenerate.count) degenerate placements"),
                pass("async-update-committed", text(rid(1)) == "Row 1 updated 0", "text=\(text(rid(1)) ?? "nil")"),
                pass("async-insert-committed", model.rows.count == 11 && model.rows.first?.text == "Engine 0", "count=\(model.rows.count)"),
                pass("final-layout-wide", modes.last == "wide", "last=\(modes.last ?? "nil")"),
                pass("resize-delivered-to-runtime", backend.metricsEvents >= 2, "windowMetrics events=\(backend.metricsEvents)"),
            ]

        case .F6:
            let starts = events(kind: "lifecycle", node: "animation", phase: "start")
            let completes = events(kind: "lifecycle", node: "animation", phase: "complete")
            let policy = events(kind: "lifecycle", node: "animation", phase: "policy").last.flatMap { payload($0)["enabled"] as? Bool }
            let order = model.rows.count > 1 ? (model.rows[0].id, model.rows[1].id) : nil
            let effective = backend.reduceMotionEffective
            let osState = backend.osReduceMotion.map { $0 ? "reduce-on" : "reduce-off" } ?? "unavailable"
            checks += [
                pass("os-reduce-motion-read", backend.osReduceMotion != nil,
                     "os=\(osState) effective=\(effective) source=\(backend.reduceMotionSource)"),
            ]
            if options.reducedVariant {
                checks += [
                    pass("reduced-policy-disables-animation", policy == false, "enabled=\(policy.map(String.init(describing:)) ?? "nil") (variant flag)"),
                    pass("reduced-no-animation-transactions", starts.isEmpty && completes.isEmpty && backend.animationTagCommits == 0,
                         "starts=\(starts.count) completes=\(completes.count) commit-tags=\(backend.animationTagCommits)"),
                    pass("reduced-final-order", order?.0 == rid(201) && order?.1 == rid(200), "count=\(model.rows.count)"),
                ]
            } else {
                // Mac oracle rule: the second start comes before the first completion (the burst overlaps).
                let overlap = starts.count == 2 && completes.count >= 1 && seq(starts[1]) < seq(completes[0])
                checks += [
                    pass("normal-policy-enabled", policy == true, "enabled=\(policy.map(String.init(describing:)) ?? "nil")"),
                    pass("two-animations-started", starts.count == 2, "starts=\(starts.count)"),
                    pass("interruption-recorded", overlap,
                         "second-start seq=\(starts.count > 1 ? seq(starts[1]) : -1) first-complete seq=\(completes.first.map { seq($0) } ?? -1)"),
                    pass("both-animations-complete", completes.count == 2, "completes=\(completes.count)"),
                    pass("final-order", order?.0 == rid(201) && order?.1 == rid(200) && model.rows.count == 12, "count=\(model.rows.count)"),
                    pass("env-reduce-controls-motion", effective ? backend.interpolatedCommits == 0 : backend.interpolatedCommits >= 3,
                         "effective-reduce=\(effective) fade-frame commits=\(backend.interpolatedCommits) (snap: 0; animate: >=3)"),
                    pass("frames-driven-by-display-tick", effective || backend.tickCommits >= 3,
                         "tick-commits=\(backend.tickCommits) ticks=\(backend.tickCount)"),
                ]
            }

        case .F7:
            let r2 = rid(2)
            let mark1 = imeSnapshots["mark1"]
            let mark2 = imeSnapshots["mark2"]
            let atInsert = imeSnapshots["insert"]
            let unmarked = imeSnapshots["unmark"]
            let m1 = UTF16Range(location: 7, length: 1)
            let m2 = UTF16Range(location: 7, length: 2)
            checks += [
                pass("committed-text-on-original-identity", text(r2) == "Row 2kana", "text=\(text(r2) ?? "nil")"),
                pass("identity-index-shift", index(r2) == 2, "index=\(index(r2).map(String.init) ?? "nil")"),
                pass("focus-stays-on-identity", lastFocusID() == r2, "focus=\(lastFocusID()?.uuidString ?? "nil")"),
                pass("insert-committed", model.rows.first?.text == "Engine 0"),
                pass("no-teardown", count(node: r2.uuidString, phase: "disappear") == 0),
                pass("text-store-keystrokes", backend.keystrokes == ["k", "a"], "replace calls=\(backend.keystrokes.joined(separator: ","))"),
                pass("composition-uncommitted-in-model", mark1?.committed == "Row 2ka" && mark2?.committed == "Row 2ka",
                     "committed during composition=\(mark1?.committed ?? "nil") / \(mark2?.committed ?? "nil")"),
                pass("composition-marked-range", mark1?.display == "Row 2kan" && mark1?.marked == m1,
                     "display=\(mark1?.display ?? "nil") marked=\(mark1?.marked.map { "\($0.location),\($0.length)" } ?? "nil")"),
                pass("marked-range-via-text-store", mark1?.viaStore == UTF16Span(start: 7, end: 8),
                     "store markedRange=\(mark1?.viaStore.map { "\($0.start)-\($0.end)" } ?? "nil")"),
                pass("composition-replaced-in-place", mark2?.display == "Row 2kana" && mark2?.marked == m2,
                     "display=\(mark2?.display ?? "nil") marked=\(mark2?.marked.map { "\($0.location),\($0.length)" } ?? "nil")"),
                pass("composition-survives-insert-above", atInsert?.display == "Row 2kan" && atInsert?.marked == m1,
                     "display=\(atInsert?.display ?? "nil") marked=\(atInsert?.marked.map { "\($0.location),\($0.length)" } ?? "nil")"),
                pass("composition-committed-on-unmark", unmarked?.committed == "Row 2kana" && unmarked?.marked == nil,
                     "committed=\(unmarked?.committed ?? "nil") marked=\(unmarked?.marked == nil ? "none" : "still")"),
                pass("ime-calls-recorded", backend.imeCalls == ["mark:n", "mark:na", "unmark"], "calls=\(backend.imeCalls.joined(separator: ","))"),
                pass("marked-text-in-commit-records", backend.imeMarkedCommits >= 2, "commits with marked text=\(backend.imeMarkedCommits)"),
            ]

        case .F8:
            let r3 = rid(3)
            let r6 = rid(6)
            let inserted = model.rows.first.map(\.id)
            let insertedControls = inserted.map { appearControls($0) } ?? []
            let starts = count(kind: "lifecycle", node: "toolbar/insert", phase: "task-start")
            let cancels = count(kind: "lifecycle", node: "toolbar/insert", phase: "task-cancel")
            let staleRejected = events(kind: "effect", node: "toolbar/insert", phase: "rejected")
                .filter { (payload($0)["reason"] as? String) == "task-cancelled" }.count
            checks += [
                pass("toolbar-activation-commits", count(node: "toolbar/insert", phase: "commit") == 1,
                     "commit=\(count(node: "toolbar/insert", phase: "commit"))"),
                pass("toolbar-task-restarts-per-request", starts == 3 && cancels == 1 && staleRejected == 1,
                     "task-starts=\(starts) (presses 1,2,3) cancels=\(cancels) stale-rejected=\(staleRejected)"),
                pass("inserted-row-exposes-controls", insertedControls.contains("field") && insertedControls.contains("delete"),
                     "controls=\(insertedControls.joined(separator: ","))"),
                pass("row3-delete-action-registered", appearControls(r3).contains("delete"), "controls=\(appearControls(r3).joined(separator: ","))"),
                pass("set-value-applied", text(r3) == "AX value", "text=\(text(r3) ?? "nil")"),
                pass("focus-moved-to-row3", lastFocusID() == r3, "focus=\(lastFocusID()?.uuidString ?? "nil")"),
                pass("delete-removes-row6", index(r6) == nil && model.rows.count == 10, "count=\(model.rows.count)"),
                pass("delete-observed-disappear", count(node: r6.uuidString, phase: "disappear") == 1),
                pass("row-identifiers-committed",
                     backend.committedIdentifiers.contains("row/\(r3.uuidString)/field")
                        && backend.committedIdentifiers.contains("row/\(r3.uuidString)/delete")
                        && backend.committedIdentifiers.contains("toolbar/insert"),
                     "row3 field/delete and toolbar/insert identifiers committed (ABI rev 0.4); count=\(backend.committedIdentifiers.count)"),
            ]

        case .F9:
            let cancels = count(kind: "lifecycle", phase: "task-cancel", includeTeardown: true)
            let expectedCancels = options.f9NoTasks ? 0 : 11
            checks += [
                pass("tasks-cancelled-at-teardown", cancels >= expectedCancels,
                     "task-cancel events=\(cancels) expected>=\(expectedCancels) (row tasks and screen task, cancelled by runtime teardown)"),
                observe("commits-after-close", "commits at close=\(closeCommitMark) now=\(backend.commitCount) (the graph is closed by teardown: no later commit)"),
                blocked("late-results-rejected", "the bridge drains the main queue only inside renderer callbacks; window_closed is the last callback, so a resumed engine continuation cannot run after close (bridge gap: post-close pump)"),
                blocked("cleanup-after-close", "same as late-results-rejected"),
                pass("tree-released", events(node: "tree", phase: "released", includeTeardown: true).count >= 1,
                     "probe deinit ran after runtime teardown and engine release, within the post-close pump (tree-released events=\(events(node: "tree", phase: "released", includeTeardown: true).count))"),
                observe("teardown-commit", "not sent: the renderer sets SHUTDOWN before window_closed, so any commit then returns SWR_E_SHUTDOWN (errors=\(backend.commitErrors.count)); the renderer frees its own tree at close"),
                pass("bridge-ledger-zero-after-teardown", backend.ledgerAfterTeardown == 0,
                     "host ledger of renderer nodes after teardown=\(backend.ledgerAfterTeardown) (host drops its node state; the renderer frees the tree itself)"),
                blocked("renderer-live-nodes-zero", "swr_stats has no live-node counter (ABI rev 0.4); only the host ledger above counts nodes"),
                observe("view-bindings-cleared-by-host", "\(backend.clearedViewBindings) model-held view references dropped after teardown"),
            ]
        }
        checks += bridgeChecks()
        return checks
    }

    // MARK: Finish

    private func finish(reason: String) {
        guard !finished else { return }
        finished = true
        let checks = buildChecks()
        print("SELFTEST-STAGES \(options.label): \(stageLog.joined(separator: " | ")) end-reason=\(reason)")
        for check in checks {
            switch check.status {
            case .observe:
                print("OBSERVE \(options.label) \(check.name): \(check.detail)")
            default:
                print("ASSERT \(options.label) \(check.name): \(check.status.rawValue) \(check.detail)")
            }
        }
        let asserted = checks.filter { $0.status == .pass || $0.status == .fail }
        let passCount = asserted.filter { $0.status == .pass }.count
        let failCount = asserted.count - passCount
        let blockedCount = checks.filter { $0.status == .blocked }.count
        let verdict: String
        if failCount > 0 {
            verdict = "FAIL"
            exitCode = 1
        } else if blockedCount > 0 {
            verdict = "BLOCKED"
            exitCode = 3
        } else {
            verdict = "PASS"
            exitCode = 0
        }
        print("SELFTEST \(options.label): \(verdict) (\(passCount)/\(asserted.count) asserted; blocked=\(blockedCount); end=\(reason))")
        fflush(stdout)
        // Ends swr_run. Needed after a window close too: the renderer loop does not return on its own.
        requestQuit?()
        // Ends the post-close pump at once (ABI rev 0.5); E_STATE before the window closed, ignored.
        try? bridge.shutdownComplete()
    }
}
