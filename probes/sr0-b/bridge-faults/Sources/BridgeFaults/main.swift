import Foundation
import CSwrFakeRender
#if os(Windows)
import WinSDK
#endif
import Dispatch

// Usage: BridgeFaults <path-to-swr_fake_render.dll>
let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: BridgeFaults <path-to-swr_fake_render.dll>")
    exit(2)
}

#if os(Windows)
gRenderer = loadRenderer(path: args[1])
print("SWR_STARTUP_OK abi=0.1 arch=x86_64 pointer_width=64 cb_table_size=\(MemoryLayout<swr_cb_table>.size)")

gLedger = UnsafeMutablePointer<Ledger>.allocate(capacity: 1)
gLedger.initialize(to: Ledger())
gCB = UnsafeMutablePointer<swr_cb_table>.allocate(capacity: 1)
gCB.initialize(to: swr_cb_table(ctx: UnsafeMutableRawPointer(gLedger), on_ax_action: onAxAction))

let r = gRenderer!
var results: [(String, Bool)] = []

// ---- T1: startup matching + caller-sized bootstrap rejection ----
do {
    let c = Check()
    var small = swr_bootstrap_info()
    small.struct_size = 0xFFFF_FFFF
    let rc8 = withUnsafeMutablePointer(to: &small) { r.bootstrap($0, 8) }
    c.fact("bootstrap with 8-byte caller rejected", rc8 != 0, "rc \(rc8)")
    c.fact("rejected call leaves struct_size untouched", small.struct_size == 0xFFFF_FFFF)
    report("T1 startup-matching", c)
    results.append(("T1 startup-matching", c.pass))
}

// ---- T2: stale handles and generation reuse ----
do {
    let c = Check()
    let A = openWindow()
    c.fact("open window A", A != 0, "gen \(A)")
    let h1 = r.nodeCreate(A)
    let h2 = r.nodeCreate(A)
    c.fact("create nodes h1,h2", h1 != 0 && h2 != 0)
    c.expect("set_text(h1, alpha)", setText(h1, "alpha"), 0)
    let (g1rc, g1) = getText(h1)
    c.fact("get_text(h1) is alpha", g1rc == 0 && g1 == "alpha", "text '\(g1)'")
    c.expect("close window A", closeWindow(A), 0)
    c.expect("set_text(h1) after close", setText(h1, "x"), SWR_E_STALE_HANDLE)
    c.expect("set_text(h2) after close", setText(h2, "y"), SWR_E_STALE_HANDLE)
    c.expect("node_check(h1) after close", r.nodeCheck(h1), SWR_E_STALE_HANDLE)
    c.expect("node_release(h1) after close", r.nodeRelease(h1), SWR_E_STALE_HANDLE)
    c.expect("post(A,h1) after close", post(A, h1, 1, 1), SWR_E_STALE_HANDLE)
    c.expect("close window A twice", closeWindow(A), SWR_E_STALE_HANDLE)
    c.fact("create node on closed window A returns 0", r.nodeCreate(A) == 0)
    let B = openWindow()
    c.fact("reopen window B", B != 0 && B != A, "gen \(B)")
    let h3 = r.nodeCreate(B)
    let reused = (h3 & 0xFFFF_FFFF) == (h1 & 0xFFFF_FFFF)
    c.fact("h3 reuses h1 slot index under new generation", h3 != 0 && reused && h3 != h1,
           "h1=\(String(h1, radix: 16)) h3=\(String(h3, radix: 16))")
    c.expect("set_text(old h1) after slot reuse", setText(h1, "stale"), SWR_E_STALE_HANDLE)
    c.expect("node_check(old h1) after slot reuse", r.nodeCheck(h1), SWR_E_STALE_HANDLE)
    c.expect("set_text(h3, beta)", setText(h3, "beta"), 0)
    let (g2rc, g2) = getText(h3)
    c.fact("h3 text is beta (old handle did not write)", g2rc == 0 && g2 == "beta", "text '\(g2)'")
    c.expect("set_text 200 bytes (over capacity)", setText(h3, String(repeating: "a", count: 200)), SWR_E_TOO_LARGE)
    c.expect("set_text null with len 3", r.nodeSetText(h3, nil, 3), SWR_E_BAD_ARG)
    let (g3rc, g3) = getText(h3)
    c.fact("h3 text unchanged by rejected writes", g3rc == 0 && g3 == "beta", "text '\(g3)'")
    report("T2 stale-handles", c)
    results.append(("T2 stale-handles", c.pass))
    gLedger.pointee.snapshot = 1
}

// ---- T3: queue overflow, 4 producer threads, slow drain ----
let windowB = gLedger.pointee.liveWindow
let nodeB: UInt64 = r.nodeCreate(windowB)
do {
    let c = Check()
    _ = setText(nodeB, "t3")
    let s0 = statsNow()
    let L0 = ledgerCopy()
    let tallies = (0..<4).map { _ in Tally() }
    let group = DispatchGroup()
    for t in tallies {
        group.enter()
        Thread {
            for i in 0..<10_000 {
                t.add(post(windowB, nodeB, 1, i % 2 == 0 ? 1 : 2))
            }
            group.leave()
        }.start()
    }
    var drainErr: Int32 = 0
    while true {
        let n = drainOnce(8)
        if n < 0 { drainErr = n; break }
        if n == 0 {
            if group.wait(timeout: .now()) == .success { break }
            _ = r.waitWake(1)
        } else {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
    c.fact("drain never returned an error", drainErr == 0, "rc \(drainErr)")
    let s1 = statsNow()
    let L1 = ledgerCopy()
    let ok = tallies.reduce(0) { $0 + $1.ok }
    let full = tallies.reduce(0) { $0 + $1.full }
    let stale = tallies.reduce(0) { $0 + $1.stale }
    let other = tallies.reduce(0) { $0 + $1.other }
    let delivered = L1.delivered - L0.delivered
    c.fact("4 x 10000 attempts accounted", ok + full + stale + other == 40_000,
           "ok \(ok) full \(full) stale \(stale) other \(other)")
    c.fact("overflow exercised (QUEUE_FULL returned)", full > 0, "full \(full)")
    c.fact("no unexpected rejections", stale == 0 && other == 0)
    c.fact("delivered + QUEUE_FULL == posted", delivered + full == 40_000,
           "delivered \(delivered) + full \(full)")
    c.fact("delivered == enqueued (C and Swift agree)", delivered == ok && Int(s1.drained - s0.drained) == ok)
    c.fact("all delivered accepted, no duplicate seq", L1.accepted - L0.accepted == delivered && L1.dupSeq - L0.dupSeq == 0)
    c.fact("queue reached capacity 256", s1.max_depth == 256, "max_depth \(s1.max_depth)")
    report("T3 queue-overflow", c)
    results.append(("T3 queue-overflow", c.pass))
}

// ---- T4: off-thread actions racing window close ----
do {
    let c = Check()
    let s0 = statsNow()
    let L0 = ledgerCopy()
    let tallies = (0..<4).map { _ in Tally() }
    let group = DispatchGroup()
    for t in tallies {
        group.enter()
        Thread {
            for i in 0..<10_000 {
                t.add(post(windowB, nodeB, 1, 2))
                if i % 50 == 0 { Thread.sleep(forTimeInterval: 0.001) }
            }
            group.leave()
        }.start()
    }
    // Drain on the main thread while producers run, until 4000 attempts are in.
    while statsNow().attempts - s0.attempts < 4_000 {
        let n = drainOnce(8)
        if n < 0 { c.fact("drain error", false, "rc \(n)"); break }
        if n == 0 { _ = r.waitWake(1) }
    }
    let attemptsAtClose = statsNow().attempts - s0.attempts
    let appliedBBeforeClose = (ledgerCopy().applied[windowB] ?? 0) - (L0.applied[windowB] ?? 0)
    c.expect("close window B while producers run", closeWindow(windowB), 0)
    let windowD = openWindow()
    let nodeD = r.nodeCreate(windowD)
    c.fact("open window D, create node", windowD != 0 && nodeD != 0, "gen \(windowD)")
    _ = setText(nodeD, "model-D")
    var okMain = 0
    var mainFull = 0
    for _ in 0..<1000 {
        var rc = post(windowD, nodeD, 1, 2)
        while rc == SWR_E_QUEUE_FULL {
            mainFull += 1
            _ = drainOnce(8)
            rc = post(windowD, nodeD, 1, 2)
        }
        if rc == 0 { okMain += 1 } else { c.fact("main post to D", false, errName(rc)) }
    }
    group.wait()
    c.fact("drain after producers finish", drainAll() == 0)
    let s1 = statsNow()
    let L1 = ledgerCopy()
    let ok = tallies.reduce(0) { $0 + $1.ok }
    let full = tallies.reduce(0) { $0 + $1.full }
    let stale = tallies.reduce(0) { $0 + $1.stale }
    let other = tallies.reduce(0) { $0 + $1.other }
    let appliedBAfterClose = (L1.applied[windowB] ?? 0) - (L0.applied[windowB] ?? 0)
    c.fact("producers: 40000 attempts accounted", ok + full + stale + other == 40_000,
           "ok \(ok) full \(full) stale \(stale) other \(other)")
    c.fact("close happened mid-flight", attemptsAtClose >= 4_000 && attemptsAtClose < 40_000,
           "attempts at close \(attemptsAtClose)")
    c.fact("stale rejections at post after close", stale > 0, "stale \(stale)")
    c.fact("some B events applied before close", appliedBBeforeClose > 0, "applied \(appliedBBeforeClose)")
    let staleInQueue = ok - appliedBBeforeClose
    c.fact("queued B events after close rejected by Swift", L1.rejWindow - L0.rejWindow == staleInQueue,
           "rejWindow \(L1.rejWindow - L0.rejWindow) expected \(staleInQueue)")
    c.fact("no B application after close", appliedBAfterClose == appliedBBeforeClose,
           "after-close applied \(appliedBAfterClose)")
    c.fact("delivered == enqueued (producers + main)", L1.delivered - L0.delivered == ok + okMain)
    c.fact("D model applied exactly the main posts", (L1.applied[windowD] ?? 0) == okMain,
           "applied \(L1.applied[windowD] ?? 0) main \(okMain) main-full-retries \(mainFull)")
    let (drc, dtext) = getText(nodeD)
    c.fact("D model text unchanged", drc == 0 && dtext == "model-D", "text '\(dtext)'")
    c.fact("no snapshot/node rejections", L1.rejSnapshot - L0.rejSnapshot == 0 && L1.rejNode - L0.rejNode == 0)
    c.fact("C post counters agree with producers", s1.posted_stale - s0.posted_stale == UInt64(stale)
           && s1.posted_ok - s0.posted_ok == UInt64(ok + okMain))
    c.fact("no duplicate seq", L1.dupSeq - L0.dupSeq == 0)
    report("T4 close-race", c)
    results.append(("T4 close-race", c.pass))

    // ---- T5: snapshot staleness, on window D ----
    let c5 = Check()
    let M0 = ledgerCopy()
    gLedger.pointee.snapshot = 5   // committed snapshot version 5
    var badPosts = 0
    for v in [UInt64(1), 2, 3, 4] {
        for _ in 0..<100 where post(windowD, nodeD, v, 2) != 0 { badPosts += 1 }
        _ = drainAll()
    }
    for _ in 0..<100 where post(windowD, nodeD, 5, 2) != 0 { badPosts += 1 }
    _ = drainAll()
    gLedger.pointee.snapshot = 6   // commit version 6: snapshot-5 actions are now stale
    for _ in 0..<100 where post(windowD, nodeD, 5, 2) != 0 { badPosts += 1 }
    _ = drainAll()
    let M1 = ledgerCopy()
    c5.fact("all 500 posts enqueued", badPosts == 0, "post failures \(badPosts)")
    c5.fact("older-snapshot actions rejected (400 + 100)", M1.rejSnapshot - M0.rejSnapshot == 500,
            "rejSnapshot \(M1.rejSnapshot - M0.rejSnapshot)")
    c5.fact("current-snapshot actions accepted (100)", M1.accepted - M0.accepted == 100,
            "accepted \(M1.accepted - M0.accepted)")
    c5.fact("model mutated only by accepted actions", (M1.applied[windowD] ?? 0) - (M0.applied[windowD] ?? 0) == 100)
    c5.fact("no window or node rejections", M1.rejWindow - M0.rejWindow == 0 && M1.rejNode - M0.rejNode == 0)
    report("T5 snapshot-staleness", c5)
    results.append(("T5 snapshot-staleness", c5.pass))
}

let passed = results.filter { $0.1 }.count
print("SUMMARY: \(passed)/\(results.count) PASS")
exit(passed == results.count ? 0 : 1)
#else
print("bridge-faults runs on Windows x64 only")
exit(2)
#endif
