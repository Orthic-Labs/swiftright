import Foundation
import SwiftRightBridge
#if os(Windows)
import WinSDK
#endif

// Modal06: SR0 snapshot row 7 on the final ABI 0.6 tuple. BridgeSmoke only checks the ARGUMENTS of menu and dialog
// requests; this host opens the real SWR_MODAL_MENU (TrackPopupMenu) and SWR_MODAL_DIALOG (TaskDialogIndirect) through
// the bridge and has scripts/drive-modal.ps1 dismiss each one with window-targeted input (UIA Invoke, PostMessage of
// WM_KEYDOWN / TDM_CLICK_BUTTON to the menu or dialog window; no global input). It asserts:
//   * the async result arrives as a SWR_EV_MODAL_RESULT with the request id, the kind, the chosen item id and index
//     (or the dismissed marker i0 = 0, i1 = -1);
//   * the main loop keeps pumping while the modal is open: a producer thread posts jobs to the main dispatch queue at
//     ~500 Hz for the whole run; their latency during the modal stays within the frame budget (probe modal-loop run 8:
//     steady p99 <= 16.7 ms; the one-off cost of opening the dialog <= 50 ms). Jobs are counted by the time they RAN (a
//     stalled queue still accepts jobs and flushes them after the modal returns), pauses between runs include the interval's
//     ends, and display ticks must keep arriving (ticks_during > 0);
//   * one pending request at a time (a second request in the same turn is SWR_E_QUEUE_FULL);
//   * late dispatch is safe: closing the window while a dialog is open (the result, if it still arrives, is ignored by
//     the host), and menu/dialog/message/commit requests made from the post-close pump are rejected with typed errors.
//
// Scenarios (request ids 1001..): S1 menu select, S2 menu Escape, S3 dialog button, S4 dialog Escape,
// S5 menu opened with a second request in the same turn, dismissed with the keyboard, S6 dialog open while the window closes.
// Exit code: 0 = every host-side check passed, 1 = a failure, 78 = startup diagnostic.
// SWR_GM_DRYRUN=1: load the renderer (Windows) and run the pure-logic self-test only; no window.

let env = ProcessInfo.processInfo.environment
let dryRun = env["SWR_GM_DRYRUN"] == "1"
let timeoutSeconds = Double(env["SWR_GM_TIMEOUT"] ?? "") ?? 90
let openBoundMs = Double(env["SWR_GM_OPEN_BOUND_MS"] ?? "") ?? 50      // one-off cost of opening a modal (modal-loop run 8 bound)
let budgetMs = Double(env["SWR_GM_BUDGET_MS"] ?? "") ?? 16.7            // one frame at 60 Hz
let gapBoundMs = Double(env["SWR_GM_GAP_BOUND_MS"] ?? "") ?? 100        // longest allowed pause between job RUNS inside a modal interval (healthy runs: ~10 ms)

// MARK: log and clock

var logFile: UnsafeMutablePointer<FILE>?

func openLog() {
    guard let p = env["SWR_GM_LOG"], !p.isEmpty else { return }
    logFile = fopen(p, "ab")
}

func asciiSafe(_ s: String) -> String {
    var out = ""
    for u in s.unicodeScalars { out += u.value < 0x80 ? String(u) : "\\u{\(String(u.value, radix: 16))}" }
    return out
}

func glog(_ s: String) {
    if let f = logFile { fputs(s + "\n", f); fflush(f) }
    print(asciiSafe(s))
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

// MARK: timers (main thread only)
//
// No precedent exists for DispatchQueue.main.asyncAfter on the bridge, so timed work does not depend on it: due actions
// are run by `service()`, which the producer's main-queue jobs (the mechanism probes/sr0-b/gpui-drain proved), the display
// ticks and a 50 ms asyncAfter chain all call. Whichever runs first fires the action; the others find nothing due.

final class Timers {
    private var items: [(due: UInt64, action: () -> Void)] = []

    func after(_ seconds: Double, _ action: @escaping () -> Void) {
        items.append((due: nowNs() + UInt64(seconds * 1e9), action: action))
    }

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

// MARK: job producer (a background thread posting to the main dispatch queue the renderer drains)

struct JobRecord { let enq: UInt64; let ran: UInt64; let late: Bool }

var jobs: [JobRecord] = []                 // appended on the main (UI) thread only

/// How well the main queue pumped during one modal interval [req, res] (pure; self-tested in the dry run).
/// Jobs are counted by the time they RAN, not the time they were enqueued: a stalled queue keeps accepting jobs (all of them
/// "enqueued during the modal") and runs them in one burst right after the modal returns, just before the result is delivered.
/// The last 100 ms of the interval are therefore left out of the count, and the pauses between runs include the interval's own
/// ends [req + 150 ms ... res], so a stall of the whole modal shows as one pause as long as the stall.
func pumpStats(_ jobs: [JobRecord], req: UInt64, res: UInt64) -> (count: Int, maxGapMs: Double) {
    let steadyStart = req + 150_000_000
    let steadyEnd = res > 100_000_000 ? res - 100_000_000 : res
    var ran: [UInt64] = []
    var n = 0
    for j in jobs {
        if j.ran >= steadyStart && j.ran <= res { ran.append(j.ran) }
        if j.ran >= steadyStart && j.ran <= steadyEnd { n += 1 }
    }
    ran.sort()
    var prev = steadyStart
    var gap = 0.0
    for r in ran + [res] {
        if r >= prev { gap = max(gap, Double(r - prev) / 1e6) }
        prev = r
    }
    return (n, gap)
}
var jobsAfterClose = 0
var hostClosed = false                      // main thread only

final class Producer {
    private let lock = NSLock()
    private var stopFlag = false
    private(set) var enqueued = 0

    func stop() { lock.lock(); stopFlag = true; lock.unlock() }

    func start() {
        Thread { [self] in
            let periodNs: UInt64 = 2_000_000                        // 500 Hz
            var next = nowNs()
            while true {
                lock.lock(); let s = stopFlag; lock.unlock()
                if s { break }
                let t = nowNs()
                if t < next {
                    if next - t > 2_500_000 { napShort() } else { napSpin() }
                    continue
                }
                next += periodNs
                if t > next + 50_000_000 { next = t }               // never burst after a long stall
                lock.lock(); enqueued += 1; lock.unlock()
                let enq = t
                DispatchQueue.main.async {
                    let ran = nowNs()
                    if hostClosed { jobsAfterClose += 1 }
                    jobs.append(JobRecord(enq: enq, ran: ran, late: hostClosed))
                    timers.service()
                }
            }
        }.start()
    }
}

// MARK: scenarios

typealias Item = BridgeWindow.ModalItem

enum ModalKind: UInt32 { case menu = 2, dialog = 3 }

struct Scenario {
    let id: UInt64
    let tag: String                 // S1 ...
    let name: String
    let kind: ModalKind
    let items: [Item]
    let title: String
    let message: String
    let defaultIndex: Int
    let dismiss: String             // instruction for the driver, logged with the request
    let expectID: UInt32            // 0 = dismissed (no choice)
    let expectIndex: Int            // -1 = dismissed
    let doubleRequest: Bool         // a second request in the same turn must be SWR_E_QUEUE_FULL
    let closeWhileOpen: Bool        // the host closes the window while the modal is open; the result is not asserted
}

let menuItems: [Item] = [
    Item(id: 11, text: "Open"),
    Item(id: 12, text: "Save", checked: true),
    .separatorItem,
    Item(id: 14, text: "Delete", disabled: true),
    Item(id: 15, text: "Quit"),
]
let dialogButtons: [Item] = [Item(id: 21, text: "Save"), Item(id: 22, text: "Don't save"), Item(id: 23, text: "Cancel")]
let dialogTitle = "SR0 Modal06 dialog"
let dialogMessage = "Choose a button. This dialog is opened by the Modal06 host through SWR_MODAL_DIALOG."

let scenarios: [Scenario] = [
    Scenario(id: 1001, tag: "S1", name: "menu-select", kind: .menu, items: menuItems, title: "", message: "", defaultIndex: 0,
             dismiss: "menu-select:4:Quit", expectID: 15, expectIndex: 4, doubleRequest: false, closeWhileOpen: false),
    Scenario(id: 1002, tag: "S2", name: "menu-escape", kind: .menu, items: menuItems, title: "", message: "", defaultIndex: 0,
             dismiss: "menu-escape", expectID: 0, expectIndex: -1, doubleRequest: false, closeWhileOpen: false),
    Scenario(id: 1003, tag: "S3", name: "dialog-click", kind: .dialog, items: dialogButtons, title: dialogTitle, message: dialogMessage, defaultIndex: 0,
             dismiss: "dialog-click:1", expectID: 22, expectIndex: 1, doubleRequest: false, closeWhileOpen: false),
    Scenario(id: 1004, tag: "S4", name: "dialog-escape", kind: .dialog, items: dialogButtons, title: dialogTitle, message: dialogMessage, defaultIndex: 2,
             dismiss: "dialog-escape", expectID: 0, expectIndex: -1, doubleRequest: false, closeWhileOpen: false),
    Scenario(id: 1005, tag: "S5", name: "menu-keys-queue-full", kind: .menu, items: [Item(id: 11, text: "Open"), Item(id: 15, text: "Quit")],
             title: "", message: "", defaultIndex: 0,
             dismiss: "menu-keys:1", expectID: 11, expectIndex: 0, doubleRequest: true, closeWhileOpen: false),
    Scenario(id: 1006, tag: "S6", name: "dialog-open-at-close", kind: .dialog, items: dialogButtons, title: dialogTitle, message: dialogMessage, defaultIndex: 0,
             dismiss: "dialog-observe", expectID: 0, expectIndex: -1, doubleRequest: false, closeWhileOpen: true),
]

struct Outcome {
    var action: UInt32
    var i0: Int32
    var i1: Int32
    var itemID: UInt32?
    var index: Int?
    var failed: Bool
    var atNs: UInt64
    var count: Int
    var afterClose: Bool
}

struct HostCheck { let name: String; let ok: Bool; let detail: String }

// MARK: pure-logic self-test (dry run)

func selfTestPureLogic() -> Bool {
    var fails: [String] = []
    if percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.99) != 10 { fails.append("p99") }
    if percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.5) != 5 { fails.append("p50") }
    if percentile([], 0.99) != -1 { fails.append("empty percentile") }
    let ids = scenarios.map { $0.id }
    if Set(ids).count != ids.count { fails.append("duplicate scenario ids") }
    for sc in scenarios {
        var seen = Set<UInt32>()
        for it in sc.items where !it.separator { if it.id == 0 || !seen.insert(it.id).inserted { fails.append("\(sc.tag) item ids") } }
        if sc.expectID != 0 {
            let selectable = sc.items.enumerated().filter { !$0.element.separator }
            if !selectable.contains(where: { $0.element.id == sc.expectID && $0.offset == sc.expectIndex }) { fails.append("\(sc.tag) expectation does not match an item") }
        }
        if sc.kind == .dialog && (sc.items.isEmpty || sc.items.count > 8) { fails.append("\(sc.tag) dialog buttons") }
        if sc.kind == .dialog && sc.defaultIndex >= sc.items.count { fails.append("\(sc.tag) default index") }
    }
    if let s1 = scenarios.first, s1.items[s1.expectIndex].text != "Quit" { fails.append("S1 index/text mismatch") }
    // pumping gate: a healthy modal (jobs run ~0.1 ms after they are enqueued, 500 Hz, 1.25 s) passes; the stalls of Modal06 runs 15 and 20 (jobs
    // keep being enqueued, all run in one burst 5 ms before the result) fails by run time even though ~550 were ENQUEUED in the interval
    let base: UInt64 = 10_000_000_000
    let req = base, res = base + 1_250_000_000
    var healthy: [JobRecord] = [], stalled: [JobRecord] = []
    var t = base
    while t < res { healthy.append(JobRecord(enq: t, ran: t + 100_000, late: false)); stalled.append(JobRecord(enq: t, ran: res - 5_000_000, late: false)); t += 2_000_000 }
    let h = pumpStats(healthy, req: req, res: res), st = pumpStats(stalled, req: req, res: res)
    if !(h.count >= 50 && h.maxGapMs <= gapBoundMs) { fails.append("pumpStats rejects a healthy modal count=\(h.count) gap=\(fms(h.maxGapMs))") }
    if st.count >= 50 || st.maxGapMs <= gapBoundMs { fails.append("pumpStats accepts the stalled modal count=\(st.count) gap=\(fms(st.maxGapMs))") }
    let enqCount = stalled.filter { $0.enq >= req + 150_000_000 && $0.enq < res }.count
    if enqCount < 50 { fails.append("stalled model is not the old defect (enqueue-time count \(enqCount))") }
    glog("DRYRUN pumpStats healthy count=\(h.count) gap_ms=\(fms(h.maxGapMs)) | stalled count=\(st.count) gap_ms=\(fms(st.maxGapMs)) (enqueue-time count would have been \(enqCount))")
    let t0 = nowNs(); napShort(); let t1 = nowNs()
    if t1 < t0 { fails.append("clock not monotonic") }
    for f in fails { glog("DRYRUN logic FAIL \(f)") }
    glog("DRYRUN logic \(fails.isEmpty ? "PASS" : "FAIL") (\(scenarios.count) scenarios)")
    return fails.isEmpty
}

// MARK: host

final class ModalHost {
    let bridge: Bridge
    let producer = Producer()
    var scale: Float = 1
    var version: UInt64 = 0
    var idx = -1
    var finishing = false
    var timedOut = false
    var closeCalls = 0
    var closedAtNs: UInt64 = 0
    var lastHandle: UInt64 = 0
    let startedNs = nowNs()
    var readyNs: UInt64 = 0
    var checks: [HostCheck] = []

    var requestAt: [UInt64: UInt64] = [:]
    var requestRC: [UInt64: Int32] = [:]
    var ticksAtRequest: [UInt64: Int] = [:]
    var outcomes: [UInt64: Outcome] = [:]
    var secondRC: Int32?
    var unexpectedResults = 0
    var duplicateResults = 0
    var lateResults = 0
    var ticks = 0
    var ticksInModal: [UInt64: Int] = [:]
    var closeRequestedNs: UInt64 = 0
    var staleEvents = 0

    var lateCommitRC: Int32?
    var lateMenuRC: Int32?
    var lateDialogRC: Int32?
    var lateMessageRC: Int32?
    var cleanupRan = false
    var cleanupLiveNodes: UInt64?
    var cleanupShutdownRC: Int32?

    init(bridge: Bridge) { self.bridge = bridge }

    func add(_ name: String, _ ok: Bool, _ detail: String = "") { checks.append(HostCheck(name: name, ok: ok, detail: detail)) }
    func sinceStartMs() -> String { fms(ms(nowNs() - startedNs)) }

    func begin(_ win: BridgeWindow) {
        if let m = try? win.metrics() {
            scale = m.scale
            lastHandle = win.handle
            glog("ready: window=\(String(win.handle, radix: 16)) client=\(m.width)x\(m.height)px scale=\(m.scale)")
            version += 1
            let bg = Rect(x: 0, y: 0, w: Float(m.width), h: Float(m.height))
            let node = NodeUpsert(id: 2, order: 1, bounds: bg, primitives: [.rect(bg, color: 0xF5F5F5FF)])
            do { try win.commit(Transaction(version: version, upserts: [node])) } catch { glog("COMMIT FAILED \(error)") }
        }
        readyNs = nowNs()
        glog("START pid=\(ProcessInfo.processInfo.processIdentifier) abi=\(bridge.info.abi_major).\(bridge.info.abi_minor) scale=\(String(format: "%.3f", Double(scale))) open_bound_ms=\(openBoundMs) budget_ms=\(budgetMs)")
        for sc in scenarios {
            glog("SCENARIO id=\(sc.id) tag=\(sc.tag) name=\(sc.name) kind=\(sc.kind == .menu ? "menu" : "dialog") items=\(sc.items.count) dismiss=\(sc.dismiss) expect=\(sc.expectID)/\(sc.expectIndex)")
        }
        try? win.requestTicks(true)
        producer.start()
        timers.after(1.0) { [self] in requestNext() }
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
                glog("TIMEOUT after \(timeoutSeconds)s at scenario index \(idx)")
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
        idx += 1
        guard idx < scenarios.count, let win = bridge.window else {
            glog("SEQUENCE end (no more scenarios)")
            finishing = true
            bridge.requestQuit()
            return
        }
        let sc = scenarios[idx]
        let t0 = nowNs()
        requestAt[sc.id] = t0
        ticksAtRequest[sc.id] = ticks
        let rc: Int32
        switch sc.kind {
        case .menu:
            rc = status { try win.requestMenu(requestID: sc.id, items: sc.items, x: 40 * scale, y: 60 * scale) }
        case .dialog:
            rc = status { try win.requestDialog(requestID: sc.id, title: sc.title, message: sc.message, buttons: sc.items, defaultIndex: sc.defaultIndex) }
        }
        requestRC[sc.id] = rc
        glog("MODAL id=\(sc.id) request tag=\(sc.tag) name=\(sc.name) kind=\(sc.kind == .menu ? "menu" : "dialog") rc=\(statusName(rc)) dismiss=\(sc.dismiss) title=\(sc.title) at_ms=\(sinceStartMs())")
        if sc.doubleRequest {
            // The pending slot is only taken by the renderer after this turn unwinds: a second request now is QUEUE_FULL.
            let rc2 = status { try win.requestMenu(requestID: sc.id + 500, items: sc.items, x: 10, y: 10) }
            secondRC = rc2
            glog("MODAL id=\(sc.id) second request in the same turn rc=\(statusName(rc2)) (expect SWR_E_QUEUE_FULL)")
        }
        if rc != 0 {
            glog("MODAL id=\(sc.id) request rejected: closing")
            finishing = true
            _ = status { try win.requestClose() }
            return
        }
        if sc.closeWhileOpen {
            timers.after(1.2) { [self] in
                guard !hostClosed, let w = bridge.window else { return }
                closeRequestedNs = nowNs()
                glog("MODAL id=\(sc.id) closing the window while the dialog is open at_ms=\(sinceStartMs())")
                finishing = true
                _ = status { try w.requestClose() }
                // The renderer closes from its own loop; if a modal that never returns blocks that, the driver rescues it.
            }
        } else {
            // per-scenario watchdog: a result must arrive
            timers.after(25) { [self] in
                if outcomes[sc.id] == nil && !hostClosed && !finishing {
                    glog("MODAL id=\(sc.id) NO RESULT after 25 s: closing")
                    timedOut = true
                    finishing = true
                    bridge.requestQuit()
                }
            }
        }
    }

    // MARK: events

    func handle(_ ev: BridgeEvent) {
        if ev.window != 0, ev.window != bridge.window?.handle { staleEvents += 1; return }
        guard ev.kind == .modalResult else { return }
        let now = nowNs()
        guard let sc = scenarios.first(where: { $0.id == ev.arg }) else {
            unexpectedResults += 1
            glog("MODAL result for unknown request id=\(ev.arg) action=\(ev.action) i0=\(ev.i0) i1=\(ev.i1) (ignored)")
            return
        }
        let choice = ev.modalChoice
        if var o = outcomes[sc.id] {
            o.count += 1
            outcomes[sc.id] = o
            duplicateResults += 1
            glog("MODAL id=\(sc.id) DUPLICATE result (ignored)")
            return
        }
        let t0 = requestAt[sc.id] ?? now
        outcomes[sc.id] = Outcome(action: ev.action, i0: ev.i0, i1: ev.i1, itemID: choice?.itemID, index: choice?.index,
                                  failed: ev.modalFailed, atNs: now, count: 1, afterClose: hostClosed)
        ticksInModal[sc.id] = ticks - (ticksAtRequest[sc.id] ?? ticks)
        if hostClosed {
            lateResults += 1
            glog("MODAL id=\(sc.id) result AFTER window_closed action=\(ev.action) i0=\(ev.i0) i1=\(ev.i1) failed=\(ev.modalFailed) (ignored: no window, no commit) elapsed_ms=\(fms(ms(now - t0)))")
            return
        }
        glog("MODAL id=\(sc.id) result tag=\(sc.tag) action=\(ev.action) i0=\(ev.i0) i1=\(ev.i1) choice=\(choice.map { "\($0.itemID)/\($0.index)" } ?? "none") failed=\(ev.modalFailed) elapsed_ms=\(fms(ms(now - t0))) ticks_during=\(ticksInModal[sc.id] ?? 0) at_ms=\(sinceStartMs())")
        if sc.closeWhileOpen { return }
        timers.after(0.4) { [self] in requestNext() }
    }

    func onClosed() {
        closeCalls += 1
        hostClosed = true
        closedAtNs = nowNs()
        glog("WINDOW_CLOSED at_ms=\(sinceStartMs())")
        let b = bridge
        let h = lastHandle
        // Late work posted before the close and run in the post-close pump: every request must be rejected, typed.
        DispatchQueue.main.async { [self] in
            let w = BridgeWindow.makeForTesting(bridge: b, handle: h)
            lateCommitRC = status { try w.commit(Transaction(version: 900_000)) }
            lateMenuRC = status { try w.requestMenu(requestID: 7001, items: [Item(id: 1, text: "x")], x: 10, y: 10) }
            lateDialogRC = status { try w.requestDialog(requestID: 7002, title: "t", message: "m", buttons: [Item(id: 1, text: "x")]) }
            lateMessageRC = status { try w.requestModal(requestID: 7003, title: "t", message: "m", buttons: .ok) }
            glog("LATE after close: commit=\(statusName(lateCommitRC ?? 0)) menu=\(statusName(lateMenuRC ?? 0)) dialog=\(statusName(lateDialogRC ?? 0)) message=\(statusName(lateMessageRC ?? 0))")
        }
        // Cleanup after a short wait, so a modal result that the dying dialog still delivers arrives (and is ignored) first.
        timers.after(0.6) { [self] in
            cleanupRan = true
            cleanupLiveNodes = b.stats().live_nodes
            do { try b.shutdownComplete(); cleanupShutdownRC = 0 }
            catch BridgeError.status(let rc, _) { cleanupShutdownRC = rc }
            catch { cleanupShutdownRC = -999 }
            producer.stop()
        }
    }

    // MARK: summary

    func finish(runResult: String) -> Int32 {
        let st = bridge.stats()
        let b = bridge
        add("startup validation", b.info.abi_major == 0 && b.info.abi_minor == 6 && b.info.fn_count == 16 && b.info.stats_size == 200,
            "abi \(b.info.abi_major).\(b.info.abi_minor) fn_count=\(b.info.fn_count) stats_size=\(b.info.stats_size)")
        add("run returned ok", runResult == "ok", runResult)
        add("sequence ran without timeout", !timedOut, "timed_out=\(timedOut)")

        for sc in scenarios where !sc.closeWhileOpen {
            let rcOK = requestRC[sc.id] == 0
            let o = outcomes[sc.id]
            var ok = false
            var detail = "no result event"
            if let o {
                let kindOK = o.action == sc.kind.rawValue
                let valueOK: Bool
                if sc.expectID != 0 {
                    valueOK = o.itemID == sc.expectID && o.index == sc.expectIndex && o.i0 == Int32(sc.expectID) && o.i1 == Int32(sc.expectIndex) && !o.failed
                } else {
                    valueOK = o.itemID == nil && o.index == nil && o.i0 == 0 && o.i1 == -1 && !o.failed
                }
                ok = rcOK && kindOK && valueOK && o.count == 1 && !o.afterClose
                detail = "request=\(statusName(requestRC[sc.id] ?? -99)) action=\(o.action) (want \(sc.kind.rawValue)) i0=\(o.i0) i1=\(o.i1) choice=\(o.itemID.map { "\($0)/\(o.index ?? -1)" } ?? "none") want=\(sc.expectID == 0 ? "dismissed" : "\(sc.expectID)/\(sc.expectIndex)") failed=\(o.failed) events=\(o.count) ticks_during=\(ticksInModal[sc.id] ?? 0)"
            } else {
                detail += " request=\(statusName(requestRC[sc.id] ?? -99))"
            }
            add("\(sc.tag) \(sc.name): async result arrives once with the expected item id and index", ok, detail)
        }
        let s5 = scenarios.first { $0.doubleRequest }
        if let s5 {
            add("\(s5.tag) one pending request at a time: a second request in the same turn is SWR_E_QUEUE_FULL, the first still delivered",
                secondRC == -7 && outcomes[s5.id] != nil, "second=\(statusName(secondRC ?? -99)) first_result=\(outcomes[s5.id] != nil)")
        }
        add("no result for an unknown id, no duplicate result", unexpectedResults == 0 && duplicateResults == 0, "unknown=\(unexpectedResults) duplicate=\(duplicateResults)")

        // pumping budget (jobs the producer posted to the main dispatch queue)
        let open = Double(openBoundMs)
        var openLat: [Double] = [], steadyLat: [Double] = [], idleLat: [Double] = []
        var perScenarioSteady: [(String, Int)] = []
        var maxRunGapMs = 0.0
        var intervals: [(UInt64, UInt64)] = []
        for sc in scenarios where !sc.closeWhileOpen {
            guard let req = requestAt[sc.id], let o = outcomes[sc.id] else { continue }
            let res = o.atNs
            intervals.append((req, res))
            let steadyStart = req + 150_000_000
            for j in jobs {
                let lat = ms(j.ran - j.enq)
                if j.enq >= req && j.enq < steadyStart { openLat.append(lat) }
                else if j.enq >= steadyStart && j.enq < res { steadyLat.append(lat) }
            }
            let ps = pumpStats(jobs, req: req, res: res)
            maxRunGapMs = max(maxRunGapMs, ps.maxGapMs)
            perScenarioSteady.append((sc.tag, ps.count))
        }
        let idleFrom = readyNs + 500_000_000
        let idleTo = (requestAt[scenarios[scenarios.count - 1].id] ?? UInt64.max) - 100_000_000
        for j in jobs where j.enq >= idleFrom && j.enq < idleTo {
            if !intervals.contains(where: { j.enq >= $0.0 - 50_000_000 && j.enq <= $0.1 + 250_000_000 }) { idleLat.append(ms(j.ran - j.enq)) }
        }
        let allLat = jobs.map { ms($0.ran - $0.enq) }
        let steadyP99 = percentile(steadyLat, 0.99)
        let openMax = openLat.max() ?? -1
        let idleP99 = percentile(idleLat, 0.99)
        glog("LATENCY_MS all n=\(allLat.count) p50=\(fms(percentile(allLat, 0.5))) p99=\(fms(percentile(allLat, 0.99))) max=\(fms(allLat.max() ?? -1)) | modal_open_one_off n=\(openLat.count) max=\(fms(openMax)) | modal_steady n=\(steadyLat.count) p50=\(fms(percentile(steadyLat, 0.5))) p99=\(fms(steadyP99)) max=\(fms(steadyLat.max() ?? -1)) max_run_gap=\(fms(maxRunGapMs)) | idle n=\(idleLat.count) p99=\(fms(idleP99)) max=\(fms(idleLat.max() ?? -1))")
        let minSteady = perScenarioSteady.map { $0.1 }.min() ?? 0
        add("main loop keeps pumping while a modal is open: jobs RUN in every modal interval (counted by run time) with no long pause", perScenarioSteady.count == scenarios.count - 1 && minSteady >= 50 && maxRunGapMs <= gapBoundMs,
            "jobs run in [request+150 ms, result-100 ms] per scenario \(perScenarioSteady.map { "\($0.0)=\($0.1)" }.joined(separator: " ")) (need >= 50 each), max pause between job runs incl. interval ends \(fms(maxRunGapMs)) ms (bound \(fms(gapBoundMs))), producer enqueued=\(producer.enqueued)")
        let tickList = scenarios.filter { !$0.closeWhileOpen }.map { ($0.tag, ticksInModal[$0.id] ?? 0) }
        add("display ticks keep arriving while a modal is open (ticks_during > 0 in every modal)", tickList.count == scenarios.count - 1 && tickList.allSatisfy { $0.1 > 0 },
            "ticks_during \(tickList.map { "\($0.0)=\($0.1)" }.joined(separator: " "))")
        add("job latency during an open modal within budget (steady p99 <= \(budgetMs) ms)", steadyP99 >= 0 && steadyP99 <= budgetMs, "p99=\(fms(steadyP99)) ms n=\(steadyLat.count)")
        add("one-off cost of opening a modal within \(Int(open)) ms (modal-loop run 8 bound)", openMax >= 0 && openMax <= open, "max=\(fms(openMax)) ms over \(openLat.count) jobs in the first 150 ms of each modal")
        add("job latency outside any modal within budget (idle p99 <= \(budgetMs) ms)", idleP99 >= 0 && idleP99 <= budgetMs, "p99=\(fms(idleP99)) ms n=\(idleLat.count)")

        // S6 and the post-close rules
        let s6 = scenarios.first { $0.closeWhileOpen }
        let s6Outcome = s6.flatMap { outcomes[$0.id] }
        add("S6 dialog open while the window closes: run returned, window_closed once, a late result (if any) was ignored",
            closeCalls == 1 && b.windowClosedCalls == 1 && closeRequestedNs != 0 && lateResults <= 1,
            "close_calls=\(closeCalls) late_results=\(lateResults) order=\(s6Outcome.map { $0.afterClose ? "result-after-close" : "result-before-close" } ?? "no-result") i0=\(s6Outcome.map { String($0.i0) } ?? "-") i1=\(s6Outcome.map { String($0.i1) } ?? "-") failed=\(s6Outcome.map { String($0.failed) } ?? "-")")
        add("requests from the post-close pump rejected: commit SWR_E_SHUTDOWN, menu/dialog/message SWR_E_STALE_HANDLE",
            lateCommitRC == -13 && lateMenuRC == -6 && lateDialogRC == -6 && lateMessageRC == -6,
            "commit=\(statusName(lateCommitRC ?? 0)) menu=\(statusName(lateMenuRC ?? 0)) dialog=\(statusName(lateDialogRC ?? 0)) message=\(statusName(lateMessageRC ?? 0)) jobs_run_after_close=\(jobsAfterClose)")
        add("no stale events, no thread violations or host panics", staleEvents == 0 && st.thread_violations == 0 && st.host_panics == 0,
            "stale=\(staleEvents) thread_violations=\(st.thread_violations) host_panics=\(st.host_panics)")
        add("live nodes zero after teardown", cleanupLiveNodes == 0 && st.live_nodes == 0, "at cleanup=\(cleanupLiveNodes.map { String($0) } ?? "none") after run=\(st.live_nodes)")
        let sinceClose = closedAtNs == 0 ? 0 : ms(nowNs() - closedAtNs) / 1000
        add("post-close pump ended by swr_shutdown_complete, not the timeout", cleanupRan && cleanupShutdownRC == 0 && st.post_close_timeouts == 0 && sinceClose < 4.5,
            "shutdown=\(statusName(cleanupShutdownRC ?? -99)) timeouts=\(st.post_close_timeouts) run returned \(String(format: "%.2f", sinceClose))s after window_closed")
        glog("renderer stats: paints=\(st.paints) commits=\(st.commits_accepted) events=\(st.events_pushed) live_nodes=\(st.live_nodes) ticks=\(ticks)")
        var pass = true
        for c in checks {
            glog("HC \(c.ok ? "PASS" : "FAIL") \(c.name) [\(c.detail)]")
            if !c.ok { pass = false }
        }
        glog("HOSTSUMMARY \(pass ? "PASS" : "FAIL") (\(checks.filter { $0.ok }.count)/\(checks.count))")
        return pass ? 0 : 1
    }
}

// MARK: main

openLog()

if dryRun {
    let ok = selfTestPureLogic()
    do {
        let bridge = try Bridge.load()
        glog("DRYRUN renderer loaded and validated: abi \(bridge.info.abi_major).\(bridge.info.abi_minor) fn_count=\(bridge.info.fn_count) stats_size=\(bridge.info.stats_size) (no window opened)")
        exit(ok ? 0 : 1)
    } catch BridgeError.unsupportedPlatform {
        glog("DRYRUN renderer loading is Windows only; logic self-test result only")
        exit(ok ? 0 : 1)
    } catch BridgeError.startup(let message) {
        glog(message)
        exit(78)
    } catch {
        glog("SWR_STARTUP_ERROR: \(error)")
        exit(78)
    }
}

do {
    let bridge = try Bridge.load()
    let host = ModalHost(bridge: bridge)
    bridge.onWindowClosed = { host.onClosed() }
    var runResult = "ok"
    bridge.onReady = { win in host.begin(win) }
    bridge.onEvent = { ev in host.handle(ev) }
    bridge.onTick = { _, _ in host.ticks += 1; timers.service() }
    do {
        try bridge.run(title: "SwiftRight Modal06", width: 640, height: 480)
    } catch {
        runResult = "run failed: \(error)"
    }
    exit(host.finish(runResult: runResult))
} catch BridgeError.startup(let message) {
    glog(message)
    exit(78)
} catch {
    glog("SWR_STARTUP_ERROR: \(error)")
    exit(78)
}
