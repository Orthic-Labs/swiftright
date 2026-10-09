import Foundation
import SwiftRightRuntime
import SwiftRightBridge
import WorkloadCore

// Headless soak (R10 memory diagnosis). The workload's own schedule (20 async row updates/inserts per second, one reorder per second,
// animated inserts, cancellations, 60 Hz scrolling commits, 10 keystrokes per second into the active field) runs for N simulated seconds
// through the real model, the real runtime and the real WinBackend commit conversion, against the mock renderer surface (Bench.swift),
// as fast as the CPU allows (no window, no renderer, no GUI, safe on a busy host).
//
//   WorkloadWin --soak [--soak-s 300] [--report-s 15] [--warm-s 20] [--rows 200] [--instr full|light] [--census] [--marshal] [--hold S]
//   (--marshal also builds and frees each commit's C transaction, the bridge's host-side allocation pattern)
//
// Prints, every `report-s` simulated seconds, process memory (Windows: heap allocated / committed / private bytes; macOS: malloc in use /
// allocated / footprint) next to the size of every table the app keeps (graph, backend, model, trace buffers), then a summary: the growth
// slope of each memory figure over the window after `warm-s`, the slope of the trace buffers alone, and the app-only remainder.
//
// What it leaves out: the real renderer (Rust heap, DirectWrite, D3D, UIA: the process heap outside this code) and the bridge's
// marshalling arenas, which are allocated and freed within one call.

/// The mock renderer plus the bridge's host-side commit marshalling (`Bridge.marshalOnly`): what `--soak --marshal` runs, so the
/// soak sees the allocation pattern of the C transaction as well.
@MainActor
final class MarshalPlatform: BackendPlatform {
    let inner: MockPlatform
    init(_ inner: MockPlatform) { self.inner = inner }
    func metrics() throws -> (width: UInt32, height: UInt32, scale: Float, active: Bool) { try inner.metrics() }
    func requestTicks(_ on: Bool) throws { try inner.requestTicks(on) }
    func requestClose() throws { try inner.requestClose() }
    func measure(_ request: MeasureRequest) throws -> SwiftRightBridge.TextMeasurement { try inner.measure(request) }
    func cells(of run: TextRunHandle) throws -> [CharCell] { try inner.cells(of: run) }
    @discardableResult func release(_ run: TextRunHandle) -> Bool { inner.release(run) }
    func commit(_ transaction: Transaction) throws {
        Bridge.marshalOnly(transaction)
        try inner.commit(transaction)
    }
    func stats() -> StatsSnap { inner.stats() }
    var liveRuns: Int { inner.liveRuns }
    var eventsDelivered: Int { 0 }
}

@MainActor
func runSoak(arguments: [String: String]) -> Int32 {
    let rows = Int(arguments["rows"] ?? "") ?? 200
    let simSeconds = Double(arguments["soak-s"] ?? "") ?? 300
    let reportEvery = Double(arguments["report-s"] ?? "") ?? 15
    let warm = Double(arguments["warm-s"] ?? "") ?? 20
    let instr = InstrLevel(rawValue: arguments["instr"] ?? "full") ?? .full
    let census = arguments["census"] != nil
    let keyHz = Double(arguments["key-hz"] ?? "") ?? 10

    var config = WorkloadConfig()
    config.totalRows = rows
    config.instr = instr
    config.warmupS = 1e9           // the model's own phase gate never ends the soak
    config.measureS = 1e9
    let recorder = RunRecorder()
    let model = WorkloadModel(config: config, recorder: recorder)
    let platform = MockPlatform(verify: false)
    let marshal = arguments["marshal"] != nil
    let backend = WinBackend(platform: marshal ? MarshalPlatform(platform) : platform, model: model, recorder: recorder, config: config)
    backend.ready()
    guard let fieldNode = backend.firstFieldNode() else {
        print("SOAK FAIL: no text field in the tree")
        return 1
    }

    func mb(_ bytes: UInt64) -> String { String(format: "%.2f", Double(bytes) / 1_048_576) }
    func mb(_ bytes: Int) -> String { mb(UInt64(max(bytes, 0))) }

    struct Row { var t: Double; var mem: MemSample; var trace: Int }
    var rowsOut: [Row] = []

    func report(_ t: Double, wall: Double) {
        let mem = MemProbe.sample()
        let trace = recorder.traceFootprint
        let g = backend.graph?.counts() ?? Graph.Counts()
        let b = backend.counts()
        let m = model.counters
        rowsOut.append(Row(t: t, mem: mem, trace: trace.usedBytes))
        var line = "[t=\(String(format: "%5.0f", t))s wall=\(String(format: "%5.1f", wall))s] priv=\(mb(mem.privateBytes)) alloc=\(mb(mem.heapAllocated)) commit=\(mb(mem.heapCommitted)) MB"
        if mem.blocks > 0 { line += " blocks=\(mem.blocks)" }
        line += " | trace used=\(mb(trace.usedBytes)) reserved=\(mb(trace.reservedBytes)) MB items=\(trace.items)"
        line += " | model rows=\(m.rows) gen=\(m.generation) detailV=\(m.detailVersion) inflight=\(m.inflight) kill=\(m.killQueue) parked=\(m.parked) timed=\(m.timed)"
        line += " | graph nodes=\(g.nodes) str=\(g.nodesByString) anim=\(g.animating) dirty=\(g.dirty) size$=\(g.sizeCacheEntries) memo=\(g.memoEntries) rowc=\(g.rowCacheEntries) stor=\(g.nodeStorageEntries) tasks=\(g.tasks) tether=\(g.tethers) obsCb=\(g.observationCallbacks) types=\(g.viewTypeInfos) txq=\(g.queuedTransactions) defer=\(g.deferredCompletions)"
        line += " | backend sent=\(b.sentNodes) runs=\(b.retainedRuns) cells=\(b.cellsHeld) ax=\(b.axRunsHeld) fld=\(b.runtimeFieldByBridge) row=\(b.rowByBridgeField) geom=\(b.fieldGeometry) err=\(b.commitErrors) | mock runs=\(platform.liveRuns)"
        print(line)
        fflush(stdout)
    }

    print("SOAK marshal=\(marshal) rows=\(rows) sim=\(Int(simSeconds))s report=\(Int(reportEvery))s warm=\(Int(warm))s instr=\(instr.rawValue) key=\(keyHz)Hz clock=\(WClock.name) pid=\(ProcessInfo.processInfo.processIdentifier)")
    let wall0 = WClock.ticks()
    var now: UInt64 = 1_000_000
    let hz = WClock.hz
    let frame = hz / 60
    let keyEvery = max(1, Int((60 / keyHz).rounded()))
    let end = now + UInt64(simSeconds * Double(hz))
    let start = now
    let alphabet = Array("mwqogdhbnk".utf16)
    var frameIndex = 0
    var typedInField = 0
    var nextReport = reportEvery
    var before: HeapCensus?
    var tookBefore = false
    report(0, wall: 0)

    while now < end {
        now &+= frame
        frameIndex += 1
        let ns = UInt64(WClock.seconds(now) * 1_000_000_000)
        backend.tick(timestampNS: ns, nowTicks: now)
        if instr == .full {
            // the workload's main-actor sampler: 200 enqueue-to-execute samples per second, each one a Task on the main actor
            for _ in 0..<(frameIndex % 3 == 0 ? 4 : 3) {
                let enqueue = WClock.ticks()
                Task { @MainActor [recorder] in recorder.addMainActor(.init(enqueueTicks: enqueue, execTicks: WClock.ticks())) }
            }
        }
        if frameIndex % keyEvery == 0 {
            if typedInField >= 680 {
                model.userEdit(model.activeID, "")      // the real run types about 700 characters; keep the field at that size
                typedInField = 0
                backend.markDirty()
            }
            let unit = alphabet[frameIndex % alphabet.count]
            _ = backend.storeReplace(node: fieldNode, range: nil, text: [unit])
            typedInField += 1
        }
        Bridge.drainMainQueueHeadless()
        Bridge.drainMainQueueHeadless()
        let t = WClock.seconds(now &- start)
        if t >= nextReport {
            nextReport += reportEvery
            if census, !tookBefore, t >= warm {
                before = HeapCensus.take()
                tookBefore = true
                print("SOAK census taken at t=\(Int(t))s")
            }
            report(t, wall: WClock.seconds(WClock.ticks() &- wall0))
        }
    }
    // let late work run, then close the way the app does
    for _ in 0..<10 { Bridge.drainMainQueueHeadless() }
    let wall = WClock.seconds(WClock.ticks() &- wall0)

    // ---- summary
    func slope(_ points: [(Double, Double)]) -> Double {
        let n = Double(points.count)
        guard n >= 2 else { return .nan }
        let mx = points.map(\.0).reduce(0, +) / n, my = points.map(\.1).reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in points { num += (x - mx) * (y - my); den += (x - mx) * (x - mx) }
        return den == 0 ? .nan : num / den
    }
    let window = rowsOut.filter { $0.t >= warm }
    func perMinute(_ f: (Row) -> Double) -> Double { slope(window.map { ($0.t / 60, f($0) / 1_048_576) }) }
    let privSlope = perMinute { Double($0.mem.privateBytes) }
    let allocSlope = perMinute { Double($0.mem.heapAllocated) }
    let commitSlope = perMinute { Double($0.mem.heapCommitted) }
    let traceSlope = perMinute { Double($0.trace) }
    func f3(_ v: Double) -> String { String(format: "%.3f", v) }
    print("SOAK-SUMMARY sim=\(Int(simSeconds))s wall=\(String(format: "%.1f", wall))s window=[\(Int(warm))s..] samples=\(window.count) instr=\(instr.rawValue)")
    print("SOAK-SLOPE MB/min: private=\(f3(privSlope)) heap_allocated=\(f3(allocSlope)) heap_committed=\(f3(commitSlope)) trace_used=\(f3(traceSlope)) | app-only private=\(f3(privSlope - traceSlope)) heap_allocated=\(f3(allocSlope - traceSlope))")
    if let first = window.first, let last = window.last {
        print("SOAK-DELTA t=\(Int(first.t))s..\(Int(last.t))s MB: private \(mb(first.mem.privateBytes))->\(mb(last.mem.privateBytes)) alloc \(mb(first.mem.heapAllocated))->\(mb(last.mem.heapAllocated)) commit \(mb(first.mem.heapCommitted))->\(mb(last.mem.heapCommitted)) trace \(mb(first.trace))->\(mb(last.trace))")
    }
    let m = model.finalIntegrity()
    print("SOAK-MODEL updates=\(m.updatesStarted)/\(m.updatesCommitted) inserts=\(m.insertsStarted)/\(m.insertsCommitted) kills=\(m.kills) stale_rejected=\(m.staleRejected) typed=\(m.typedCount) reorders=\(m.reorders) wrong=\(m.wrongNodeEdits) row_task_starts=\(m.rowTaskStarts) cancels=\(m.rowTaskCancels)")
    if census, let before {
        let after = HeapCensus.take()
        print("SOAK-CENSUS busy-block growth by size class (first sample after warm-up -> end); class k = 2^(k-1) < size <= 2^k bytes")
        for row in after.growth(since: before).prefix(14) {
            print("  class \(String(format: "%2d", row.sizeClass)) (<= \(1 << row.sizeClass) B): blocks \(row.count >= 0 ? "+" : "")\(row.count) bytes \(row.bytes >= 0 ? "+" : "")\(row.bytes)")
        }
        let totalGrowth = after.busyBytes.reduce(0, +) &- before.busyBytes.reduce(0, +)
        print("SOAK-CENSUS busy bytes \(mb(before.busyBytes.reduce(0, +)))->\(mb(after.busyBytes.reduce(0, +))) MB (delta \(Int64(bitPattern: totalGrowth)) B); free bytes \(mb(before.freeBytes))->\(mb(after.freeBytes)) MB")
    }
    if let hold = arguments["hold"].flatMap(Double.init) {
        print("SOAK holding for \(hold) s (pid \(ProcessInfo.processInfo.processIdentifier))")
        fflush(stdout)
        Thread.sleep(forTimeInterval: hold)
    }
    return model.integrity.wrongNodeEdits == 0 ? 0 : 1
}
