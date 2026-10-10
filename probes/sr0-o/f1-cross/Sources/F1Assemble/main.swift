import Foundation
import CryptoKit

// F1Assemble mac --raw mac-raw.json --events mac-events.jsonl --stimulus f1-stimulus.json --out trace.json [--keep-lists]
// F1Assemble win --rec winrec.json --side winside.json --events events.txt --stimulus f1-stimulus.json --out trace.json [--keep-lists]
// Writes <out> and <out>.notes.json (adaptations applied, excluded event kinds).

func eprint(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
let args = CommandLine.arguments
func arg(_ n: String) -> String? {
    guard let i = args.firstIndex(of: n), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func json(_ path: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
}
guard args.count > 1, let outPath = arg("--out"), let stimPath = arg("--stimulus"), let evPath = arg("--events") else {
    eprint("usage: F1Assemble mac|win ... (see source header)"); exit(2)
}
let keepLists = args.contains("--keep-lists")
let opt = NormOptions(keepLists: keepLists)
let stimData = try Data(contentsOf: URL(fileURLWithPath: stimPath))
let sourceHash = "sha256:" + SHA256.hash(data: stimData).map { String(format: "%02x", $0) }.joined()
let stim = try JSONSerialization.jsonObject(with: stimData) as! [String: Any]
let logicalById: [String: String] = Dictionary(uniqueKeysWithValues: (stim["steps"] as! [[String: Any]]).map { ($0["id"] as! String, $0["logicalAction"] as! String) })
let stepOrder = (stim["steps"] as! [[String: Any]]).map { $0["id"] as! String }
// `modelRows`: a list of field identifiers to put in `model`, or "all" for every row/<uuid>/field node in the tree.
let modelRowsAll = (stim["modelRows"] as? String) == "all"
let modelRows = (stim["modelRows"] as? [String]) ?? []
let fixtureId = (stim["fixtureId"] as? String) ?? "F1"
// Steps whose effect lines are not compared (stimulus.json `ignoreEffectsInSteps`, each with a documented reason): F9 close.
let ignoreEffectsInSteps = Set((stim["ignoreEffectsInSteps"] as? [String]) ?? [])
let declaredEdges: [TEdge] = ((stim["declaredOrder"] as? [[String: String]]) ?? []).compactMap {
    guard let b = $0["before"], let a = $0["after"] else { return nil }
    return TEdge(before: b, after: a)
}

struct RawStep {
    var id: String, native: String
    var startNs: UInt64, endNs: UInt64
    var tree: RNode
    var closed = false      // the step closed the window: no tree is observable
    var focusedIdentifier: String?
    var focusRole: String?
    var selection: TRange?
}

func macNode(_ d: [String: Any]) -> RNode {
    var n = RNode(role: d["role"] as? String ?? "?", subrole: d["subrole"] as? String, id: d["identifier"] as? String,
                  title: d["title"] as? String, label: d["label"] as? String, value: d["value"] as? String)
    n.settable = d["valueSettable"] as? Bool ?? false
    n.actions = d["actions"] as? [String] ?? []
    n.children = (d["children"] as? [[String: Any]] ?? []).map(macNode)
    return n
}

func winNode(_ d: [String: Any]) -> RNode {
    var n = RNode(role: d["controlType"] as? String ?? "?", subrole: nil, id: d["automationId"] as? String,
                  title: nil, label: d["name"] as? String, value: d["value"] as? String)
    n.actions = d["patterns"] as? [String] ?? []
    n.hasFocus = d["hasFocus"] as? Bool ?? false
    n.children = (d["children"] as? [[String: Any]] ?? []).map(winNode)
    return n
}

var platform: TPlatform
var raw: [RawStep] = []
let mode = args[1]
if mode == "mac" {
    guard let rawPath = arg("--raw") else { eprint("mac needs --raw"); exit(2) }
    let r = try json(rawPath) as! [String: Any]
    let p = r["platform"] as! [String: String]
    platform = TPlatform(os: p["os"]!, osBuild: p["osBuild"]!, arch: p["arch"]!, toolchain: p["toolchain"]!)
    for s in r["steps"] as! [[String: Any]] {
        let focus = s["focus"] as? [String: Any] ?? [:]
        var sel: TRange?
        if let o = focus["selection"] as? [String: Any] { sel = TRange(location: (o["location"] as! NSNumber).intValue, length: (o["length"] as! NSNumber).intValue) }
        raw.append(RawStep(id: s["id"] as! String, native: s["nativeMapping"] as! String,
                           startNs: (s["monoStartNs"] as! NSNumber).uint64Value, endNs: (s["monoEndNs"] as! NSNumber).uint64Value,
                           tree: (s["tree"] as? [String: Any]).map(macNode) ?? RNode(role: "AXApplication"),
                           closed: (s["closed"] as? Bool) ?? (s["tree"] == nil),
                           focusedIdentifier: (focus["identifier"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                           focusRole: focus["role"] as? String, selection: sel))
    }
} else if mode == "win" {
    guard let recPath = arg("--rec"), let sidePath = arg("--side") else { eprint("win needs --rec and --side"); exit(2) }
    let rec = try json(recPath) as! [String: Any]
    let side = try json(sidePath) as! [String: Any]
    let p = rec["platform"] as! [String: String]
    platform = TPlatform(os: p["os"]!, osBuild: p["osBuild"]!, arch: p["arch"]!, toolchain: p["toolchain"]!)
    let obs = rec["observations"] as! [[String: Any]]
    let steps = rec["steps"] as! [[String: Any]]
    let extras = side["steps"] as! [[String: Any]]
    for i in 0..<steps.count {
        var sel: TRange?
        if let o = obs[i]["selection"] as? [String: Any] { sel = TRange(location: (o["location"] as! NSNumber).intValue, length: (o["length"] as! NSNumber).intValue) }
        let tree = winNode(extras[i]["tree"] as! [String: Any])
        raw.append(RawStep(id: steps[i]["id"] as! String, native: steps[i]["nativeMapping"] as! String,
                           startNs: (extras[i]["monoStartNs"] as! NSNumber).uint64Value, endNs: (extras[i]["monoEndNs"] as! NSNumber).uint64Value,
                           tree: tree, closed: obs[i]["axNodes"] == nil || obs[i]["axNodes"] is NSNull,
                           focusedIdentifier: nil, focusRole: nil, selection: sel))
    }
} else { eprint("mode must be mac or win"); exit(2) }

guard raw.map(\.id) == stepOrder else { eprint("step ids \(raw.map(\.id)) differ from the stimulus \(stepOrder)"); exit(3) }

let events = try loadEvents(path: evPath)
let mapping = mapEvents(events, stepStarts: raw.map { ($0.id, $0.startNs) }, endNs: raw.last!.endNs)

var applied = Set<String>()
var steps: [TStep] = []
var observations: [TObservation] = []
for s in raw {
    let n = mode == "mac" ? Cross.normalizeMac(s.tree, opt) : Cross.normalizeWin(s.tree, opt)
    applied.formUnion(n.applied)
    // Focus: Mac reports the focused element's identifier; Windows marks the focused node in the tree.
    var focused: String?
    if mode == "mac" {
        if let f = s.focusedIdentifier, n.nodes.contains(where: { $0.id == f }) { focused = f }
    } else {
        focused = n.focusedId
    }
    if focused == "window" { focused = nil; applied.insert("A9") }   // A9: window-level focus == nothing focused
    var model: [String: String] = [:]
    let idents = modelRowsAll ? n.nodes.map(\.id).filter { $0.hasPrefix("row/") && $0.hasSuffix("/field") } : modelRows
    for ident in idents {
        if let node = n.nodes.first(where: { $0.id == ident }), let v = node.value {
            let key = ident.hasSuffix("/field") ? String(ident.dropLast("/field".count)) : ident
            model[key] = v
        }
    }
    let m = mapping.perStep[s.id] ?? MappedStep()
    steps.append(TStep(id: s.id, logicalAction: logicalById[s.id]!, nativeMapping: s.native, timestamp: "mono_ns \(s.startNs)"))
    observations.append(TObservation(stepId: s.id, model: s.closed ? [:] : model, focusedNodeId: s.closed ? nil : focused,
                                     selection: (s.closed || focused == nil) ? nil : s.selection,   // the selection belongs to the focused canonical node
                                     lifecycle: m.lifecycle, effects: ignoreEffectsInSteps.contains(s.id) ? [] : canonicalEffects(m.effects),
                                     axNodes: s.closed ? nil : n.nodes))
}

let trace = TTrace(fixtureId: fixtureId, sourceHash: sourceHash, platform: platform, steps: steps, observations: observations, declaredOrder: declaredEdges)
try encodePretty(trace).write(to: URL(fileURLWithPath: outPath))
let notes: [String: Any] = ["mode": mode, "keepLists": keepLists, "adaptationsApplied": applied.sorted(), "excludedEvents": mapping.excluded,
                            "eventCount": events.count, "sourceHash": sourceHash]
try JSONSerialization.data(withJSONObject: notes, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outPath + ".notes.json"))
print("wrote \(outPath) steps=\(steps.count) applied=\(applied.sorted()) excluded=\(mapping.excluded)")
