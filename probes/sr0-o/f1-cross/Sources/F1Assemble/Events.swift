import Foundation

// In-process instrumentation merge. Both fixtures emit {kind, node_id, payload, mono_ns}: the Mac as JSONL (plus `step`),
// the Windows exe as `EVT {json}` stdout lines (plus `seq`). Events are assigned to steps by the shared monotonic clock
// (DispatchTime uptime), never by arrival in a file.

struct Event {
    var kind: String
    var node: String
    var payload: [String: Any]
    var mono: UInt64
    var phase: String { (payload["phase"] as? String) ?? (payload["op"] as? String) ?? "" }
}

func loadEvents(path: String) throws -> [Event] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    var out: [Event] = []
    for raw in text.split(whereSeparator: \.isNewline) {
        var line = String(raw).trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("EVT ") { line = String(line.dropFirst(4)) }
        guard line.hasPrefix("{"), let d = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let kind = o["kind"] as? String, let node = o["node_id"] as? String else { continue }
        let mono = (o["mono_ns"] as? NSNumber)?.uint64Value ?? 0
        out.append(Event(kind: kind, node: node, payload: o["payload"] as? [String: Any] ?? [:], mono: mono))
    }
    return out.sorted { $0.mono < $1.mono }
}

private func isUUID(_ s: String) -> Bool { UUID(uuidString: s) != nil }

/// Canonical node key: row UUID -> `row/<uuid>`; `window`, `screen`, `toolbar/insert` stay as named.
func nodeKey(_ n: String) -> String { isUUID(n) ? "row/\(n)" : n }

struct MappedStep {
    var lifecycle: [TLifecycle] = []
    var effects: [String] = []
}

struct EventMapping {
    var perStep: [String: MappedStep] = [:]
    var excluded: [String: Int] = [:]    // "kind/phase" -> count, so nothing is dropped silently
}

/// Mapping rules (recorded as adaptations E1..E4 in RESULT.md).
func mapEvents(_ events: [Event], stepStarts: [(id: String, start: UInt64)], endNs: UInt64) -> EventMapping {
    var m = EventMapping()
    for s in stepStarts { m.perStep[s.id] = MappedStep() }
    func step(for t: UInt64) -> String? {
        if t >= endNs { return nil }
        var chosen = stepStarts[0].id          // events before the first step start belong to `initial`
        for s in stepStarts where s.start <= t { chosen = s.id }
        return chosen
    }
    var endMode: [String: String] = [:]
    for e in events {
        guard let sid = step(for: e.mono) else { m.excluded["after-last-observation/\(e.kind)/\(e.phase)", default: 0] += 1; continue }
        let node = nodeKey(e.node)
        let ph = e.phase
        switch (e.kind, ph) {
        case ("lifecycle", "appear"), ("lifecycle", "disappear"):
            m.perStep[sid]!.lifecycle.append(TLifecycle(kind: ph, node: node))
        case ("lifecycle", "root-appear"):
            m.perStep[sid]!.lifecycle.append(TLifecycle(kind: "appear", node: "window"))
        case ("lifecycle", "root-disappear"):
            m.perStep[sid]!.lifecycle.append(TLifecycle(kind: "disappear", node: "window"))
        case ("lifecycle", "task-start"):
            m.perStep[sid]!.lifecycle.append(TLifecycle(kind: "taskStart", node: node))
        case ("lifecycle", "task-cancel"):
            m.perStep[sid]!.lifecycle.append(TLifecycle(kind: "taskCancel", node: node))
        case ("lifecycle", "start"), ("lifecycle", "complete"), ("lifecycle", "policy"):
            guard e.node == "animation" else { m.excluded["\(e.kind)/\(ph)", default: 0] += 1; continue }
            // F6 animation transactions (node `animation`): per-tag start/complete lifecycle, policy as an effect line.
            if ph == "policy" {
                m.perStep[sid]!.effects.append("animation-policy enabled=\(e.payload["enabled"] as? Bool ?? false)")
            } else {
                let tag = (e.payload["tag"] as? String) ?? "?"
                m.perStep[sid]!.lifecycle.append(TLifecycle(kind: "animation-\(ph)", node: "animation/\(tag)"))
            }
        case ("state", ""):
            // F5 layout passes (node `layout`): only changes of the non-degenerate layout mode are compared.
            // Only the mode a step ENDS in is compared (a step may pass through intermediate modes while the window settles).
            if e.node == "layout", (e.payload["degenerate"] as? Bool) != true, let mode = e.payload["mode"] as? String {
                endMode[sid] = mode
            } else { m.excluded["\(e.kind)/\(ph)", default: 0] += 1 }
        case ("lifecycle", "released") where e.node == "tree":
            m.perStep[sid]!.lifecycle.append(TLifecycle(kind: "treeReleased", node: "tree"))
        case ("lifecycle", "local-edit"):
            // @State write count per row identity (the row's `local N` counter).
            m.perStep[sid]!.lifecycle.append(TLifecycle(kind: "localEdit", node: node))
        case ("effect", "engine-request"), ("effect", "engine-release"), ("effect", "commit"), ("effect", "cleanup"), ("effect", "rejected"):
            let what = (e.payload["key"] as? String) ?? (e.payload["effect"] as? String) ?? ""
            var s = "\(ph) \(node) \(what)"
            if ph == "rejected", let r = e.payload["reason"] as? String { s += " reason=\(r)" }
            m.perStep[sid]!.effects.append(s)
        case ("state", "insert"):
            let idx = (e.payload["index"] as? NSNumber)?.intValue ?? -1
            m.perStep[sid]!.effects.append("insert-row index=\(idx) row=\(e.payload["id"] as? String ?? "?")")
        case ("state", "remove"):
            m.perStep[sid]!.effects.append("remove-row row=\(e.node)")
        default:
            m.excluded["\(e.kind)/\(ph)", default: 0] += 1
        }
    }
    var previous: String?
    for st in stepStarts {
        if let mode = endMode[st.id] {
            if mode != previous { m.perStep[st.id]!.effects.insert("layout-mode \(mode)", at: 0) }
            previous = mode
        }
    }
    return m
}


/// Node an effect line belongs to. Effects follow the oracle digest rule (sr0-a.canonical/v2): sibling events of different
/// nodes between two driver operations are unordered (sibling `.task` start order across rows, the engine's release order),
/// while each node's own sequence keeps its recorded order. The comparator compares `effects` as an ordered list, so both
/// platforms are stored grouped by node.
func effectNode(_ line: String) -> String {
    let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
    guard let head = parts.first else { return "" }
    switch head {
    case "insert-row":
        if let r = line.range(of: " row=") { return "row/" + String(line[r.upperBound...]) }
        return "model"
    case "remove-row":
        if let r = line.range(of: " row=") { return "row/" + String(line[r.upperBound...]) }
        return "model"
    case "layout-mode": return "layout"
    case "animation-policy": return "animation"
    default: return parts.count > 1 ? parts[1] : head
    }
}

private func isModelOp(_ line: String) -> Bool {
    let head = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
    return ["insert-row", "remove-row", "layout-mode", "animation-policy"].contains(head)
}

/// Model-level operations (driver-ordered) keep their place; the scheduler-ordered lines between two of them (engine
/// requests, releases, commits, rejections, cleanups across different nodes) are grouped by node, per-node order stable.
func canonicalEffects(_ effects: [String]) -> [String] {
    var out: [String] = []
    var run: [String] = []
    func flush() {
        out += run.enumerated().sorted { a, b in
            let ka = effectNode(a.element), kb = effectNode(b.element)
            return ka == kb ? a.offset < b.offset : ka < kb
        }.map(\.element)
        run = []
    }
    for line in effects {
        if isModelOp(line) { flush(); out.append(line) } else { run.append(line) }
    }
    flush()
    return out
}
