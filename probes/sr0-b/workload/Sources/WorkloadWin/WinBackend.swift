import Foundation
import SwiftRightRuntime
import SwiftRightBridge
import WorkloadCore
#if os(Windows)
import func WinSDK.IsDebuggerPresent
#endif

// WinBackend: the SR0 workload on the fresh runtime and the real renderer through bridge ABI 0.6, instrumented.
// Commit conversion, text store and event path follow probes/sr0-s/fresh-on-bridge/BridgeBackend.swift (same full-upsert
// design, no culling, no diffing: the workload measures the bridge as the SDK would use it). Additions:
//
//   * BridgeClock: every LEAF bridge call (measure, cells, release, commit, stats) is timed once; nothing nests, so
//     per-frame and per-input bridge time never double-counts. Event pop and callback dispatch inside the Bridge
//     package are not wrappable without editing it and are excluded (documented in RUNBOOK.md).
//   * per-frame samples (frames.csv): bridge time since the previous commit, measure calls, upserts, renderer paint count.
//   * per-input samples (bridge_input.csv): handler time and bridge time of each keystroke text-store call.
//   * commit stamps for the visible-response join: after each accepted commit, inputs received since the last commit
//     get (commit QPC, renderer paint counter). Every paint after that counter includes the response (the renderer
//     paints and commits on the one UI thread), so the first PresentMon present from that paint on is the response frame.
//   * ticks.csv: every display tick with the renderer's own QPC timestamp and paint counter (the QPC-to-present map).

enum WStyle {
    static let fontFamily = "Segoe UI"
    static let fontSizeDIP: Float = 16
    static let lineHeightDIP: Float = 24
    static let textColor: UInt32 = 0x1F1F1FFF
    static let fieldFill: UInt32 = 0xFFFFFFFF
    static let fieldBorder: UInt32 = 0x888888FF
    static let caretColor: UInt32 = 0x111111FF
    static let fieldInsetX: Float = 6
    static let runBlock: UInt64 = 32
}

func fadedColor(_ color: UInt32, _ opacity: Double) -> UInt32 {
    let clamped = min(max(opacity, 0), 1)
    let alpha = UInt32((Double(color & 0xFF) * clamped).rounded())
    return (color & 0xFFFFFF00) | alpha
}

/// Renderer counters (swr_stats) copied by value; the C type itself is not importable from this target.
struct StatsSnap {
    var paints: UInt64 = 0, commitsAccepted: UInt64 = 0, commitsRejected: UInt64 = 0, commitsDeferred: UInt64 = 0
    var measureCalls: UInt64 = 0, measureCacheHits: UInt64 = 0, ticksDelivered: UInt64 = 0
    var hostPanics: UInt64 = 0, reentryRefused: UInt64 = 0, threadViolations: UInt64 = 0
    var eventsDroppedFull: UInt64 = 0, liveNodes: UInt64 = 0
}

extension Bridge {
    func statsSnap() -> StatsSnap {
        let s = stats()
        return StatsSnap(paints: s.paints, commitsAccepted: s.commits_accepted, commitsRejected: s.commits_rejected,
                         commitsDeferred: s.commits_deferred, measureCalls: s.measure_calls,
                         measureCacheHits: s.measure_cache_hits, ticksDelivered: s.ticks_delivered,
                         hostPanics: s.host_panics, reentryRefused: s.reentry_refused,
                         threadViolations: s.thread_violations, eventsDroppedFull: s.events_dropped_full,
                         liveNodes: s.live_nodes)
    }
}

/// Accumulates the duration of leaf bridge calls.
final class BridgeClock {
    let enabled: Bool
    private(set) var totalTicks: UInt64 = 0
    private(set) var calls = 0
    private(set) var measureCalls = 0

    init(enabled: Bool) { self.enabled = enabled }

    @inline(__always)
    func time<T>(measure: Bool = false, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let s = WClock.ticks()
        defer {
            totalTicks &+= WClock.ticks() &- s
            calls += 1
            if measure { measureCalls += 1 }
        }
        return try body()
    }

    var totalNS: UInt64 { totalTicks &* 1_000_000_000 / WClock.hz }
}

@MainActor
final class BridgeTextMeasurer: TextMeasurer {
    let bridge: Bridge
    let scale: Float
    let clock: BridgeClock
    private(set) var failures = 0
    private(set) var lastError = ""

    init(bridge: Bridge, scale: Float, clock: BridgeClock) {
        self.bridge = bridge
        self.scale = scale
        self.clock = clock
    }

    func measure(_ request: TextMeasureRequest) -> SwiftRightRuntime.TextMeasurement {
        guard !request.text.isEmpty else {
            return SwiftRightRuntime.TextMeasurement(size: .zero, baseline: 0, lineCount: 0)
        }
        let maxWidth = Float(request.proposedWidth ?? 0) * scale
        do {
            let m = try clock.time(measure: true) {
                try bridge.measure(MeasureRequest(
                    text: request.text, fontFamily: WStyle.fontFamily,
                    fontSize: WStyle.fontSizeDIP, lineHeight: WStyle.lineHeightDIP,
                    scale: scale, maxWidth: maxWidth))
            }
            clock.time { _ = bridge.release(m.run) }
            return SwiftRightRuntime.TextMeasurement(
                size: LayoutSize(width: CGFloat(m.width / scale), height: CGFloat(m.height / scale)),
                baseline: CGFloat(m.firstBaseline / scale),
                lineCount: m.lineCount)
        } catch {
            failures += 1
            lastError = "\(error)"
            let lines = max(1, request.text.split(separator: " ").count)
            return SwiftRightRuntime.TextMeasurement(
                size: LayoutSize(width: CGFloat(request.text.count) * 8, height: CGFloat(lines) * 24),
                baseline: 18, lineCount: lines)
        }
    }
}

struct FieldGeometry {
    let origin: (x: Float, y: Float)
    let cells: [CharCell]
    let lines: [LineInfo]
    let lineHeightPx: Float
}

func rowUUID(in runtimeID: String) -> UUID? {
    for part in runtimeID.split(separator: "[").dropFirst() {
        if let end = part.firstIndex(of: "]"), let uuid = UUID(uuidString: String(part[..<end])) {
            return uuid
        }
    }
    return nil
}

func runtimeRange(_ span: UTF16Span) -> UTF16Range {
    UTF16Range(location: Int(span.start), length: max(0, Int(span.end) - Int(span.start)))
}

func bridgeSpan(_ range: UTF16Range) -> UTF16Span {
    UTF16Span(start: UInt32(range.location), end: UInt32(range.location + range.length))
}

@MainActor
final class WinBackend {
    let bridge: Bridge
    let model: WorkloadModel
    let recorder: RunRecorder
    let config: WorkloadConfig
    let clock: BridgeClock
    private(set) var window: BridgeWindow?
    private(set) var graph: Graph?
    private(set) var measurer: BridgeTextMeasurer?
    private(set) var scale: Float = 1
    private var version: UInt64 = 0
    private var nextID: UInt64 = 1
    private var idByKey: [String: UInt64] = [:]
    private var liveParent: [UInt64: UInt64] = [:]
    private var dirty = false

    // rebuilt every commit
    private var runtimeFieldByBridge: [UInt64: String] = [:]
    private var rowByBridgeField: [UInt64: UUID] = [:]
    private var fieldGeometry: [UInt64: FieldGeometry] = [:]
    private var scrollNodeID: String?
    private var scrollMax: CGFloat = 0
    private var focusedField: UInt64 = 0

    // bookkeeping
    private(set) var commitCount = 0
    private(set) var commitErrors: [String] = []
    private(set) var drawFailures = 0
    private(set) var lastDrawError = ""
    private(set) var tickCount = 0
    private(set) var commitsAfterClose = 0
    private(set) var closedFlag = false
    private(set) var closeRequested = false
    private(set) var maxUpserts = 0
    private(set) var maxPrimitives = 0
    private(set) var scaleChanges = 0
    private var inTick = false
    private var lastFrameTotal: UInt64 = 0
    private var lastFrameMeasures = 0
    private var lastFrameEndTicks: UInt64 = 0
    var statsAtReady: StatsSnap?
    var onFinished: (() -> Void)?

    init(bridge: Bridge, model: WorkloadModel, recorder: RunRecorder, config: WorkloadConfig) {
        self.bridge = bridge
        self.model = model
        self.recorder = recorder
        self.config = config
        self.clock = BridgeClock(enabled: config.instr == .full)
    }

    // MARK: lifecycle

    func ready(_ win: BridgeWindow) {
        window = win
        do {
            let metrics = try win.metrics()
            scale = metrics.scale
            let meas = BridgeTextMeasurer(bridge: bridge, scale: scale, clock: clock)
            measurer = meas
            let g = Graph(WorkloadRoot(model: model), measurer: meas, scale: CGFloat(scale))
            g.rootProposal = proposal(width: metrics.width, height: metrics.height)
            g.setRootEnvironment { $0.accessibilityReduceMotion = false }
            g.commitSink = { [weak self] record in
                MainActor.assumeIsolated { self?.commit(record) }
            }
            graph = g
            model.onMutate = { [weak self] in
                MainActor.assumeIsolated { self?.dirty = true }
            }
            try win.requestTicks(true)
            statsAtReady = bridge.statsSnap()
            g.flush()
            model.focusActive()
            g.flush()
            recorder.meta["scale"] = String(scale)
            #if os(Windows)
            recorder.meta["debugger_present"] = String(IsDebuggerPresent())
            #endif
            recorder.meta["width_px"] = String(metrics.width)
            recorder.meta["height_px"] = String(metrics.height)
            recorder.meta["window_active_at_ready"] = String(metrics.active)
            OverheadBench.run(into: recorder)
            print("WORKLOAD-WIN-READY scale=\(scale) px=\(metrics.width)x\(metrics.height) hz=\(WClock.hz)")
            fflush(stdout)
        } catch {
            commitErrors.append("ready: \(error)")
            print("WORKLOAD-WIN-READY-FAILED \(error)")
        }
    }

    private func proposal(width: UInt32, height: UInt32) -> ProposedViewSize {
        ProposedViewSize(width: CGFloat(width) / CGFloat(scale), height: CGFloat(height) / CGFloat(scale))
    }

    /// Display tick: the renderer's QPC timestamp of the presented frame that asked.
    func tick(timestampNS: UInt64) {
        tickCount += 1
        let now = WClock.ticks()
        if !closedFlag {
            let s = bridge.stats()
            recorder.addTick(.init(tsNS: timestampNS, rxTicks: now, paints: s.paints, commits: s.commits_accepted))
        }
        guard let graph, !closedFlag else { return }
        model.advance(nowTicks: now)
        if let id = scrollNodeID {
            graph.scroll(id, to: CGFloat(model.scrollPhase) * scrollMax)
            dirty = true
        }
        flushIfDirty()
        inTick = true
        graph.tick(now: Double(timestampNS) / 1_000_000_000)
        inTick = false
        if !closeRequested, model.phase(nowTicks: now) == .finished {
            closeRequested = true
            try? window?.requestClose()
        }
    }

    func closed() {
        closedFlag = true
        model.close()
        graph?.tearDown()
        window = nil
        graph = nil
        measurer = nil
        pumpStart = WClock.ticks()
        postClosePump(hops: 0)
    }

    private var pumpStart: UInt64 = 0
    private(set) var liveNodesAtPump: UInt64 = 0
    private(set) var pumpHops = 0

    /// Hops the main queue (the post-close pump, ABI rev 0.5) while late results run into the closed guard, then finishes.
    private func postClosePump(hops: Int) {
        pumpHops = hops
        let live = bridge.stats().live_nodes
        liveNodesAtPump = live
        let elapsed = WClock.seconds(WClock.ticks() &- pumpStart)
        let settled = elapsed > 0.5 && live == 0 && model.enginePending == 0
        if settled || elapsed > 3.0 {
            onFinished?()
            return
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.postClosePump(hops: hops + 1) } }
    }

    func flushIfDirty() {
        guard dirty, let graph else { return }
        dirty = false
        graph.flush()
    }

    // MARK: runtime -> bridge

    private func bridgeID(_ key: String) -> UInt64 {
        if let id = idByKey[key] { return id }
        let id = nextID
        nextID += 1
        idByKey[key] = id
        return id
    }

    private func runBlock(_ key: String) -> UInt64 {
        if let base = idByKey["\(key)#runs"] { return base }
        let base = nextID
        nextID += WStyle.runBlock
        idByKey["\(key)#runs"] = base
        return base
    }

    private func inflate(_ r: Rect, dx: Float, dy: Float) -> Rect {
        Rect(x: r.x - dx, y: r.y - dy, w: r.w + 2 * dx, h: r.h + 2 * dy)
    }

    private func measure(_ text: String, color: UInt32, maxWidth: Float, into releasable: inout [TextRunHandle]) -> SwiftRightBridge.TextMeasurement? {
        do {
            let m = try clock.time(measure: true) {
                try bridge.measure(MeasureRequest(
                    text: text, fontFamily: WStyle.fontFamily, color: color,
                    fontSize: WStyle.fontSizeDIP, lineHeight: WStyle.lineHeightDIP,
                    scale: scale, maxWidth: maxWidth))
            }
            releasable.append(m.run)
            return m
        } catch {
            drawFailures += 1
            lastDrawError = "\(error)"
            return nil
        }
    }

    func commit(_ record: CommitRecord) {
        guard let window, !closedFlag else {
            if closedFlag, record.root != nil {
                commitsAfterClose += 1
                model.noteCommitAfterClose()
            }
            return
        }
        guard let root = record.root else { return }
        let startTicks = WClock.ticks()
        runtimeFieldByBridge = [:]
        rowByBridgeField = [:]
        fieldGeometry = [:]
        scrollNodeID = nil
        focusedField = 0

        var upserts: [NodeUpsert] = []
        var parents: [UInt64: UInt64] = [:]
        var releasable: [TextRunHandle] = []
        walk(root, parent: 0, order: 0, record: record, clip: nil, upserts: &upserts, parents: &parents, releasable: &releasable)

        var removes: [UInt64] = []
        for (id, parent) in liveParent where parents[id] == nil {
            if parent == 0 || parents[parent] != nil { removes.append(id) }
        }
        version += 1
        let transaction = Transaction(version: version, focus: focusedField, upserts: upserts, removes: removes)
        maxUpserts = max(maxUpserts, upserts.count)
        maxPrimitives = max(maxPrimitives, upserts.reduce(0) { $0 + $1.primitives.count })
        var accepted = false
        do {
            try clock.time { try window.commit(transaction) }
            commitCount += 1
            liveParent = parents
            accepted = true
        } catch {
            commitErrors.append("commit v\(version): \(error)")
        }
        let endTicks = WClock.ticks()
        for handle in releasable { clock.time { _ = bridge.release(handle) } }
        if accepted {
            let paints = bridge.stats().paints
            if recorder.hasUnstamped {
                recorder.stampCommit(ticks: endTicks, paints: paints, version: version)
            }
            if config.instr == .full {
                let total = clock.totalTicks
                recorder.addFrame(.init(
                    version: version, startTicks: startTicks, endTicks: endTicks,
                    bridgeNS: (total &- lastFrameTotal) &* 1_000_000_000 / WClock.hz,
                    measureCalls: clock.measureCalls - lastFrameMeasures,
                    upserts: upserts.count, paints: paints))
                lastFrameTotal = total
                lastFrameMeasures = clock.measureCalls
            }
        }
        lastFrameEndTicks = endTicks
    }

    private func walk(_ node: ResolvedNode, parent: UInt64, order: UInt32, record: CommitRecord, clip: Rect?,
                      upserts: inout [NodeUpsert], parents: inout [UInt64: UInt64], releasable: inout [TextRunHandle]) {
        let id = bridgeID(node.id)
        parents[id] = parent
        let pf = node.pixelFrame
        let s = scale
        let alpha = node.opacity
        var bounds = Rect(x: Float(pf.x), y: Float(pf.y), w: Float(pf.width), h: Float(pf.height))
        var prims: [Primitive] = []
        var semantic: SemanticNode?
        var flags: NodeFlags = []
        var childClip = clip

        switch node.kind {
        case "ScrollView":
            scrollNodeID = node.id
            if let content = node.children.first {
                scrollMax = max(0, content.frame.height - node.frame.height)
            }
            childClip = bounds

        case "Text":
            let text = node.text ?? ""
            if !text.isEmpty, let m = measure(text, color: fadedColor(WStyle.textColor, alpha),
                                             maxWidth: Float(pf.width) + 1, into: &releasable) {
                prims.append(.text(m.run, x: Float(pf.x), y: Float(pf.y)))
            }
            semantic = SemanticNode(role: .staticText, label: text)

        case "TextField":
            let text = node.text ?? ""
            let field = inflate(bounds, dx: WStyle.fieldInsetX * s, dy: 0)
            bounds = field
            prims.append(.rect(field, color: fadedColor(WStyle.fieldFill, alpha), radius: 3 * s,
                               borderColor: fadedColor(WStyle.fieldBorder, alpha), borderWidth: max(1, s)))
            let origin = (x: Float(pf.x), y: Float(pf.y))
            let lh = WStyle.lineHeightDIP * s
            let focused = record.focused.map { node.id == $0 || node.id.hasPrefix($0 + "/") } ?? false
            runtimeFieldByBridge[id] = node.id
            let row = rowUUID(in: node.id) ?? model.active.id
            rowByBridgeField[id] = row
            if focused { focusedField = id }
            var runs: [AXTextRun] = []
            var selection: (anchor: TextSelectionPosition, focus: TextSelectionPosition)?
            let runBase = runBlock(node.id)
            if !text.isEmpty, let m = measure(text, color: fadedColor(WStyle.textColor, alpha), maxWidth: 0, into: &releasable) {
                let cells = (try? clock.time { try bridge.cells(of: m.run) }) ?? []
                prims.append(.text(m.run, x: origin.x, y: origin.y))
                let caretEnd = node.selection.map { $0.location + $0.length } ?? text.utf16.count
                let caretIndex = min(caretEnd, cells.count)
                if focused {
                    let caretRectPx = caretRect(cells: cells, lines: m.lines, index: caretIndex, origin: origin,
                                                lineHeightPx: lh, width: max(1, 1.5 * s))
                    prims.append(.rect(caretRectPx, color: fadedColor(WStyle.caretColor, alpha)))
                }
                runs = makeAXTextRuns(text: text, measurement: m, cells: cells, origin: origin,
                                      lineHeightPx: lh, firstRunID: runBase)
                if !runs.isEmpty {
                    let line = caretIndex < cells.count ? Int(cells[caretIndex].line) : Int(cells.last?.line ?? 0)
                    let inLine = cells.prefix(caretIndex).filter { Int($0.line) == line }.count
                    let position = TextSelectionPosition(run: runBase + UInt64(min(line, runs.count - 1)), character: UInt32(inLine))
                    selection = (anchor: position, focus: position)
                }
                fieldGeometry[id] = FieldGeometry(origin: origin, cells: cells, lines: m.lines, lineHeightPx: lh)
            } else {
                fieldGeometry[id] = FieldGeometry(origin: origin, cells: [], lines: [], lineHeightPx: lh)
                runs = makeAXTextRuns(text: "", measurement: nil, cells: [], origin: origin, lineHeightPx: lh, firstRunID: runBase)
                if let first = runs.first {
                    let position = TextSelectionPosition(run: first.id, character: 0)
                    selection = (anchor: position, focus: position)
                }
            }
            let identifier = rowUUID(in: node.id) == nil ? "active/field" : "row/\(row.uuidString)/field"
            semantic = SemanticNode(role: .textField, label: "", value: text,
                                    actions: [.focus, .setValue, .setSelection], runs: runs, selection: selection,
                                    identifier: identifier)
            flags = [.hitTarget, .focusable, .editable]

        default:
            break
        }

        if let c = clip, !prims.isEmpty {
            prims = [.clipPush(c)] + prims + [.clipPop]
        }
        upserts.append(NodeUpsert(id: id, parent: parent, order: order, flags: flags, bounds: bounds,
                                  primitives: prims, semantic: semantic))
        for (index, child) in node.children.enumerated() {
            walk(child, parent: id, order: UInt32(index), record: record, clip: childClip,
                 upserts: &upserts, parents: &parents, releasable: &releasable)
        }
    }

    // MARK: bridge events -> runtime

    func handle(_ ev: BridgeEvent) {
        guard let kind = ev.kind else { return }
        switch kind {
        case .axAction:
            switch ev.axAction {
            case .focus?:
                if let row = rowByBridgeField[ev.node] { focusRow(row) }
            case .setValue?:
                if let row = rowByBridgeField[ev.node] { model.userEdit(row, ev.text) }
            default:
                break
            }
        case .pointer:
            if ev.action == 1, let row = rowByBridgeField[ev.node] { focusRow(row) }
        case .windowMetrics:
            applyMetrics(width: ev.i0, height: ev.i1, scale: ev.x)
        default:
            break
        }
        flushIfDirty()
    }

    private func focusRow(_ row: UUID) {
        model.focusSetter?(row)
        dirty = true
    }

    private func applyMetrics(width: Int32, height: Int32, scale newScale: Float) {
        if newScale > 0, abs(newScale - scale) > 0.001 { scaleChanges += 1 }
        guard width > 0, height > 0 else { return }
        graph?.rootProposal = proposal(width: UInt32(width), height: UInt32(height))
        dirty = true
    }

    // MARK: text store (inside native input handling: never pumps)

    private func textState(bridgeNode: UInt64) -> TextInputState? {
        runtimeFieldByBridge[bridgeNode].flatMap { graph?.textInput($0) }
    }

    /// Runs `body` as one input scope: records handler time and bridge time when it produced a model input.
    private func inputScope(_ body: () -> Bool) -> Bool {
        guard config.instr == .full else { return body() }
        let before = recorder.inputs.count
        let t0 = WClock.ticks()
        let b0 = clock.totalTicks
        let result = body()
        let t1 = WClock.ticks()
        let b1 = clock.totalTicks
        if recorder.inputs.count > before {
            recorder.addBridgeInput(.init(
                seq: recorder.inputs.count,
                handlerNS: (t1 &- t0) &* 1_000_000_000 / WClock.hz,
                bridgeNS: (b1 &- b0) &* 1_000_000_000 / WClock.hz))
        }
        return result
    }

    func storeSelection(node: UInt64) -> (range: UTF16Span, reversed: Bool)? {
        guard let state = textState(bridgeNode: node) else { return nil }
        return (bridgeSpan(state.selection), false)
    }

    func storeMarkedRange(node: UInt64) -> UTF16Span? {
        textState(bridgeNode: node)?.markedRange.map(bridgeSpan)
    }

    func storeText(node: UInt64, range: UTF16Span) -> (units: [UInt16], adjusted: UTF16Span)? {
        guard let state = textState(bridgeNode: node) else { return nil }
        let units = Array(state.display.utf16)
        let n = UInt32(units.count)
        let start = min(range.start, n)
        let end = max(start, min(range.end, n))
        return (Array(units[Int(start)..<Int(end)]), UTF16Span(start: start, end: end))
    }

    func storeReplace(node: UInt64, range: UTF16Span?, text: [UInt16]) -> Bool {
        inputScope {
            guard let state = textState(bridgeNode: node) else { return false }
            let ok = state.replace(range: range.map(runtimeRange), text: String(decoding: text, as: UTF16.self))
            dirty = true
            flushIfDirty()
            return ok
        }
    }

    func storeReplaceAndMark(node: UInt64, range: UTF16Span?, text: [UInt16], newSelection: UTF16Span?) -> Bool {
        guard let state = textState(bridgeNode: node) else { return false }
        let ok = state.replaceAndMark(range: range.map(runtimeRange), text: String(decoding: text, as: UTF16.self),
                                      newSelection: newSelection.map(runtimeRange))
        dirty = true
        flushIfDirty()
        return ok
    }

    func storeUnmark(node: UInt64) -> Bool {
        _ = textState(bridgeNode: node)?.unmark()
        dirty = true
        flushIfDirty()
        return true
    }

    func storeCaretBounds(node: UInt64, range: UTF16Span) -> Rect? {
        guard let g = fieldGeometry[node] else { return nil }
        return caretRect(cells: g.cells, lines: g.lines, index: Int(range.start), origin: g.origin,
                         lineHeightPx: g.lineHeightPx, width: 2)
    }

    func measurerFailures() -> Int { measurer?.failures ?? 0 }
}

final class WorkloadTextStore: TextStore {
    let backend: WinBackend

    init(backend: WinBackend) { self.backend = backend }

    func selection(node: SwiftRightBridge.NodeID) -> (range: UTF16Span, reversed: Bool)? {
        MainActor.assumeIsolated { backend.storeSelection(node: node) }
    }

    func markedRange(node: SwiftRightBridge.NodeID) -> UTF16Span? {
        MainActor.assumeIsolated { backend.storeMarkedRange(node: node) }
    }

    func text(node: SwiftRightBridge.NodeID, range: UTF16Span) -> (units: [UInt16], adjusted: UTF16Span)? {
        MainActor.assumeIsolated { backend.storeText(node: node, range: range) }
    }

    func replace(node: SwiftRightBridge.NodeID, range: UTF16Span?, text: [UInt16]) -> Bool {
        MainActor.assumeIsolated { backend.storeReplace(node: node, range: range, text: text) }
    }

    func replaceAndMark(node: SwiftRightBridge.NodeID, range: UTF16Span?, text: [UInt16], newSelection: UTF16Span?) -> Bool {
        MainActor.assumeIsolated { backend.storeReplaceAndMark(node: node, range: range, text: text, newSelection: newSelection) }
    }

    func unmark(node: SwiftRightBridge.NodeID) -> Bool {
        MainActor.assumeIsolated { backend.storeUnmark(node: node) }
    }

    func caretBounds(node: SwiftRightBridge.NodeID, range: UTF16Span) -> Rect? {
        MainActor.assumeIsolated { backend.storeCaretBounds(node: node, range: range) }
    }
}
