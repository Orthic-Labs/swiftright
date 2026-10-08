import CDispatchPrivate
import CSwiftRightRender
import Dispatch
import Foundation
import WinSDK

// SR0-B probe. Synchronous entry on the initial thread (no async main).
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
}

let windowClosedCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    windowClosedCalls += 1
}

// ---- Entry ----

print("initial_thread_id=\(mainThreadId)")

var info = swr_bootstrap_info()
let queryRc = swr_bootstrap_query(&info, UInt32(MemoryLayout<swr_bootstrap_info>.size))
print("bootstrap_query_rc=\(queryRc) abi=\(info.abi_major).\(info.abi_minor) pointer_width=\(info.pointer_width) fn_table_size=\(info.fn_table_size)")
guard queryRc == 0, info.abi_major == 0, info.abi_minor == 1, info.pointer_width == 64 else {
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
    window_closed: windowClosedCallback
)
let runRc = swr_run(&callbacks)
let mainThreadAfter = GetCurrentThreadId()

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

let pass = runRc == 0
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
