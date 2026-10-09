import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
struct Check {
    let name: String
    let pass: Bool
    let detail: String
    /// Observations record a platform outcome (e.g. preserved vs fresh @State). They never fail the verdict.
    var observe: Bool = false
}

/// Read-only view over the recorded events and the final model.
@MainActor
struct Evidence {
    let model: RowModel
    let events: [[String: Any]]

    func payload(_ index: Int) -> [String: Any] {
        events[index]["payload"] as? [String: Any] ?? [:]
    }

    func tag(_ index: Int) -> String {
        let p = payload(index)
        return (p["phase"] as? String) ?? (p["op"] as? String) ?? ""
    }

    func find(kind: String? = nil, node: String? = nil, tag wanted: String? = nil, step: String? = nil) -> [Int] {
        events.indices.filter { index in
            let event = events[index]
            if let kind, (event["kind"] as? String) != kind { return false }
            if let node, (event["node_id"] as? String) != node { return false }
            if let wanted, tag(index) != wanted { return false }
            if let step, (event["step"] as? String) != step { return false }
            return true
        }
    }

    func trail(_ node: String) -> [String] {
        find(node: node).map { "\(events[$0]["kind"] as? String ?? "")/\(tag($0))" }
    }

    func text(_ id: UUID) -> String? { model.rows.first { $0.id == id }?.text }

    func index(_ id: UUID) -> Int? { model.index(of: id) }

    func lastFocus() -> String? {
        find(kind: "focus").last.flatMap { payload($0)["focused"] as? String }
    }

    func lastLocal(_ id: UUID) -> Int? {
        find(node: id.uuidString, tag: "local-edit").last.flatMap { payload($0)["local"] as? Int }
    }

    func check(_ name: String, _ pass: Bool, _ detail: String = "") -> Check {
        Check(name: name, pass: pass, detail: detail)
    }

    func observe(_ name: String, _ value: String, _ detail: String = "") -> Check {
        Check(name: name, pass: true, detail: "value=\(value) \(detail)", observe: true)
    }

    /// Milliseconds between two recorded event indices, from the in-process monotonic clock.
    func millis(_ from: Int, _ to: Int) -> Int {
        let a = events[from]["mono_ns"] as? UInt64 ?? 0
        let b = events[to]["mono_ns"] as? UInt64 ?? 0
        return Int((b &- a) / 1_000_000)
    }
}

@MainActor
struct SelfTestCase {
    let steps: [[String: Any]]
    let checks: (Evidence) -> [Check]
}

func isSubsequence<T: Equatable>(_ needle: [T], of haystack: [T]) -> Bool {
    var position = 0
    for value in haystack where position < needle.count && value == needle[position] {
        position += 1
    }
    return position == needle.count
}

/// Scripted programmatic equivalents of the slice stimuli. Keyboard and pointer input are out-of-process.
@MainActor
func makeCase(fixture: FixtureConfig.Fixture, reduced: Bool, f3GapMs: Int = 0) -> SelfTestCase {
    let fixtureNumber = fixture.number
    func rid(_ slot: Int) -> UUID { RowModel.rowID(fixture: fixtureNumber, slot: slot) }

    switch fixture {
    case .F1:
        return SelfTestCase(steps: [
            ["step": "focus", "row": 5],
            ["step": "type", "row": 5, "text": "abc"],
            ["step": "release", "key": "insert-above", "value": 0],
            ["step": "type", "row": 5, "text": "d"],
        ], checks: { e in
            let row5 = rid(5)
            return [
                e.check("insert-committed-at-top", e.model.rows.first?.text == "Engine 0",
                        "top=\(e.model.rows.first?.text ?? "nil")"),
                e.check("row5-text", e.text(row5) == "Row 5abcd", "text=\(e.text(row5) ?? "nil")"),
                e.check("row5-identity-index-shift", e.index(row5) == 5, "index=\(e.index(row5) ?? -1)"),
                e.check("row5-not-torn-down",
                        e.find(node: row5.uuidString, tag: "disappear").isEmpty
                            && e.find(node: row5.uuidString, tag: "appear").count == 1),
                e.check("row5-state-continuous", e.lastLocal(row5) == 2, "local=\(e.lastLocal(row5) ?? -1)"),
                e.check("focus-stays-row5", e.lastFocus() == row5.uuidString, "focus=\(e.lastFocus() ?? "nil")"),
                e.check("no-rejected-effects", e.find(kind: "effect", tag: "rejected").isEmpty),
            ]
        })

    case .F2:
        let expected = [1, 2, 4, 5, 6, 7, 8, 3, 9, 10].map { rid($0) }
        return SelfTestCase(steps: [
            ["step": "focus", "row": 3],
            ["step": "type", "row": 3, "text": "-x"],
            ["step": "move", "from": 2, "to": 8],
        ], checks: { e in
            let row3 = rid(3)
            return [
                e.check("row3-moved-to-index7", e.index(row3) == 7, "index=\(e.index(row3) ?? -1)"),
                e.check("row3-text-preserved", e.text(row3) == "Row 3-x", "text=\(e.text(row3) ?? "nil")"),
                e.check("order-matches-move", e.model.rows.map(\.id) == expected),
                e.check("focus-stays-row3", e.lastFocus() == row3.uuidString, "focus=\(e.lastFocus() ?? "nil")"),
                e.check("no-teardown-on-move", e.find(node: row3.uuidString, tag: "disappear").isEmpty),
                e.check("local-state-kept", e.lastLocal(row3) == 1, "local=\(e.lastLocal(row3) ?? -1)"),
            ]
        })

    case .F3:
        // Removal, optional settle gap (the driver's `ms` is a minimum wait), then reinsertion of the same UUID.
        return SelfTestCase(steps: [
            ["step": "focus", "row": 4],
            ["step": "type", "row": 4, "text": "x"],
            ["step": "remove-row", "row": 4, "ms": f3GapMs],
            ["step": "insert-row", "row": 4, "text": "Row 4", "index": 3],
            ["step": "release-all"],
        ], checks: { e in
            let row4 = rid(4).uuidString
            let removal = e.find(kind: "state", node: row4, tag: "remove").first
            let disappear = e.find(node: row4, tag: "disappear").first
            let cancel = e.find(node: row4, tag: "task-cancel").first
            let appears = e.find(node: row4, tag: "appear")
            let secondLocal = appears.count == 2 ? e.payload(appears[1])["local"] as? Int : nil
            let rejected = e.find(kind: "effect", node: row4, tag: "rejected")
            let commits = e.find(kind: "effect", node: row4, tag: "commit")
            let commitGen = commits.first.flatMap { e.payload($0)["gen"] as? Int }
            let rejectedReason = rejected.first.flatMap { e.payload($0)["reason"] as? String }
            let outcome: String
            switch secondLocal {
            case 0?: outcome = "fresh"
            case 1?: outcome = "preserved"
            case let n?: outcome = "other(\(n))"
            case nil: outcome = "no-reinsert"
            }
            let gap = (removal != nil && appears.count == 2) ? e.millis(removal!, appears[1]) : -1
            let taskStarts = e.find(node: row4, tag: "task-start").count
            return [
                e.check("teardown-disappear-before-cancel",
                        disappear != nil && cancel != nil && disappear! < cancel!,
                        "disappear=\(disappear.map(String.init) ?? "nil") cancel=\(cancel.map(String.init) ?? "nil")"),
                e.check("reinserted-index-and-text", e.index(rid(4)) == 3 && e.text(rid(4)) == "Row 4",
                        "index=\(e.index(rid(4)) ?? -1) text=\(e.text(rid(4)) ?? "nil")"),
                e.check("task-restarted-for-reinsert", taskStarts == 2, "task-starts=\(taskStarts)"),
                e.check("old-result-rejected", rejected.count == 1 && rejectedReason == "task-cancelled",
                        "rejected=\(rejected.count) reason=\(rejectedReason ?? "nil")"),
                e.check("only-new-instance-commits", commits.count == 1 && commitGen == 1,
                        "commits=\(commits.count) gen=\(commitGen.map(String.init) ?? "nil")"),
                e.observe("reinsert-local-state", outcome,
                          "second-local=\(secondLocal.map(String.init) ?? "nil") appears=\(appears.count) gap-ms=\(gap)"),
                e.observe("reinsert-focus", e.lastFocus() == row4 ? "focused" : "not-focused",
                          "focus=\(e.lastFocus() ?? "nil")"),
            ]
        })

    case .F4:
        return SelfTestCase(steps: [
            ["step": "remove-row", "row": 2],
            ["step": "release", "key": "load-\(rid(2).uuidString)-g0", "value": 42],
            ["step": "release", "key": "load-\(rid(1).uuidString)-g0", "value": 7],
        ], checks: { e in
            let row2 = rid(2).uuidString
            let cancelIndex = e.find(node: row2, tag: "task-cancel").first
            let releaseIndex = e.find(node: row2, tag: "engine-release").first
            let rejected = e.find(kind: "effect", node: row2, tag: "rejected")
            let reason = rejected.first.flatMap { e.payload($0)["reason"] as? String }
            let trail = e.trail(row2)
            return [
                e.check("cancel-delivered-before-late-result",
                        cancelIndex != nil && releaseIndex != nil && cancelIndex! < releaseIndex!),
                e.check("stale-result-rejected", rejected.count == 1 && reason == "task-cancelled",
                        "rejected=\(rejected.count) reason=\(reason ?? "nil")"),
                e.check("result-not-committed", e.model.committedNotes[rid(2)] == nil
                        && e.find(kind: "effect", node: row2, tag: "commit").isEmpty),
                e.check("cleanup-observed-after-rejection", trail.last == "effect/cleanup", "trail-last=\(trail.last ?? "nil")"),
                e.check("control-row-commits", e.model.committedNotes[rid(1)] == 7,
                        "row1-note=\(e.model.committedNotes[rid(1)].map(String.init) ?? "nil")"),
                e.check("row-removed", e.model.rows.count == 9, "count=\(e.model.rows.count)"),
            ]
        })

    case .F5:
        return SelfTestCase(steps: [
            ["step": "resize", "width": 720, "height": 560, "ms": 300],
            ["step": "resize", "width": 360, "height": 560, "ms": 300],
            ["step": "release", "key": "update-1", "value": 0],
            ["step": "release", "key": "insert-1", "value": 0],
            ["step": "resize", "width": 720, "height": 560, "ms": 300],
        ], checks: { e in
            let layouts = e.find(node: "layout")
            let modes = layouts.compactMap { e.payload($0)["mode"] as? String }
            let real = layouts.filter { (e.payload($0)["degenerate"] as? Bool) != true }
            let degenerate = layouts.filter { (e.payload($0)["degenerate"] as? Bool) == true }
            let offender = real.first { (e.payload($0)["contained"] as? Bool) != true }
            let offenderDetail = offender.map { i -> String in
                let p = e.payload(i)
                return "event=\(i) width=\(p["width"] ?? "?") bounds=[\(p["bounds"] ?? "?")] outside=\(p["outside"] ?? [])"
            } ?? ""
            return [
                e.check("wide-narrow-wide-transitions", isSubsequence(["wide", "narrow", "wide"], of: modes),
                        "modes=\(modes.joined(separator: ">"))"),
                e.check("all-placements-contained", !real.isEmpty && offender == nil,
                        "placements=\(real.count) offender: \(offenderDetail)"),
                e.observe("zero-width-placement-passes", "\(degenerate.count)",
                          "contained-flags=\(degenerate.map { (e.payload($0)["contained"] as? Bool) == true ? "T" : "F" }.joined())"),
                e.check("async-update-committed", e.text(rid(1)) == "Row 1 updated 0", "text=\(e.text(rid(1)) ?? "nil")"),
                e.check("async-insert-committed", e.model.rows.count == 11 && e.model.rows.first?.text == "Engine 0",
                        "count=\(e.model.rows.count)"),
                e.check("final-layout-wide", modes.last == "wide", "last=\(modes.last ?? "nil")"),
            ]
        })

    case .F6:
        // Both inserts in one turn: the only variant that produced an overlapping (interrupted) pair in probing.
        return SelfTestCase(steps: [
            ["step": "burst-insert", "ms": 1500],
        ], checks: { e in
            let starts = e.find(node: "animation", tag: "start")
            let completes = e.find(node: "animation", tag: "complete")
            let policy = e.find(node: "animation", tag: "policy").last.flatMap { e.payload($0)["enabled"] as? Bool }
            let overlap: Bool = {
                guard starts.count == 2, let firstComplete = completes.first else { return false }
                return starts[1] < firstComplete
            }()
            let finalFirst = e.model.rows.first?.id
            let finalSecond = e.model.rows.count > 1 ? e.model.rows[1].id : nil
            if reduced {
                return [
                    e.check("reduced-policy-disables-animation", policy == false, "enabled=\(policy.map(String.init(describing:)) ?? "nil")"),
                    e.check("reduced-no-animation-transactions", starts.isEmpty && completes.isEmpty,
                            "starts=\(starts.count) completes=\(completes.count)"),
                    e.check("reduced-final-order", finalFirst == rid(201) && finalSecond == rid(200)),
                ]
            }
            return [
                e.check("normal-policy-enabled", policy == true, "enabled=\(policy.map(String.init(describing:)) ?? "nil")"),
                e.check("two-animations-started", starts.count == 2, "starts=\(starts.count)"),
                e.check("interruption-recorded", overlap, "second-start-before-first-complete=\(overlap) completes=\(completes.count)"),
                e.check("both-animations-complete", completes.count == 2, "completes=\(completes.count)"),
                e.check("final-order", finalFirst == rid(201) && finalSecond == rid(200) && e.model.rows.count == 12,
                        "count=\(e.model.rows.count)"),
            ]
        })

    case .F7:
        return SelfTestCase(steps: [
            ["step": "focus", "row": 2],
            ["step": "type", "row": 2, "text": "ka"],
            ["step": "release", "key": "insert-above", "value": 0],
            ["step": "type", "row": 2, "text": "na"],
        ], checks: { e in
            let row2 = rid(2)
            return [
                e.check("committed-text-on-original-identity", e.text(row2) == "Row 2kana", "text=\(e.text(row2) ?? "nil")"),
                e.check("identity-index-shift", e.index(row2) == 2, "index=\(e.index(row2) ?? -1)"),
                e.check("focus-stays-on-identity", e.lastFocus() == row2.uuidString, "focus=\(e.lastFocus() ?? "nil")"),
                e.check("insert-committed", e.model.rows.first?.text == "Engine 0"),
                e.check("no-teardown", e.find(node: row2.uuidString, tag: "disappear").isEmpty),
            ]
        })

    case .F8:
        return SelfTestCase(steps: [
            ["step": "toolbar-insert"],
            ["step": "release", "key": "insert-toolbar-1", "value": 0],
            ["step": "set-text", "row": 3, "text": "AX value"],
            ["step": "focus", "row": 3],
            ["step": "remove-row", "row": 6],
        ], checks: { e in
            let row3 = rid(3)
            let inserted = rid(101)
            let insertedAppear = e.find(node: inserted.uuidString, tag: "appear").first
            let insertedControls = insertedAppear.flatMap { e.payload($0)["controls"] as? [String] } ?? []
            let row3Appear = e.find(node: row3.uuidString, tag: "appear").first
            let row3Controls = row3Appear.flatMap { e.payload($0)["controls"] as? [String] } ?? []
            return [
                e.check("toolbar-activation-commits",
                        e.find(node: "toolbar/insert", tag: "commit").count == 1
                            && e.find(node: "toolbar/insert", tag: "task-start").count == 1),
                e.check("inserted-row-exposes-controls", insertedControls.contains("field") && insertedControls.contains("delete"),
                        "controls=\(insertedControls.joined(separator: ","))"),
                e.check("row3-delete-action-registered", row3Controls.contains("delete")),
                e.check("set-value-applied", e.text(row3) == "AX value", "text=\(e.text(row3) ?? "nil")"),
                e.check("focus-moved-to-row3", e.lastFocus() == row3.uuidString, "focus=\(e.lastFocus() ?? "nil")"),
                e.check("delete-removes-row6", e.index(rid(6)) == nil && e.model.rows.count == 10,
                        "count=\(e.model.rows.count)"),
                e.check("delete-observed-disappear", e.find(node: rid(6).uuidString, tag: "disappear").count == 1),
            ]
        })

    case .F9:
        return SelfTestCase(steps: [
            ["step": "close-window", "ms": 300],
            ["step": "release-all"],
        ], checks: { e in
            let cancelsAtClose = e.find(tag: "task-cancel", step: "close-window").count
            let commitsAfterClose = e.find(tag: "commit", step: "release-all").count
            let rejectedAfterClose = e.find(tag: "rejected", step: "release-all").count
            let cleanupAfterClose = e.find(tag: "cleanup", step: "release-all").count
            let released = e.find(node: "tree", tag: "released").count
            return [
                e.check("tasks-cancelled-at-close", cancelsAtClose == 11, "cancels=\(cancelsAtClose) (10 rows + screen sync)"),
                e.check("no-commit-after-close", commitsAfterClose == 0, "commits=\(commitsAfterClose)"),
                e.check("late-results-rejected", rejectedAfterClose == 11, "rejected=\(rejectedAfterClose)"),
                e.check("cleanup-after-close", cleanupAfterClose == 11, "cleanup=\(cleanupAfterClose)"),
                // CONTRACT §3 F9: tree release is a Windows runtime requirement, not a Mac oracle assertion.
                e.observe("tree-released", released >= 1 ? "released" : "retained", "tree-released-events=\(released)"),
            ]
        })
    }
}

@MainActor
final class SelfTestRunner {
    let session: FixtureSession

    init(session: FixtureSession) {
        self.session = session
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 28) {
            print("SELFTEST watchdog-timeout")
            fflush(stdout)
            exit(3)
        }
        Task { await run() }
    }

    private func run() async {
        let fixture = session.config.fixture.rawValue
        let testCase = makeCase(fixture: session.config.fixture, reduced: session.config.reducedMotion,
                                f3GapMs: session.config.f3GapMs)
        let driver = session.driver
        await driver.settle(minimumMs: 300)
        for step in testCase.steps {
            await driver.perform(step)
        }
        if session.config.fixture == .F9 {
            // Closing the window does not end the process in self-test mode; wait (bounded) for the tree release event.
            for _ in 0..<60 {
                if session.log.events().contains(where: { ($0["node_id"] as? String) == "tree" }) { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            await driver.settle()
        }
        let evidence = Evidence(model: session.model, events: session.log.events())
        var checks = testCase.checks(evidence)
        if session.config.fixture == .F9 {
            // Diagnostic for the tree-release assertion: is the closed window object still retained by AppKit?
            let titled = NSApplication.shared.windows.filter { $0.title.hasPrefix("SR0 Fixture") }
            checks.append(Check(name: "window-objects-after-close", pass: true,
                                detail: "titled=\(titled.count) visible=\(titled.filter(\.isVisible).count) released-flag=\(titled.map { $0.isReleasedWhenClosed })",
                                observe: true))
        }
        var failures = 0
        var asserted = 0
        for check in checks {
            if check.observe {
                print("OBSERVE \(fixture) \(check.name): \(check.detail)")
                continue
            }
            asserted += 1
            if !check.pass { failures += 1 }
            print("ASSERT \(fixture) \(check.name): \(check.pass ? "PASS" : "FAIL") \(check.detail)")
        }
        let verdict = failures == 0 ? "PASS" : "FAIL"
        let label = session.config.f3VariantName.map { "\(fixture) variant=\($0)" }
            ?? "\(fixture)\(session.config.reducedMotion ? "-reduced" : "")"
        print("SELFTEST \(label): \(verdict) (\(asserted - failures)/\(asserted))")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}
