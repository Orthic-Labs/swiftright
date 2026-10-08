import CDispatchPrivate
import Dispatch
import Foundation
import WinSDK

// SR0-D probe: drive Swift's main dispatch queue from a host-owned Win32 message loop.
// Synchronous entry point (no async main). No GPUI/Rust.

let totalJobs = 10_000
let paceHz = 1_000
let chainHops = 1_000
let idleSeconds: UInt32 = 5
let nestedAt = 5_000
let watchdogMs: UInt32 = 120_000

// ---- QPC timing ----
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

// ---- Cross-thread state (lock protected) ----
let sharedLock = NSLock()
var workDoneShared = false

// ---- Main-thread state (touched only on the initial thread) ----
let mainThreadId: UInt32 = GetCurrentThreadId()
var latenciesMs: [Double] = []
var jobsRun = 0
var threadMismatches = 0
var reentryViolations = 0
var drainCalls = 0
var draining = false
var nestedRan = false
var outerInProgress = false
var nestedRecursionViolations = 0
var mainHops = 0
var mainHopMismatches = 0
var chainDone = false
var workCounter: UInt64 = 0
var workDoneLocal = false
var idleStart: Int64 = 0
var idleEnd: Int64 = 0
var quitIssued = false
var idleWakeups = 0
var eventWakes = 0
var msgWakes = 0
var loopIterations = 0
var quitting = false
var timedOut = false

latenciesMs.reserveCapacity(totalJobs)

func wide(_ s: String) -> [UInt16] { Array(s.utf16) + [0] }

func drainMainQueue() {
    drainCalls += 1
    if draining {
        reentryViolations += 1
        return
    }
    draining = true
    _dispatch_main_queue_callback_4CF(nil)
    draining = false
}

func maybeFinishWork() {
    guard !workDoneLocal, jobsRun == totalJobs, nestedRan, chainDone else { return }
    workDoneLocal = true
    idleStart = qpcNow()
    sharedLock.lock()
    workDoneShared = true
    sharedLock.unlock()
}

func offMainHop() async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async { c.resume() }
    }
}

@MainActor func mainChain(_ n: Int) async {
    mainHops += 1
    workCounter &+= 1
    if GetCurrentThreadId() != mainThreadId { mainHopMismatches += 1 }
    if n + 1 >= chainHops {
        chainDone = true
        maybeFinishWork()
        return
    }
    await offMainHop()
    await mainChain(n + 1)
}

func runNestedTest() {
    outerInProgress = true
    DispatchQueue.main.async {
        nestedRan = true
        workCounter &+= 1
        if outerInProgress { nestedRecursionViolations += 1 }
        if GetCurrentThreadId() != mainThreadId { threadMismatches += 1 }
        maybeFinishWork()
    }
    outerInProgress = false
}

func runProducer() {
    let period = Int64(qpcFreq / Double(paceHz))
    let start = qpcNow()
    for i in 0..<totalJobs {
        let target = start + Int64(i) * period
        while qpcNow() < target { Sleep(0) }
        let t0 = qpcNow()
        DispatchQueue.main.async {
            latenciesMs.append(msSince(t0))
            jobsRun += 1
            workCounter &+= 1
            if GetCurrentThreadId() != mainThreadId { threadMismatches += 1 }
            if i == nestedAt { runNestedTest() }
            maybeFinishWork()
        }
    }
    let enqueueEnd = qpcNow()
    print("producer enqueue_rate_hz=\(Double(totalJobs) / (Double(enqueueEnd - start) / qpcFreq))")

    // Wait for the main thread to finish the workload (with watchdog).
    let waitStart = qpcNow()
    while true {
        sharedLock.lock()
        let done = workDoneShared
        sharedLock.unlock()
        if done { break }
        if msSince(waitStart) > Double(watchdogMs) {
            timedOut = true
            break
        }
        Sleep(5)
    }

    // Idle window: no work is enqueued for idleSeconds.
    Sleep(idleSeconds * 1000)

    DispatchQueue.main.async {
        quitIssued = true
        workCounter &+= 1
        idleEnd = qpcNow()
        PostQuitMessage(0)
    }
}

// ---- 1. Message-only window on the initial thread ----
let startQpc = qpcNow()
let hwndMessage = HWND(bitPattern: -3)  // HWND_MESSAGE
var staticClass = wide("STATIC")
var windowName = wide("sr0d-drain")
let hwnd = CreateWindowExW(0, staticClass, windowName, 0, 0, 0, 0, 0, hwndMessage, nil, nil, nil)
if hwnd == nil {
    fatalError("CreateWindowExW failed: \(GetLastError())")
}
print("initial_thread_id=\(mainThreadId) hwnd_message=ok")

// ---- 2. Main-queue wake handle (private SPI) ----
let dispatchHandle = _dispatch_get_main_queue_handle_4CF()
if dispatchHandle == nil {
    fatalError("_dispatch_get_main_queue_handle_4CF returned NULL")
}
print("main_queue_wake_handle=\(String(describing: dispatchHandle))")

// ---- 3. Workload ----
let producer = Thread { runProducer() }
producer.start()
Task { @MainActor in await mainChain(0) }

// ---- 4. Host-owned message loop ----
var handles: [HANDLE?] = [dispatchHandle]
let loopStart = qpcNow()
while !quitting {
    loopIterations += 1
    let before = workCounter
    let r = MsgWaitForMultipleObjectsEx(1, &handles, 0xFFFF_FFFF, 0x04FF, 0x0004)
    if r == 0 {
        eventWakes += 1
        drainMainQueue()
    } else if r == 1 {
        msgWakes += 1
    } else {
        fatalError("MsgWaitForMultipleObjectsEx failed r=\(r) err=\(GetLastError())")
    }
    var msg = MSG()
    while PeekMessageW(&msg, nil, 0, 0, 0x0001) {
        if msg.message == 0x0012 {  // WM_QUIT
            quitting = true
            break
        }
        _ = TranslateMessage(&msg)
        _ = DispatchMessageW(&msg)
        workCounter &+= 1
    }
    if workDoneLocal && !quitIssued && workCounter == before {
        idleWakeups += 1
    }
}
let loopEnd = qpcNow()

// ---- Guard self-test: a deliberate re-entry must be counted and skipped ----
let violationsBeforeSelfTest = reentryViolations
draining = true
drainMainQueue()
draining = false
let guardSelfTestDetected = reentryViolations - violationsBeforeSelfTest == 1
reentryViolations = violationsBeforeSelfTest

_ = DestroyWindow(hwnd)

// ---- Report ----
let sorted = latenciesMs.sorted()
func pct(_ p: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    let rank = Int((p * Double(sorted.count)).rounded(.up))
    return sorted[min(max(rank - 1, 0), sorted.count - 1)]
}
func fmt(_ v: Double) -> String { String(format: "%.4f", v) }

let idleSec = Double(idleEnd - idleStart) / qpcFreq
print("jobs_run=\(jobsRun)/\(totalJobs)")
print("latency_ms p50=\(fmt(pct(0.50))) p95=\(fmt(pct(0.95))) p99=\(fmt(pct(0.99))) max=\(fmt(sorted.last ?? .nan))")
print("thread_mismatches=\(threadMismatches)")
print("reentrancy_violations=\(reentryViolations) drain_calls=\(drainCalls) guard_selftest_detected=\(guardSelfTestDetected)")
print("nested_ran=\(nestedRan) nested_recursion_violations=\(nestedRecursionViolations)")
print("mainactor_hops=\(mainHops)/\(chainHops) mainactor_thread_mismatches=\(mainHopMismatches)")
print("idle_window_s=\(fmt(idleSec)) idle_wakeups=\(idleWakeups) event_wakes=\(eventWakes) msg_wakes=\(msgWakes) loop_iterations=\(loopIterations)")
print("workload_timed_out=\(timedOut)")
print("total_runtime_s=\(fmt(Double(loopEnd - startQpc) / qpcFreq)) loop_s=\(fmt(Double(loopEnd - loopStart) / qpcFreq))")
