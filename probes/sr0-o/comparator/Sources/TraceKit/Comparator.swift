import Foundation

/// One semantic difference. `path` is `leaf` or `leaf[node]`; `step` is the observation's step id or `-`.
public struct Diff: Codable, Sendable, Equatable {
    public var fixture: String
    public var step: String
    public var path: String
    public var expected: String
    public var actual: String
}

/// A declared, reasoned allowance for one field (and optionally one node).
/// `mapping` lists accepted -> candidate values that are permitted; `allowAnyValue` permits any difference.
/// Entries with an empty `reason` are ignored, so every allowance must be justified.
public struct Adaptation: Codable, Sendable, Equatable {
    public var field: String           // leaf field, e.g. "axNodes.label"
    public var nodeId: String?         // nil = any node
    public var mapping: [String: String]?
    public var allowAnyValue: Bool?
    public var reason: String
}

public struct ComparisonReport: Codable, Sendable, Equatable {
    public var fixture: String
    public var passed: Bool
    public var diffs: [Diff]
    public var notes: [String]
}

public enum TraceComparator {
    /// Exact semantic comparison of normalized traces. Timestamps and platform tuples are not failing
    /// fields: a platform difference is noted, because cross-platform comparison is expected.
    public static func compare(accepted: Trace, candidate: Trace, adaptations: [Adaptation] = []) -> ComparisonReport {
        var c = Collector(fixture: accepted.fixtureId, adaptations: adaptations.filter { !$0.reason.isEmpty })
        var notes: [String] = []

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

        return ComparisonReport(fixture: accepted.fixtureId, passed: c.diffs.isEmpty, diffs: c.diffs, notes: notes)
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
        if mapA.count != a.count || mapB.count != b.count {
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

/// Collects diffs and applies adaptations at the leaf level.
struct Collector {
    let fixture: String
    let adaptations: [Adaptation]
    var diffs: [Diff] = []

    init(fixture: String, adaptations: [Adaptation]) {
        self.fixture = fixture
        self.adaptations = adaptations
    }

    mutating func report(step: String, leaf: String, node: String?, expected: String, actual: String) {
        if isAdapted(leaf: leaf, node: node, expected: expected, actual: actual) { return }
        let path = node.map { "\(leaf)[\($0)]" } ?? leaf
        diffs.append(Diff(fixture: fixture, step: step, path: path, expected: expected, actual: actual))
    }

    private func isAdapted(leaf: String, node: String?, expected: String, actual: String) -> Bool {
        for a in adaptations where a.field == leaf && (a.nodeId == nil || a.nodeId == node) {
            if a.allowAnyValue == true { return true }
            if let mapping = a.mapping, mapping[expected] == actual { return true }
        }
        return false
    }
}
