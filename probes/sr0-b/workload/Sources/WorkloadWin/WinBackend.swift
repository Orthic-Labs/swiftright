import Foundation
import SwiftRightRuntime
import SwiftRightBridge
import WorkloadCore
#if os(Windows)
import func WinSDK.IsDebuggerPresent
#endif

// WinBackend: the SR0 workload on the fresh runtime and the real renderer through bridge ABI 0.6, instrumented.
// Text store and event path follow probes/sr0-s/fresh-on-bridge/BridgeBackend.swift. Commit conversion differs from that file's
// full-upsert design (R10 performance diagnosis: the first workload run committed every runtime node and re-measured every text
// on every commit, 0.3 to 0.4 s per commit at 200 rows):
//
//   * Only nodes that paint, speak or take input are sent (Text, TextField), flat under the window root in paint order; the
//     structure nodes between them carry nothing the renderer reads (`flattenStructure`).
//   * Each sent node is remembered. A node whose placement, text, caret and clip are unchanged is not rebuilt, measured or
//     upserted; a node that only moved keeps its shaped text run and AX runs (shifted), so scrolling calls the shaper zero
//     times (`reuseUnchangedNodes`). Runs are released when the text changes, the node goes, or the window closes.
//   * Bridge ids are the runtime's node creation numbers, so no id is hashed per commit.
//   * A commit with nothing to send is not submitted.
//
// Instrumentation (unchanged in kind):
//
//   * BridgeClock: every LEAF bridge call (measure, cells, release, commit, stats) is timed once; nothing nests, so
//     per-frame and per-input bridge time never double-counts. Event pop and callback dispatch inside the Bridge
//     package are not wrappable without editing it and are excluded.
//   * per-frame samples (frames.csv): bridge time since the previous commit, measure calls, upserts, renderer paint count.
//   * per-input samples (bridge_input.csv): handler time and bridge time of each keystroke text-store call.
//   * commit stamps for the visible-response join: after each accepted commit, inputs received since the last commit
//     get (commit QPC, renderer paint counter). Every paint after that counter includes the response (the renderer
//     paints and commits on the one UI thread), so the first PresentMon present from that paint on is the response frame.
//   * ticks.csv: every display tick with the renderer's own QPC timestamp and paint counter (the QPC-to-present map).
//
// `WorkloadWin --bench [--verify]` drives this class headlessly against a mock renderer (Bench.swift).

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

/// The renderer surface the backend drives. `BridgePlatform` is the real bridge ABI 0.6; the headless benchmark and the
/// tests substitute a mock, which is what lets the commit conversion run (and be timed) without a window or renderer.
@MainActor
protocol BackendPlatform: AnyObject {
    func metrics() throws -> (width: UInt32, height: UInt32, scale: Float, active: Bool)
    func requestTicks(_ on: Bool) throws
    func requestClose() throws
    func measure(_ request: MeasureRequest) throws -> SwiftRightBridge.TextMeasurement
    func cells(of run: TextRunHandle) throws -> [CharCell]
    @discardableResult func release(_ run: TextRunHandle) -> Bool
    func commit(_ transaction: Transaction) throws
    func stats() -> StatsSnap
}

@MainActor
final class BridgePlatform: BackendPlatform {
    let bridge: Bridge
    private(set) var window: BridgeWindow?

    init(bridge: Bridge) { self.bridge = bridge }

    func attach(_ win: BridgeWindow) { window = win }
    func detach() { window = nil }

    private func live() throws -> BridgeWindow {
        guard let window else { throw BridgeError.status(-6, "window gone") }
        return window
    }

    func metrics() throws -> (width: UInt32, height: UInt32, scale: Float, active: Bool) { try live().metrics() }
    func requestTicks(_ on: Bool) throws { try live().requestTicks(on) }
    func requestClose() throws { try live().requestClose() }
    func measure(_ request: MeasureRequest) throws -> SwiftRightBridge.TextMeasurement { try bridge.measure(request) }
    func cells(of run: TextRunHandle) throws -> [CharCell] { try bridge.cells(of: run) }
    @discardableResult func release(_ run: TextRunHandle) -> Bool { bridge.release(run) }
    func commit(_ transaction: Transaction) throws { try live().commit(transaction) }
    func stats() -> StatsSnap { bridge.statsSnap() }
}

/// Cumulative commit-conversion phase times (QPC ticks) and counts; the headless benchmark reads deltas of it.
struct CommitTimes {
    var walkTicks: UInt64 = 0       // runtime record -> node upserts (includes measure and cells calls)
    var removeTicks: UInt64 = 0     // live-parent diff -> removes
    var submitTicks: UInt64 = 0     // platform.commit
    var releaseTicks: UInt64 = 0    // releasing the shaped runs of the commit
    var commits = 0
    var skipped = 0                 // commits with nothing to send (not submitted)
    var nodesWalked = 0
    var upserts = 0
    var primitives = 0
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
    let platform: BackendPlatform
    let scale: Float
    let clock: BridgeClock
    private(set) var failures = 0
    private(set) var lastError = ""

    init(platform: BackendPlatform, scale: Float, clock: BridgeClock) {
        self.platform = platform
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
                try platform.measure(MeasureRequest(
                    text: request.text, fontFamily: WStyle.fontFamily,
                    fontSize: WStyle.fontSizeDIP, lineHeight: WStyle.lineHeightDIP,
                    scale: scale, maxWidth: maxWidth))
            }
            clock.time { _ = platform.release(m.run) }
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
    let platform: BackendPlatform
    let model: WorkloadModel
    let recorder: RunRecorder
    let config: WorkloadConfig
    let clock: BridgeClock
    private(set) var windowLive = false
    private(set) var graph: Graph?
    private(set) var measurer: BridgeTextMeasurer?
    private(set) var scale: Float = 1
    private var version: UInt64 = 0
    private var epoch: UInt32 = 0
    private var sentNodes: [UInt64: SentNode] = [:]
    private var lastFocus: UInt64 = 0
    private var dirty = false
    /// Re-measure and re-upsert only the nodes whose rendered content changed since the last accepted commit. False restores
    /// the SR0-R10 full-upsert behaviour (the benchmark's reference).
    var reuseUnchangedNodes = true
    /// Send only the nodes that paint, speak or take input (Text and TextField here), flat under the window root and numbered in
    /// paint order, instead of every runtime node. A structure node (stack, modifier, user view, scroll) has no primitives, no
    /// semantics and no flags, so the renderer never reads it: it paints from `primitives`, hits on flagged bounds, and builds
    /// accessibility from semantic nodes. Each commit clones the renderer's node table, so fewer nodes is cheaper for it too.
    /// False sends every node (the reference for the benchmark's equivalence check).
    var flattenStructure = true

    // kept in step with `sentNodes`
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
    private(set) var times = CommitTimes()
    private(set) var maxUpserts = 0
    private(set) var maxPrimitives = 0
    private(set) var scaleChanges = 0
    private var inTick = false
    private var lastFrameTotal: UInt64 = 0
    private var lastFrameMeasures = 0
    private var lastFrameEndTicks: UInt64 = 0
    var statsAtReady: StatsSnap?
    var onFinished: (() -> Void)?

    init(platform: BackendPlatform, model: WorkloadModel, recorder: RunRecorder, config: WorkloadConfig) {
        self.platform = platform
        self.model = model
        self.recorder = recorder
        self.config = config
        self.clock = BridgeClock(enabled: config.instr == .full)
    }

    // MARK: lifecycle

    func ready() {
        windowLive = true
        do {
            let metrics = try platform.metrics()
            scale = metrics.scale
            let meas = BridgeTextMeasurer(platform: platform, scale: scale, clock: clock)
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
            try platform.requestTicks(true)
            statsAtReady = platform.stats()
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
    func tick(timestampNS: UInt64, nowTicks: UInt64? = nil) {
        tickCount += 1
        let now = nowTicks ?? WClock.ticks()
        if !closedFlag {
            let s = platform.stats()
            recorder.addTick(.init(tsNS: timestampNS, rxTicks: now, paints: s.paints, commits: s.commitsAccepted))
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
            try? platform.requestClose()
        }
    }

    func closed() {
        closedFlag = true
        model.close()
        graph?.tearDown()
        releaseRetainedRuns()
        windowLive = false
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
        let live = platform.stats().liveNodes
        liveNodesAtPump = live
        let elapsed = WClock.seconds(WClock.ticks() &- pumpStart)
        let settled = elapsed > 0.5 && live == 0 && model.enginePending == 0
        if settled || elapsed > 3.0 {
            onFinished?()
            return
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.postClosePump(hops: hops + 1) } }
    }

    /// Benchmark and test hooks.
    func markDirty() { dirty = true }
    func applyMetricsForBench(widthPx: UInt32, heightPx: UInt32) {
        applyMetrics(width: Int32(widthPx), height: Int32(heightPx), scale: scale)
    }

    func flushIfDirty() {
        guard dirty, let graph else { return }
        dirty = false
        graph.flush()
    }

    // MARK: runtime -> bridge
    //
    // Commit conversion keeps what it has sent. Each runtime node maps to one bridge node whose id is its creation number
    // (`ResolvedNode.instance`, never reused, so no id is hashed per commit and a removed-then-reinserted row is a new node as
    // the ABI requires). For every node the walk compares what would be sent (placement, text, caret, clip) with what was sent
    // last; an identical node costs no measurement, no marshalling and no upsert. A node whose text is unchanged keeps its
    // shaped run, so scrolling or re-flowing re-sends positions without calling the shaper. Runs are released when the text
    // changes or the node goes away. `reuseUnchangedNodes = false` restores the full re-measure, full re-upsert behaviour
    // of the SR0 first implementation (the benchmark's reference).

    /// Everything that decides one node's upsert besides its retained text shape.
    private struct NodeSig: Equatable {
        var parent: UInt64
        var order: UInt32
        var frame: PixelRect
        var opacity: Double
        var kind: UInt8                 // 0 structure, 1 Text, 2 TextField, 3 ScrollView
        var text: String?
        var focused: Bool
        var selection: UTF16Range?
        var clip: Rect?
    }

    /// One measured text value. `origin` is where `axRuns` were laid out; a node that only moved shifts them.
    private struct TextShape {
        var text: String
        var color: UInt32
        var maxWidth: Float
        var measurement: SwiftRightBridge.TextMeasurement
        var cells: [CharCell]
        var axRuns: [AXTextRun]
        var origin: (x: Float, y: Float)
        /// True when the node retains the run (released when the text changes or the node goes); false in reference mode,
        /// where every run is released right after its commit.
        var retained: Bool
    }

    private struct SentNode {
        var sig: NodeSig?               // nil: rebuild next commit (a measure failed)
        var parent: UInt64
        var seen: UInt32
        var shape: TextShape?
        var field: (runtimeID: String, row: UUID, identifier: String)?
    }

    /// One commit conversion pass: what it upserts, what it created, and how to undo it if the renderer refuses the commit.
    private struct Pass {
        var upserts: [NodeUpsert] = []
        var primitives = 0
        var seen = 0
        var created: [TextRunHandle] = []       // runs made in this pass (released if the commit fails)
        var replaced: [TextRunHandle] = []      // runs this pass superseded (released once the commit succeeds)
        var undo: [(id: UInt64, previous: SentNode?)] = []
        var emitted = 0                         // nodes of the tree that are sent (flattening skips structure nodes)
        var focusPrefix: String?
        var focusID: String?
    }

    private func bridgeID(_ node: ResolvedNode) -> UInt64 { UInt64(node.instance) + 1 }

    /// AX text-run ids live in the node-id namespace: a block of `WStyle.runBlock` ids per field, above any node id.
    private func runBase(_ node: ResolvedNode) -> UInt64 { (1 << 40) + UInt64(node.instance) * WStyle.runBlock }

    private func inflate(_ r: Rect, dx: Float, dy: Float) -> Rect {
        Rect(x: r.x - dx, y: r.y - dy, w: r.w + 2 * dx, h: r.h + 2 * dy)
    }

    /// The shaped text for `text`, reused from `previous` when text, colour and width are unchanged.
    private func shape(_ text: String, color: UInt32, maxWidth: Float, wantCells: Bool, previous: TextShape?,
                       pass: inout Pass) -> TextShape? {
        if reuseUnchangedNodes, let p = previous, p.retained, p.text == text, p.color == color, p.maxWidth == maxWidth { return p }
        do {
            let m = try clock.time(measure: true) {
                try platform.measure(MeasureRequest(
                    text: text, fontFamily: WStyle.fontFamily, color: color,
                    fontSize: WStyle.fontSizeDIP, lineHeight: WStyle.lineHeightDIP,
                    scale: scale, maxWidth: maxWidth))
            }
            pass.created.append(m.run)
            let cells = wantCells ? ((try? clock.time { try platform.cells(of: m.run) }) ?? []) : []
            return TextShape(text: text, color: color, maxWidth: maxWidth, measurement: m, cells: cells, axRuns: [],
                             origin: (0, 0), retained: reuseUnchangedNodes)
        } catch {
            drawFailures += 1
            lastDrawError = "\(error)"
            return nil
        }
    }

    func commit(_ record: CommitRecord) {
        guard windowLive, !closedFlag else {
            if closedFlag, record.root != nil {
                commitsAfterClose += 1
                model.noteCommitAfterClose()
            }
            return
        }
        guard let root = record.root else { return }
        let startTicks = WClock.ticks()
        epoch &+= 1
        scrollNodeID = nil
        focusedField = 0
        var pass = Pass()
        pass.focusID = record.focused
        pass.focusPrefix = record.focused.map { $0 + "/" }
        var rootOrder: UInt32 = 0
        walk(root, parent: 0, order: &rootOrder, clip: nil, pass: &pass)
        let walkEnd = WClock.ticks()

        // Nodes that were sent and are no longer in the tree. Only the top of a vanished subtree is removed (the renderer takes
        // its descendants with it); every vanished node gives up its retained run.
        var removes: [UInt64] = []
        var vanished: [UInt64] = []
        if sentNodes.count > pass.emitted {
            for (id, node) in sentNodes where node.seen != epoch {
                vanished.append(id)
                if node.parent == 0 || sentNodes[node.parent]?.seen == epoch { removes.append(id) }
            }
        }
        let removeEnd = WClock.ticks()

        let focusChanged = focusedField != lastFocus
        let nothingToSend = pass.upserts.isEmpty && removes.isEmpty && !focusChanged
        var accepted = false
        var submitted = false
        if !nothingToSend {
            version += 1
            submitted = true
            let transaction = Transaction(version: version, focus: focusedField, upserts: pass.upserts, removes: removes)
            maxUpserts = max(maxUpserts, pass.upserts.count)
            maxPrimitives = max(maxPrimitives, pass.primitives)
            do {
                try clock.time { try platform.commit(transaction) }
                commitCount += 1
                accepted = true
            } catch {
                commitErrors.append("commit v\(version): \(error)")
            }
        }
        let endTicks = WClock.ticks()

        // The renderer holds its own reference to every run a committed node uses, so superseded and abandoned runs are
        // released now. On a refused commit the previous state is restored and this pass's runs are dropped instead.
        var toRelease: [TextRunHandle] = []
        if accepted || nothingToSend {
            lastFocus = focusedField
            toRelease = pass.replaced
            for id in vanished {
                if let gone = sentNodes.removeValue(forKey: id) {
                    if let run = gone.shape?.measurement.run, gone.shape?.retained == true { toRelease.append(run) }
                    runtimeFieldByBridge[id] = nil
                    rowByBridgeField[id] = nil
                    fieldGeometry[id] = nil
                }
            }
            if !reuseUnchangedNodes { toRelease.append(contentsOf: pass.created) }
        } else {
            for (id, previous) in pass.undo.reversed() { sentNodes[id] = previous }
            toRelease = pass.created
        }
        for handle in toRelease { clock.time { _ = platform.release(handle) } }
        let releaseEnd = WClock.ticks()
        times.walkTicks &+= walkEnd &- startTicks
        times.removeTicks &+= removeEnd &- walkEnd
        times.submitTicks &+= endTicks &- removeEnd
        times.releaseTicks &+= releaseEnd &- endTicks
        times.commits += submitted ? 1 : 0
        times.skipped += submitted ? 0 : 1
        times.nodesWalked += pass.seen
        times.upserts += pass.upserts.count
        times.primitives += pass.primitives
        if accepted {
            let paints = platform.stats().paints
            if recorder.hasUnstamped {
                recorder.stampCommit(ticks: endTicks, paints: paints, version: version)
            }
            if config.instr == .full {
                let total = clock.totalTicks
                recorder.addFrame(.init(
                    version: version, startTicks: startTicks, endTicks: endTicks,
                    bridgeNS: (total &- lastFrameTotal) &* 1_000_000_000 / WClock.hz,
                    measureCalls: clock.measureCalls - lastFrameMeasures,
                    upserts: pass.upserts.count, paints: paints))
                lastFrameTotal = total
                lastFrameMeasures = clock.measureCalls
            }
        }
        lastFrameEndTicks = endTicks
    }

    /// Releases every retained run (window teardown) and forgets what was sent.
    private func releaseRetainedRuns() {
        for (_, node) in sentNodes {
            if let shape = node.shape, shape.retained { clock.time { _ = platform.release(shape.measurement.run) } }
        }
        sentNodes.removeAll()
    }

    /// Visits `node` and its descendants in paint order. `order` is the next sibling number under `parent`: a node that is sent
    /// takes it, and its own children count from zero under it; a node that is not sent (flattening) hands the counter on to
    /// its children, which then belong to `parent`.
    private func walk(_ node: ResolvedNode, parent: UInt64, order: inout UInt32, clip: Rect?, pass: inout Pass) {
        pass.seen += 1
        let pf = node.pixelFrame
        let kindCode: UInt8
        switch node.kind {
        case "Text": kindCode = 1
        case "TextField": kindCode = 2
        case "ScrollView": kindCode = 3
        default: kindCode = 0
        }
        var childClip = clip
        if kindCode == 3 {
            scrollNodeID = node.id
            if let content = node.children.first {
                scrollMax = max(0, content.frame.height - node.frame.height)
            }
            childClip = Rect(x: Float(pf.x), y: Float(pf.y), w: Float(pf.width), h: Float(pf.height))
        }
        guard !flattenStructure || kindCode == 1 || kindCode == 2 else {
            for child in node.children { walk(child, parent: parent, order: &order, clip: childClip, pass: &pass) }
            return
        }

        let id = bridgeID(node)
        pass.emitted += 1
        let myOrder = order
        order += 1
        var focused = false
        if kindCode == 2, let prefix = pass.focusPrefix, let focusID = pass.focusID {
            focused = node.id == focusID || node.id.hasPrefix(prefix)
            if focused { focusedField = id }
        }
        let sig = NodeSig(parent: parent, order: myOrder, frame: pf, opacity: node.opacity, kind: kindCode,
                          text: kindCode == 1 || kindCode == 2 ? (node.text ?? "") : nil, focused: focused,
                          selection: kindCode == 2 ? node.selection : nil, clip: clip)
        let sent = sentNodes[id]
        if reuseUnchangedNodes, let sent, sent.sig == sig {
            sentNodes[id]?.seen = epoch
        } else {
            rebuild(node, id: id, parent: parent, order: myOrder, clip: clip, kind: kindCode, focused: focused, sig: sig,
                    previous: sent, pass: &pass)
        }
        var childOrder: UInt32 = 0
        for child in node.children { walk(child, parent: id, order: &childOrder, clip: childClip, pass: &pass) }
    }

    /// Builds the upsert of a node that is new or changed, reusing its retained text shape where the text is unchanged.
    private func rebuild(_ node: ResolvedNode, id: UInt64, parent: UInt64, order: UInt32, clip: Rect?, kind: UInt8, focused: Bool,
                         sig: NodeSig, previous: SentNode?, pass: inout Pass) {
        let pf = node.pixelFrame
        let s = scale
        let alpha = node.opacity
        var bounds = Rect(x: Float(pf.x), y: Float(pf.y), w: Float(pf.width), h: Float(pf.height))
        var prims: [Primitive] = []
        var semantic: SemanticNode?
        var flags: NodeFlags = []
        var shape = previous?.shape
        var field = previous?.field
        var ok = true

        switch kind {
        case 1:
            let text = node.text ?? ""
            if !text.isEmpty {
                if let m = self.shape(text, color: fadedColor(WStyle.textColor, alpha), maxWidth: Float(pf.width) + 1,
                                      wantCells: false, previous: shape, pass: &pass) {
                    if shape?.measurement.run != m.measurement.run, let old = shape, old.retained { pass.replaced.append(old.measurement.run) }
                    shape = m
                    prims.append(.text(m.measurement.run, x: Float(pf.x), y: Float(pf.y)))
                } else {
                    ok = false
                }
            } else {
                if let old = shape, old.retained { pass.replaced.append(old.measurement.run) }
                shape = nil
            }
            semantic = SemanticNode(role: .staticText, label: text)

        case 2:
            let text = node.text ?? ""
            let fieldRect = inflate(bounds, dx: WStyle.fieldInsetX * s, dy: 0)
            bounds = fieldRect
            prims.append(.rect(fieldRect, color: fadedColor(WStyle.fieldFill, alpha), radius: 3 * s,
                               borderColor: fadedColor(WStyle.fieldBorder, alpha), borderWidth: max(1, s)))
            let origin = (x: Float(pf.x), y: Float(pf.y))
            let lh = WStyle.lineHeightDIP * s
            if field == nil {
                let uuid = rowUUID(in: node.id)
                let row = uuid ?? model.active.id
                field = (node.id, row, uuid == nil ? "active/field" : "row/\(row.uuidString)/field")
            }
            let identity = field!
            runtimeFieldByBridge[id] = node.id
            rowByBridgeField[id] = identity.row
            var runs: [AXTextRun] = []
            var selection: (anchor: TextSelectionPosition, focus: TextSelectionPosition)?
            let base = runBase(node)
            if !text.isEmpty {
                if var m = self.shape(text, color: fadedColor(WStyle.textColor, alpha), maxWidth: 0, wantCells: true,
                                      previous: shape, pass: &pass) {
                    prims.append(.text(m.measurement.run, x: origin.x, y: origin.y))
                    let cells = m.cells
                    let caretEnd = node.selection.map { $0.location + $0.length } ?? text.utf16.count
                    let caretIndex = min(caretEnd, cells.count)
                    if focused {
                        let caretRectPx = caretRect(cells: cells, lines: m.measurement.lines, index: caretIndex, origin: origin,
                                                    lineHeightPx: lh, width: max(1, 1.5 * s))
                        prims.append(.rect(caretRectPx, color: fadedColor(WStyle.caretColor, alpha)))
                    }
                    if m.axRuns.isEmpty {
                        m.axRuns = makeAXTextRuns(text: text, measurement: m.measurement, cells: cells, origin: origin,
                                                  lineHeightPx: lh, firstRunID: base)
                    } else if m.origin.x != origin.x || m.origin.y != origin.y {
                        // Same text, new place: the runs are origin-relative except their bounds, which just shift.
                        let dx = origin.x - m.origin.x, dy = origin.y - m.origin.y
                        for index in m.axRuns.indices {
                            m.axRuns[index].bounds.x += dx
                            m.axRuns[index].bounds.y += dy
                        }
                    }
                    m.origin = origin
                    runs = m.axRuns
                    if !runs.isEmpty {
                        let line = caretIndex < cells.count ? Int(cells[caretIndex].line) : Int(cells.last?.line ?? 0)
                        var inLine = 0
                        for cell in cells[0..<caretIndex] where Int(cell.line) == line { inLine += 1 }
                        let position = TextSelectionPosition(run: base + UInt64(min(line, runs.count - 1)), character: UInt32(inLine))
                        selection = (anchor: position, focus: position)
                    }
                    fieldGeometry[id] = FieldGeometry(origin: origin, cells: cells, lines: m.measurement.lines, lineHeightPx: lh)
                    if shape?.measurement.run != m.measurement.run, let old = shape, old.retained { pass.replaced.append(old.measurement.run) }
                    shape = m
                } else {
                    ok = false
                    fieldGeometry[id] = FieldGeometry(origin: origin, cells: [], lines: [], lineHeightPx: lh)
                }
            } else {
                if let old = shape, old.retained { pass.replaced.append(old.measurement.run) }
                shape = nil
                fieldGeometry[id] = FieldGeometry(origin: origin, cells: [], lines: [], lineHeightPx: lh)
                runs = makeAXTextRuns(text: "", measurement: nil, cells: [], origin: origin, lineHeightPx: lh, firstRunID: base)
                if let first = runs.first {
                    let position = TextSelectionPosition(run: first.id, character: 0)
                    selection = (anchor: position, focus: position)
                }
            }
            semantic = SemanticNode(role: .textField, label: "", value: text,
                                    actions: [.focus, .setValue, .setSelection], runs: runs, selection: selection,
                                    identifier: identity.identifier)
            flags = [.hitTarget, .focusable, .editable]

        default:
            break
        }

        if let c = clip, !prims.isEmpty {
            prims = [.clipPush(c)] + prims + [.clipPop]
        }
        pass.primitives += prims.count
        pass.upserts.append(NodeUpsert(id: id, parent: parent, order: order, flags: flags, bounds: bounds,
                                       primitives: prims, semantic: semantic))
        pass.undo.append((id, previous))
        sentNodes[id] = SentNode(sig: ok ? sig : nil, parent: parent, seen: epoch,
                                 shape: reuseUnchangedNodes ? shape : nil, field: field)
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
