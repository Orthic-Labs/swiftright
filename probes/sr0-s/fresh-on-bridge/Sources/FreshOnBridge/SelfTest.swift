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

    private func events(kind: String? = nil, node: String? = nil, phase wanted: String? = nil) -> [[String: Any]] {
        log.events().filter { e in
            if let kind, e["kind"] as? String != kind { return false }
            if let node, e["node_id"] as? String != node { return false }
            if let wanted, phase(e) != wanted { return false }
            return true
        }
    }

    private func count(kind: String? = nil, node: String? = nil, phase wanted: String? = nil) -> Int {
        events(kind: kind, node: node, phase: wanted).count
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
                .act("release insert-above") {
                    self.commitMark = self.backend.commitCount
                    self.engine.release("insert-above", value: 0)
                },
                .wait("insert committed") { self.model.rows.first?.text == "Engine 0" && self.backend.commitCount > self.commitMark },
                .wait("typed na") { self.text(self.rid(2)) == "Row 2kana" },
                .awaitClose,
            ]

        case .F8:
            return [
                .wait("toolbar insert pending") { self.pendingHas("insert-toolbar-1") },
                .act("release toolbar insert") { self.engine.release("insert-toolbar-1", value: 0) },
                .wait("toolbar row committed") { self.model.rows.first?.text == "Toolbar 0" },
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
                     "windows-focused=\(focusedAfter) mac-oracle-focused=\(oracleFocus) (runtime FocusState tag for a removed row is not cleared)"),
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
            let starts = count(kind: "lifecycle", node: "animation", phase: "start")
            let policyEvents = events(kind: "lifecycle", node: "animation", phase: "policy")
            let policy = policyEvents.last.flatMap { payload($0)["enabled"] as? Bool }
            let order = model.rows.count > 1 ? (model.rows[0].id, model.rows[1].id) : nil
            if options.reducedVariant {
                checks += [
                    pass("reduced-policy-disables-animation", policy == false, "enabled=\(policy.map(String.init(describing:)) ?? "nil") (variant flag path)"),
                    blocked("system-reduce-motion-read", "SwiftRightRuntime exposes no accessibilityReduceMotion environment key; the OS setting cannot be read"),
                    pass("reduced-no-animation-transactions", starts == 0 && backend.animationTagCommits == 0,
                         "starts=\(starts) commit-tags=\(backend.animationTagCommits)"),
                    pass("reduced-final-order", order?.0 == rid(201) && order?.1 == rid(200), "count=\(model.rows.count)"),
                ]
            } else {
                let overlapBlocked = "runtime records animation tags per commit only; no interpolation, duration or completion callback"
                checks += [
                    blocked("normal-policy-enabled", "system reduce-motion cannot be read (no accessibilityReduceMotion key); policy enabled=\(policy.map(String.init(describing:)) ?? "nil") from the variant path only"),
                    pass("two-animations-started", starts == 2, "transaction starts=\(starts) (model-opened withAnimation calls)"),
                    observe("animation-tag-commits", "\(backend.animationTagCommits) commit records carried an animation tag"),
                    blocked("interruption-recorded", overlapBlocked),
                    blocked("both-animations-complete", "no withAnimation completion criteria or completion callback in the runtime"),
                    pass("final-order", order?.0 == rid(201) && order?.1 == rid(200) && model.rows.count == 12, "count=\(model.rows.count)"),
                ]
            }

        case .F7:
            let r2 = rid(2)
            checks += [
                pass("committed-text-on-original-identity", text(r2) == "Row 2kana", "text=\(text(r2) ?? "nil")"),
                pass("identity-index-shift", index(r2) == 2, "index=\(index(r2).map(String.init) ?? "nil")"),
                pass("focus-stays-on-identity", lastFocusID() == r2, "focus=\(lastFocusID()?.uuidString ?? "nil")"),
                pass("insert-committed", model.rows.first?.text == "Engine 0"),
                pass("no-teardown", count(node: r2.uuidString, phase: "disappear") == 0),
                blocked("ime-composition", "runtime TextField has no marked-text (composition) state; replaceAndMark is a plain replace in the bridge"),
                pass("text-store-keystrokes", backend.keystrokes == ["k", "a", "n", "a"], "replace calls=\(backend.keystrokes.joined(separator: ","))"),
            ]

        case .F8:
            let r3 = rid(3)
            let r6 = rid(6)
            let inserted = model.rows.first.map(\.id)
            let insertedControls = inserted.map { appearControls($0) } ?? []
            checks += [
                pass("toolbar-activation-commits",
                     count(node: "toolbar/insert", phase: "commit") == 1 && count(node: "toolbar/insert", phase: "task-start") == 1,
                     "commit=\(count(node: "toolbar/insert", phase: "commit")) start=\(count(node: "toolbar/insert", phase: "task-start"))"),
                blocked("toolbar-task-restarts-per-request", "runtime task has no id parameter (.task(id:)); the button action starts the effect instead"),
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
            let treeReleased = events(node: "tree", phase: "released").count >= 1
            let releasedAtGraphDrop = backend.releasedAfterGraphDrop
            let cleared = backend.clearedViewBindings
            let cancels = count(kind: "lifecycle", phase: "task-cancel")
            checks += [
                blocked("tasks-cancelled-at-close", "no runtime unmount or teardown API; row and screen tasks are not cancelled by window close (task-cancel events recorded in the run: \(cancels))"),
                observe("commits-after-close", "commits at close=\(closeCommitMark) now=\(backend.commitCount); the graph is dropped at close, so no flush can commit afterwards"),
                blocked("late-results-rejected", "window_closed is the last host callback; the MainActor executor is not pumped afterwards, so late engine results cannot resume"),
                blocked("cleanup-after-close", "same as late-results-rejected"),
                observe("tree-released-at-graph-drop", "\(releasedAtGraphDrop) (probe deinit right after the graph is dropped, before the host clears its model bindings)"),
                observe("view-bindings-cleared-by-host", "\(cleared) model-held view references (focus binding, text-input handlers) dropped at close"),
                pass("tree-released", treeReleased,
                     "tree-released-events=\(events(node: "tree", phase: "released").count) after host close (probe deinit; pending row tasks keep nodes alive)"),
                blocked("renderer-live-nodes-zero", "swr_stats has no live-node counter"),
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
    }
}
