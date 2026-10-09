import Foundation
import SwiftRightRuntime
import SwiftRightBridge
import WorkloadCore

// WorkloadWin: the SR0 section 11 workload on the fresh runtime + the real Windows renderer (bridge ABI 0.6).
//
//   WorkloadWin.exe --run-id r1 --out <dir> [--warmup-s 10] [--measure-s 60] [--instr full|light]
//   WorkloadWin.exe --model-selftest <seconds>      headless model check (no window, no renderer)
//   WorkloadWin.exe --count-nodes                   headless runtime-only check: resolved node counts + flush timings
//   WorkloadWin.exe --overhead                      timer micro-benchmark only
//   WorkloadWin.exe --bench [--rows N --iters N --only keystroke|row|reorder|insert|tick|anim] [--verify]
//                                                   headless commit benchmark / equivalence check against a mock renderer (Bench.swift)
//
// Self-timed: 10 s warm-up, 60 s measured run, window close (teardown + post-close pump), then raw CSVs,
// integrity.json and meta.json are written to --out. The external driver (scripts/inject.ps1) posts the keystrokes.
// Exit codes: 0 complete, 1 run failed or ended early, 78 startup diagnostic.

let args = WorkloadArgs(CommandLine.arguments)

@MainActor
func countNodes() -> Int32 {
    var config = args.config
    config.runID = "count"
    let recorder = RunRecorder()
    let model = WorkloadModel(config: config, recorder: recorder)
    let graph = Graph(WorkloadRoot(model: model), measurer: nil, scale: 1)
    graph.rootProposal = ProposedViewSize(width: 960, height: 640)
    var kinds: [String: Int] = [:]
    var total = 0
    func visit(_ n: ResolvedNode) {
        total += 1
        kinds[n.kind, default: 0] += 1
        n.children.forEach(visit)
    }
    let t0 = WClock.ticks()
    graph.flush()
    let t1 = WClock.ticks()
    guard let root = graph.snapshot() else { print("COUNT-NODES FAIL no snapshot"); return 1 }
    visit(root)
    print("COUNT-NODES total=\(total) first_flush_ms=\(WClock.ms(t1 &- t0))")
    for (k, v) in kinds.sorted(by: { $0.value > $1.value }).prefix(14) { print("  \(k): \(v)") }
    var now: UInt64 = 1_000_000
    var flushMS: [Double] = []
    for _ in 0..<300 {
        now += WClock.hz / 60
        model.advance(nowTicks: now)
        let a = WClock.ticks()
        graph.flush()
        flushMS.append(WClock.ms(WClock.ticks() &- a))
    }
    flushMS.sort()
    print("COUNT-NODES runtime_flush_ms p50=\(flushMS[150]) p95=\(flushMS[285]) max=\(flushMS.last!) (default measurer, no bridge)")
    print("COUNT-NODES limits: upserts <= 4096, primitives <= 65536 per transaction (swiftright.h)")
    return total <= 4096 ? 0 : 2
}

@MainActor
func runWorkload() -> Int32 {
    let bridge: Bridge
    do {
        bridge = try Bridge.load()
    } catch BridgeError.startup(let message) {
        print(message)
        return 78
    } catch {
        print("SWR_STARTUP_ERROR: \(error)")
        return 78
    }
    let config = args.config
    let recorder = RunRecorder()
    let model = WorkloadModel(config: config, recorder: recorder)
    let platform = BridgePlatform(bridge: bridge)
    let backend = WinBackend(platform: platform, model: model, recorder: recorder, config: config)
    bridge.textStore = WorkloadTextStore(backend: backend)
    var sampler: MainActorSampler?
    var finished = false

    backend.onFinished = {
        guard !finished else { return }
        finished = true
        sampler?.stop()
        writeOutputs(bridge: bridge, backend: backend, model: model, recorder: recorder, config: config, aborted: false)
        try? bridge.shutdownComplete()
        bridge.requestQuit()
    }
    bridge.onReady = { win in
        MainActor.assumeIsolated {
            platform.attach(win)
            backend.ready()
            if config.instr == .full {
                let s = MainActorSampler(recorder: recorder)
                s.start()
                sampler = s
            }
        }
    }
    bridge.onEvent = { ev in MainActor.assumeIsolated { backend.handle(ev) } }
    bridge.onTick = { _, ts in MainActor.assumeIsolated { backend.tick(timestampNS: ts) } }
    bridge.onWindowClosed = { MainActor.assumeIsolated { backend.closed(); platform.detach() } }

    do {
        try bridge.run(title: "SwiftRight SR0 Workload", width: 960, height: 640)
    } catch {
        print("run failed: \(error)")
        fflush(stdout)
        return 1
    }
    if !finished {
        sampler?.stop()
        writeOutputs(bridge: bridge, backend: backend, model: model, recorder: recorder, config: config, aborted: true)
        return 1
    }
    return 0
}

@MainActor
func writeOutputs(bridge: Bridge, backend: WinBackend, model: WorkloadModel, recorder: RunRecorder, config: WorkloadConfig, aborted: Bool) {
    let dir = config.outDir
    recorder.write(dir: dir)
    let end = bridge.statsSnap()
    let start = backend.statsAtReady
    let i = model.finalIntegrity()
    let extra: [String: Any] = [
        "run_id": config.runID,
        "app_exit": aborted ? "aborted" : "complete",
        "commit_count": backend.commitCount,
        "commit_errors": backend.commitErrors.count,
        "commit_error_first": backend.commitErrors.first ?? "",
        "draw_failures": backend.drawFailures,
        "measurer_failures": backend.measurerFailures(),
        "max_upserts_per_commit": backend.maxUpserts,
        "max_primitives_per_commit": backend.maxPrimitives,
        "ticks_seen": backend.tickCount,
        "commits_after_close_backend": backend.commitsAfterClose,
        "live_nodes_at_pump": Int(backend.liveNodesAtPump),
        "pump_hops": backend.pumpHops,
        "scale_changes": backend.scaleChanges,
        "renderer_paints": Int(end.paints &- (start?.paints ?? 0)),
        "renderer_commits_accepted": Int(end.commitsAccepted &- (start?.commitsAccepted ?? 0)),
        "renderer_commits_rejected": Int(end.commitsRejected &- (start?.commitsRejected ?? 0)),
        "renderer_commits_deferred": Int(end.commitsDeferred &- (start?.commitsDeferred ?? 0)),
        "renderer_measure_calls": Int(end.measureCalls &- (start?.measureCalls ?? 0)),
        "renderer_measure_cache_hits": Int(end.measureCacheHits &- (start?.measureCacheHits ?? 0)),
        "renderer_ticks_delivered": Int(end.ticksDelivered &- (start?.ticksDelivered ?? 0)),
        "renderer_host_panics": Int(end.hostPanics),
        "renderer_reentry_refused": Int(end.reentryRefused),
        "renderer_thread_violations": Int(end.threadViolations),
        "renderer_events_dropped_full": Int(end.eventsDroppedFull),
        "renderer_live_nodes_final": Int(end.liveNodes),
        "bridge_timed_calls": backend.clock.calls,
        "bridge_measure_calls_timed": backend.clock.measureCalls,
    ]
    try? WorkloadModel.integrityJSON(i, extra: extra).write(toFile: dir + "/integrity.json", atomically: true, encoding: .utf8)
    var meta: [String: Any] = [
        "run_id": config.runID,
        "platform": "windows",
        "instr": config.instr.rawValue,
        "clock": WClock.name,
        "hz": Int(WClock.hz),
        "t0_ticks": Int(model.t0),
        "measure_start_ticks": Int(model.measureStartTicks),
        "measure_end_ticks": Int(model.measureEndTicks),
        "warmup_s": config.warmupS,
        "measure_s": config.measureS,
        "seed": String(config.seed),
        "window_dip": ["w": 960, "h": 640],
        "total_rows": config.totalRows,
        "abi_major": Int(bridge.info.abi_major),
        "abi_minor": Int(bridge.info.abi_minor),
        "pid": Int(ProcessInfo.processInfo.processIdentifier),
        "font": "Segoe UI 16/24 DIP",
    ]
    for (k, v) in recorder.meta { meta[k] = v }
    try? jsonString(meta).write(toFile: dir + "/meta.json", atomically: true, encoding: .utf8)
    print("WORKLOAD-WIN-DONE run=\(config.runID) dir=\(dir) aborted=\(aborted)")
    fflush(stdout)
}

let status: Int32
if args.options["model-selftest"] != nil {
    #if os(Windows)
    // The main queue is drained only by the renderer's pump on Windows, so a headless MainActor replay cannot run
    // here. The model is shared source: run `WorkloadMac --model-selftest 30` on macOS for it.
    print("MODEL-SELFTEST not available on Windows (shared core; run WorkloadMac --model-selftest on macOS)")
    status = 2
    #else
    let seconds = Double(args.options["model-selftest"] ?? "") ?? 30
    Task { @MainActor in
        let (integrity, failures) = await WorkloadModel.headlessSelfTest(seconds: seconds)
        print(WorkloadModel.integrityJSON(integrity))
        for f in failures { print("MODEL-SELFTEST FAIL: \(f)") }
        if failures.isEmpty { print("MODEL-SELFTEST PASS (\(seconds) s synthetic)") }
        exit(failures.isEmpty ? 0 : 1)
    }
    dispatchMain()
    #endif
} else if args.options["overhead"] != nil {
    let r = RunRecorder()
    OverheadBench.run(into: r)
    for o in r.overhead { print("\(o.name): \(o.nsPerPair) ns (n=\(o.iterations))") }
    status = 0
} else if args.options["bench"] != nil {
    status = MainActor.assumeIsolated { runBench(arguments: args.options) }
} else if args.options["count-nodes"] != nil {
    status = MainActor.assumeIsolated { countNodes() }
} else {
    status = MainActor.assumeIsolated { runWorkload() }
}
fflush(stdout)
exit(status)
