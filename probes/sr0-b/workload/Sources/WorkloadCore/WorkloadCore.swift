import Foundation
import Observation
#if WORKLOAD_RUNTIME
import SwiftRightRuntime
#else
import SwiftUI
#endif
#if os(Windows)
import struct WinSDK.LARGE_INTEGER
import func WinSDK.QueryPerformanceCounter
import func WinSDK.QueryPerformanceFrequency
#elseif canImport(Darwin)
import Darwin
#endif

// SR0 plan v2 lane R10: shared workload model (architecture.md section 11, "SR0 workload").
//
//   200 stable-ID editable rows: 199 list rows + 1 pinned active editor row (the typing target).
//   20 asynchronous row updates/inserts per second (alternating), one reorder per second,
//   continuous scrolling (host-applied, driven by `scrollPhase`) and continuous editing (external input script),
//   fixed-size data (every insert removes an unrelated row; a cancelled update replaces its row in one mutation),
//   width-dependent text layout (WorkloadLayout in WorkloadScreen.swift + detail strings that change wrap count),
//   interrupted animation (a second animated insert 150 ms into the first), cancellation (rows removed while their
//   update is in flight; per-row tasks cancelled on removal) and window teardown (`close()` + host F9-style pump).
//
// Every schedule is derived from the host's monotonic clock through `advance(nowTicks:)`, never from wall timers, so
// both OSes replay the same operation sequence (seeded) at the same rates. Only the clock source differs.

// MARK: - clock

public enum WClock {
    #if os(Windows)
    /// QPC frequency. QPC ticks are the clock domain shared with SendInput timestamps and PresentMon (CONTRACT section 5).
    public static let hz: UInt64 = {
        var f = LARGE_INTEGER()
        QueryPerformanceFrequency(&f)
        return UInt64(f.QuadPart)
    }()
    public static func ticks() -> UInt64 {
        var c = LARGE_INTEGER()
        QueryPerformanceCounter(&c)
        return UInt64(c.QuadPart)
    }
    public static let name = "QPC"
    #else
    /// macOS: CLOCK_UPTIME_RAW in nanoseconds (the domain of mach_absolute_time, timebase applied).
    public static let hz: UInt64 = 1_000_000_000
    public static func ticks() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    public static let name = "mach-uptime-ns"
    #endif

    public static func ms(_ ticks: UInt64) -> Double { Double(ticks) * 1000.0 / Double(hz) }
    public static func seconds(_ ticks: UInt64) -> Double { Double(ticks) / Double(hz) }
}

// MARK: - configuration

public enum InstrLevel: String, Sendable {
    /// All timers: bridge timers, per-frame samples, main-actor sampler, input and tick logs.
    case full
    /// Only what the visible-response join needs (input receipts, commit stamps, ticks). Used to measure overhead.
    case light
}

public struct WorkloadConfig: Sendable {
    public var totalRows = 200                // 199 list rows + the pinned active row
    public var opIntervalMS = 50.0            // 20 asynchronous row updates/inserts per second
    public var reorderIntervalMS = 1000.0     // one reorder per second
    public var animPeriodMS = 2500.0          // animated insert burst period
    public var animInterruptMS = 150.0        // second animated insert, mid-animation
    public var scrollPeriodS = 12.0           // triangle wave over the full content height
    public var warmupS = 10.0
    public var measureS = 60.0
    public var seed: UInt64 = 0x5352_3042_5231_30
    public var instr: InstrLevel = .full
    public var runID = "run"
    public var outDir = "."
    public init() {}
}

// MARK: - deterministic PRNG

public struct SplitMix64: Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func below(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
}

// MARK: - rows

/// A rectangle in window coordinates, points (own type: Foundation's CGRect is not uniform across the two flavours).
public struct WRegion: Sendable {
    public var x = 0.0, y = 0.0, w = 0.0, h = 0.0
    public init() {}
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

public struct Row: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var slot: Int
    public var text: String
    public var detail: String

    public init(id: UUID, slot: Int, text: String, detail: String) {
        self.id = id; self.slot = slot; self.text = text; self.detail = detail
    }
}

enum Detail {
    static func text(slot: Int, version: Int) -> String {
        // Alternates short and long strings: the wrapped line count at a fixed column width changes with each update.
        if version % 2 == 0 {
            return "Item \(slot) ready (v\(version))"
        }
        return "Item \(slot) queued for review (v\(version)): this longer description wraps onto several lines at the narrow column width and onto fewer at the wide one."
    }
}

func workloadRowID(_ slot: Int) -> UUID {
    let tail = String(slot)
    let last = String(repeating: "0", count: max(0, 12 - tail.count)) + tail
    return UUID(uuidString: "5B0A0000-0000-4000-8000-\(last)")!
}

// MARK: - run recorder (raw samples)

/// Raw-sample store for one run. All timestamps are `WClock` ticks. Appends are lock-protected (the main-actor sampler
/// thread appends too). Written to CSV by `write`.
public final class RunRecorder: @unchecked Sendable {
    public struct Input {
        public var seq: Int
        public var rxTicks: UInt64
        public var textLen: Int
        public var commitTicks: UInt64 = 0
        public var paintsAtCommit: UInt64 = 0
        public var commitVersion: UInt64 = 0
    }
    public struct Frame {
        public var version: UInt64
        public var startTicks: UInt64
        public var endTicks: UInt64
        public var bridgeNS: UInt64
        public var measureCalls: Int
        public var upserts: Int
        public var paints: UInt64
        public init(version: UInt64, startTicks: UInt64, endTicks: UInt64, bridgeNS: UInt64, measureCalls: Int, upserts: Int, paints: UInt64) {
            self.version = version; self.startTicks = startTicks; self.endTicks = endTicks; self.bridgeNS = bridgeNS
            self.measureCalls = measureCalls; self.upserts = upserts; self.paints = paints
        }
    }
    public struct BridgeInput {
        public var seq: Int
        public var handlerNS: UInt64
        public var bridgeNS: UInt64
        public init(seq: Int, handlerNS: UInt64, bridgeNS: UInt64) {
            self.seq = seq; self.handlerNS = handlerNS; self.bridgeNS = bridgeNS
        }
    }
    public struct TickSample {
        public var tsNS: UInt64
        public var rxTicks: UInt64
        public var paints: UInt64
        public var commits: UInt64
        public init(tsNS: UInt64, rxTicks: UInt64, paints: UInt64, commits: UInt64) {
            self.tsNS = tsNS; self.rxTicks = rxTicks; self.paints = paints; self.commits = commits
        }
    }
    public struct MainActorSample {
        public var enqueueTicks: UInt64
        public var execTicks: UInt64
        public init(enqueueTicks: UInt64, execTicks: UInt64) { self.enqueueTicks = enqueueTicks; self.execTicks = execTicks }
    }
    public struct OverheadProbe {
        public var name: String
        public var nsPerPair: Double
        public var iterations: Int
        public init(name: String, nsPerPair: Double, iterations: Int) { self.name = name; self.nsPerPair = nsPerPair; self.iterations = iterations }
    }

    private let lock = NSLock()
    public private(set) var inputs: [Input] = []
    public private(set) var frames: [Frame] = []
    public private(set) var bridgeInputs: [BridgeInput] = []
    public private(set) var ticks: [TickSample] = []
    public private(set) var mainActor: [MainActorSample] = []
    public private(set) var overhead: [OverheadProbe] = []
    private var firstUnstamped = 0
    public var meta: [String: String] = [:]

    public init() {
        inputs.reserveCapacity(2048)
        frames.reserveCapacity(16384)
        bridgeInputs.reserveCapacity(2048)
        ticks.reserveCapacity(16384)
        mainActor.reserveCapacity(16384)
    }

    public func inputRx(seq: Int, ticks t: UInt64, textLen: Int) {
        lock.lock(); defer { lock.unlock() }
        inputs.append(Input(seq: seq, rxTicks: t, textLen: textLen))
    }

    /// Stamps every input not yet stamped with the commit that carried it (commit accepted by the renderer).
    public func stampCommit(ticks t: UInt64, paints: UInt64, version: UInt64) {
        lock.lock(); defer { lock.unlock() }
        while firstUnstamped < inputs.count {
            inputs[firstUnstamped].commitTicks = t
            inputs[firstUnstamped].paintsAtCommit = paints
            inputs[firstUnstamped].commitVersion = version
            firstUnstamped += 1
        }
    }

    public var hasUnstamped: Bool {
        lock.lock(); defer { lock.unlock() }
        return firstUnstamped < inputs.count
    }

    public func addFrame(_ f: Frame) { lock.lock(); frames.append(f); lock.unlock() }
    public func addBridgeInput(_ b: BridgeInput) { lock.lock(); bridgeInputs.append(b); lock.unlock() }
    public func addTick(_ t: TickSample) { lock.lock(); ticks.append(t); lock.unlock() }
    public func addMainActor(_ m: MainActorSample) { lock.lock(); mainActor.append(m); lock.unlock() }
    public func addOverhead(_ o: OverheadProbe) { lock.lock(); overhead.append(o); lock.unlock() }

    /// Writes every table as CSV into `dir` (created if missing). Returns the file names written.
    @discardableResult
    public func write(dir: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var written: [String] = []
        func put(_ name: String, _ header: String, _ rows: [String]) {
            let text = header + "\n" + rows.joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
            try? text.write(toFile: dir + "/" + name, atomically: true, encoding: .utf8)
            written.append(name)
        }
        put("inputs.csv", "seq,rx_ticks,text_len,commit_ticks,paints_at_commit,commit_version",
            inputs.map { "\($0.seq),\($0.rxTicks),\($0.textLen),\($0.commitTicks),\($0.paintsAtCommit),\($0.commitVersion)" })
        put("frames.csv", "version,start_ticks,end_ticks,bridge_ns,measure_calls,upserts,paints",
            frames.map { "\($0.version),\($0.startTicks),\($0.endTicks),\($0.bridgeNS),\($0.measureCalls),\($0.upserts),\($0.paints)" })
        put("bridge_input.csv", "seq,handler_ns,bridge_ns",
            bridgeInputs.map { "\($0.seq),\($0.handlerNS),\($0.bridgeNS)" })
        put("ticks.csv", "ts_ns,rx_ticks,paints,commits",
            ticks.map { "\($0.tsNS),\($0.rxTicks),\($0.paints),\($0.commits)" })
        put("mainactor.csv", "enqueue_ticks,exec_ticks",
            mainActor.map { "\($0.enqueueTicks),\($0.execTicks)" })
        put("overhead_probe.csv", "name,ns_per_pair,iterations",
            overhead.map { "\($0.name),\($0.nsPerPair),\($0.iterations)" })
        return written
    }
}

// MARK: - integrity

public struct WorkloadIntegrity: Sendable {
    public var rowsFinal = 0
    public var rowsMin = Int.max
    public var rowsMax = 0
    public var uniqueIDs = true
    public var activeText = ""
    public var typedCount = 0
    public var wrongNodeEdits = 0
    public var staleCommitted = 0
    public var staleRejected = 0
    public var updatesStarted = 0
    public var updatesCommitted = 0
    public var insertsStarted = 0
    public var insertsCommitted = 0
    public var kills = 0
    public var reorders = 0
    public var animBursts = 0
    public var animInterrupts = 0
    public var opsSkipped = 0
    public var rowTaskStarts = 0
    public var rowTaskCancels = 0
    public var rowAppears = 0
    public var rowDisappears = 0
    public var commitsAfterClose = 0
    public var lateResultsAfterClose = 0
    public var closed = false
    public var tasksParkedAtClose = 0
    public var tasksParkedAfterRelease = 0
}

// MARK: - engine (injected clock, explicit completion)

@MainActor
public final class WorkloadEngine {
    private struct Timed {
        let due: Double
        let order: Int
        let continuation: CheckedContinuation<Int, Never>
    }
    private var timed: [Timed] = []
    private var parked: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var counter = 0
    public var parkedCount: Int { parked.count }
    public var timedCount: Int { timed.count }

    /// Suspends until `deliverDue` passes `due` (engine seconds). Cancellation does not resume it: a late result is
    /// delivered and must be rejected by the owner guard (the Mac oracle's F4 behaviour).
    func call(due: Double) async -> Int {
        counter += 1
        let order = counter
        return await withCheckedContinuation { continuation in
            timed.append(Timed(due: due, order: order, continuation: continuation))
        }
    }

    func deliverDue(now: Double) {
        guard !timed.isEmpty else { return }
        let ready = timed.filter { $0.due <= now }.sorted { ($0.due, $0.order) < ($1.due, $1.order) }
        guard !ready.isEmpty else { return }
        timed.removeAll { $0.due <= now }
        for item in ready { item.continuation.resume(returning: item.order) }
    }

    func park(_ id: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if let old = parked.updateValue(continuation, forKey: id) { old.resume() }
        }
    }

    func releaseAll() {
        let timedNow = timed
        timed.removeAll()
        for item in timedNow { item.continuation.resume(returning: 0) }
        let parkedNow = parked
        parked.removeAll()
        for (_, c) in parkedNow { c.resume() }
    }
}

// MARK: - model

public enum RunPhase: Sendable { case warmup, measure, finished }

@MainActor
@Observable
public final class WorkloadModel {
    @ObservationIgnored public let config: WorkloadConfig
    @ObservationIgnored public let recorder: RunRecorder
    @ObservationIgnored let engine = WorkloadEngine()
    /// Called after every mutation that needs a flush (the Windows host sets its dirty flag here).
    @ObservationIgnored public var onMutate: (() -> Void)?
    /// Focus setter registered by the root view body (the typing target is focused through it).
    @ObservationIgnored public var focusSetter: ((UUID?) -> Void)?
    /// Rectangle of the visible-response region (the "typed N" text) in window coordinates, points. Mac only.
    @ObservationIgnored public var counterRect = WRegion()
    @ObservationIgnored private var rng: SplitMix64
    @ObservationIgnored private var generation: [UUID: Int] = [:]
    @ObservationIgnored private var inflight: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextSlot: Int
    @ObservationIgnored private var detailVersion: [UUID: Int] = [:]
    @ObservationIgnored private var userSeq = 0

    /// Identity of the pinned active row (constant: only its text changes).
    @ObservationIgnored public let activeID = workloadRowID(0)
    public var rows: [Row]
    public var active: Row
    public var typedCount = 0
    public var opsDone = 0
    public var scrollPhase = 0.0

    @ObservationIgnored public private(set) var integrity = WorkloadIntegrity()
    @ObservationIgnored public private(set) var closed = false
    @ObservationIgnored public private(set) var t0: UInt64 = 0
    @ObservationIgnored public private(set) var elapsed = 0.0
    @ObservationIgnored private var nextOpAt = 0.0
    @ObservationIgnored private var opIndex = 0
    @ObservationIgnored private var updateIndex = 0
    @ObservationIgnored private var nextReorderAt = 1.0
    @ObservationIgnored private var nextAnimAt = 2.0
    @ObservationIgnored private var interruptAt = -1.0
    @ObservationIgnored private var killQueue: [(at: Double, id: UUID)] = []
    @ObservationIgnored private var animSerial = 0

    public init(config: WorkloadConfig, recorder: RunRecorder) {
        self.config = config
        self.recorder = recorder
        rng = SplitMix64(seed: config.seed)
        let listCount = config.totalRows - 1
        rows = (1...listCount).map { slot in
            let id = workloadRowID(slot)
            return Row(id: id, slot: slot, text: "Row \(slot)", detail: Detail.text(slot: slot, version: 0))
        }
        active = Row(id: activeID, slot: 0, text: "", detail: "")
        nextSlot = listCount + 1
        integrity.rowsMin = rows.count + 1
        integrity.rowsMax = rows.count + 1
    }

    public var rowTotal: Int { rows.count + 1 }
    /// Engine continuations still waiting (timed results plus parked row tasks).
    public var enginePending: Int { engine.parkedCount + engine.timedCount }

    // MARK: run clock

    /// Wall-clock-free phase from the host clock: warm-up, then the measured run, then finished.
    public func phase(nowTicks: UInt64) -> RunPhase {
        guard t0 != 0 else { return .warmup }
        let s = WClock.seconds(nowTicks &- t0)
        if s < config.warmupS { return .warmup }
        if s < config.warmupS + config.measureS { return .measure }
        return .finished
    }

    public var measureStartTicks: UInt64 { t0 &+ UInt64(config.warmupS * Double(WClock.hz)) }
    public var measureEndTicks: UInt64 { t0 &+ UInt64((config.warmupS + config.measureS) * Double(WClock.hz)) }

    // MARK: schedule

    /// Advances the schedule to the host clock. Called from the host's frame tick (Windows) or its 60 Hz timer (macOS).
    public func advance(nowTicks: UInt64) {
        guard !closed else { return }
        if t0 == 0 { t0 = nowTicks }
        elapsed = WClock.seconds(nowTicks &- t0)
        let wave = elapsed / config.scrollPeriodS
        let frac = wave - wave.rounded(.down)
        scrollPhase = frac < 0.5 ? frac * 2 : (1 - frac) * 2
        engine.deliverDue(now: elapsed)

        var started = 0
        while nextOpAt <= elapsed, started < 4 {
            performOp(index: opIndex)
            opIndex += 1
            nextOpAt += config.opIntervalMS / 1000
            started += 1
        }
        if nextOpAt <= elapsed {
            let skipped = Int((elapsed - nextOpAt) / (config.opIntervalMS / 1000)) + 1
            integrity.opsSkipped += skipped
            nextOpAt = elapsed + config.opIntervalMS / 1000
        }
        while let kill = killQueue.first, kill.at <= elapsed {
            killQueue.removeFirst()
            replaceRow(kill.id)
        }
        if nextReorderAt <= elapsed {
            nextReorderAt += config.reorderIntervalMS / 1000
            reorderOne()
        }
        if nextAnimAt <= elapsed {
            nextAnimAt += config.animPeriodMS / 1000
            interruptAt = elapsed + config.animInterruptMS / 1000
            animatedInsert(first: true)
        }
        if interruptAt >= 0, interruptAt <= elapsed {
            interruptAt = -1
            animatedInsert(first: false)
        }
    }

    private func performOp(index: Int) {
        opsDone += 1
        if index % 2 == 0 {
            startUpdate()
        } else {
            startInsert()
        }
        onMutate?()
    }

    private func latency() -> Double { 0.020 + Double(rng.below(41)) / 1000 }   // 20..60 ms

    private func randomUnrelatedRow() -> UUID? {
        guard !rows.isEmpty else { return nil }
        return rows[rng.below(rows.count)].id
    }

    // MARK: asynchronous row updates and inserts (engine-completed, owner-guarded)

    private func startUpdate() {
        guard let target = randomUnrelatedRow() else { return }
        integrity.updatesStarted += 1
        updateIndex += 1
        let gen = generation[target, default: 0]
        let due = elapsed + latency()
        if updateIndex % 5 == 0 {
            // Cancellation scenario: the row is replaced (removed, fresh identity inserted at the same index)
            // 20 ms after the request, before its engine result arrives.
            integrity.kills += 1
            killQueue.append((elapsed + 0.020, target))
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let value = await self.engine.call(due: due)
            self.finishUpdate(target: target, gen: gen, value: value, cancelled: Task.isCancelled)
        }
        inflight[target] = task
    }

    private func finishUpdate(target: UUID, gen: Int, value: Int, cancelled: Bool) {
        inflight[target] = nil
        if closed {
            integrity.lateResultsAfterClose += 1
            return
        }
        guard !cancelled, generation[target, default: 0] == gen, let index = rows.firstIndex(where: { $0.id == target }) else {
            integrity.staleRejected += 1
            return
        }
        // Independent commit check: the guard above admitted it, so the owner must be live right here.
        let version = detailVersion[target, default: 0] + 1
        detailVersion[target] = version
        rows[index].detail = Detail.text(slot: rows[index].slot, version: version)
        rows[index].text = "Row \(rows[index].slot) updated \(value)"
        if generation[target, default: 0] != gen || closed { integrity.staleCommitted += 1 }
        integrity.updatesCommitted += 1
        onMutate?()
    }

    private func startInsert() {
        integrity.insertsStarted += 1
        let index = rng.below(rows.count + 1)
        let due = elapsed + latency()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let value = await self.engine.call(due: due)
            self.finishInsert(index: index, value: value)
        }
    }

    private func finishInsert(index: Int, value: Int) {
        if closed {
            integrity.lateResultsAfterClose += 1
            return
        }
        if value == 0 {   // released without a result (teardown path)
            integrity.staleRejected += 1
            return
        }
        let row = makeRow(text: "Engine \(value)")
        rows.insert(row, at: min(index, rows.count))
        removeUnrelated(excluding: row.id)
        integrity.insertsCommitted += 1
        trackSize()
        onMutate?()
    }

    private func makeRow(text: String) -> Row {
        let slot = nextSlot
        nextSlot += 1
        return Row(id: workloadRowID(slot), slot: slot, text: text, detail: Detail.text(slot: slot, version: 0))
    }

    /// Removes one random row that is not the new one (the active row is never in `rows`).
    private func removeUnrelated(excluding keep: UUID) {
        guard rows.count > 1 else { return }
        var victim = rows[rng.below(rows.count)].id
        if victim == keep { victim = rows[(rows.firstIndex { $0.id == keep }! + 1) % rows.count].id }
        removeRow(victim)
    }

    private func removeRow(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows.remove(at: index)
        generation[id, default: 0] += 1
        inflight[id]?.cancel()
        inflight[id] = nil
    }

    /// Cancelled-update scenario: same index, new identity, size unchanged.
    private func replaceRow(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let fresh = makeRow(text: "Replaced \(nextSlot)")
        removeRow(id)
        rows.insert(fresh, at: min(index, rows.count))
        trackSize()
        onMutate?()
    }

    private func reorderOne() {
        guard rows.count > 2 else { return }
        let source = rng.below(rows.count)
        var destination = rng.below(rows.count + 1)
        if destination == source || destination == source + 1 { destination = (source + 5) % (rows.count + 1) }
        let item = rows.remove(at: source)
        let target = destination > source ? destination - 1 : destination
        rows.insert(item, at: min(max(target, 0), rows.count))
        integrity.reorders += 1
        onMutate?()
    }

    private func animatedInsert(first: Bool) {
        integrity.animBursts += 1
        if !first { integrity.animInterrupts += 1 }
        animSerial += 1
        let row = makeRow(text: "Anim \(animSerial)")
        withAnimation(.easeInOut(duration: 0.4), {
            rows.insert(row, at: 0)
            removeUnrelated(excluding: row.id)
        })
        trackSize()
        onMutate?()
    }

    private func trackSize() {
        let n = rowTotal
        integrity.rowsMin = min(integrity.rowsMin, n)
        integrity.rowsMax = max(integrity.rowsMax, n)
    }

    // MARK: user edits (external input script)

    /// The single UI write path: every TextField binding setter lands here.
    public func userEdit(_ id: UUID, _ newValue: String) {
        guard !closed else { return }
        if id == active.id {
            active.text = newValue
            typedCount += 1
            userSeq += 1
            recorder.inputRx(seq: userSeq, ticks: WClock.ticks(), textLen: newValue.count)
            onMutate?()
        } else if let index = rows.firstIndex(where: { $0.id == id }) {
            // The input script types only into the active row. An edit anywhere else is a wrong-node edit.
            integrity.wrongNodeEdits += 1
            rows[index].text = newValue
            onMutate?()
        } else {
            integrity.wrongNodeEdits += 1
        }
    }

    public func focusActive() { focusSetter?(active.id) }

    // MARK: per-row tasks and lifecycle (cancellation)

    public func rowTaskBody(_ id: UUID) async {
        integrity.rowTaskStarts += 1
        await withTaskCancellationHandler {
            await engine.park(id)
        } onCancel: {
            Task { @MainActor [weak self] in self?.integrity.rowTaskCancels += 1 }
        }
        if closed { integrity.tasksParkedAfterRelease += 1 }
    }

    public func noteRowAppear() { integrity.rowAppears += 1 }
    public func noteRowDisappear() { integrity.rowDisappears += 1 }

    // MARK: teardown

    /// Window close: nothing may commit afterwards. Parked row tasks and engine continuations are released so late
    /// results run into the closed guard (counted), as in the Mac F9 oracle.
    public func close() {
        guard !closed else { return }
        integrity.tasksParkedAtClose = engine.parkedCount
        closed = true
        integrity.closed = true
        for task in inflight.values { task.cancel() }
        engine.releaseAll()
    }

    public func noteCommitAfterClose() { integrity.commitsAfterClose += 1 }

    /// Final snapshot for the integrity file.
    public func finalIntegrity() -> WorkloadIntegrity {
        var i = integrity
        i.rowsFinal = rowTotal
        i.typedCount = typedCount
        i.activeText = active.text
        var seen = Set<UUID>([active.id])
        for r in rows where !seen.insert(r.id).inserted { i.uniqueIDs = false }
        return i
    }

    public static func integrityJSON(_ i: WorkloadIntegrity, extra: [String: Any] = [:]) -> String {
        var d: [String: Any] = [
            "rows_final": i.rowsFinal, "rows_min": i.rowsMin, "rows_max": i.rowsMax, "unique_ids": i.uniqueIDs,
            "active_text": i.activeText, "typed_count": i.typedCount, "wrong_node_edits": i.wrongNodeEdits,
            "stale_committed": i.staleCommitted, "stale_rejected": i.staleRejected,
            "updates_started": i.updatesStarted, "updates_committed": i.updatesCommitted,
            "inserts_started": i.insertsStarted, "inserts_committed": i.insertsCommitted,
            "kills": i.kills, "reorders": i.reorders, "anim_bursts": i.animBursts, "anim_interrupts": i.animInterrupts,
            "ops_skipped": i.opsSkipped, "row_task_starts": i.rowTaskStarts, "row_task_cancels": i.rowTaskCancels,
            "row_appears": i.rowAppears, "row_disappears": i.rowDisappears,
            "commits_after_close": i.commitsAfterClose, "late_results_after_close": i.lateResultsAfterClose,
            "closed": i.closed, "tasks_parked_at_close": i.tasksParkedAtClose,
            "tasks_parked_after_release": i.tasksParkedAfterRelease,
        ]
        for (k, v) in extra { d[k] = v }
        let data = (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys, .prettyPrinted])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - main-actor enqueue -> execution sampler

/// Samples Swift main-actor enqueue-to-execution latency (architecture section 11: p99 <= 16.7 ms on Windows).
/// A background thread stamps the clock, enqueues a `@MainActor` task, and the task stamps the clock when it runs.
/// 200 samples/s. Thread start/stop only; no allocation in the sampled path beyond the Task itself.
public final class MainActorSampler: @unchecked Sendable {
    private let recorder: RunRecorder
    private var thread: Thread?
    private let stopLock = NSLock()
    private var stopped = false
    private let intervalMS: Int

    public init(recorder: RunRecorder, intervalMS: Int = 5) {
        self.recorder = recorder
        self.intervalMS = intervalMS
    }

    public func start() {
        let t = Thread { [self] in
            while true {
                stopLock.lock(); let done = stopped; stopLock.unlock()
                if done { return }
                let enqueue = WClock.ticks()
                Task { @MainActor [recorder] in
                    recorder.addMainActor(.init(enqueueTicks: enqueue, execTicks: WClock.ticks()))
                }
                Thread.sleep(forTimeInterval: Double(intervalMS) / 1000)
            }
        }
        t.name = "workload-main-actor-sampler"
        t.qualityOfService = .userInitiated
        thread = t
        t.start()
    }

    public func stop() {
        stopLock.lock(); stopped = true; stopLock.unlock()
    }
}

// MARK: - instrumentation overhead micro-benchmark

public enum OverheadBench {
    /// Cost of one timestamp pair (the unit every Swift timer in the Windows host pays) and of one recorder append.
    public static func run(into recorder: RunRecorder) {
        let n = 200_000
        var sink: UInt64 = 0
        let a = WClock.ticks()
        for _ in 0..<n { let s = WClock.ticks(); let e = WClock.ticks(); sink &+= e &- s }
        let b = WClock.ticks()
        recorder.addOverhead(.init(name: "timestamp_pair", nsPerPair: WClock.ms(b &- a) * 1_000_000 / Double(n), iterations: n))
        let scratch = RunRecorder()
        let c = WClock.ticks()
        for i in 0..<20_000 { scratch.addFrame(.init(version: UInt64(i), startTicks: 0, endTicks: 0, bridgeNS: 0, measureCalls: 0, upserts: 0, paints: 0)) }
        let d = WClock.ticks()
        recorder.addOverhead(.init(name: "recorder_append", nsPerPair: WClock.ms(d &- c) * 1_000_000 / 20_000, iterations: 20_000))
        if sink == 42 { print("") }
    }
}

// MARK: - headless model self-test (no window, no GUI)

extension WorkloadModel {
    /// Replays the schedule at 60 Hz on a synthetic clock for `seconds`, typing at 10 Hz into the active row, and
    /// returns the integrity. Used on both OSes to check the model before any GUI run. The task queue is pumped with
    /// `Task.yield` between steps.
    @MainActor
    public static func headlessSelfTest(seconds: Double, config: WorkloadConfig = WorkloadConfig()) async -> (WorkloadIntegrity, [String]) {
        let recorder = RunRecorder()
        let model = WorkloadModel(config: config, recorder: recorder)
        var failures: [String] = []
        let hz = WClock.hz
        let step = hz / 60
        var now: UInt64 = 1_000_000
        let end = now + UInt64(seconds * Double(hz))
        var typed = ""
        var nextKey = now
        let alphabet = Array("mwqogdhbnk")
        var k = 0
        while now < end {
            model.advance(nowTicks: now)
            if now >= nextKey {
                let c = alphabet[k % alphabet.count]
                k += 1
                typed.append(c)
                model.userEdit(model.active.id, typed)
                nextKey += hz / 10
            }
            for _ in 0..<3 { await Task.yield() }
            if model.rowTotal != config.totalRows { failures.append("row total \(model.rowTotal) at \(WClock.seconds(now - 1_000_000))s") ; break }
            now += step
        }
        for _ in 0..<5 { await Task.yield() }
        model.close()
        for _ in 0..<20 { await Task.yield() }
        let i = model.finalIntegrity()
        if !i.uniqueIDs { failures.append("duplicate row ids") }
        if i.wrongNodeEdits != 0 { failures.append("wrong-node edits \(i.wrongNodeEdits)") }
        if i.staleCommitted != 0 { failures.append("stale commits \(i.staleCommitted)") }
        if i.activeText != typed { failures.append("active text mismatch") }
        if i.typedCount != k { failures.append("typed count \(i.typedCount) != sent \(k)") }
        if i.rowsMin != config.totalRows || i.rowsMax != config.totalRows { failures.append("row count range \(i.rowsMin)...\(i.rowsMax)") }
        if i.reorders < Int(seconds) - 2 { failures.append("reorders \(i.reorders)") }
        if i.updatesStarted + i.insertsStarted < Int(seconds * 20) - 20 { failures.append("ops started \(i.updatesStarted + i.insertsStarted)") }
        if i.staleRejected == 0 { failures.append("cancellation never exercised (stale_rejected = 0)") }
        if i.animInterrupts == 0 { failures.append("no interrupted animation") }
        return (i, failures)
    }
}

// MARK: - command line

public struct WorkloadArgs {
    public var config = WorkloadConfig()
    public var options: [String: String] = [:]

    /// `--key value` pairs and bare `--flag`s. Known keys: run-id, out, warmup-s, measure-s, instr, seed.
    public init(_ arguments: [String]) {
        var i = 1
        while i < arguments.count {
            let a = arguments[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if i + 1 < arguments.count, !arguments[i + 1].hasPrefix("--") {
                    options[key] = arguments[i + 1]
                    i += 1
                } else {
                    options[key] = "1"
                }
            }
            i += 1
        }
        if let v = options["run-id"] { config.runID = v }
        if let v = options["out"] { config.outDir = v }
        if let v = options["warmup-s"], let d = Double(v) { config.warmupS = d }
        if let v = options["measure-s"], let d = Double(v) { config.measureS = d }
        if let v = options["instr"], let l = InstrLevel(rawValue: v) { config.instr = l }
        if let v = options["seed"], let s = UInt64(v) { config.seed = s }
    }
}

public func jsonString(_ d: [String: Any]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys, .prettyPrinted])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}
