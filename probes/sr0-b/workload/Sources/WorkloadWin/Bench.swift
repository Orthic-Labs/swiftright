import Foundation
import SwiftRightRuntime
import SwiftRightBridge
import WorkloadCore

// Headless commit benchmark (R10 performance diagnosis). No window, no renderer, no GUI: the runtime and the WinBackend commit
// conversion run against a mock renderer surface, so the same `--bench` works on the Mac (WORKLOAD_FLAVOR=runtime) and on Windows.
//
//   WorkloadWin --bench [--rows 200] [--iters 60] [--verify] [--replay-s 6]
//
// Each scenario mutates the model the way the workload does, flushes through the backend, and reports wall time per commit
// (p50 / p95 / max) with the phase split: runtime evaluate, layout, diff, transactions, record resolution, backend walk,
// bridge submit, run release. The mock charges nothing for measure / commit marshalling (the real bridge costs ~8 us per
// measure call on the Dell), so counts of measure calls, cells calls and upserts are reported next to the times.
// `--verify` compares what the renderer would paint, hit-test and publish after incremental, flattened commits against a
// full-upsert reference (every node, every commit) after every commit. The mock enforces the renderer's commit validation
// (parents exist, ids unique across nodes and AX runs, limits) so a malformed incremental commit fails here, not on the Dell.

// MARK: layout-compatible constructors for bridge value types (their memberwise inits are internal to the bridge package)

private struct MirrorLine { var utf8Start: UInt32; var utf8Len: UInt32; var width: Float; var top: Float; var baseline: Float }
private struct MirrorCell {
    var utf8Offset: UInt32; var utf8Len: UInt32; var line: UInt32; var wordStart: Bool; var lineBreak: Bool; var x0: Float; var x1: Float
}
private struct MirrorMeasurement {
    var run: TextRunHandle; var width: Float; var height: Float; var firstBaseline: Float; var lastBaseline: Float
    var lines: [LineInfo]; var charCount: UInt32; var cacheHit: Bool; var cacheKey: UInt64
}

private func layoutsMatch() -> Bool {
    MemoryLayout<MirrorLine>.size == MemoryLayout<LineInfo>.size && MemoryLayout<MirrorLine>.alignment == MemoryLayout<LineInfo>.alignment
        && MemoryLayout<MirrorCell>.size == MemoryLayout<CharCell>.size && MemoryLayout<MirrorCell>.alignment == MemoryLayout<CharCell>.alignment
        && MemoryLayout<MirrorMeasurement>.size == MemoryLayout<SwiftRightBridge.TextMeasurement>.size
        && MemoryLayout<MirrorMeasurement>.alignment == MemoryLayout<SwiftRightBridge.TextMeasurement>.alignment
}

// MARK: mock renderer surface

/// A renderer stand-in: deterministic text shaping (fixed advance, greedy word wrap) and a shadow of the committed tree.
@MainActor
final class MockPlatform: BackendPlatform {
    struct ShadowNode: Equatable {
        var parent: UInt64
        var order: UInt32
        var flags: UInt32
        var bounds: [Float]
        var primitives: [String]
        var semantic: String
        var runIDs: [UInt64] = []
    }

    let scale: Float
    let widthPx: UInt32
    let heightPx: UInt32
    let verify: Bool
    private var nextRun: UInt64 = 1
    private var live = Set<UInt64>()
    private var runInfo: [UInt64: String] = [:]
    private(set) var shadow: [UInt64: ShadowNode] = [:]
    private(set) var shadowFocus: UInt64 = 0
    private(set) var lastVersion: UInt64 = 0
    private(set) var validationErrors: [String] = []

    private(set) var measureCalls = 0
    private(set) var cellsCalls = 0
    private(set) var releaseCalls = 0
    private(set) var commitCalls = 0
    private(set) var upsertTotal = 0
    private(set) var removeTotal = 0
    private(set) var primitiveTotal = 0
    private(set) var staleRunUse = 0
    private(set) var versionErrors = 0
    var liveRuns: Int { live.count }

    init(scaleDIP: Float = 2.5, widthDIP: UInt32 = 960, heightDIP: UInt32 = 640, verify: Bool) {
        scale = scaleDIP
        widthPx = UInt32(Float(widthDIP) * scaleDIP)
        heightPx = UInt32(Float(heightDIP) * scaleDIP)
        self.verify = verify
        precondition(layoutsMatch(), "bridge value type layout changed: update the Mirror* structs in Bench.swift")
    }

    func metrics() throws -> (width: UInt32, height: UInt32, scale: Float, active: Bool) { (widthPx, heightPx, scale, true) }
    func requestTicks(_ on: Bool) throws {}
    func requestClose() throws {}

    func measure(_ request: MeasureRequest) throws -> SwiftRightBridge.TextMeasurement {
        measureCalls += 1
        let advance = 8.4 * request.scale
        let lineH = request.lineHeight * request.scale
        var lines: [MirrorLine] = []
        let utf8 = Array(request.text.utf8)
        // Greedy word wrap on spaces at maxWidth (physical px), a '\n' always breaks.
        var start = 0
        var lineWidth: Float = 0
        var lastSpace = -1
        var i = 0
        func flush(_ end: Int, _ w: Float) {
            lines.append(MirrorLine(utf8Start: UInt32(start), utf8Len: UInt32(end - start), width: w,
                                    top: Float(lines.count) * lineH, baseline: Float(lines.count) * lineH + lineH * 0.75))
        }
        while i < utf8.count {
            let c = utf8[i]
            if c == 10 { flush(i, Float(i - start) * advance); start = i + 1; lastSpace = -1; i += 1; continue }
            if c == 32 { lastSpace = i }
            let w = Float(i + 1 - start) * advance
            if request.maxWidth > 0, w > request.maxWidth, i > start {
                let cut = lastSpace > start ? lastSpace + 1 : i
                flush(cut, Float(cut - start) * advance)
                start = cut
                lastSpace = -1
                i = cut
                continue
            }
            lineWidth = w
            i += 1
        }
        if start < utf8.count || lines.isEmpty { flush(utf8.count, lineWidth) }
        let handle = TextRunHandle(raw: nextRun)
        nextRun += 1
        live.insert(handle.raw)
        let width = lines.map(\.width).max() ?? 0
        if verify {
            runInfo[handle.raw] = "\"\(request.text)\"c\(request.color)mw\(request.maxWidth)w\(width)h\(Float(lines.count) * lineH)"
        }
        let m = MirrorMeasurement(run: handle, width: width, height: Float(lines.count) * lineH,
                                  firstBaseline: lineH * 0.75, lastBaseline: Float(max(0, lines.count - 1)) * lineH + lineH * 0.75,
                                  lines: unsafeBitCast(lines, to: [LineInfo].self),
                                  charCount: UInt32(request.text.count), cacheHit: false, cacheKey: 0)
        return unsafeBitCast(m, to: SwiftRightBridge.TextMeasurement.self)
    }

    func cells(of run: TextRunHandle) throws -> [CharCell] {
        cellsCalls += 1
        guard live.contains(run.raw) else { staleRunUse += 1; throw BridgeError.status(-6, "stale run") }
        // One cell per character of the run's text, fixed advance (the text is recovered from the verify table when present).
        let count = runInfo[run.raw].map { info -> Int in
            guard info.hasPrefix("\""), let end = info.range(of: "\"c", options: .backwards) else { return 0 }
            return info[info.index(after: info.startIndex)..<end.lowerBound].utf16.count
        } ?? 24
        var out: [MirrorCell] = []
        out.reserveCapacity(count)
        for k in 0..<count {
            out.append(MirrorCell(utf8Offset: UInt32(k), utf8Len: 1, line: 0, wordStart: k == 0, lineBreak: false,
                                  x0: Float(k) * 8.4 * scale, x1: Float(k + 1) * 8.4 * scale))
        }
        return unsafeBitCast(out, to: [CharCell].self)
    }

    @discardableResult
    func release(_ run: TextRunHandle) -> Bool {
        releaseCalls += 1
        return live.remove(run.raw) != nil
    }

    /// Applies a transaction the way the renderer does (swiftright-render/src/tree.rs `commit`): removes first, then upserts that
    /// replace a node, then the checks. Any failed check leaves the tree untouched (all or nothing).
    func commit(_ transaction: Transaction) throws {
        commitCalls += 1
        if transaction.version <= lastVersion { versionErrors += 1; throw BridgeError.status(-11, "stale version") }
        guard transaction.upserts.count <= 4096, transaction.removes.count <= 4096 else {
            validationErrors.append("limit: \(transaction.upserts.count) upserts, \(transaction.removes.count) removes")
            throw BridgeError.status(-8, "too large")
        }
        var primTotal = 0
        for u in transaction.upserts {
            primTotal += u.primitives.count
            for p in u.primitives { if case .text(let h, _, _) = p, !live.contains(h.raw) { staleRunUse += 1 } }
        }
        guard primTotal <= 65536 else { validationErrors.append("limit: \(primTotal) primitives"); throw BridgeError.status(-8, "too large") }
        guard verify else {
            lastVersion = transaction.version
            upsertTotal += transaction.upserts.count
            removeTotal += transaction.removes.count
            primitiveTotal += primTotal
            return
        }
        var staged = shadow
        var doomed = Set(transaction.removes)
        var grew = true
        while grew {
            grew = false
            for (id, node) in staged where !doomed.contains(id) && doomed.contains(node.parent) { doomed.insert(id); grew = true }
        }
        for id in doomed { staged[id] = nil }
        var seen = Set<UInt64>()
        for u in transaction.upserts {
            guard u.id != 0, seen.insert(u.id).inserted else { validationErrors.append("bad or repeated id \(u.id)"); throw BridgeError.status(-1, "bad id") }
            var prims: [String] = []
            for p in u.primitives {
                switch p {
                case .rect(let r, let c, let rad, let bc, let bw): prims.append("R(\(r.x),\(r.y),\(r.w),\(r.h),\(c),\(rad),\(bc),\(bw))")
                case .text(let h, let x, let y): prims.append("T(\(runInfo[h.raw] ?? "?"),\(x),\(y))")
                case .clipPush(let r): prims.append("CP(\(r.x),\(r.y),\(r.w),\(r.h))")
                case .clipPop: prims.append("CPOP")
                case .underline(let r, let c): prims.append("U(\(r.x),\(r.y),\(r.w),\(r.h),\(c))")
                default: prims.append("O")
                }
            }
            var sem = "-"
            var runIDs: [UInt64] = []
            if let s = u.semantic {
                let runs = s.runs.map { "\($0.id):\($0.text):\($0.bounds.x),\($0.bounds.y),\($0.bounds.w),\($0.bounds.h):\($0.charLengths):\($0.charPositions):\($0.charWidths):\($0.wordStarts)" }.joined(separator: ";")
                let sel = s.selection.map { "\($0.anchor.run).\($0.anchor.character)-\($0.focus.run).\($0.focus.character)" } ?? "-"
                sem = "\(s.role.rawValue)|\(s.label)|\(s.value)|\(s.actions.rawValue)|\(s.multiline)|\(s.identifier)|\(s.toggled.rawValue)|\(String(describing: s.selected))|\(s.disabled)|\(sel)|\(runs)"
                runIDs = s.runs.map(\.id)
            }
            staged[u.id] = ShadowNode(parent: u.parent, order: u.order, flags: u.flags.rawValue,
                                      bounds: [u.bounds.x, u.bounds.y, u.bounds.w, u.bounds.h], primitives: prims, semantic: sem,
                                      runIDs: runIDs)
        }
        // The renderer's checks: parents exist and chains reach the root; node ids and AX run ids share one namespace; the focus
        // target exists.
        var ids = Set<UInt64>()
        for (id, node) in staged {
            var cur = node.parent
            var hops = 0
            while cur != 0 {
                guard let p = staged[cur], hops <= 256 else { validationErrors.append("node \(id): parent \(cur) missing or cycle"); throw BridgeError.status(-12, "not found") }
                cur = p.parent
                hops += 1
            }
            if !ids.insert(id).inserted { validationErrors.append("duplicate id \(id)"); throw BridgeError.status(-1, "dup") }
        }
        for (_, node) in staged {
            for r in node.runIDs where r == 0 || !ids.insert(r).inserted {
                validationErrors.append("AX run id \(r) collides"); throw BridgeError.status(-1, "dup run")
            }
        }
        if transaction.focus != 0, staged[transaction.focus] == nil { validationErrors.append("focus \(transaction.focus) missing"); throw BridgeError.status(-12, "focus") }
        shadow = staged
        shadowFocus = transaction.focus
        lastVersion = transaction.version
        upsertTotal += transaction.upserts.count
        removeTotal += transaction.removes.count
        primitiveTotal += primTotal
    }

    func stats() -> StatsSnap {
        var s = StatsSnap()
        s.paints = UInt64(commitCalls)
        s.commitsAccepted = UInt64(commitCalls)
        s.liveNodes = UInt64(shadow.count + live.count)
        return s
    }

    /// What the renderer shows from this tree, in paint order: for each node that paints, speaks or takes input, its id, bounds,
    /// flags, primitives, semantics and nearest semantic ancestor. Structure nodes (no primitives, no semantics, no flags) are
    /// not part of it: the renderer never reads them, so a tree without them is the same tree.
    func effective() -> [String] {
        var children: [UInt64: [(UInt32, UInt64)]] = [:]
        for (id, n) in shadow { children[n.parent, default: []].append((n.order, id)) }
        for key in children.keys { children[key]!.sort { ($0.0, $0.1) < ($1.0, $1.1) } }
        var out: [String] = []
        func visit(_ id: UInt64, axParent: UInt64) {
            guard let n = shadow[id] else { return }
            let content = !n.primitives.isEmpty || n.semantic != "-" || n.flags != 0
            if content {
                out.append("\(id)|axparent=\(n.semantic != "-" ? axParent : 0)|\(n.bounds)|\(n.flags)|\(n.primitives)|\(n.semantic)")
            }
            let next = n.semantic != "-" ? id : axParent
            for (_, c) in children[id] ?? [] { visit(c, axParent: next) }
        }
        for (_, c) in children[0] ?? [] { visit(c, axParent: 0) }
        return out
    }

    /// First difference between what this tree shows and what `other`'s does, or nil when they show the same.
    func difference(from other: MockPlatform) -> String? {
        if shadowFocus != other.shadowFocus { return "focus \(shadowFocus) vs \(other.shadowFocus)" }
        let a = effective(), b = other.effective()
        if a.count != b.count { return "visible node count \(a.count) vs \(b.count)" }
        for (x, y) in zip(a, b) where x != y { return "visible node differs:\n  \(x)\n  \(y)" }
        return nil
    }
}

// MARK: statistics

private func pct(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p + 0.5))]
}

private func ms(_ ns: UInt64) -> Double { Double(ns) / 1_000_000 }

private struct Sample {
    var wallNS: UInt64 = 0
    var evaluateNS: UInt64 = 0
    var layoutNS: UInt64 = 0
    var diffNS: UInt64 = 0
    var transactionNS: UInt64 = 0
    var resolveNS: UInt64 = 0
    var walkNS: UInt64 = 0
    var removeNS: UInt64 = 0
    var submitNS: UInt64 = 0
    var releaseNS: UInt64 = 0
    var commits = 0
    var evaluations = 0
    var nodesWalked = 0
    var upserts = 0
    var primitives = 0
    var measures = 0
    var cells = 0
}

@MainActor
private final class BenchRig {
    let model: WorkloadModel
    let backend: WinBackend
    let platform: MockPlatform
    var graph: Graph { backend.graph! }
    var samples: [String: [Sample]] = [:]
    var order: [String] = []
    var syntheticNow: UInt64 = 1_000_000

    init(rows: Int, verify: Bool, quietSchedule: Bool, reuse: Bool = true, flatten: Bool = true) {
        var config = WorkloadConfig()
        config.totalRows = rows
        config.instr = .full
        if quietSchedule {
            config.opIntervalMS = 1e12
            config.reorderIntervalMS = 1e12
            config.animPeriodMS = 1e12
        }
        let recorder = RunRecorder()
        model = WorkloadModel(config: config, recorder: recorder)
        platform = MockPlatform(verify: verify)
        backend = WinBackend(platform: platform, model: model, recorder: recorder, config: config)
        backend.reuseUnchangedNodes = reuse
        backend.flattenStructure = flatten
        backend.ready()
        graph.profile = GraphProfile()
    }

    /// Runs `body`, which must end in a flush or tick, and records the deltas as one sample of `name`.
    func measure(_ name: String, _ body: () -> Void) {
        let p0 = graph.profile ?? GraphProfile()
        let t0 = backend.times
        let m0 = platform.measureCalls, c0 = platform.cellsCalls
        let start = WClock.ticks()
        body()
        let wall = WClock.ticks() &- start
        let p1 = graph.profile ?? GraphProfile()
        let t1 = backend.times
        var s = Sample()
        func tn(_ t: UInt64) -> UInt64 { t &* 1_000_000_000 / WClock.hz }
        s.wallNS = tn(wall)
        s.evaluateNS = p1.evaluateNS &- p0.evaluateNS
        s.layoutNS = p1.layoutNS &- p0.layoutNS
        s.diffNS = p1.diffNS &- p0.diffNS
        s.transactionNS = p1.transactionNS &- p0.transactionNS
        s.resolveNS = p1.resolveNS &- p0.resolveNS
        s.walkNS = tn(t1.walkTicks &- t0.walkTicks)
        s.removeNS = tn(t1.removeTicks &- t0.removeTicks)
        s.submitNS = tn(t1.submitTicks &- t0.submitTicks)
        s.releaseNS = tn(t1.releaseTicks &- t0.releaseTicks)
        s.commits = t1.commits - t0.commits
        s.evaluations = p1.evaluations - p0.evaluations
        s.nodesWalked = t1.nodesWalked - t0.nodesWalked
        s.upserts = t1.upserts - t0.upserts
        s.primitives = t1.primitives - t0.primitives
        s.measures = platform.measureCalls - m0
        s.cells = platform.cellsCalls - c0
        if samples[name] == nil { order.append(name) }
        samples[name, default: []].append(s)
    }

    /// Advances the synthetic clock by one 60 Hz frame and runs the backend tick (model schedule, scroll, flush, animations).
    func tick() {
        syntheticNow &+= WClock.hz / 60
        let ns = UInt64(WClock.seconds(syntheticNow) * 1_000_000_000)
        backend.tick(timestampNS: ns, nowTicks: syntheticNow)
    }

    func report() {
        func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
        }
        func left(_ text: String, _ width: Int) -> String {
            text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
        }
        func f(_ value: Double, _ width: Int, _ digits: Int = 2) -> String {
            let scale = pow(10.0, Double(digits))
            let rounded = (value * scale).rounded() / scale
            var text = "\(rounded)"
            if let dot = text.firstIndex(of: ".") {
                let have = text.distance(from: dot, to: text.endIndex) - 1
                if have < digits { text += String(repeating: "0", count: digits - have) }
            } else {
                text += "." + String(repeating: "0", count: digits)
            }
            return pad(text, width)
        }
        print(left("scenario", 26) + pad("n", 4) + pad("p50ms", 9) + pad("p95ms", 9) + pad("maxms", 9) + " | "
              + ["eval", "layout", "diff", "txn", "resolve"].map { pad($0, 7) }.joined() + " | "
              + ["walk", "remv", "submit", "relse"].map { pad($0, 7) }.joined() + " | "
              + ["evals", "walked", "upsrt", "meas", "cells"].map { pad($0, 7) }.joined())
        for name in order {
            let rows = samples[name] ?? []
            let wall = rows.map { ms($0.wallNS) }.sorted()
            func mean(_ f: (Sample) -> UInt64) -> Double { rows.isEmpty ? 0 : rows.map { ms(f($0)) }.reduce(0, +) / Double(rows.count) }
            func meanI(_ f: (Sample) -> Int) -> Double { rows.isEmpty ? 0 : Double(rows.map(f).reduce(0, +)) / Double(rows.count) }
            print(left(name, 26) + pad("\(rows.count)", 4) + f(pct(wall, 0.5), 9) + f(pct(wall, 0.95), 9) + f(wall.last ?? .nan, 9) + " | "
                  + [mean(\.evaluateNS), mean(\.layoutNS), mean(\.diffNS), mean(\.transactionNS), mean(\.resolveNS)].map { f($0, 7) }.joined() + " | "
                  + [mean(\.walkNS), mean(\.removeNS), mean(\.submitNS), mean(\.releaseNS)].map { f($0, 7) }.joined() + " | "
                  + [meanI(\.evaluations), meanI(\.nodesWalked), meanI(\.upserts), meanI(\.measures), meanI(\.cells)].map { pad("\(Int($0.rounded()))", 7) }.joined())
        }
    }
}

// MARK: scenarios (shared by the benchmark and the verification pass)

private let longDetail = "queued for review"

/// A UUID string `<prefix>-0000-4000-8000-<12 digits>` for a bench row.
private func benchID(_ prefix: String, _ slot: Int) -> String {
    let digits = String(slot)
    return "\(prefix)-0000-4000-8000-" + String(repeating: "0", count: max(0, 12 - digits.count)) + digits
}

@MainActor
private func detailText(slot: Int, version: Int) -> String {
    version % 2 == 0
        ? "Item \(slot) ready (v\(version))"
        : "Item \(slot) \(longDetail) (v\(version)): this longer description wraps onto several lines at the narrow column width and onto fewer at the wide one."
}

/// Every mutation the workload performs, as a closure over the model; each ends with `flushIfDirty`.
@MainActor
private enum Mutation {
    static func keystroke(_ rig: BenchRig, _ n: Int) {
        rig.model.userEdit(rig.model.active.id, String(repeating: "m", count: n % 40 + 1) + "|\(n)")
        rig.backend.markDirty()
        rig.backend.flushIfDirty()
    }

    static func rowUpdate(_ rig: BenchRig, _ n: Int) {
        let m = rig.model
        let index = (n * 37 + 11) % m.rows.count
        let slot = m.rows[index].slot
        m.rows[index].detail = detailText(slot: slot, version: n + 1)
        m.rows[index].text = "Row \(slot) updated \(n)"
        rig.backend.markDirty()
        rig.backend.flushIfDirty()
    }

    static func reorder(_ rig: BenchRig, _ n: Int) {
        let m = rig.model
        let source = (n * 53 + 7) % m.rows.count
        var destination = (n * 29 + 90) % (m.rows.count + 1)
        if destination == source || destination == source + 1 { destination = (source + 5) % (m.rows.count + 1) }
        let item = m.rows.remove(at: source)
        m.rows.insert(item, at: min(max(destination > source ? destination - 1 : destination, 0), m.rows.count))
        rig.backend.markDirty()
        rig.backend.flushIfDirty()
    }

    /// Moves keyboard focus to a row's field (caret appears there, leaves the previous field).
    static func focusMove(_ rig: BenchRig, _ n: Int) {
        let m = rig.model
        let target = n % 3 == 0 ? m.activeID : m.rows[(n * 11 + 5) % m.rows.count].id
        m.focusSetter?(target)
        rig.backend.markDirty()
        rig.backend.flushIfDirty()
    }

    /// Input-method edits on the active field through the text-store entry points the renderer calls: compose, mark, commit.
    static func imeEdit(_ rig: BenchRig, _ n: Int) {
        guard let fieldID = rig.graph.ids(ofKind: "TextField").first, let instance = rig.graph.nodeInstance(fieldID) else { return }
        let node = UInt64(instance) + 1
        let composed = Array("ni\(n % 7)".utf16)
        switch n % 3 {
        case 0: _ = rig.backend.storeReplaceAndMark(node: node, range: nil, text: composed, newSelection: nil)
        case 1: _ = rig.backend.storeUnmark(node: node)
        default: _ = rig.backend.storeReplace(node: node, range: nil, text: Array("z".utf16))
        }
    }

    /// Insert a fresh row at a position and drop an unrelated one (fixed-size data), unanimated.
    static func insertRemove(_ rig: BenchRig, _ n: Int) {
        let m = rig.model
        let slot = 10_000 + n
        let row = Row(id: UUID(uuidString: benchID("7C0A0000", slot))!, slot: slot,
                      text: "Engine \(n)", detail: detailText(slot: slot, version: 0))
        let index = (n * 41 + 3) % (m.rows.count + 1)
        m.rows.insert(row, at: index)
        m.rows.remove(at: (index + 60) % m.rows.count == index ? 0 : (index + 60) % m.rows.count)
        rig.backend.markDirty()
        rig.backend.flushIfDirty()
    }

    /// Animated insert at the top plus an unrelated removal, then the frames of the 0.4 s animation. Returns nothing; each
    /// frame is its own sample under `name` ("animated insert" for the mutation frame, "animation frame" for the ticks).
    static func animatedInsert(_ rig: BenchRig, _ n: Int) {
        let m = rig.model
        let slot = 20_000 + n
        let row = Row(id: UUID(uuidString: benchID("7C0B0000", slot))!, slot: slot,
                      text: "Anim \(n)", detail: detailText(slot: slot, version: 0))
        rig.measure("animated insert (mutation)") {
            withAnimation(.easeInOut(duration: 0.4), {
                m.rows.insert(row, at: 0)
                m.rows.remove(at: m.rows.count / 2)
            })
            rig.backend.markDirty()
            rig.backend.flushIfDirty()
        }
        for _ in 0..<28 { rig.measure("animation frame (tick)") { rig.tick() } }
    }
}

// MARK: entry points

@MainActor
func runBench(arguments: [String: String]) -> Int32 {
    let rows = Int(arguments["rows"] ?? "") ?? 200
    let iters = Int(arguments["iters"] ?? "") ?? 60
    let verify = arguments["verify"] != nil
    let reuse = arguments["no-reuse"] == nil
    let flatten = arguments["no-flatten"] == nil

    if verify { return runVerify(rows: rows, iters: max(iters, 40)) }

    let rig = BenchRig(rows: rows, verify: false, quietSchedule: true, reuse: reuse, flatten: flatten)
    print("BENCH rows=\(rows) iters=\(iters) reuse=\(reuse) flatten=\(flatten) clock=\(WClock.name) hz=\(WClock.hz) nodes=\(rig.graph.profile?.liveNodes ?? 0)")
    // first full commit (the ready() flushes already ran; force one more full evaluation by a root environment change)
    rig.measure("full re-evaluation") {
        rig.graph.setRootEnvironment { $0.accessibilityReduceMotion = false }
        rig.backend.markDirty()
        rig.backend.flushIfDirty()
    }
    for n in 0..<5 { Mutation.keystroke(rig, n); Mutation.rowUpdate(rig, n) }   // warm-up
    rig.samples.removeAll(); rig.order.removeAll()
    rig.measure("full re-evaluation") {
        rig.graph.setRootEnvironment { $0.accessibilityReduceMotion = false }
        rig.backend.markDirty()
        rig.backend.flushIfDirty()
    }
    let only = arguments["only"]
    func wants(_ key: String) -> Bool { only == nil || only == key }
    if wants("keystroke") { for n in 0..<iters { rig.measure("keystroke (active field)") { Mutation.keystroke(rig, n + 100) } } }
    if wants("row") { for n in 0..<iters { rig.measure("row update (1 row)") { Mutation.rowUpdate(rig, n) } } }
    if wants("reorder") { for n in 0..<iters { rig.measure("reorder (1 row moved)") { Mutation.reorder(rig, n) } } }
    if wants("insert") { for n in 0..<iters { rig.measure("insert + remove") { Mutation.insertRemove(rig, n) } } }
    if wants("tick") { for _ in 0..<iters { rig.measure("idle tick (scroll only)") { rig.tick() } } }
    if wants("anim") { for n in 0..<max(3, iters / 20) { Mutation.animatedInsert(rig, n) } }
    rig.report()
    if let hold = ProcessInfo.processInfo.environment["BENCH_HOLD"].flatMap(Double.init) {
        print("BENCH holding for \(hold) s (pid \(ProcessInfo.processInfo.processIdentifier))")
        fflush(stdout)
        Thread.sleep(forTimeInterval: hold)
    }
    print("mock renderer: runs live=\(rig.platform.liveRuns) stale-run-use=\(rig.platform.staleRunUse) version-errors=\(rig.platform.versionErrors) commits=\(rig.platform.commitCalls) upserts=\(rig.platform.upsertTotal) removes=\(rig.platform.removeTotal)")
    return rig.platform.staleRunUse == 0 && rig.platform.versionErrors == 0 ? 0 : 1
}

/// Two backends fed by identical model replays: one sends every node every commit (the reference), one sends only changed
/// content nodes, flat. After every commit the two mock renderers must show the same thing (paint order, bounds, primitives,
/// semantics, focus), and the subject's trees must pass the renderer's own commit validation.
@MainActor
private func runVerify(rows: Int, iters: Int) -> Int32 {
    let reference = BenchRig(rows: rows, verify: true, quietSchedule: true, reuse: false, flatten: false)
    let subject = BenchRig(rows: rows, verify: true, quietSchedule: true, reuse: true, flatten: true)
    var failures = 0
    var checks = 0
    func check(_ label: String) {
        checks += 1
        if let d = subject.platform.difference(from: reference.platform), failures < 8 {
            failures += 1
            print("VERIFY FAIL after \(label): \(d)")
        } else if subject.platform.difference(from: reference.platform) != nil {
            failures += 1
        }
    }
    check("ready")
    let steps: [(String, (BenchRig, Int) -> Void)] = [
        ("keystroke", Mutation.keystroke), ("row update", Mutation.rowUpdate), ("reorder", Mutation.reorder),
        ("insert+remove", Mutation.insertRemove), ("focus", Mutation.focusMove), ("ime", Mutation.imeEdit),
    ]
    for n in 0..<iters {
        for (label, step) in steps {
            step(reference, n); step(subject, n)
            check("\(label) #\(n)")
        }
        for _ in 0..<2 { reference.tick(); subject.tick(); check("tick #\(n)") }
    }
    for n in 0..<3 {
        Mutation.animatedInsert(reference, n); Mutation.animatedInsert(subject, n)
        check("animated insert #\(n)")
    }
    for _ in 0..<40 { reference.tick(); subject.tick() }
    check("after animations")
    // resize: a narrower window flips the layout to one column, a wider one back to two
    for (w, h) in [(500, 640), (960, 640), (700, 400)] as [(UInt32, UInt32)] {
        for rig in [reference, subject] {
            rig.backend.applyMetricsForBench(widthPx: UInt32(Float(w) * rig.platform.scale), heightPx: UInt32(Float(h) * rig.platform.scale))
            rig.backend.flushIfDirty()
        }
        check("resize \(w)x\(h)")
    }
    // teardown: every run handle must be released and the tree emptied
    for rig in [reference, subject] { rig.backend.closed() }
    let leaked = subject.platform.liveRuns
    let invalid = subject.platform.validationErrors + reference.platform.validationErrors
    print("VERIFY checks=\(checks) failures=\(failures) subject: commits=\(subject.platform.commitCalls) upserts=\(subject.platform.upsertTotal) (reference upserts=\(reference.platform.upsertTotal)) measures=\(subject.platform.measureCalls) (reference \(reference.platform.measureCalls)) live runs after close=\(leaked) stale-run-use=\(subject.platform.staleRunUse) validation-errors=\(invalid.count)\(invalid.first.map { " first=" + $0 } ?? "")")
    return failures == 0 && leaked == 0 && subject.platform.staleRunUse == 0 && invalid.isEmpty ? 0 : 1
}
