import CDispatchPrivate
import CSwiftRightRender
import Dispatch
import Foundation
import WinSDK

// SR0-B modal-loop probe. Synchronous entry on the initial thread.
// Swift main-queue jobs run from a GPUI foreground task via
// _dispatch_main_queue_callback_4CF inside the guarded drain callback.
// The Rust AccessKit queue is popped in the same drain callback.
// Runner (scripts/run-modal.ps1) performs a real SendInput border drag-resize
// and 2,000 UIA Invoke calls from a separate thread, closing the window mid-stream.

let totalJobs = 30_000          // 1 kHz, up to 30 s of workload (runner closes the window earlier)
let paceHz = 1_000
let totalHops = 500
let hopEvery = 10
let modalFallbackJob = 22_000   // TaskDialog is requested 300 jobs after the 3rd size/move loop exits (resize, move, drag); this is the fallback if that never happens
let watchdogSeconds: Double = 150
let axButtonNode: UInt64 = 2    // NodeId of the button in build_tree()

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

let mainThreadId: UInt32 = GetCurrentThreadId()

let enqueueTicks = UnsafeMutablePointer<Int64>.allocate(capacity: totalJobs)
let latenciesMs = UnsafeMutablePointer<Double>.allocate(capacity: totalJobs)
let phaseAt = UnsafeMutablePointer<UInt32>.allocate(capacity: totalJobs)
latenciesMs.initialize(repeating: -1, count: totalJobs)
phaseAt.initialize(repeating: 0xFF, count: totalJobs)
let loopAt = UnsafeMutablePointer<UInt32>.allocate(capacity: totalJobs)   // size/move loop ordinal (WM_ENTERSIZEMOVE count) when the job ran
loopAt.initialize(repeating: 0, count: totalJobs)
// Loop ordinals: 1 = SC_SIZE live resize, 2 = SC_MOVE (0xF012) move loop, 3 = injected SendInput border drag. The runner runs them in that order.
var loopDrains: [Int] = [0, 0, 0, 0]

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
var tickCount = 0
var loopReadyCalls = 0
var loopReadyThreadMismatches = 0
var windowClosedCalls = 0
var axApplied = 0
var axUnsupported = 0
var axAppliedAfterClose = 0
var modelClicks = 0
var modalResults: [Int32] = []
var jobsAtClose = -1
var enqueuedAtClose = -1
var jobsAtFinalFlush = -1
var framesAtStart: UInt64 = 0
var framesAtEnd: UInt64 = 0

// Cross-thread state.
let stateLock = NSLock()
var closedFlag = false
var enqueuedCount = 0
var enqueuedAfterClose = 0
var modalRequestRc: Int32 = -99
var watchdogFired = false
var producerFinished = false

func runProducer() {
    let period = Int64(qpcFreq / Double(paceHz))
    let start = qpcNow()
    var hopsEnqueued = 0
    var modalRequested = false
    var exit3At = -1
    for i in 0..<totalJobs {
        let target = start + Int64(i) * period
        while qpcNow() < target { Sleep(0) }
        stateLock.lock()
        let closed = closedFlag
        stateLock.unlock()
        if closed { enqueuedAfterClose += 1; break }
        if exit3At < 0 && swr_stat(22) >= 3 { exit3At = i }
        if !modalRequested && ((exit3At >= 0 && i >= exit3At + 300) || i >= modalFallbackJob) {
            modalRequested = true
            let rc = swr_request_modal(1)
            stateLock.lock(); modalRequestRc = rc; stateLock.unlock()
        }
        enqueueTicks[i] = qpcNow()
        stateLock.lock(); enqueuedCount += 1; stateLock.unlock()
        DispatchQueue.main.async {
            latenciesMs[i] = msSince(enqueueTicks[i])
            phaseAt[i] = swr_phase()
            loopAt[i] = UInt32(truncatingIfNeeded: swr_stat(21))
            jobsRun += 1
            if GetCurrentThreadId() != mainThreadId { jobThreadMismatches += 1 }
        }
        if i % hopEvery == 0 && hopsEnqueued < totalHops {
            hopsEnqueued += 1
            Task { @MainActor in
                hopsRun += 1
                if GetCurrentThreadId() != mainThreadId { hopThreadMismatches += 1 }
            }
        }
    }
    stateLock.lock(); producerFinished = true; stateLock.unlock()
    print("producer enqueued=\(enqueuedCount) hops=\(hopsEnqueued)")
}

func runWatchdog() {
    Thread.sleep(forTimeInterval: watchdogSeconds)
    stateLock.lock()
    watchdogFired = true
    stateLock.unlock()
    _ = swr_request_quit()
}

// Pops every record the Rust side has queued. Stale records never come back.
func drainAccessKitQueue() {
    var rec = swr_ui_record()
    while swr_ax_pop(&rec) == 1 {
        if rec.tag == 1 {
            if rec.node_id == axButtonNode && rec.action == 1 {
                axApplied += 1
                modelClicks += 1
                if closedFlag { axAppliedAfterClose += 1 }
            } else {
                axUnsupported += 1
            }
        } else if rec.tag == 2 {
            modalResults.append(rec.value)
        }
    }
}

func drainFromRust() {
    drainCalls += 1
    if swr_phase() & 1 != 0 { loopDrains[min(Int(swr_stat(21)), 3)] += 1 }
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
    drainAccessKitQueue()
    drainingSwift = false
}

let drainCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    drainFromRust()
}

let tickCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    tickCount += 1
}

let loopReadyCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    loopReadyCalls += 1
    if GetCurrentThreadId() != mainThreadId { loopReadyThreadMismatches += 1 }
    framesAtStart = swr_frames_rendered()
    Thread { runProducer() }.start()
    Thread { runWatchdog() }.start()
}

// Shutdown: mark closed (no new work), flush pending main-queue jobs while
// the loop is still alive, pop the last AccessKit records, then return.
// Rust rejects every queued AX record from this point.
let windowClosedCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    windowClosedCalls += 1
    stateLock.lock()
    closedFlag = true
    enqueuedAtClose = enqueuedCount
    stateLock.unlock()
    jobsAtClose = jobsRun
    drainingSwift = true
    _dispatch_main_queue_callback_4CF(nil)
    drainingSwift = false
    jobsAtFinalFlush = jobsRun
    drainAccessKitQueue()
    framesAtEnd = swr_frames_rendered()
}

// ---- Entry ----

print("initial_thread_id=\(mainThreadId)")

var info = swr_bootstrap_info()
let queryRc = swr_bootstrap_query(&info, UInt32(MemoryLayout<swr_bootstrap_info>.size))
print("bootstrap_query_rc=\(queryRc) abi=\(info.abi_major).\(info.abi_minor) pointer_width=\(info.pointer_width) fn_table_size=\(info.fn_table_size)")
guard queryRc == 0, info.abi_major == 0, info.abi_minor == 2, info.pointer_width == 64, info.fn_table_size == 9 else {
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
    tick: tickCallback,
    window_closed: windowClosedCallback
)
let runRc = swr_run(&callbacks)
let mainThreadAfter = GetCurrentThreadId()

// ---- Report (main thread, after swr_run returned) ----

drainAccessKitQueue()
func counter(_ i: UInt32) -> UInt64 { swr_stat(i) }

func pct(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return -1 }
    let sorted = xs.sorted()
    let rank = max(1, Int((Double(sorted.count) * p).rounded(.up)))
    return sorted[min(sorted.count, rank) - 1]
}

// Latency sample sets, tagged by the phase in effect when the job ran.
var allLat: [Double] = []
var resizeLat: [Double] = []   // bit 0 set, loop ordinal 1 (SC_SIZE)
var moveLat: [Double] = []     // bit 0 set, loop ordinal 2 (SC_MOVE 0xF012)
var dragLat: [Double] = []     // bit 0 set, loop ordinal 3 (injected border drag)
var modalLat: [Double] = []    // bit 1 set (TaskDialog)
var idleLat: [Double] = []
var openLat: [Double] = []     // phase value 4: TaskDialog construction stall, one-off, reported separately
for i in 0..<totalJobs where latenciesMs[i] >= 0 {
    let v = latenciesMs[i]
    let ph = phaseAt[i]
    allLat.append(v)
    if ph & 1 != 0 {
        switch loopAt[i] { case 1: resizeLat.append(v); case 2: moveLat.append(v); default: dragLat.append(v) }
    }
    if ph & 2 != 0 { modalLat.append(v) }
    if ph & 4 != 0 { openLat.append(v) }
    if ph == 0 { idleLat.append(v) }
}
let mismatches = jobThreadMismatches + hopThreadMismatches + drainThreadMismatches + loopReadyThreadMismatches
let resizeDrains = counter(11) + counter(13)
let sizeEnters = counter(21), sizeExits = counter(22)
let frames = framesAtEnd &- framesAtStart

let axAttempts = counter(0), axEnq = counter(1), axFull = counter(2), axRejPost = counter(3)
let axPopApplied = counter(4), axPopStale = counter(5), axQueueLen = counter(8)
let axSumAttemptsOk = axAttempts == axEnq + axRejPost + axFull
let axSumEnqOk = axEnq == axPopApplied + axPopStale && axQueueLen == 0
let swiftSumOk = Int(axPopApplied) == axApplied + axUnsupported
let lateDropped = enqueuedCount - jobsRun
let closeOk = jobsAtClose >= 0 && enqueuedAtClose == jobsAtFinalFlush

print("jobs_run=\(jobsRun)/\(enqueuedCount) enqueued_before_close=\(enqueuedAtClose) run_by_final_flush=\(jobsAtFinalFlush) enqueued_after_close_refused=\(enqueuedAfterClose) late_dropped=\(lateDropped)")
print(String(format: "latency_ms all p99=%.4f max=%.4f n=%d", pct(allLat, 0.99), allLat.max() ?? -1, allLat.count))
print(String(format: "latency_ms idle p99=%.4f n=%d", pct(idleLat, 0.99), idleLat.count))
print(String(format: "latency_ms during_live_resize p50=%.4f p99=%.4f max=%.4f n=%d", pct(resizeLat, 0.5), pct(resizeLat, 0.99), resizeLat.max() ?? -1, resizeLat.count))
print(String(format: "latency_ms during_modal p50=%.4f p99=%.4f max=%.4f n=%d", pct(modalLat, 0.5), pct(modalLat, 0.99), modalLat.max() ?? -1, modalLat.count))
print(String(format: "latency_ms modal_open_one_off max=%.4f n=%d (budget: single bounded stall <= 50 ms; excluded from during_modal)", openLat.max() ?? -1, openLat.count))
print(String(format: "latency_ms during_move p50=%.4f p99=%.4f max=%.4f n=%d", pct(moveLat, 0.5), pct(moveLat, 0.99), moveLat.max() ?? -1, moveLat.count))
print(String(format: "latency_ms during_injected_border_drag p50=%.4f p99=%.4f max=%.4f n=%d", pct(dragLat, 0.5), pct(dragLat, 0.99), dragLat.max() ?? -1, dragLat.count))
print("loop_drains resize=\(loopDrains[1]) move=\(loopDrains[2]) border_drag=\(loopDrains[3]) size_loop_enters=\(sizeEnters) exits=\(sizeExits)")
print("thread_mismatches=\(mismatches) (jobs=\(jobThreadMismatches) hops=\(hopThreadMismatches) drain=\(drainThreadMismatches) loop_ready=\(loopReadyThreadMismatches))")
print("mainactor_hops=\(hopsRun)/\(totalHops)")
print("swift_drain_calls=\(drainCalls) swift_reentry_violations=\(drainReentryViolations) selftest_swift_result=\(selftestResult) ticks=\(tickCount)")
print("rust_drain_calls=\(counter(9)) drains_idle=\(counter(10)) drains_sizing=\(counter(11)) drains_modal=\(counter(12)) drains_both=\(counter(13)) deferred_callbacks=\(counter(14)) nested_executed=\(counter(15)) selftest_detected=\(counter(27)) panics=\(counter(16))")
print("nc_lbuttondown=\(counter(28)) nc_last_hittest_code=\(counter(29))")
print("size_loop_enter=\(counter(21)) size_loop_exit=\(counter(22)) frames_during_workload=\(frames) frames_at_start=\(framesAtStart) frames_at_end=\(framesAtEnd)")
print("modal_request_rc=\(modalRequestRc) modal_requests=\(counter(17)) modal_opened=\(counter(18)) modal_results=\(counter(19)) modal_errors=\(counter(20)) modal_result_values=\(modalResults)")
print("ax_attempts=\(axAttempts) enqueued=\(axEnq) full=\(axFull) rejected_stale_at_post=\(axRejPost)")
print("ax_popped_applied=\(axPopApplied) popped_stale=\(axPopStale) queue_len_end=\(axQueueLen) swift_applied=\(axApplied) swift_unsupported=\(axUnsupported) swift_applied_after_close=\(axAppliedAfterClose) rust_applied_after_close=\(counter(7)) model_clicks=\(modelClicks)")
print("sum_attempts_ok=\(axSumAttemptsOk) sum_enqueued_ok=\(axSumEnqOk) swift_matches_rust=\(swiftSumOk)")
print("window_closed_calls=\(windowClosedCalls) close_flush_ok=\(closeOk) watchdog_fired=\(watchdogFired) wake_signals=\(counter(25)) wake_wait_failures=\(counter(26))")
print("swr_set_wake_handle_rc=\(setRc) swr_run_rc=\(runRc) main_thread_after_run_same=\(mainThreadAfter == mainThreadId)")

func budgetOk(_ xs: [Double]) -> Bool { xs.isEmpty ? false : pct(xs, 0.99) <= 16.7 }
let openMax = openLat.max() ?? -1
let critModal = budgetOk(modalLat)
let critOpen = openMax <= 50   // n=0 is reported, not hidden; the stall is expected on this build
let critResize = budgetOk(resizeLat) && counter(11) > 0 && loopDrains[1] > 0
let critMove = budgetOk(moveLat) && loopDrains[2] > 0
let critDrag = budgetOk(dragLat) && loopDrains[3] > 0 && sizeEnters >= 3
let critNested = counter(15) == 0
func pf(_ b: Bool) -> String { b ? "PASS" : "FAIL" }
print("criterion during_modal_p99<=16.7ms: \(pf(critModal)) p99=\(String(format: "%.4f", pct(modalLat, 0.99))) n=\(modalLat.count)")
print("criterion modal_open_one_off_max<=50ms: \(pf(critOpen)) max=\(String(format: "%.4f", openMax)) n=\(openLat.count)")
print("criterion during_live_resize_p99<=16.7ms_and_drains_sizing>0: \(pf(critResize)) p99=\(String(format: "%.4f", pct(resizeLat, 0.99))) n=\(resizeLat.count) loop_drains=\(loopDrains[1]) drains_sizing=\(counter(11))")
print("criterion during_move_p99<=16.7ms_and_drains>0: \(pf(critMove)) p99=\(String(format: "%.4f", pct(moveLat, 0.99))) n=\(moveLat.count) loop_drains=\(loopDrains[2])")
print("criterion injected_border_drag_p99<=16.7ms_and_drains>0_and_ENTERSIZEMOVE_fired: \(pf(critDrag)) p99=\(String(format: "%.4f", pct(dragLat, 0.99))) n=\(dragLat.count) loop_drains=\(loopDrains[3]) size_enters=\(sizeEnters)")
print("criterion nested_executed=0: \(pf(critNested)) nested_executed=\(counter(15))")
let pass = runRc == 0
    && windowClosedCalls == 1
    && !watchdogFired
    && mainThreadAfter == mainThreadId
    && mismatches == 0
    && drainReentryViolations == 0
    && critNested
    && counter(16) == 0
    && selftestResult == 1
    && critModal && critOpen && critResize && critMove && critDrag
    && counter(18) == 1 && counter(19) == 1 && modalResults == [1]
    && modalRequestRc == 0
    && axSumAttemptsOk && axSumEnqOk && swiftSumOk
    && axAppliedAfterClose == 0 && counter(7) == 0
    && closeOk
    && counter(26) == 0
print("verdict=\(pass ? "PASS" : "FAIL")")
exit(pass ? 0 : 1)
