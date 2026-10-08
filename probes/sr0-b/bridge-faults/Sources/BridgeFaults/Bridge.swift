import Foundation
import CSwrFakeRender
#if os(Windows)
import WinSDK
#endif

// Function types for ABI v0, resolved with GetProcAddress (explicit loading, no import-table link).
typealias BootstrapFn = @convention(c) (UnsafeMutablePointer<swr_bootstrap_info>?, UInt32) -> Int32
typealias WindowOpenFn = @convention(c) () -> UInt64
typealias WindowCloseFn = @convention(c) (UInt64) -> Int32
typealias NodeCreateFn = @convention(c) (UInt64) -> UInt64
typealias NodeOpFn = @convention(c) (UInt64) -> Int32
typealias NodeSetTextFn = @convention(c) (UInt64, UnsafePointer<CChar>?, UInt32) -> Int32
typealias NodeGetTextFn = @convention(c) (UInt64, UnsafeMutablePointer<CChar>?, UInt32, UnsafeMutablePointer<UInt32>?) -> Int32
typealias PostFn = @convention(c) (UInt64, UInt64, UInt64, UInt32) -> Int32
typealias DrainFn = @convention(c) (UnsafePointer<swr_cb_table>?, UInt32) -> Int32
typealias WaitFn = @convention(c) (UInt32) -> Int32
typealias StatsFn = @convention(c) (UnsafeMutablePointer<swr_stats>?) -> Void

struct Renderer {
    let bootstrap: BootstrapFn
    let windowOpen: WindowOpenFn
    let windowClose: WindowCloseFn
    let nodeCreate: NodeCreateFn
    let nodeRelease: NodeOpFn
    let nodeCheck: NodeOpFn
    let nodeSetText: NodeSetTextFn
    let nodeGetText: NodeGetTextFn
    let post: PostFn
    let drain: DrainFn
    let waitWake: WaitFn
    let stats: StatsFn
}

/// Swift-owned model and counters. Only the main thread touches it: the drain callback runs there.
struct Ledger {
    var liveWindow: UInt64 = 0
    var snapshot: UInt64 = 0
    var delivered = 0
    var accepted = 0
    var rejWindow = 0
    var rejSnapshot = 0
    var rejNode = 0
    var applied: [UInt64: Int] = [:]     // accepted actions per window generation (the "model")
    var seqSeen = Set<UInt64>()
    var dupSeq = 0
}

var gRenderer: Renderer!
var gLedger: UnsafeMutablePointer<Ledger>!
var gCB: UnsafeMutablePointer<swr_cb_table>!

func startupFail(_ message: String) -> Never {
    print(message)
    fflush(stdout)
    exit(78)
}

#if os(Windows)
func procAddress<T>(_ module: HMODULE, _ name: String, _ type: T.Type) -> T? {
    guard let p = GetProcAddress(module, name) else { return nil }
    return unsafeBitCast(p, to: type)
}

/// Loads the renderer and validates identity BEFORE resolving anything else.
/// Exits with code 78 and a deterministic SWR_STARTUP_ERROR line on any mismatch.
func loadRenderer(path: String) -> Renderer {
    let handle: HMODULE? = path.withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
    guard let module = handle else {
        startupFail("SWR_STARTUP_ERROR: renderer not found \(path)")
    }
    guard let boot = procAddress(module, "swr_bootstrap_query", BootstrapFn.self) else {
        startupFail("SWR_STARTUP_ERROR: missing symbol swr_bootstrap_query")
    }
    var info = swr_bootstrap_info()
    let rc = withUnsafeMutablePointer(to: &info) { boot($0, UInt32(MemoryLayout<swr_bootstrap_info>.size)) }
    if rc != 0 {
        startupFail("SWR_STARTUP_ERROR: bootstrap query rejected rc=\(rc)")
    }
    if info.abi_major != 0 || info.abi_minor != 1 {
        startupFail("SWR_STARTUP_ERROR: abi mismatch expected 0.1 got \(info.abi_major).\(info.abi_minor)")
    }
    let arch = withUnsafeBytes(of: info.arch) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    if arch != "x86_64" {
        startupFail("SWR_STARTUP_ERROR: arch mismatch expected x86_64 got \(arch)")
    }
    let hostPointerWidth = UInt32(MemoryLayout<UnsafeRawPointer>.size * 8)
    if info.pointer_width != hostPointerWidth {
        startupFail("SWR_STARTUP_ERROR: pointer width mismatch expected \(hostPointerWidth) got \(info.pointer_width)")
    }
    let hostTable = UInt32(MemoryLayout<swr_cb_table>.size)
    if info.cb_table_size != hostTable {
        startupFail("SWR_STARTUP_ERROR: callback table size mismatch expected \(hostTable) got \(info.cb_table_size)")
    }
    func need<T>(_ name: String, _ type: T.Type) -> T {
        guard let f = procAddress(module, name, type) else {
            startupFail("SWR_STARTUP_ERROR: missing symbol \(name)")
        }
        return f
    }
    return Renderer(
        bootstrap: boot,
        windowOpen: need("swr_window_open", WindowOpenFn.self),
        windowClose: need("swr_window_close", WindowCloseFn.self),
        nodeCreate: need("swr_node_create", NodeCreateFn.self),
        nodeRelease: need("swr_node_release", NodeOpFn.self),
        nodeCheck: need("swr_node_check", NodeOpFn.self),
        nodeSetText: need("swr_node_set_text", NodeSetTextFn.self),
        nodeGetText: need("swr_node_get_text", NodeGetTextFn.self),
        post: need("swr_post_ax_action", PostFn.self),
        drain: need("swr_drain_events", DrainFn.self),
        waitWake: need("swr_wait_wake", WaitFn.self),
        stats: need("swr_get_stats", StatsFn.self)
    )
}
#endif

/// Drain callback: a plain C function (no captures). Validates generation, snapshot and node, then applies.
func onAxAction(ctx: UnsafeMutableRawPointer?, ev evp: UnsafePointer<swr_event>?) {
    guard let ctx, let evp else { return }
    let L = ctx.assumingMemoryBound(to: Ledger.self)
    let ev = evp.pointee
    L.pointee.delivered += 1
    if ev.window_gen == 0 || ev.window_gen != L.pointee.liveWindow {
        L.pointee.rejWindow += 1
        return
    }
    if ev.snapshot_version < L.pointee.snapshot {
        L.pointee.rejSnapshot += 1
        return
    }
    if gRenderer.nodeCheck(ev.node_handle) != 0 {
        L.pointee.rejNode += 1
        return
    }
    L.pointee.accepted += 1
    L.pointee.applied[ev.window_gen, default: 0] += 1
    if !L.pointee.seqSeen.insert(ev.seq).inserted {
        L.pointee.dupSeq += 1
    }
}

func errName(_ c: Int32) -> String {
    switch c {
    case 0: return "SWR_OK"
    case SWR_E_BAD_ARG: return "SWR_E_BAD_ARG"
    case SWR_E_STALE_HANDLE: return "SWR_E_STALE_HANDLE"
    case SWR_E_QUEUE_FULL: return "SWR_E_QUEUE_FULL"
    case SWR_E_TOO_LARGE: return "SWR_E_TOO_LARGE"
    case SWR_E_NO_SLOT: return "SWR_E_NO_SLOT"
    case SWR_E_TIMEOUT: return "SWR_E_TIMEOUT"
    case SWR_E_BUSY: return "SWR_E_BUSY"
    default: return "rc\(c)"
    }
}

func openWindow() -> UInt64 {
    let g = gRenderer.windowOpen()
    gLedger.pointee.liveWindow = g
    return g
}

func closeWindow(_ g: UInt64) -> Int32 {
    let rc = gRenderer.windowClose(g)
    if rc == 0 { gLedger.pointee.liveWindow = 0 }
    return rc
}

func post(_ win: UInt64, _ node: UInt64, _ snap: UInt64, _ action: UInt32) -> Int32 {
    gRenderer.post(win, node, snap, action)
}

func setText(_ h: UInt64, _ s: String) -> Int32 {
    s.withCString { gRenderer.nodeSetText(h, $0, UInt32(s.utf8.count)) }
}

func getText(_ h: UInt64) -> (Int32, String) {
    var buf = [CChar](repeating: 0, count: 256)
    var len: UInt32 = 0
    let rc = buf.withUnsafeMutableBufferPointer { gRenderer.nodeGetText(h, $0.baseAddress, UInt32($0.count), &len) }
    return (rc, rc == 0 ? String(cString: buf) : "")
}

func drainOnce(_ max: UInt32) -> Int32 {
    gRenderer.drain(UnsafePointer(gCB!), max)
}

func drainAll() -> Int32 {
    while true {
        let n = drainOnce(64)
        if n <= 0 { return n }
    }
}

func statsNow() -> swr_stats {
    var s = swr_stats()
    withUnsafeMutablePointer(to: &s) { gRenderer.stats($0) }
    return s
}

func ledgerCopy() -> Ledger { gLedger.pointee }

final class Tally {
    var ok = 0, full = 0, stale = 0, other = 0
    func add(_ rc: Int32) {
        switch rc {
        case 0: ok += 1
        case SWR_E_QUEUE_FULL: full += 1
        case SWR_E_STALE_HANDLE: stale += 1
        default: other += 1
        }
    }
}

final class Check {
    var lines: [String] = []
    var pass = true
    func expect(_ label: String, _ got: Int32, _ want: Int32) {
        let mark = got == want ? "" : "  <-- expected \(errName(want))"
        lines.append("  \(label) = \(errName(got))\(mark)")
        if got != want { pass = false }
    }
    func fact(_ label: String, _ cond: Bool, _ detail: String = "") {
        lines.append("  \(label): \(cond ? "yes" : "NO")\(detail.isEmpty ? "" : " [\(detail)]")")
        if !cond { pass = false }
    }
}

func report(_ name: String, _ c: Check) {
    print("TEST \(name): \(c.pass ? "PASS" : "FAIL")")
    for l in c.lines { print(l) }
}
