import Foundation
import Testing
@testable import TraceKit

/// An allowance applies to one fixture, named steps, one leaf, one node and one exact value pair, and nowhere else.
/// Synthetic two-step, two-row traces: every test changes one fact and checks whether a scoped allowance covers it.
private enum Syn {
    static let rowA = "row/A", rowB = "row/B"

    static func observation(_ step: String, a: String = "x", b: String = "y", focus: String? = nil,
                            selection: UTF16Range? = nil, effects: [String] = [], lifecycle: [LifecycleEvent] = []) -> Observation {
        Observation(stepId: step, model: [rowA: a, rowB: b], focusedNodeId: focus, selection: selection,
                    lifecycle: lifecycle, effects: effects, axNodes: nil)
    }

    static func trace(fixture: String = "FX", s1: Observation = observation("s1"), s2: Observation = observation("s2"),
                      conditions: [String: String]? = nil) -> Trace {
        Trace(schemaVersion: traceSchemaVersion, fixtureId: fixture, sourceHash: "h",
              platform: PlatformTuple(os: "macos", osBuild: "1", arch: "arm64", toolchain: "t"),
              steps: ["s1", "s2"].map { TraceStep(id: $0, logicalAction: "act \($0)", nativeMapping: "native \($0)", timestamp: "t") },
              observations: [s1, s2], declaredOrder: [], conditions: conditions)
    }

    static func modelAllowance(step: String = "s1", node: String = rowA, fixture: String = "FX",
                               pair: [String: String] = ["x": "z"]) -> Adaptation {
        Adaptation(id: "T1", status: "unproven", fixture: fixture, steps: [step], field: "model", nodeId: node, mapping: pair,
                   reason: "test only: scoped model allowance")
    }

    static func paths(_ r: ComparisonReport) -> [String] { r.diffs.map { "\($0.step) \($0.path)" } }
}

@Suite("Allowances are step-scoped and node-scoped")
struct AllowanceScopeTests {
    @Test func allowance_covers_exactly_its_fixture_step_node_and_pair() {
        let accepted = Syn.trace()
        let candidate = Syn.trace(s1: Syn.observation("s1", a: "z"))
        let r = TraceComparator.compare(accepted: accepted, candidate: candidate, adaptations: [Syn.modelAllowance()])
        #expect(r.passed, "\(Syn.paths(r))")
        #expect(r.allowed.count == 1)
        #expect(r.allowed.first?.allowance == "T1")
        #expect(r.allowed.first?.path == "model[row/A]")
        #expect(r.notes.isEmpty)
    }

    @Test func allowance_does_not_apply_at_another_step() {
        // the same node and pair differ at s2, but the allowance names s1 only
        let candidate = Syn.trace(s1: Syn.observation("s1", a: "z"), s2: Syn.observation("s2", a: "z"))
        let r = TraceComparator.compare(accepted: Syn.trace(), candidate: candidate, adaptations: [Syn.modelAllowance()])
        #expect(!r.passed)
        #expect(Syn.paths(r) == ["s2 model[row/A]"])
        #expect(r.allowed.map(\.step) == ["s1"])
    }

    @Test func allowance_does_not_apply_to_another_node() {
        // same step and same value pair on row B; the allowance names row A
        let candidate = Syn.trace(s1: Syn.observation("s1", a: "z", b: "z"))
        let accepted = Syn.trace(s1: Syn.observation("s1", a: "x", b: "x"))
        let r = TraceComparator.compare(accepted: accepted, candidate: candidate, adaptations: [Syn.modelAllowance()])
        #expect(!r.passed)
        #expect(Syn.paths(r) == ["s1 model[row/B]"])
    }

    @Test func allowance_does_not_apply_to_another_fixture() {
        let candidate = Syn.trace(fixture: "FY", s1: Syn.observation("s1", a: "z"))
        let accepted = Syn.trace(fixture: "FY")
        let r = TraceComparator.compare(accepted: accepted, candidate: candidate, adaptations: [Syn.modelAllowance(fixture: "FX")])
        #expect(!r.passed)
        #expect(Syn.paths(r) == ["s1 model[row/A]"])
    }

    @Test func allowance_does_not_apply_to_another_value_pair() {
        // the allowed pair is x -> z; the candidate shows w, and a different baseline value would not match either
        let r = TraceComparator.compare(accepted: Syn.trace(), candidate: Syn.trace(s1: Syn.observation("s1", a: "w")),
                                        adaptations: [Syn.modelAllowance()])
        #expect(!r.passed)
        #expect(r.diffs.first?.actual == "w")
        let reverse = TraceComparator.compare(accepted: Syn.trace(s1: Syn.observation("s1", a: "z")), candidate: Syn.trace(s1: Syn.observation("s1", a: "x")),
                                              adaptations: [Syn.modelAllowance()])
        #expect(!reverse.passed, "the pair is directional: expected z, actual x is not x -> z")
    }

    @Test func allowance_does_not_apply_to_another_leaf() {
        let candidate = Syn.trace(s1: Syn.observation("s1", a: "z", focus: "row/A/field"))
        let r = TraceComparator.compare(accepted: Syn.trace(), candidate: candidate, adaptations: [Syn.modelAllowance()])
        #expect(Syn.paths(r) == ["s1 focusedNodeId"])
    }

    @Test func a_step_list_covers_each_named_step_and_no_other() {
        var a = Syn.modelAllowance()
        a.steps = ["s1", "s2"]
        let both = Syn.trace(s1: Syn.observation("s1", a: "z"), s2: Syn.observation("s2", a: "z"))
        #expect(TraceComparator.compare(accepted: Syn.trace(), candidate: both, adaptations: [a]).passed)
        a.steps = ["s2"]
        let r = TraceComparator.compare(accepted: Syn.trace(), candidate: both, adaptations: [a])
        #expect(Syn.paths(r) == ["s1 model[row/A]"])
    }

    @Test func non_node_leaves_are_step_scoped_too() {
        let accepted = Syn.trace()
        let candidate = Syn.trace(s1: Syn.observation("s1", focus: "row/A/field", selection: UTF16Range(location: 0, length: 0)),
                                  s2: Syn.observation("s2", focus: "row/A/field", selection: UTF16Range(location: 0, length: 0)))
        let focus = Adaptation(id: "T2", fixture: "FX", steps: ["s1"], field: "focusedNodeId",
                               mapping: ["<none>": "row/A/field"], reason: "test only")
        let selection = Adaptation(id: "T3", fixture: "FX", steps: ["s1"], field: "selection",
                                   mapping: ["<none>": "location=0 length=0"], reason: "test only")
        let r = TraceComparator.compare(accepted: accepted, candidate: candidate, adaptations: [focus, selection])
        #expect(Set(Syn.paths(r)) == ["s2 focusedNodeId", "s2 selection"])
        #expect(Set(r.allowed.map(\.allowance)) == ["T2", "T3"])
    }

    @Test func native_mapping_allowance_is_bound_to_fixture_and_steps() {
        var candidate = Syn.trace()
        for i in candidate.steps.indices { candidate.steps[i].nativeMapping = "other \(i)" }
        let n1 = Adaptation(id: "N1", fixture: "FX", steps: ["s1"], field: "steps.nativeMapping", allowAnyValue: true, reason: "test only")
        let r = TraceComparator.compare(accepted: Syn.trace(), candidate: candidate, adaptations: [n1])
        #expect(Syn.paths(r) == ["s2 steps.nativeMapping"])
        let wrongFixture = Adaptation(id: "N1", fixture: "FY", steps: ["s1", "s2"], field: "steps.nativeMapping", allowAnyValue: true, reason: "test only")
        #expect(TraceComparator.compare(accepted: Syn.trace(), candidate: candidate, adaptations: [wrongFixture]).diffs.count == 2)
        // the logical action is a different leaf: native-mapping tolerance never reaches it
        var logical = Syn.trace()
        logical.steps[0].logicalAction = "different intent"
        let both = Adaptation(id: "N1", fixture: "FX", steps: ["s1", "s2"], field: "steps.nativeMapping", allowAnyValue: true, reason: "test only")
        #expect(Syn.paths(TraceComparator.compare(accepted: Syn.trace(), candidate: logical, adaptations: [both])) == ["s1 steps.logicalAction"])
    }
}

@Suite("Invalid allowances are ignored, never silently widened")
struct InvalidAllowanceTests {
    private func run(_ a: Adaptation) -> ComparisonReport {
        TraceComparator.compare(accepted: Syn.trace(), candidate: Syn.trace(s1: Syn.observation("s1", a: "z")), adaptations: [a])
    }

    @Test func unscoped_allowances_are_ignored_and_noted() {
        var noFixture = Syn.modelAllowance(); noFixture.fixture = nil
        var noSteps = Syn.modelAllowance(); noSteps.steps = nil
        var emptySteps = Syn.modelAllowance(); emptySteps.steps = []
        var noNode = Syn.modelAllowance(); noNode.nodeId = nil
        var noReason = Syn.modelAllowance(); noReason.reason = "  "
        for a in [noFixture, noSteps, emptySteps, noNode, noReason] {
            let r = run(a)
            #expect(!r.passed)
            #expect(r.notes.contains { $0.hasPrefix("allowance T1 ignored") }, "\(r.notes)")
            #expect(r.allowed.isEmpty)
        }
    }

    @Test func any_value_is_only_for_the_native_mapping_leaf() {
        var any = Syn.modelAllowance(); any.mapping = nil; any.allowAnyValue = true
        #expect(!run(any).passed)
        var both = Syn.modelAllowance(); both.allowAnyValue = true
        #expect(!run(both).passed)
    }

    @Test func a_node_id_on_a_non_node_leaf_is_invalid() {
        let a = Adaptation(id: "T9", fixture: "FX", steps: ["s1"], field: "focusedNodeId", nodeId: "row/A/field",
                           mapping: ["<none>": "row/A/field"], reason: "test only")
        let r = TraceComparator.compare(accepted: Syn.trace(), candidate: Syn.trace(s1: Syn.observation("s1", focus: "row/A/field")), adaptations: [a])
        #expect(!r.passed)
        #expect(r.notes.contains { $0.contains("nodeId must be absent") })
    }

    @Test func comparability_leaves_cannot_be_adapted() {
        for leaf in ["fixtureId", "schemaVersion", "sourceHash", "conditions", "steps.order"] {
            let a = Adaptation(id: "T9", fixture: "FX", steps: ["s1"], field: leaf, mapping: ["a": "b"], reason: "test only")
            #expect(a.problem?.contains("never adaptable") == true, "\(leaf)")
        }
    }

    @Test func unused_allowances_are_noted_not_failed() {
        let r = TraceComparator.compare(accepted: Syn.trace(), candidate: Syn.trace(), adaptations: [Syn.modelAllowance()])
        #expect(r.passed)
        #expect(r.notes.contains { $0.contains("T1") && $0.contains("not exercised") })
    }
}

@Suite("Run conditions")
struct ConditionTests {
    private let mac = ["reduceMotion.effective": "false", "reduceMotion.variant": "false"]

    @Test func equal_conditions_pass() {
        #expect(TraceComparator.compare(accepted: Syn.trace(conditions: mac), candidate: Syn.trace(conditions: mac)).passed)
    }

    @Test func different_motion_conditions_fail() {
        var win = mac
        win["reduceMotion.effective"] = "true"
        let r = TraceComparator.compare(accepted: Syn.trace(conditions: mac), candidate: Syn.trace(conditions: win))
        #expect(!r.passed)
        let d = r.diffs.first { $0.path == "conditions[reduceMotion.effective]" }
        #expect(d?.expected == "false")
        #expect(d?.actual == "true")
        #expect(r.diffs.count == 1)
    }

    @Test func a_condition_recorded_on_one_side_only_fails() {
        let r = TraceComparator.compare(accepted: Syn.trace(conditions: mac), candidate: Syn.trace())
        #expect(Set(r.diffs.map(\.path)) == ["conditions[reduceMotion.effective]", "conditions[reduceMotion.variant]"])
        #expect(r.diffs.allSatisfy { $0.actual == "<absent>" })
    }

    @Test func no_allowance_can_forgive_a_condition_difference() {
        var win = mac
        win["reduceMotion.effective"] = "true"
        let any = [
            Adaptation(id: "C", fixture: "FX", steps: ["-"], field: "conditions", nodeId: "reduceMotion.effective",
                       mapping: ["false": "true"], reason: "test only"),
            Adaptation(id: "C2", fixture: "FX", steps: ["s1", "s2"], field: "conditions", mapping: ["false": "true"], reason: "test only"),
        ]
        let r = TraceComparator.compare(accepted: Syn.trace(conditions: mac), candidate: Syn.trace(conditions: win), adaptations: any)
        #expect(!r.passed)
        #expect(r.allowed.isEmpty)
    }
}

@Suite("Duplicate AX ids")
struct DuplicateIdTests {
    private func trace(_ nodes: [CanonicalNode]) -> Trace {
        var t = Syn.trace()
        t.observations[0].axNodes = nodes
        return t
    }
    private func node(_ id: String) -> CanonicalNode { CanonicalNode(id: id, role: "text-field", label: nil, value: nil, actions: [], parent: "window", order: 0) }

    @Test func equal_duplicate_counts_agree_and_different_counts_differ() {
        let two = trace([node("a"), node("a"), node("a")]), same = trace([node("a"), node("a"), node("a")]), none = trace([node("a")])
        #expect(TraceComparator.compare(accepted: two, candidate: same).passed)
        let r = TraceComparator.compare(accepted: two, candidate: none)
        #expect(Syn.paths(r) == ["s1 axNodes.duplicateId"])
        #expect(r.diffs.first?.expected == "2 duplicates")
        #expect(r.diffs.first?.actual == "0 duplicates")
    }
}
