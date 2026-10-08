import CDispatchPrivate
import CSwiftRightRender
import Dispatch
import Foundation
import WinSDK

// SR0-B frame-clock probe (C ABI 0.2). Synchronous entry on the initial thread.
// Phases (phases thread): idle A (3 s, no animation) -> workload (5000 jobs at 1 kHz,
// 500 MainActor hops, continuous animation) -> idle B (3 s after animation stops).
// Ticks arrive from Rust through the drain path and are answered with swr_submit_commit.

let totalJobs = 5_000
let paceHz = 1_000
let totalHops = 500
let hopEvery = 10
let tickCap = 8_192
let watchdogSeconds: Double = 150

var outDir = "."
var timerRes: UInt32 = 0
for a in CommandLine.arguments.dropFirst() {
    if a.hasPrefix("--out=") { outDir = String(a.dropFirst("--out=".count)) }
    if a == "--timer-res-1" { timerRes = 1 }
}

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

func sleepMs(_ ms: Double) { Thread.sleep(forTimeInterval: ms / 1000.0) }

// Set once on the initial thread, before swr_run.
let mainThreadId: UInt32 = GetCurrentThreadId()

// Written by the producer before enqueue; written on the main thread at execution.
// Dispatch enqueue provides the happens-before edge for the job's own slot.
let enqueueTicks = UnsafeMutablePointer<Int64>.allocate(capacity: totalJobs)
let execTicks = UnsafeMutablePointer<Int64>.allocate(capacity: totalJobs)
execTicks.initialize(repeating: -1, count: totalJobs)
let tickEntryMs = UnsafeMutablePointer<Double>.allocate(capacity: tickCap)
let tickCostMs = UnsafeMutablePointer<Double>.allocate(capacity: tickCap)

// Main-thread-only state (read after swr_run returns).
var jobThreadMismatches = 0
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
var animCounter: UInt64 = 0
var tickCount = 0

// Cross-thread state (guarded by stateLock).
let stateLock = NSLock()
var jobsDone = 0
var hopsDone = 0
var ticksDelivered = 0
var phaseDone = false
var watchdogFired = false
var phaseWin = [Int64](repeating: 0, count: 6)
var idleAPaints: UInt64 = 0
var idleBPaints: UInt64 = 0
var idleATicks = 0
var idleBTicks = 0
var workloadTicks = 0

func currentJobs() -> (Int, Int) {
    stateLock.lock(); defer { stateLock.unlock() }
    return (jobsDone, hopsDone)
}

func currentTicks() -> Int {
    stateLock.lock(); defer { stateLock.unlock() }
    return ticksDelivered
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
            execTicks[i] = qpcNow()
            if GetCurrentThreadId() != mainThreadId { jobThreadMismatches += 1 }
            stateLock.lock()
            jobsDone += 1
            stateLock.unlock()
        }
        if i % hopEvery == 0 && hopsEnqueued < totalHops {
            hopsEnqueued += 1
            Task { @MainActor in
                if GetCurrentThreadId() != mainThreadId { hopThreadMismatches += 1 }
                stateLock.lock()
                hopsDone += 1
                stateLock.unlock()
            }
        }
    }
    print("producer enqueue_rate_hz=\(Double(totalJobs) / (Double(qpcNow() - start) / qpcFreq)) hops_enqueued=\(hopsEnqueued)")
}

func runPhases() {
    sleepMs(1000)
    let ia0 = qpcNow()
    let pA0 = swr_paints()
    let tA0 = currentTicks()
    sleepMs(3000)
    let ia1 = qpcNow()
    let pA1 = swr_paints()
    let tA1 = currentTicks()

    let ws = qpcNow()
    let tW0 = currentTicks()
    _ = swr_set_animating(1)
    Thread { runProducer() }.start()
    let deadline = Date().addingTimeInterval(60)
    while Date() < deadline {
        let (j, h) = currentJobs()
        if j == totalJobs && h == totalHops { break }
        sleepMs(5)
    }
    let we = qpcNow()
    let tW1 = currentTicks()
    _ = swr_set_animating(0)
    sleepMs(300)

    let ib0 = qpcNow()
    let pB0 = swr_paints()
    let tB0 = currentTicks()
    sleepMs(3000)
    let ib1 = qpcNow()
    let pB1 = swr_paints()
    let tB1 = currentTicks()

    stateLock.lock()
    phaseWin = [ws, we, ia0, ia1, ib0, ib1]
    idleAPaints = pA1 &- pA0
    idleBPaints = pB1 &- pB0
    idleATicks = tA1 - tA0
    idleBTicks = tB1 - tB0
    workloadTicks = tW1 - tW0
    phaseDone = true
    stateLock.unlock()
    _ = swr_request_quit()
}

func runWatchdog() {
    sleepMs(watchdogSeconds * 1000)
    stateLock.lock()
    let done = phaseDone
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

/// One display tick, delivered outside any GPUI borrow. Advances the animation
/// counter and submits the commit that the next paint displays.
let tickCallback: @convention(c) (UnsafeMutableRawPointer?, UInt64) -> Void = { _, targetNs in
    let t0 = qpcNow()
    animCounter += 1
    _ = swr_submit_commit(animCounter)
    let t1 = qpcNow()
    if tickCount < tickCap {
        let entryNs = Double(t0) * 1e9 / qpcFreq - Double(targetNs)
        tickEntryMs[tickCount] = entryNs / 1e6
        tickCostMs[tickCount] = Double(t1 - t0) * 1000.0 / qpcFreq
    }
    tickCount += 1
    stateLock.lock()
    ticksDelivered += 1
    stateLock.unlock()
}

let loopReadyCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    loopReadyCalls += 1
    if GetCurrentThreadId() != mainThreadId { loopReadyThreadMismatches += 1 }
    Thread { runPhases() }.start()
    Thread { runWatchdog() }.start()
}

let windowClosedCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    windowClosedCalls += 1
}

func pct(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return -1 }
    let rank = max(1, Int((Double(sorted.count) * p).rounded(.up)))
    return sorted[min(sorted.count, rank) - 1]
}

// ---- Entry ----

print("initial_thread_id=\(mainThreadId) timer_resolution_1ms_requested=\(timerRes) out=\(outDir)")

var info = swr_bootstrap_info()
let queryRc = swr_bootstrap_query(&info, UInt32(MemoryLayout<swr_bootstrap_info>.size))
print("bootstrap_query_rc=\(queryRc) abi=\(info.abi_major).\(info.abi_minor) pointer_width=\(info.pointer_width) fn_table_size=\(info.fn_table_size)")
guard queryRc == 0, info.abi_major == 0, info.abi_minor == 2, info.pointer_width == 64 else {
    print("bootstrap_rejected")
    exit(2)
}

if timerRes == 1 {
    print("timer_resolution_1ms_rc=\(swr_set_timer_resolution(1))")
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
    tick: tickCallback
)
fflush(nil)
let runRc = swr_run(&callbacks)
let mainThreadAfter = GetCurrentThreadId()

// ---- Report (main thread, after swr_run returned) ----

let jobsRun = (0..<totalJobs).filter { execTicks[$0] >= 0 }.count
var latencies: [Double] = []
var jobLines = "i,enq_qpc,exec_qpc,latency_ms\n"
for i in 0..<totalJobs where execTicks[i] >= 0 {
    let lat = Double(execTicks[i] - enqueueTicks[i]) * 1000.0 / qpcFreq
    latencies.append(lat)
    jobLines += "\(i),\(enqueueTicks[i]),\(execTicks[i]),\(String(format: "%.4f", lat))\n"
}
latencies.sort()
var tickLines = "k,entry_ms,cost_ms\n"
var entries: [Double] = []
var costs: [Double] = []
for k in 0..<min(tickCount, tickCap) {
    entries.append(tickEntryMs[k])
    costs.append(tickCostMs[k])
    tickLines += "\(k),\(String(format: "%.4f", tickEntryMs[k])),\(String(format: "%.4f", tickCostMs[k]))\n"
}
entries.sort()
costs.sort()
try? jobLines.write(toFile: outDir + "\\jobs.csv", atomically: true, encoding: .utf8)
try? tickLines.write(toFile: outDir + "\\ticks.csv", atomically: true, encoding: .utf8)

let mismatches = jobThreadMismatches + hopThreadMismatches + drainThreadMismatches + loopReadyThreadMismatches
let (jobsDoneFinal, hopsDoneFinal) = currentJobs()
stateLock.lock()
let finalIdleA = idleAPaints
let finalIdleB = idleBPaints
let finalIdleATicks = idleATicks
let finalIdleBTicks = idleBTicks
let finalWorkloadTicks = workloadTicks
let finalPhaseDone = phaseDone
let finalWatchdog = watchdogFired
let finalWin = phaseWin
let finalTicksDelivered = ticksDelivered
stateLock.unlock()

print("jobs_run=\(jobsRun)/\(totalJobs) jobs_done_counter=\(jobsDoneFinal)")
print(String(format: "latency_ms p50=%.4f p95=%.4f p99=%.4f max=%.4f", pct(latencies, 0.50), pct(latencies, 0.95), pct(latencies, 0.99), latencies.last ?? -1))
print(String(format: "tick_entry_ms p50=%.4f p95=%.4f p99=%.4f max=%.4f n=%d", pct(entries, 0.50), pct(entries, 0.95), pct(entries, 0.99), entries.last ?? -1, entries.count))
print(String(format: "tick_to_commit_ms p50=%.4f p95=%.4f p99=%.4f max=%.4f n=%d", pct(costs, 0.50), pct(costs, 0.95), pct(costs, 0.99), costs.last ?? -1, costs.count))
print("thread_mismatches=\(mismatches) (jobs=\(jobThreadMismatches) hops=\(hopThreadMismatches) drain=\(drainThreadMismatches) loop_ready=\(loopReadyThreadMismatches))")
print("reentrancy_violations_swift=\(drainReentryViolations) drain_calls_swift=\(drainCalls) selftest_swift_result=\(selftestResult)")
print("mainactor_hops=\(hopsDoneFinal)/\(totalHops)")
print("idle_A_paints=\(finalIdleA) idle_A_ticks=\(finalIdleATicks) workload_ticks=\(finalWorkloadTicks) ticks_delivered=\(finalTicksDelivered)")
print("idle_B_paints=\(finalIdleB) idle_B_ticks=\(finalIdleBTicks)")
print("loop_ready_calls=\(loopReadyCalls) window_closed_calls=\(windowClosedCalls) watchdog_fired=\(finalWatchdog) phases_done=\(finalPhaseDone)")
print("swr_set_wake_handle_rc=\(setRc) swr_run_rc=\(runRc) main_thread_after_run_same=\(mainThreadAfter == mainThreadId)")
print("window_ticks ws=\(finalWin[0]) we=\(finalWin[1]) idleA=[\(finalWin[2]),\(finalWin[3])] idleB=[\(finalWin[4]),\(finalWin[5])]")
fflush(nil)

let dumpRc = outDir.withCString { swr_dump($0) }
print("swr_dump_rc=\(dumpRc)")
finalWin.withUnsafeBufferPointer { wp in
    _ = swr_report(enqueueTicks, execTicks, UInt32(totalJobs), wp.baseAddress)
}
fflush(nil)

let pass = runRc == 0
    && jobsRun == totalJobs
    && hopsDoneFinal == totalHops
    && mismatches == 0
    && drainReentryViolations == 0
    && finalPhaseDone
    && finalIdleA == 0
    && finalIdleB == 0
    && finalIdleATicks == 0
    && finalIdleBTicks == 0
    && finalWorkloadTicks > 0
    && windowClosedCalls == 1
    && !finalWatchdog
    && mainThreadAfter == mainThreadId
print("verdict=\(pass ? "PASS" : "FAIL")")
exit(pass ? 0 : 1)
