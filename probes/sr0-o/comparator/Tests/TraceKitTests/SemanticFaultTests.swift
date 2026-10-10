import Foundation
import Testing
@testable import TraceKit

private func fieldPaths(_ r: ComparisonReport) -> [String] {
    r.diffs.map { "\($0.step) \($0.path)" }
}

private func diff(_ r: ComparisonReport, step: String, path: String) -> Diff? {
    r.diffs.first { $0.step == step && $0.path == path }
}

@Suite("Accepted baselines and passing candidates")
struct PassingCandidates {
    @Test func accepted_F1_matches_probe_shape() throws {
        let t = try F1Baseline.accepted()
        let ax = t.observations.first { $0.stepId == "initial" }?.axNodes ?? []
        // Strip rules: no containers left, text fields hang off list-item rows.
        let stripped: Set<String> = ["AXCell", "AXColumn", "AXScrollArea", "AXHostingView", "AXGroup"]
        #expect(ax.allSatisfy { !stripped.contains($0.role) })
        let field = try #require(ax.first { $0.id == IDs.fieldId(IDs.row(5)) })
        #expect(field.value == "Row 5")
        let rowParent = try #require(ax.first { $0.id == field.parent })
        #expect(rowParent.role == "list-item")
        let insert = try #require(ax.first { $0.id == "toolbar/insert" })
        #expect(insert.role == "button")
        #expect(insert.label == "Insert above")          // AXDescription, not AXTitle
        #expect(insert.actions.contains("activate"))     // AXPress
        #expect(ax.contains { $0.role == "list" })       // AXOutline
        #expect(t.observations.count == 5)
    }

    @Test func identical_candidate_passes() throws {
        let a = try F1Baseline.accepted()
        let r = TraceComparator.compare(accepted: a, candidate: a)
        #expect(r.passed, "\(fieldPaths(r))")
        #expect(r.diffs.isEmpty)
    }

    @Test func permuted_unordered_lifecycle_passes() throws {
        let a = try F1Baseline.accepted()
        var b = a
        for i in b.observations.indices { b.observations[i].lifecycle.reverse() }
        #expect(b.observations[0].lifecycle != a.observations[0].lifecycle)
        let r = TraceComparator.compare(accepted: a, candidate: b)
        #expect(r.passed, "\(fieldPaths(r))")
    }

    @Test func timestamps_and_platform_build_do_not_fail() throws {
        let a = try F1Baseline.accepted()
        var b = a
        for i in b.steps.indices { b.steps[i].timestamp = "other-\(i)" }
        b.platform.osBuild = "27.0.2 (ZZZ)"
        let r = TraceComparator.compare(accepted: a, candidate: b)
        #expect(r.passed, "\(fieldPaths(r))")
        #expect(r.notes.count == 1)
    }
}

@Suite("Injected semantic faults must fail with precise diffs")
struct FaultTests {
    /// (a) wrong row identity: after the final "d", focus moves to row 6 and the text lands there.
    @Test func a_wrong_row_identity_fails() throws {
        let a = try F1Baseline.accepted()
        var b = a
        let last = b.observations.count - 1
        precondition(b.observations[last].stepId == "after_type_d")
        b.observations[last].focusedNodeId = IDs.fieldId(IDs.row(6))
        b.observations[last].selection = UTF16Range(location: 6, length: 0)
        b.observations[last].model[IDs.modelKey(IDs.row(5))] = "Row 5abc"
        b.observations[last].model[IDs.modelKey(IDs.row(6))] = "Row 6d"

        let r = TraceComparator.compare(accepted: a, candidate: b)
        #expect(!r.passed)
        #expect(diff(r, step: "after_type_d", path: "focusedNodeId")?.actual == IDs.fieldId(IDs.row(6)))
        #expect(diff(r, step: "after_type_d", path: "model[row/\(IDs.row(5))]")?.actual == "Row 5abc")
        #expect(diff(r, step: "after_type_d", path: "model[row/\(IDs.row(5))]")?.expected == "Row 5abcd")
        #expect(diff(r, step: "after_type_d", path: "model[row/\(IDs.row(6))]")?.expected == "Row 6")
        #expect(diff(r, step: "after_type_d", path: "selection")?.actual == "location=6 length=0")
        print("FAULT a diffs:\n" + r.diffs.map { "  \($0.step) \($0.path): expected \($0.expected), got \($0.actual)" }.joined(separator: "\n"))
    }

    /// (b) stale task commit: completion after cancellation writes into model state and emits an effect.
    @Test func b_stale_task_commit_fails() throws {
        let a = F4SyntheticBaseline.accepted()
        var b = a
        let row5 = IDs.modelKey(IDs.row(5))
        b.observations[2].model[row5] = "async-42"
        b.observations[2].effects = ["commit-task-result \(row5) async-42"]
        b.observations[2].lifecycle = [LifecycleEvent(kind: "taskComplete", node: row5)]

        let r = TraceComparator.compare(accepted: a, candidate: b)
        #expect(!r.passed)
        #expect(diff(r, step: "release_completion", path: "model[\(row5)]")?.expected == "<absent>")
        #expect(diff(r, step: "release_completion", path: "model[\(row5)]")?.actual == "async-42")
        #expect(diff(r, step: "release_completion", path: "effects")?.actual == "commit-task-result \(row5) async-42")
        #expect(diff(r, step: "release_completion", path: "lifecycle.count[taskComplete:\(row5)]")?.actual == "1")
        print("FAULT b diffs:\n" + r.diffs.map { "  \($0.step) \($0.path): expected \($0.expected), got \($0.actual)" }.joined(separator: "\n"))
    }

    /// Declared order violated (partial-order enforcement): cancel is logged before disappear.
    @Test func b2_declared_order_violation_fails() throws {
        let a = F4SyntheticBaseline.accepted()
        var b = a
        b.observations[1].lifecycle.reverse()
        let r = TraceComparator.compare(accepted: a, candidate: b)
        #expect(!r.passed)
        let order = r.diffs.first { $0.path == "lifecycle.order[disappear:row/\(IDs.row(5)) before taskCancel:row/\(IDs.row(5))]" }
        #expect(order != nil, "\(fieldPaths(r))")
        #expect(r.diffs.count == 1)
    }

    /// (c) missing accessibility action: AXPress removed from toolbar/insert.
    @Test func c_missing_activate_action_fails() throws {
        let a = try F1Baseline.accepted()
        let raw = try Fx.rawAX()
        let edited = RawEdit.map(raw) { n in
            guard n.identifier == "toolbar/insert" else { return n }
            var m = n
            m.actions = (m.actions ?? []).filter { $0 != "AXPress" }
            return m
        }
        var b = a
        b.observations[0].axNodes = MacAXNormalizer.normalize(edited)

        let r = TraceComparator.compare(accepted: a, candidate: b)
        #expect(!r.passed)
        let d = diff(r, step: "initial", path: "axNodes.actions[toolbar/insert]")
        #expect(d?.expected.contains("activate") == true)
        #expect(d?.actual.contains("activate") == false)
        #expect(d?.expected.contains("show-menu") == true && d?.actual.contains("show-menu") == true)
        #expect(r.diffs.count == 1)
        print("FAULT c diffs:\n" + r.diffs.map { "  \($0.step) \($0.path): expected \($0.expected), got \($0.actual)" }.joined(separator: "\n"))
    }

    /// (d) extra container not in the strip list: an AXSplitGroup wraps the outline.
    @Test func d_extra_container_fails() throws {
        let a = try F1Baseline.accepted()
        var b = a
        b.observations[0].axNodes = MacAXNormalizer.normalize(RawEdit.wrapOutline(try Fx.rawAX()))

        let r = TraceComparator.compare(accepted: a, candidate: b)
        #expect(!r.passed)
        // The wrapper takes the sibling slot anon:main#0, which the accepted tree holds with another role.
        let extra = r.diffs.filter { $0.actual.contains("AXSplitGroup") }
        #expect(extra.count == 1, "\(fieldPaths(r))")
        #expect(extra.first?.path == "axNodes.role[anon:main#0]")
        #expect(r.diffs.allSatisfy { $0.step == "initial" })
        print("FAULT d: \(r.diffs.count) diffs; extra: \(extra.map { "\($0.path) actual=\($0.actual)" })")
    }

    /// (e) label change: toolbar/insert AXDescription changes; no tolerance without a declared adaptation.
    @Test func e_label_change_fails() throws {
        let a = try F1Baseline.accepted()
        let raw = try Fx.rawAX()
        let edited = RawEdit.map(raw) { n in
            guard n.identifier == "toolbar/insert" else { return n }
            var m = n
            m.label = "Insert below"
            return m
        }
        var b = a
        b.observations[0].axNodes = MacAXNormalizer.normalize(edited)

        let r = TraceComparator.compare(accepted: a, candidate: b)
        #expect(!r.passed)
        let d = diff(r, step: "initial", path: "axNodes.label[toolbar/insert]")
        #expect(d?.expected == "Insert above")
        #expect(d?.actual == "Insert below")
        #expect(r.diffs.count == 1)
    }

    @Test func e2_label_change_passes_only_with_reasoned_adaptation() throws {
        let a = try F1Baseline.accepted()
        let edited = RawEdit.map(try Fx.rawAX()) { n in
            guard n.identifier == "toolbar/insert" else { return n }
            var m = n
            m.label = "Insert below"
            return m
        }
        var b = a
        b.observations[0].axNodes = MacAXNormalizer.normalize(edited)

        let unreasoned = Adaptation(fixture: "F1", steps: ["initial"], field: "axNodes.label", nodeId: "toolbar/insert",
                                    mapping: ["Insert above": "Insert below"], allowAnyValue: nil, reason: "")
        #expect(!TraceComparator.compare(accepted: a, candidate: b, adaptations: [unreasoned]).passed)

        let reasoned = Adaptation(fixture: "F1", steps: ["initial"], field: "axNodes.label", nodeId: "toolbar/insert",
                                  mapping: ["Insert above": "Insert below"], allowAnyValue: nil,
                                  reason: "test only: localized label mapping")
        #expect(TraceComparator.compare(accepted: a, candidate: b, adaptations: [reasoned]).passed)

        // scoped to another step or another fixture it forgives nothing
        var elsewhere = reasoned
        elsewhere.steps = ["focus_row5"]
        #expect(!TraceComparator.compare(accepted: a, candidate: b, adaptations: [elsewhere]).passed)
        elsewhere = reasoned
        elsewhere.fixture = "F2"
        #expect(!TraceComparator.compare(accepted: a, candidate: b, adaptations: [elsewhere]).passed)
        // the legacy unscoped form is no longer accepted
        let legacy = Adaptation(field: "axNodes.label", nodeId: "toolbar/insert",
                                mapping: ["Insert above": "Insert below"], allowAnyValue: nil, reason: "test only")
        #expect(!TraceComparator.compare(accepted: a, candidate: b, adaptations: [legacy]).passed)
    }

    @Test func unlisted_stripped_name_is_not_silently_removed() throws {
        // A real UIA-style fixture would name Pane; here an unknown AX role must survive normalization.
        let raw = RawAXNode(role: "AXWindow", children: [RawAXNode(role: "AXLayoutArea", children: [])])
        let nodes = MacAXNormalizer.normalize(raw)
        #expect(nodes.contains { $0.role == "AXLayoutArea" && $0.parent != nil })
    }
}

@Suite("Repeatability")
struct RepeatabilityTests {
    @Test func twenty_identical_runs_agree() throws {
        let base = try F1Baseline.accepted()
        var runs: [Trace] = []
        for i in 0..<20 {
            var t = base
            for s in t.steps.indices { t.steps[s].timestamp = "run\(i)-step\(s)" }   // timing varies
            runs.append(t)
        }
        let report = Repeatability.check(runs)
        #expect(report.runs == 20)
        #expect(report.allAgree, "\(report)")
        #expect(report.disagreeingPaths.isEmpty)
    }

    @Test func one_variant_run_is_flagged() throws {
        let base = try F1Baseline.accepted()
        var runs = Array(repeating: base, count: 20)
        let edited = RawEdit.map(try Fx.rawAX()) { n in
            guard n.identifier == "toolbar/insert" else { return n }
            var m = n
            m.label = "Insert below"
            return m
        }
        runs[13].observations[0].axNodes = MacAXNormalizer.normalize(edited)

        let report = Repeatability.check(runs)
        #expect(!report.allAgree)
        #expect(report.flaggedRuns == [14])
        #expect(report.disagreeingPaths == ["initial axNodes.label[toolbar/insert]"])
        print("REPEAT variant: \(report)")
    }
}

@Suite("Windows UIA stub normalizer")
struct UIAStubTests {
    @Test func maps_control_types_and_strips_named_containers() {
        let raw = RawUIANode(controlType: "Window", name: "Fixture", children: [
            RawUIANode(controlType: "Pane", children: [
                RawUIANode(controlType: "List", automationId: "rows", children: [
                    RawUIANode(controlType: "ListItem", children: [
                        RawUIANode(controlType: "Edit", automationId: "row/X/field", value: "Row 5", patterns: ["ValuePattern"]),
                    ]),
                ]),
                RawUIANode(controlType: "Button", name: "Insert above", automationId: "toolbar/insert", patterns: ["InvokePattern"]),
            ]),
        ])
        let nodes = UIANormalizer.normalize(raw)
        #expect(nodes.map(\.role) == ["window", "list", "list-item", "text-field", "button"])
        let edit = nodes.first { $0.id == "row/X/field" }
        #expect(edit?.parent?.hasPrefix("anon:") == true)
        #expect(edit?.actions == ["set-value"])
        #expect(nodes.first { $0.id == "toolbar/insert" }?.actions == ["activate"])
        #expect(!nodes.contains { $0.role == "Pane" })
    }
}

/// Writes the accepted F1 trace and fault candidates as JSON when SR0O_EMIT_DIR is set (for the CLI check).
@Suite("Trace emission for the CLI")
struct EmitTests {
    @Test func emit_when_requested() throws {
        guard let dir = ProcessInfo.processInfo.environment["SR0O_EMIT_DIR"] else { return }
        let base = try F1Baseline.accepted()
        let rawAX = try Fx.rawAX()
        func write(_ t: Trace, _ name: String) throws {
            try TraceCodec.json(t).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        try write(base, "accepted-f1.json")
        try write(base, "candidate-identical.json")

        var a = base
        a.observations[4].focusedNodeId = IDs.fieldId(IDs.row(6))
        try write(a, "fault-a-row-identity.json")

        var c = base
        c.observations[0].axNodes = MacAXNormalizer.normalize(RawEdit.map(rawAX) { n in
            guard n.identifier == "toolbar/insert" else { return n }
            var m = n; m.actions = (m.actions ?? []).filter { $0 != "AXPress" }; return m
        })
        try write(c, "fault-c-missing-press.json")

        var e = base
        e.observations[0].axNodes = MacAXNormalizer.normalize(RawEdit.map(rawAX) { n in
            guard n.identifier == "toolbar/insert" else { return n }
            var m = n; m.label = "Insert below"; return m
        })
        try write(e, "fault-e-label.json")

        let f4 = F4SyntheticBaseline.accepted()
        var b = f4
        b.observations[2].model[IDs.modelKey(IDs.row(5))] = "async-42"
        b.observations[2].effects = ["commit-task-result \(IDs.modelKey(IDs.row(5))) async-42"]
        b.observations[2].lifecycle = [LifecycleEvent(kind: "taskComplete", node: IDs.modelKey(IDs.row(5)))]
        try write(f4, "accepted-f4-synthetic.json")
        try write(b, "fault-b-stale-commit.json")
    }
}
