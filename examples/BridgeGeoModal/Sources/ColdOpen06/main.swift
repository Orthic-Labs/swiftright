import Foundation
import SwiftRightBridge
#if os(Windows)
import WinSDK
#endif

// ColdOpen06 (SR0 T10): measures the cost of opening ONE modal in a fresh process, with two explicitly separate measures.
//
//   M1 main-queue blocking during open   Producer jobs are posted to the main dispatch queue at ~500 Hz. For one open
//        requested at req_ns, M1 = the largest (ran - enqueued) over the jobs enqueued in [req, req + 150 ms), the same
//        quantity Modal06 reports as modal_open_one_off, plus M1gap = the longest pause between consecutive job RUNS in
//        [req - 10 ms, req + 300 ms]. It says how long the UI thread was unavailable around the open. It does NOT say
//        when the dialog became visible.
//   M2 request -> dialog visible         The host logs req_ns, the monotonic QueryPerformanceCounter clock in ns taken just
//        before the bridge request. The driver (scripts/drive-coldopen.ps1) listens for the window with SetWinEventHook
//        (EVENT_OBJECT_SHOW / EVENT_SYSTEM_MENUPOPUPSTART, the first moment a window of the modal's class is visible) and
//        with UI Automation (WindowOpened / MenuOpened event: the first moment UIA announces the window) and stamps each
//        with the same QPC clock. M2 = stamp - req_ns. QPC is one system-wide clock, so host and driver stamps compare.
//
// One process opens SWR_CO_OPENS (default 1) modals of SWR_CO_KIND (menu | dialog). A cold run is OPENS=1 (the first modal of
// the process), a warm run is OPENS=2 and is read at open 2. The driver dismisses each modal with window-targeted input after
// holding it. Exit code: 0 = every open delivered a result, 1 = not, 78 = startup diagnostic.
// SWR_CO_DRYRUN=1: pure-logic self-test only (no window).

let env = ProcessInfo.processInfo.environment
let dryRun = env["SWR_CO_DRYRUN"] == "1"
let kindName = env["SWR_CO_KIND"] ?? "dialog"
let opensWanted = max(1, Int(env["SWR_CO_OPENS"] ?? "") ?? 1)
let timeoutSeconds = Double(env["SWR_CO_TIMEOUT"] ?? "") ?? 40
let leadSeconds = Double(env["SWR_CO_LEAD_S"] ?? "") ?? 1.0            // window ready -> first request (the driver registers its listeners meanwhile)

var logFile: UnsafeMutablePointer<FILE>?
func openLog() {
    guard let p = env["SWR_CO_LOG"], !p.isEmpty else { return }
    logFile = fopen(p, "ab")
}
func glog(_ s: String) {
    if let f = logFile { fputs(s + "\n", f); fflush(f) }
    print(s)
    fflush(stdout)
}

#if os(Windows)
let qpcFreq: Double = {
    var f = LARGE_INTEGER()
    _ = QueryPerformanceFrequency(&f)
    return Double(f.QuadPart)
}()
func nowNs() -> UInt64 {
    var c = LARGE_INTEGER()
    _ = QueryPerformanceCounter(&c)
    return UInt64(Double(c.QuadPart) * 1e9 / qpcFreq)
}
func napShort() { Sleep(1) }
func napSpin() { Sleep(0) }
#else
func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func napShort() { usleep(1000) }
func napSpin() { usleep(50) }
#endif

func ms(_ ns: UInt64) -> Double { Double(ns) / 1e6 }
func fms(_ x: Double) -> String { String(format: "%.2f", x) }
func percentile(_ xs: [Double], _ p: Double) -> Double {
    if xs.isEmpty { return -1 }
    let s = xs.sorted()
    let i = min(s.count - 1, max(0, Int((p * Double(s.count)).rounded(.up)) - 1))
    return s[i]
}
func status(_ body: () throws -> Void) -> Int32 {
    do { try body(); return 0 } catch BridgeError.status(let rc, _) { return rc } catch { return -999 }
}

final class Timers {
    private var items: [(due: UInt64, action: () -> Void)] = []
    func after(_ seconds: Double, _ action: @escaping () -> Void) { items.append((due: nowNs() + UInt64(seconds * 1e9), action: action)) }
    func service() {
        if items.isEmpty { return }
        let now = nowNs()
        let due = items.filter { $0.due <= now }
        if due.isEmpty { return }
        items.removeAll { $0.due <= now }
        for d in due { d.action() }
    }
}
let timers = Timers()

struct JobRecord { let enq: UInt64; let ran: UInt64 }
var jobs: [JobRecord] = []
var hostClosed = false

final class Producer {
    private let lock = NSLock()
    private var stopFlag = false
    func stop() { lock.lock(); stopFlag = true; lock.unlock() }
    func start() {
        Thread { [self] in
            let periodNs: UInt64 = 2_000_000
            var next = nowNs()
            while true {
                lock.lock(); let s = stopFlag; lock.unlock()
                if s { break }
                let t = nowNs()
                if t < next { if next - t > 2_500_000 { napShort() } else { napSpin() }; continue }
                next += periodNs
                if t > next + 50_000_000 { next = t }
                let enq = t
                DispatchQueue.main.async {
                    jobs.append(JobRecord(enq: enq, ran: nowNs()))
                    timers.service()
                }
            }
        }.start()
    }
}

typealias Item = BridgeWindow.ModalItem
let menuItems: [Item] = [Item(id: 11, text: "Open"), Item(id: 12, text: "Save", checked: true), .separatorItem, Item(id: 14, text: "Delete", disabled: true), Item(id: 15, text: "Quit")]
let dialogButtons: [Item] = [Item(id: 21, text: "Save"), Item(id: 22, text: "Don't save"), Item(id: 23, text: "Cancel")]
let dialogTitle = "SR0 ColdOpen06 dialog"
let dialogMessage = "Choose a button. This dialog is opened by the ColdOpen06 host through SWR_MODAL_DIALOG."

/// M1 and M1gap for one open at `req` (pure; self-tested). Returns (job count in the window, max job delay ms, longest run gap ms).
func blockingStats(_ jobs: [JobRecord], req: UInt64) -> (n: Int, maxDelayMs: Double, gapMs: Double) {
    var n = 0
    var maxDelay = -1.0
    var ran: [UInt64] = []
    let winEnd = req + 150_000_000
    let gapFrom = req > 10_000_000 ? req - 10_000_000 : 0
    for j in jobs {
        if j.enq >= req && j.enq < winEnd { n += 1; maxDelay = max(maxDelay, ms(j.ran - j.enq)) }
        if j.ran >= gapFrom && j.ran <= req + 300_000_000 { ran.append(j.ran) }
    }
    ran.sort()
    var gap = 0.0
    if ran.count > 1 { for i in 1..<ran.count { gap = max(gap, ms(ran[i] - ran[i - 1])) } }
    return (n, maxDelay, gap)
}

func selfTest() -> Bool {
    var fails: [String] = []
    let base: UInt64 = 10_000_000_000
    var healthy: [JobRecord] = [], stalled: [JobRecord] = []
    var t = base - 100_000_000
    while t < base + 600_000_000 {
        healthy.append(JobRecord(enq: t, ran: t + 100_000))
        // a 40 ms stall starting at req: every job enqueued in [req, req + 40 ms) runs at req + 40 ms
        let stallEnd = base + 40_000_000
        stalled.append(JobRecord(enq: t, ran: (t >= base && t < stallEnd) ? stallEnd : t + 100_000))
        t += 2_000_000
    }
    let h = blockingStats(healthy, req: base), s = blockingStats(stalled, req: base)
    if h.n < 70 || h.maxDelayMs > 0.2 || h.gapMs > 2.1 { fails.append("healthy \(h)") }
    if abs(s.maxDelayMs - 40.0) > 0.5 || s.gapMs < 39 || s.gapMs > 42 { fails.append("stalled \(s)") }
    if percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.99) != 10 { fails.append("p99") }
    glog("DRYRUN blockingStats healthy delay=\(fms(h.maxDelayMs)) gap=\(fms(h.gapMs)) | 40 ms stall delay=\(fms(s.maxDelayMs)) gap=\(fms(s.gapMs))")
    for f in fails { glog("DRYRUN logic FAIL \(f)") }
    glog("DRYRUN logic \(fails.isEmpty ? "PASS" : "FAIL")")
    return fails.isEmpty
}

final class ColdHost {
    let bridge: Bridge
    let producer = Producer()
    var scale: Float = 1
    var version: UInt64 = 0
    var open = 0
    var finishing = false
    var timedOut = false
    var closeCalls = 0
    var lastHandle: UInt64 = 0
    let startedNs = nowNs()
    var readyNs: UInt64 = 0
    var reqNs: [Int: UInt64] = [:]
    var reqRC: [Int: Int32] = [:]
    var resNs: [Int: UInt64] = [:]
    var resAction: [Int: UInt32] = [:]
    var resI0: [Int: Int32] = [:]
    var resI1: [Int: Int32] = [:]
    var resFailed: [Int: Bool] = [:]
    var ticks = 0
    var cleanupRan = false
    var shutdownRC: Int32?
    let isMenu = kindName == "menu"

    init(bridge: Bridge) { self.bridge = bridge }

    func begin(_ win: BridgeWindow) {
        if let m = try? win.metrics() {
            scale = m.scale
            lastHandle = win.handle
            version += 1
            let bg = Rect(x: 0, y: 0, w: Float(m.width), h: Float(m.height))
            let node = NodeUpsert(id: 2, order: 1, bounds: bg, primitives: [.rect(bg, color: 0xF5F5F5FF)])
            do { try win.commit(Transaction(version: version, upserts: [node])) } catch { glog("COMMIT FAILED \(error)") }
        }
        readyNs = nowNs()
        glog("START pid=\(ProcessInfo.processInfo.processIdentifier) kind=\(kindName) opens=\(opensWanted) abi=\(bridge.info.abi_major).\(bridge.info.abi_minor) scale=\(String(format: "%.3f", Double(scale))) window=\(String(win.handle, radix: 16)) ready_ns=\(readyNs)")
        try? win.requestTicks(true)
        producer.start()
        timers.after(leadSeconds) { [self] in requestNext() }
        watchdog()
        safetyService()
    }

    func safetyService() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            timers.service()
            if !cleanupRan { safetyService() }
        }
    }

    func watchdog() {
        timers.after(1.0) { [self] in
            if hostClosed || finishing { return }
            if Double(nowNs() - startedNs) / 1e9 > timeoutSeconds {
                glog("TIMEOUT after \(timeoutSeconds)s at open \(open)")
                timedOut = true
                finishing = true
                bridge.requestQuit()
                return
            }
            watchdog()
        }
    }

    func requestNext() {
        if hostClosed || finishing { return }
        open += 1
        guard open <= opensWanted, let win = bridge.window else {
            finishing = true
            bridge.requestQuit()
            return
        }
        let n = open
        let id = UInt64(1000 + n)
        let t0 = nowNs()
        reqNs[n] = t0
        let rc: Int32
        if isMenu {
            rc = status { try win.requestMenu(requestID: id, items: menuItems, x: 40 * scale, y: 60 * scale) }
        } else {
            rc = status { try win.requestDialog(requestID: id, title: dialogTitle, message: dialogMessage, buttons: dialogButtons, defaultIndex: 0) }
        }
        reqRC[n] = rc
        glog("OPEN n=\(n) kind=\(kindName) id=\(id) rc=\(statusName(rc)) req_ns=\(t0) dismiss=\(isMenu ? "menu-escape" : "dialog-click:1")")
        if rc != 0 { finishing = true; bridge.requestQuit(); return }
        timers.after(20) { [self] in
            if resNs[n] == nil && !hostClosed && !finishing {
                glog("OPEN n=\(n) NO RESULT after 20 s")
                timedOut = true; finishing = true; bridge.requestQuit()
            }
        }
    }

    func handle(_ ev: BridgeEvent) {
        if ev.window != 0, ev.window != bridge.window?.handle { return }
        guard ev.kind == .modalResult else { return }
        let now = nowNs()
        let n = Int(ev.arg) - 1000
        if resNs[n] != nil || reqNs[n] == nil { glog("RESULT unexpected or duplicate id=\(ev.arg)"); return }
        resNs[n] = now; resAction[n] = ev.action; resI0[n] = ev.i0; resI1[n] = ev.i1; resFailed[n] = ev.modalFailed
        glog("RESULT n=\(n) action=\(ev.action) i0=\(ev.i0) i1=\(ev.i1) failed=\(ev.modalFailed) res_ns=\(now) held_ms=\(fms(ms(now - (reqNs[n] ?? now))))")
        timers.after(0.5) { [self] in requestNext() }
    }

    func onClosed() {
        closeCalls += 1
        hostClosed = true
        let b = bridge
        timers.after(0.4) { [self] in
            cleanupRan = true
            do { try b.shutdownComplete(); shutdownRC = 0 } catch BridgeError.status(let rc, _) { shutdownRC = rc } catch { shutdownRC = -999 }
            producer.stop()
        }
    }

    func finish(runResult: String) -> Int32 {
        let st = bridge.stats()
        var idle: [Double] = []
        if let first = reqNs[1] {
            for j in jobs where j.enq >= readyNs + 300_000_000 && j.enq < first - 50_000_000 { idle.append(ms(j.ran - j.enq)) }
        }
        glog("IDLE n=\(idle.count) p99=\(fms(percentile(idle, 0.99))) max=\(fms(idle.max() ?? -1))")
        var ok = runResult == "ok" && !timedOut && shutdownRC == 0 && st.thread_violations == 0 && st.host_panics == 0
        for n in 1...opensWanted {
            guard let r = reqNs[n] else { ok = false; continue }
            let b = blockingStats(jobs, req: r)
            let good = reqRC[n] == 0 && resNs[n] != nil && resAction[n] == (isMenu ? 2 : 3)
            if !good { ok = false }
            glog("M1 n=\(n) kind=\(kindName) jobs=\(b.n) blocking_max_ms=\(fms(b.maxDelayMs)) run_gap_ms=\(fms(b.gapMs))")
        }
        glog("renderer stats: paints=\(st.paints) commits=\(st.commits_accepted) live_nodes=\(st.live_nodes) ticks=\(ticks) thread_violations=\(st.thread_violations) host_panics=\(st.host_panics) shutdown=\(statusName(shutdownRC ?? -99)) run=\(runResult)")
        glog("HOSTSUMMARY \(ok ? "PASS" : "FAIL")")
        return ok ? 0 : 1
    }
}

openLog()

if dryRun {
    let ok = selfTest()
    do {
        let bridge = try Bridge.load()
        glog("DRYRUN renderer loaded and validated: abi \(bridge.info.abi_major).\(bridge.info.abi_minor) (no window opened)")
        exit(ok ? 0 : 1)
    } catch BridgeError.unsupportedPlatform {
        glog("DRYRUN renderer loading is Windows only; logic self-test result only")
        exit(ok ? 0 : 1)
    } catch BridgeError.startup(let message) { glog(message); exit(78) }
    catch { glog("SWR_STARTUP_ERROR: \(error)"); exit(78) }
}

do {
    let bridge = try Bridge.load()
    let host = ColdHost(bridge: bridge)
    bridge.onWindowClosed = { host.onClosed() }
    var runResult = "ok"
    bridge.onReady = { win in host.begin(win) }
    bridge.onEvent = { ev in host.handle(ev) }
    bridge.onTick = { _, _ in host.ticks += 1; timers.service() }
    do { try bridge.run(title: "SwiftRight ColdOpen06", width: 640, height: 480) } catch { runResult = "run failed: \(error)" }
    exit(host.finish(runResult: runResult))
} catch BridgeError.startup(let message) { glog(message); exit(78) }
catch { glog("SWR_STARTUP_ERROR: \(error)"); exit(78) }
