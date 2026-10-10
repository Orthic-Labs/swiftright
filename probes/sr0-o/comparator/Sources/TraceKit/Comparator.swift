import Foundation

/// One semantic difference. `path` is `leaf` or `leaf[node]`; `step` is the observation's step id or `-`.
public struct Diff: Codable, Sendable, Equatable {
    public var fixture: String
    public var step: String
    public var path: String
    public var expected: String
    public var actual: String
}

/// A declared, reasoned allowance for one value pair at one place. It applies to exactly the named fixture, the named
/// step(s), the leaf `field` and, for node leaves, the named `nodeId`; it never applies anywhere else.
///
/// `mapping` lists accepted -> candidate value pairs that are permitted. `allowAnyValue` is reserved for the declared
/// native-input leaf `steps.nativeMapping` (the platforms drive the same logical step differently by contract); it is
/// still bound to the fixture and steps. An allowance that is not fully scoped, has no reason, or names an unadaptable
/// leaf is INVALID: it is ignored (the diff stays) and the report notes why.
public struct Adaptation: Codable, Sendable, Equatable {
    public var id: String?             // short handle used in reports, e.g. "P1"
    public var status: String?         // "contract" | "oracle-quirk" | "unproven"; free text for the reader, never for matching
    public var fixture: String?        // config id the allowance applies to (the trace's fixtureId)
    public var steps: [String]?        // step ids the allowance applies to
    public var field: String           // leaf field, e.g. "axNodes.label"
    public var nodeId: String?         // required for node leaves, forbidden for the others
    public var mapping: [String: String]?
    public var allowAnyValue: Bool?
    public var reason: String

    public init(id: String? = nil, status: String? = nil, fixture: String? = nil, steps: [String]? = nil,
                field: String, nodeId: String? = nil, mapping: [String: String]? = nil,
                allowAnyValue: Bool? = nil, reason: String) {
        self.id = id; self.status = status; self.fixture = fixture; self.steps = steps
        self.field = field; self.nodeId = nodeId; self.mapping = mapping
        self.allowAnyValue = allowAnyValue; self.reason = reason
    }

    /// Leaves that identify a node in their path (`leaf[node]`); an allowance on one must name that node.
    static let nodeLeaves: Set<String> = [
        "model", "lifecycle.count", "lifecycle.order", "axNodes.presence", "axNodes.role", "axNodes.label",
        "axNodes.value", "axNodes.actions", "axNodes.parent", "axNodes.order",
    ]
    /// Leaves no allowance may touch: they say whether the two traces are comparable at all.
    static let unadaptable: Set<String> = ["fixtureId", "schemaVersion", "sourceHash", "conditions", "steps.order", "observation"]
    /// The one leaf where `allowAnyValue` is accepted.
    static let anyValueLeaf = "steps.nativeMapping"

    var label: String { id ?? field }

    /// nil when the allowance is valid, else the reason it is ignored.
    var problem: String? {
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "no reason" }
        guard let fixture, !fixture.isEmpty else { return "no fixture" }
        guard let steps, !steps.isEmpty, steps.allSatisfy({ !$0.isEmpty && $0 != "-" }) else { return "no steps" }
        if Adaptation.unadaptable.contains(field) { return "leaf \(field) is never adaptable" }
        if Adaptation.nodeLeaves.contains(field) {
            if nodeId == nil || nodeId == "" { return "leaf \(field) needs a nodeId" }
        } else if nodeId != nil {
            return "leaf \(field) has no node, nodeId must be absent"
        }
        let any = allowAnyValue == true
        let pairs = mapping.map { !$0.isEmpty } ?? false
        if any == pairs { return "needs exactly one of mapping or allowAnyValue" }
        if any && field != Adaptation.anyValueLeaf { return "allowAnyValue is only for \(Adaptation.anyValueLeaf)" }
        return nil
    }
}

/// A difference that an allowance forgave, kept in the report so the verdict shows what was allowed.
public struct AllowedDiff: Codable, Sendable, Equatable {
    public var allowance: String
    public var status: String?
    public var step: String
    public var path: String
    public var expected: String
    public var actual: String
}

public struct ComparisonReport: Codable, Sendable, Equatable {
    public var fixture: String
    public var passed: Bool
    public var diffs: [Diff]
    public var notes: [String]
    public var allowed: [AllowedDiff] = []
}

public enum TraceComparator {
    /// Exact semantic comparison of normalized traces. Timestamps and platform tuples are not failing
    /// fields: a platform difference is noted, because cross-platform comparison is expected.
    public static func compare(accepted: Trace, candidate: Trace, adaptations: [Adaptation] = []) -> ComparisonReport {
        var c = Collector(fixture: accepted.fixtureId, adaptations: adaptations)
        var notes: [String] = []
        for a in adaptations { if let why = a.problem { notes.append("allowance \(a.label) ignored: \(why)") } }

        if candidate.fixtureId != accepted.fixtureId {
            c.report(step: "-", leaf: "fixtureId", node: nil, expected: accepted.fixtureId, actual: candidate.fixtureId)
        }
        if candidate.schemaVersion != accepted.schemaVersion {
            c.report(step: "-", leaf: "schemaVersion", node: nil, expected: accepted.schemaVersion, actual: candidate.schemaVersion)
        }
        if candidate.sourceHash != accepted.sourceHash {
            c.report(step: "-", leaf: "sourceHash", node: nil, expected: accepted.sourceHash, actual: candidate.sourceHash)
        }
        if candidate.platform != accepted.platform {
            notes.append("platform differs (not compared): accepted \(accepted.platform) candidate \(candidate.platform)")
        }

        let conditionsA = accepted.conditions ?? [:], conditionsB = candidate.conditions ?? [:]
        for key in Set(conditionsA.keys).union(conditionsB.keys).sorted() where conditionsA[key] != conditionsB[key] {
            c.report(step: "-", leaf: "conditions", node: key,
                     expected: conditionsA[key] ?? "<absent>", actual: conditionsB[key] ?? "<absent>")
        }

        compareSteps(accepted.steps, candidate.steps, into: &c)

        for a in accepted.observations {
            guard let b = candidate.observations.first(where: { $0.stepId == a.stepId }) else {
                c.report(step: a.stepId, leaf: "observation", node: nil, expected: "present", actual: "absent")
                continue
            }
            compareObservation(a, b, into: &c)
        }
        for b in candidate.observations where !accepted.observations.contains(where: { $0.stepId == b.stepId }) {
            c.report(step: b.stepId, leaf: "observation", node: nil, expected: "absent", actual: "present")
        }

        compareOrder(accepted: accepted, candidate: candidate, into: &c)

        notes += c.unusedNotes()
        return ComparisonReport(fixture: accepted.fixtureId, passed: c.diffs.isEmpty, diffs: c.diffs, notes: notes, allowed: c.allowed)
    }

    private static func compareSteps(_ a: [TraceStep], _ b: [TraceStep], into c: inout Collector) {
        if a.map(\.id) != b.map(\.id) {
            c.report(step: "-", leaf: "steps.order", node: nil,
                     expected: a.map(\.id).joined(separator: ","), actual: b.map(\.id).joined(separator: ","))
        }
        for s in a {
            guard let t = b.first(where: { $0.id == s.id }) else { continue }
            if s.logicalAction != t.logicalAction {
                c.report(step: s.id, leaf: "steps.logicalAction", node: nil, expected: s.logicalAction, actual: t.logicalAction)
            }
            if s.nativeMapping != t.nativeMapping {
                c.report(step: s.id, leaf: "steps.nativeMapping", node: nil, expected: s.nativeMapping, actual: t.nativeMapping)
            }
        }
    }

    private static func compareObservation(_ a: Observation, _ b: Observation, into c: inout Collector) {
        let s = a.stepId

        for key in Set(a.model.keys).union(b.model.keys).sorted() {
            let e = a.model[key] ?? "<absent>"
            let x = b.model[key] ?? "<absent>"
            if e != x { c.report(step: s, leaf: "model", node: key, expected: e, actual: x) }
        }

        if a.focusedNodeId != b.focusedNodeId {
            c.report(step: s, leaf: "focusedNodeId", node: nil,
                     expected: a.focusedNodeId ?? "<none>", actual: b.focusedNodeId ?? "<none>")
        }

        let selA = describe(a.selection), selB = describe(b.selection)
        if selA != selB { c.report(step: s, leaf: "selection", node: nil, expected: selA, actual: selB) }

        if a.effects != b.effects {
            c.report(step: s, leaf: "effects", node: nil,
                     expected: a.effects.isEmpty ? "<none>" : a.effects.joined(separator: " | "),
                     actual: b.effects.isEmpty ? "<none>" : b.effects.joined(separator: " | "))
        }

        // Lifecycle: multiset per event key. Permutation is checked by declared order below.
        let countsA = counts(a.lifecycle.map(\.key)), countsB = counts(b.lifecycle.map(\.key))
        for key in Set(countsA.keys).union(countsB.keys).sorted() where countsA[key, default: 0] != countsB[key, default: 0] {
            c.report(step: s, leaf: "lifecycle.count", node: key,
                     expected: String(countsA[key, default: 0]), actual: String(countsB[key, default: 0]))
        }

        switch (a.axNodes, b.axNodes) {
        case (nil, nil):
            break
        case (.some, nil):
            c.report(step: s, leaf: "axNodes", node: nil, expected: "captured", actual: "not captured")
        case (nil, .some):
            c.report(step: s, leaf: "axNodes", node: nil, expected: "not captured", actual: "captured")
        case let (.some(an), .some(bn)):
            compareNodes(an, bn, step: s, into: &c)
        }
    }

    private static func compareNodes(_ a: [CanonicalNode], _ b: [CanonicalNode], step s: String, into c: inout Collector) {
        let mapA = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let mapB = Dictionary(b.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Duplicate ids (a stale or malformed tree): the two sides must show the same number; equal counts are agreement.
        if a.count - mapA.count != b.count - mapB.count {
            c.report(step: s, leaf: "axNodes.duplicateId", node: nil,
                     expected: "\(a.count - mapA.count) duplicates", actual: "\(b.count - mapB.count) duplicates")
        }
        for id in Set(mapA.keys).union(mapB.keys).sorted() {
            switch (mapA[id], mapB[id]) {
            case let (x?, nil):
                c.report(step: s, leaf: "axNodes.presence", node: id, expected: "role=\(x.role)", actual: "<absent>")
            case let (nil, y?):
                c.report(step: s, leaf: "axNodes.presence", node: id, expected: "<absent>", actual: "role=\(y.role)")
            case let (x?, y?):
                let fields: [(String, String, String)] = [
                    ("axNodes.role", x.role, y.role),
                    ("axNodes.label", show(x.label), show(y.label)),
                    ("axNodes.value", show(x.value), show(y.value)),
                    ("axNodes.actions", x.actions.sorted().joined(separator: ","), y.actions.sorted().joined(separator: ",")),
                    ("axNodes.parent", show(x.parent), show(y.parent)),
                    ("axNodes.order", String(x.order), String(y.order)),
                ]
                for (leaf, e, actual) in fields where e != actual {
                    c.report(step: s, leaf: leaf, node: id, expected: e, actual: actual)
                }
            case (nil, nil):
                break
            }
        }
    }

    private static func compareOrder(accepted: Trace, candidate: Trace, into c: inout Collector) {
        let sequence: [(step: String, key: String)] = candidate.observations.flatMap { o in
            o.lifecycle.map { (step: o.stepId, key: $0.key) }
        }
        func index(_ key: String) -> Int? { sequence.firstIndex(where: { $0.key == key }) }

        for edge in accepted.declaredOrder {
            guard let ib = index(edge.before), let ia = index(edge.after) else { continue }
            if ib > ia {
                c.report(step: sequence[ia].step, leaf: "lifecycle.order", node: "\(edge.before) before \(edge.after)",
                         expected: "before", actual: "after")
            }
        }
    }

    private static func describe(_ r: UTF16Range?) -> String {
        guard let r else { return "<none>" }
        return "location=\(r.location) length=\(r.length)"
    }

    private static func counts(_ keys: [String]) -> [String: Int] {
        keys.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func show(_ s: String?) -> String { s ?? "<nil>" }
}

/// Collects diffs and applies adaptations at the leaf level. An adaptation applies to a diff only when fixture, step,
/// leaf, node and the exact value pair all match; invalid adaptations never apply.
struct Collector {
    let fixture: String
    let adaptations: [Adaptation]
    var diffs: [Diff] = []
    var allowed: [AllowedDiff] = []
    private var used: Set<Int> = []

    init(fixture: String, adaptations: [Adaptation]) {
        self.fixture = fixture
        self.adaptations = adaptations
    }

    mutating func report(step: String, leaf: String, node: String?, expected: String, actual: String) {
        let path = node.map { "\(leaf)[\($0)]" } ?? leaf
        if let index = adaptation(step: step, leaf: leaf, node: node, expected: expected, actual: actual) {
            used.insert(index)
            allowed.append(AllowedDiff(allowance: adaptations[index].label, status: adaptations[index].status, step: step, path: path, expected: expected, actual: actual))
            return
        }
        diffs.append(Diff(fixture: fixture, step: step, path: path, expected: expected, actual: actual))
    }

    private func adaptation(step: String, leaf: String, node: String?, expected: String, actual: String) -> Int? {
        for (index, a) in adaptations.enumerated() where a.problem == nil {
            guard a.fixture == fixture, a.steps?.contains(step) == true, a.field == leaf, a.nodeId == node else { continue }
            if a.allowAnyValue == true { return index }
            if let mapping = a.mapping, mapping[expected] == actual { return index }
        }
        return nil
    }

    /// Valid allowances that forgave nothing: harmless for the verdict, but worth a reader's attention.
    func unusedNotes() -> [String] {
        adaptations.enumerated().filter { $0.element.problem == nil && !used.contains($0.offset) }
            .map { "allowance \($0.element.label) (\($0.element.field)) was not exercised" }
    }
}
