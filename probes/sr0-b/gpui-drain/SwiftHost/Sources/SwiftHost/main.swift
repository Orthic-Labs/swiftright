import CDispatchPrivate
import CSwiftRightRender
import Dispatch
import Foundation
import WinSDK

// SR0-B probe. Also carries the late-dispatch fault test (architecture.md stage B: "reject new
// work after shutdown begins & fault-test late dispatch"): continuations addressed to a stale
// window generation, a closed window or a removed node must be rejected or dropped, counted,
// and never delivered to Swift after the target is gone.
// Synchronous entry on the initial thread (no async main).
// GPUI's loop runs inside swr_run on this thread. Swift's main dispatch queue
// is drained from a GPUI foreground task via _dispatch_main_queue_callback_4CF.

let totalJobs = 5_000
let paceHz = 1_000
let totalHops = 500
let hopEvery = 10
let watchdogSeconds: Double = 120

let qpcFreq: Double = {
    var f = LARGE_INTEGER()
    _ = QueryPerformanceFrequency(&f)
    return Double(f.QuadPart)
}()

@inline(__always) func qpcNow() -> Int64 {
    var c = LARGE_INTEGER()
    _ = QueryPerformanceCounter(&c)
    return c.QuadPart
}

func msSince(_ t: Int64) -> Double { Double(qpcNow() - t) * 1000.0 / qpcFreq }

// Set once on the initial thread, before swr_run.
let mainThreadId: UInt32 = GetCurrentThreadId()

// Written by the producer before enqueue, read on the main thread after the
// job runs. Dispatch enqueue provides the happens-before edge.
let enqueueTicks = UnsafeMutablePointer<Int64>.allocate(capacity: totalJobs)
let latenciesMs = UnsafeMutablePointer<Double>.allocate(capacity: totalJobs)
latenciesMs.initialize(repeating: -1, count: totalJobs)

// Main-thread-only state.
var jobsRun = 0
var jobThreadMismatches = 0
var hopsRun = 0
var hopThreadMismatches = 0
var drainCalls = 0
var drainReentryViolations = 0
var drainThreadMismatches = 0
var drainingSwift = false
var selftestRan = false
var selftestResult: Int32 = -99
var loopReadyCalls = 0
var loopReadyThreadMismatches = 0
var windowClosedCalls = 0
var framesAtStart: UInt64 = 0
var framesAtEnd: UInt64 = 0
var workloadStartTick: Int64 = 0
var workloadEndTick: Int64 = 0
var quitIssued = false

// Late-dispatch fault test. Job callback state is main-thread-only; the fault thread owns the rest.
var lateDelivered = 0
var lateDeliveredAfterClose = 0
var lateDeliveredDeadNode = 0
var lateThreadMismatches = 0
let liveNodeId: UInt64 = 7
let deadNodeId: UInt64 = 8
var lateRcValid: Int32 = -99
var lateRcWrongGen: Int32 = -99
var lateRcNoGen: Int32 = -99
var lateRcLiveNode: Int32 = -99
var lateRcDeadNode: Int32 = -99
var lateStormOk = 0
var lateStormStale = 0
var lateStormFull = 0
var lateStormOther = 0
var lateStormDone = false
let lateStormStaleTarget = 200

// Cross-thread state.
let stateLock = NSLock()
var finishedFlag = false
var watchdogFired = false

func maybeFinish() {
    guard !quitIssued, jobsRun == totalJobs, hopsRun == totalHops else { return }
    quitIssued = true
    workloadEndTick = qpcNow()
    framesAtEnd = swr_frames_rendered()
    stateLock.lock()
    finishedFlag = true
    stateLock.unlock()
    // Quit from a main-queue job, as the spec requires.
    DispatchQueue.main.async {
        _ = swr_request_quit()
    }
}

func runProducer() {
    let period = Int64(qpcFreq / Double(paceHz))
    let start = qpcNow()
    var hopsEnqueued = 0
    for i in 0..<totalJobs {
        let target = start + Int64(i) * period
        while qpcNow() < target { Sleep(0) }
        enqueueTicks[i] = qpcNow()
        DispatchQueue.main.async {
            latenciesMs[i] = msSince(enqueueTicks[i])
            jobsRun += 1
            if GetCurrentThreadId() != mainThreadId { jobThreadMismatches += 1 }
            maybeFinish()
        }
        if i % hopEvery == 0 && hopsEnqueued < totalHops {
            hopsEnqueued += 1
            Task { @MainActor in
                hopsRun += 1
                if GetCurrentThreadId() != mainThreadId { hopThreadMismatches += 1 }
                maybeFinish()
            }
        }
    }
    print("producer enqueue_rate_hz=\(Double(totalJobs) / (Double(qpcNow() - start) / qpcFreq)) hops_enqueued=\(hopsEnqueued)")
}

// Runs on its own thread from loop_ready. Targets the live window generation, then keeps posting
// through window close until the runtime has rejected lateStormStaleTarget late posts.
func runLateDispatchFault() {
    let gen = swr_window_generation()
    lateRcValid = swr_post_job(gen, 0, 1)
    lateRcWrongGen = swr_post_job(gen &+ 1000, 0, 2)
    lateRcNoGen = swr_post_job(0, 0, 3)
    _ = swr_node_set(liveNodeId, 1)
    lateRcLiveNode = swr_post_job(gen, liveNodeId, 4)
    _ = swr_node_set(deadNodeId, 1)
    _ = swr_node_set(deadNodeId, 0)
    lateRcDeadNode = swr_post_job(gen, deadNodeId, 5)

    let deadline = qpcNow() + Int64(qpcFreq * 150.0)
    var token: UInt64 = 100
    while qpcNow() < deadline {
        token += 1
        let rc = swr_post_job(gen, 0, token)
        switch rc {
        case 0: lateStormOk += 1
        case -7: lateStormStale += 1
        case -8: lateStormFull += 1
        default: lateStormOther += 1
        }
        if lateStormStale >= lateStormStaleTarget { break }
        Sleep(1)
    }
    stateLock.lock()
    lateStormDone = true
    stateLock.unlock()
}

func runWatchdog() {
    Thread.sleep(forTimeInterval: watchdogSeconds)
    stateLock.lock()
    let done = finishedFlag
    if !done { watchdogFired = true }
    stateLock.unlock()
    if !done { _ = swr_request_quit() }
}

func drainMainQueueFromRust() {
    drainCalls += 1
    if drainingSwift {
        drainReentryViolations += 1
        return
    }
    if GetCurrentThreadId() != mainThreadId { drainThreadMismatches += 1 }
    if !selftestRan {
        selftestRan = true
        selftestResult = swr_selftest_reentry()
    }
    drainingSwift = true
    _dispatch_main_queue_callback_4CF(nil)
    drainingSwift = false
}

let drainCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    drainMainQueueFromRust()
}

let loopReadyCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    loopReadyCalls += 1
    if GetCurrentThreadId() != mainThreadId { loopReadyThreadMismatches += 1 }
    framesAtStart = swr_frames_rendered()
    workloadStartTick = qpcNow()
    Thread { runProducer() }.start()
    Thread { runWatchdog() }.start()
    Thread { runLateDispatchFault() }.start()
}

let jobCallback: @convention(c) (UnsafeMutableRawPointer?, UInt64, UInt64) -> Void = { _, node, _ in
    lateDelivered += 1
    if GetCurrentThreadId() != mainThreadId { lateThreadMismatches += 1 }
    if windowClosedCalls > 0 { lateDeliveredAfterClose += 1 }
    if node == deadNodeId { lateDeliveredDeadNode += 1 }
}

let windowClosedCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    windowClosedCalls += 1
}

// ---- Entry ----

print("initial_thread_id=\(mainThreadId)")

var info = swr_bootstrap_info()
let queryRc = swr_bootstrap_query(&info, UInt32(MemoryLayout<swr_bootstrap_info>.size))
print("bootstrap_query_rc=\(queryRc) abi=\(info.abi_major).\(info.abi_minor) pointer_width=\(info.pointer_width) fn_table_size=\(info.fn_table_size)")
guard queryRc == 0, info.abi_major == 0, info.abi_minor == 2, info.pointer_width == 64 else {
    print("bootstrap_rejected")
    exit(2)
}

let wakeHandle = _dispatch_get_main_queue_handle_4CF()
print("main_queue_wake_handle=\(String(describing: wakeHandle))")
let setRc = swr_set_wake_handle(wakeHandle)

var callbacks = swr_host_callbacks(
    struct_size: UInt32(MemoryLayout<swr_host_callbacks>.size),
    ctx: nil,
    loop_ready: loopReadyCallback,
    drain: drainCallback,
    window_closed: windowClosedCallback,
    job: jobCallback
)
let runRc = swr_run(&callbacks)
let mainThreadAfter = GetCurrentThreadId()

// Late dispatch after the loop has ended: the generation is retired, so this must be rejected.
let lateRcAfterRun = swr_post_job(swr_window_generation() &+ 1, 0, 999)
let lateRcAfterRunOldGen = swr_post_job(1, 0, 998)
var lateWaitMs = 0
while lateWaitMs < 5000 {
    stateLock.lock()
    let d = lateStormDone
    stateLock.unlock()
    if d { break }
    Thread.sleep(forTimeInterval: 0.05)
    lateWaitMs += 50
}
var lateStats = swr_late_stats_t()
let lateStatsRc = swr_late_stats(&lateStats, UInt32(MemoryLayout<swr_late_stats_t>.size))

// ---- Report (main thread, after swr_run returned) ----

let jobsDone = jobsRun
var latencies = Array(UnsafeBufferPointer(start: latenciesMs, count: totalJobs)).filter { $0 >= 0 }
latencies.sort()
// Nearest-rank percentile.
func pct(_ p: Double) -> Double {
    guard !latencies.isEmpty else { return -1 }
    let rank = max(1, Int((Double(latencies.count) * p).rounded(.up)))
    return latencies[min(latencies.count, rank) - 1]
}
let p50 = pct(0.50)
let p95 = pct(0.95)
let p99 = pct(0.99)
let pmax = latencies.last ?? -1
let frames = framesAtEnd &- framesAtStart
let workloadSeconds = Double(workloadEndTick &- workloadStartTick) / qpcFreq
let mismatches = jobThreadMismatches + hopThreadMismatches + drainThreadMismatches + loopReadyThreadMismatches
let reentry = drainReentryViolations

print("jobs_run=\(jobsDone)/\(totalJobs)")
print(String(format: "latency_ms p50=%.4f p95=%.4f p99=%.4f max=%.4f", p50, p95, p99, pmax))
print("thread_mismatches=\(mismatches) (jobs=\(jobThreadMismatches) hops=\(hopThreadMismatches) drain=\(drainThreadMismatches) loop_ready=\(loopReadyThreadMismatches))")
print("reentrancy_violations_swift=\(reentry) drain_calls_swift=\(drainCalls) selftest_swift_result=\(selftestResult)")
print("mainactor_hops=\(hopsRun)/\(totalHops)")
print("frames_during_workload=\(frames) workload_s=\(String(format: "%.3f", workloadSeconds)) frames_at_start=\(framesAtStart) frames_at_end=\(framesAtEnd)")
print("loop_ready_calls=\(loopReadyCalls) window_closed_calls=\(windowClosedCalls) watchdog_fired=\(watchdogFired)")
print("swr_set_wake_handle_rc=\(setRc) swr_run_rc=\(runRc) main_thread_after_run_same=\(mainThreadAfter == mainThreadId)")

stateLock.lock()
let lateDone = lateStormDone
stateLock.unlock()
let lateAccounted = lateStats.posted_ok == lateStats.delivered + lateStats.dropped_at_close + lateStats.dropped_at_deliver
let lateOk = lateStatsRc == 0
    && lateDone
    && lateRcValid == 0 && lateRcWrongGen == -7 && lateRcNoGen == -7
    && lateRcLiveNode == 0 && lateRcDeadNode == -7
    && lateRcAfterRun == -7 && lateRcAfterRunOldGen == -7
    && lateDeliveredAfterClose == 0 && lateDeliveredDeadNode == 0 && lateThreadMismatches == 0
    && lateAccounted
    && UInt64(lateDelivered) == lateStats.delivered
    && lateDelivered >= 2
    && lateStats.rejected_stale_gen >= 1 && lateStats.rejected_stale_node >= 1
    && lateStats.rejected_closed >= UInt64(lateStormStaleTarget)
    && lateStormOther == 0
print("late_dispatch rc_valid=\(lateRcValid) rc_wrong_gen=\(lateRcWrongGen) rc_no_gen=\(lateRcNoGen) rc_live_node=\(lateRcLiveNode) rc_dead_node=\(lateRcDeadNode) rc_after_run=\(lateRcAfterRun) rc_after_run_old_gen=\(lateRcAfterRunOldGen)")
print("late_dispatch storm_ok=\(lateStormOk) storm_stale=\(lateStormStale) storm_full=\(lateStormFull) storm_other=\(lateStormOther) storm_done=\(lateDone)")
print("late_dispatch swift_delivered=\(lateDelivered) delivered_after_close=\(lateDeliveredAfterClose) delivered_dead_node=\(lateDeliveredDeadNode) thread_mismatches=\(lateThreadMismatches)")
print("late_dispatch stats_rc=\(lateStatsRc) posted_ok=\(lateStats.posted_ok) delivered=\(lateStats.delivered) dropped_at_close=\(lateStats.dropped_at_close) dropped_at_deliver=\(lateStats.dropped_at_deliver) rejected_closed=\(lateStats.rejected_closed) rejected_stale_gen=\(lateStats.rejected_stale_gen) rejected_stale_node=\(lateStats.rejected_stale_node) rejected_full=\(lateStats.rejected_full) accounted=\(lateAccounted)")
print("late_dispatch_verdict=\(lateOk ? "PASS" : "FAIL")")

let pass = runRc == 0
    && lateOk
    && jobsDone == totalJobs
    && hopsRun == totalHops
    && mismatches == 0
    && reentry == 0
    && p99 >= 0 && p99 <= 16.7
    && frames > 0
    && windowClosedCalls == 1
    && !watchdogFired
    && mainThreadAfter == mainThreadId
print("verdict=\(pass ? "PASS" : "FAIL")")
exit(pass ? 0 : 1)
