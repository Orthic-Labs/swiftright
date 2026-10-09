import CSwiftRight
import Foundation
#if os(Windows)
import CDispatchPrivate
#endif

/// The Swift side of the renderer ABI. One `Bridge` per process (ABI v0 opens one window).
///
/// Threading (swiftright.h): `run` blocks on the calling thread, which becomes the UI
/// thread; every callback and every method below except `requestQuit` must be used on it.
/// The main dispatch queue is drained from the renderer's drain callback, with a
/// non-reentrant guard, so `MainActor` work and `Task`s run on the UI thread.
public final class Bridge {
    let api: swr_api
    public let info: swr_bootstrap_info

    public var onReady: ((BridgeWindow) -> Void)?
    public var onTick: ((BridgeWindow, UInt64) -> Void)?
    /// Called for every event that passes the window-generation check.
    public var onEvent: ((BridgeEvent) -> Void)?
    public var onWindowClosed: (() -> Void)?
    public var textStore: TextStore?

    /// Same events as `onEvent`, as an AsyncStream (iterate it on the MainActor).
    public let events: AsyncStream<BridgeEvent>
    private let continuation: AsyncStream<BridgeEvent>.Continuation

    public private(set) var window: BridgeWindow?
    public private(set) var staleEventsDropped = 0
    public private(set) var drainReentryRefused = 0
    public private(set) var drainCalls = 0
    /// Result of `swr_selftest_reentry` from inside the first drain: 1 = nested drain refused.
    public private(set) var reentrySelftest: Int32 = -99
    public private(set) var windowClosedCalls = 0
    private var draining = false

    init(api: swr_api, info: swr_bootstrap_info) {
        self.api = api
        self.info = info
        var cont: AsyncStream<BridgeEvent>.Continuation!
        self.events = AsyncStream(BridgeEvent.self, bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    // MARK: bootstrap validation (platform neutral; order as in bridge-faults)

    static func archName(_ info: swr_bootstrap_info) -> String {
        var i = info
        return withUnsafeBytes(of: &i.arch) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Validates identity BEFORE any other symbol is resolved or any callback installed.
    public static func validate(_ i: swr_bootstrap_info) throws {
        if i.abi_major != UInt32(SWR_ABI_MAJOR) || i.abi_minor != UInt32(SWR_ABI_MINOR) {
            throw BridgeError.startup("SWR_STARTUP_ERROR: abi mismatch expected \(SWR_ABI_MAJOR).\(SWR_ABI_MINOR) got \(i.abi_major).\(i.abi_minor)")
        }
        let arch = archName(i)
        if arch != "x86_64" {
            throw BridgeError.startup("SWR_STARTUP_ERROR: arch mismatch expected x86_64 got \(arch)")
        }
        let width = UInt32(MemoryLayout<UnsafeRawPointer>.size * 8)
        if i.pointer_width != width {
            throw BridgeError.startup("SWR_STARTUP_ERROR: pointer width mismatch expected \(width) got \(i.pointer_width)")
        }
        let sizes: [(String, UInt32, Int)] = [
            ("host_callbacks", i.host_callbacks_size, MemoryLayout<swr_host_callbacks>.size),
            ("api_table", i.api_table_size, MemoryLayout<swr_api>.size),
            ("transaction", i.transaction_size, MemoryLayout<swr_transaction>.size),
            ("node", i.node_size, MemoryLayout<swr_node>.size),
            ("primitive", i.primitive_size, MemoryLayout<swr_primitive>.size),
            ("semantic", i.semantic_size, MemoryLayout<swr_semantic>.size),
            ("ax_text_run", i.ax_text_run_size, MemoryLayout<swr_ax_text_run>.size),
            ("event", i.event_size, MemoryLayout<swr_event>.size),
            ("measure_request", i.measure_request_size, MemoryLayout<swr_measure_request>.size),
            ("measure_result", i.measure_result_size, MemoryLayout<swr_measure_result>.size),
            ("line_info", i.line_info_size, MemoryLayout<swr_line_info>.size),
            ("char_cell", i.char_cell_size, MemoryLayout<swr_char_cell>.size),
            ("stats", i.stats_size, MemoryLayout<swr_stats>.size),
        ]
        for (name, got, want) in sizes where Int(got) != want {
            throw BridgeError.startup("SWR_STARTUP_ERROR: \(name) table size mismatch expected \(want) got \(got)")
        }
        if i.fn_count != UInt32(SWR_API_FN_COUNT) {
            throw BridgeError.startup("SWR_STARTUP_ERROR: function count mismatch expected \(SWR_API_FN_COUNT) got \(i.fn_count)")
        }
    }

    // MARK: running

    /// Opens the window, runs the renderer loop, and blocks until the post-close pump ends
    /// (`shutdownComplete()` or the renderer's timeout, rev 0.5). `onReady` fires once
    /// (UI thread, outside all renderer borrows). `onWindowClosed` runs teardown; late
    /// main-queue work is still drained after it.
    @discardableResult
    public func run(title: String, width: UInt32, height: UInt32) throws -> Int32 {
        #if os(Windows)
        let wake = _dispatch_get_main_queue_handle_4CF()
        guard let runFn = api.run else { throw BridgeError.startup("SWR_STARTUP_ERROR: missing function run") }
        var cb = makeCallbacks()
        let arena = Arena()
        let t = arena.string(title)
        var opts = swr_run_options()
        opts.struct_size = UInt32(MemoryLayout<swr_run_options>.size)
        opts.title = t.ptr
        opts.title_len = t.len
        opts.host_wake_handle = wake
        opts.width_dip = width
        opts.height_dip = height
        let rc = withUnsafePointer(to: &opts) { o in withUnsafePointer(to: &cb) { runFn(o, $0) } }
        if rc != 0 { throw BridgeError.status(rc, "swr_run") }
        return rc
        #else
        throw BridgeError.unsupportedPlatform
        #endif
    }

    /// Thread-safe.
    public func requestQuit() {
        _ = api.request_quit?()
    }

    /// Ends the post-close pump (ABI rev 0.5). UI thread only. Valid once `onWindowClosed`
    /// has been entered (E_STATE before that); idempotent. `run` returns after this.
    public func shutdownComplete() throws {
        let rc = api.shutdown_complete?() ?? -3
        if rc != 0 { throw BridgeError.status(rc, "swr_shutdown_complete") }
    }

    func makeCallbacks() -> swr_host_callbacks {
        var cb = swr_host_callbacks()
        cb.struct_size = UInt32(MemoryLayout<swr_host_callbacks>.size)
        cb.ctx = Unmanaged.passUnretained(self).toOpaque()
        cb.loop_ready = { ctx, w in Bridge.from(ctx).loopReady(w) }
        cb.drain = { ctx in Bridge.from(ctx).drain() }
        cb.events_available = { ctx in Bridge.from(ctx).eventsAvailable() }
        cb.tick = { ctx, w, ts in Bridge.from(ctx).tick(w, ts) }
        cb.window_closed = { ctx, w in Bridge.from(ctx).windowClosed(w) }
        cb.ime_get_selection = { ctx, _, node, out in
            guard let ts = Bridge.from(ctx).textStore, let out, let s = ts.selection(node: node) else { return -12 }
            out.pointee = swr_utf16_selection(range: swr_utf16_range(start: s.range.start, end: s.range.end),
                                              reversed: s.reversed ? 1 : 0, reserved: 0)
            return 0
        }
        cb.ime_get_marked = { ctx, _, node, out, has in
            guard let ts = Bridge.from(ctx).textStore, let out, let has else { return -12 }
            if let m = ts.markedRange(node: node) {
                out.pointee = swr_utf16_range(start: m.start, end: m.end)
                has.pointee = 1
            } else {
                has.pointee = 0
            }
            return 0
        }
        cb.ime_copy_text = { ctx, _, node, range, buf, cap, len, adjusted in
            guard let ts = Bridge.from(ctx).textStore, let buf, let len, let adjusted,
                  let r = ts.text(node: node, range: UTF16Span(start: range.start, end: range.end))
            else { return -12 }
            let n = min(r.units.count, Int(cap))
            for i in 0..<n { buf[i] = r.units[i] }
            len.pointee = UInt32(n)
            adjusted.pointee = swr_utf16_range(start: r.adjusted.start, end: r.adjusted.end)
            return 0
        }
        cb.ime_replace = { ctx, _, node, range, text, len in
            guard let ts = Bridge.from(ctx).textStore else { return -12 }
            let units = text.map { Array(UnsafeBufferPointer(start: $0, count: Int(len))) } ?? []
            let r = range.map { UTF16Span(start: $0.pointee.start, end: $0.pointee.end) }
            return ts.replace(node: node, range: r, text: units) ? 0 : -1
        }
        cb.ime_replace_and_mark = { ctx, _, node, range, text, len, newSel in
            guard let ts = Bridge.from(ctx).textStore else { return -12 }
            let units = text.map { Array(UnsafeBufferPointer(start: $0, count: Int(len))) } ?? []
            let r = range.map { UTF16Span(start: $0.pointee.start, end: $0.pointee.end) }
            let s = newSel.map { UTF16Span(start: $0.pointee.start, end: $0.pointee.end) }
            return ts.replaceAndMark(node: node, range: r, text: units, newSelection: s) ? 0 : -1
        }
        cb.ime_unmark = { ctx, _, node in
            guard let ts = Bridge.from(ctx).textStore else { return -12 }
            return ts.unmark(node: node) ? 0 : -1
        }
        cb.ime_caret_bounds = { ctx, _, node, range, out in
            guard let ts = Bridge.from(ctx).textStore, let out,
                  let r = ts.caretBounds(node: node, range: UTF16Span(start: range.start, end: range.end))
            else { return -12 }
            out.pointee = cRect(r)
            return 0
        }
        return cb
    }

    private static func from(_ ctx: UnsafeMutableRawPointer?) -> Bridge {
        Unmanaged<Bridge>.fromOpaque(ctx!).takeUnretainedValue()
    }

    // MARK: callbacks (UI thread)

    private func loopReady(_ w: UInt64) {
        let win = BridgeWindow(bridge: self, handle: w)
        window = win
        onReady?(win)
    }

    /// Drains the main dispatch queue. Non-reentrant: a nested call is refused and counted.
    private func drain() {
        drainCalls += 1
        if draining {
            drainReentryRefused += 1
            return
        }
        draining = true
        defer { draining = false }
        if reentrySelftest == -99 { reentrySelftest = api.selftest_reentry?() ?? -98 }
        #if os(Windows)
        _dispatch_main_queue_callback_4CF(nil)
        #endif
    }

    private func eventsAvailable() {
        guard let pop = api.event_pop else { return }
        var raw = swr_event()
        while true {
            let rc = pop(&raw)
            if rc != 0 { break }
            // Swift-side generation check: events for any window but the live one are dropped.
            if raw.window != 0, raw.window != window?.handle {
                staleEventsDropped += 1
                continue
            }
            let ev = decodeEvent(raw)
            onEvent?(ev)
            continuation.yield(ev)
        }
    }

    private func tick(_ w: UInt64, _ ts: UInt64) {
        guard let win = window, win.handle == w else { return }
        onTick?(win, ts)
    }

    private func windowClosed(_ w: UInt64) {
        windowClosedCalls += 1
        onWindowClosed?()
        window = nil
        continuation.finish()
    }

    // MARK: measurement and runs (UI thread)

    /// Synchronous measurement. Returns a RETAINED run handle: call `release(_:)` when done.
    public func measure(_ r: MeasureRequest) throws -> TextMeasurement {
        guard let fn = api.measure_text else { throw BridgeError.status(-3, "measure_text") }
        var cap = 64
        while true {
            let arena = Arena()
            var req = swr_measure_request()
            req.struct_size = UInt32(MemoryLayout<swr_measure_request>.size)
            let t = arena.string(r.text); req.text = t.ptr; req.text_len = t.len
            let f = arena.string(r.fontFamily); req.font_family = f.ptr; req.font_family_len = f.len
            let l = arena.string(r.locale); req.locale = l.ptr; req.locale_len = l.len
            req.font_weight = r.weight
            req.direction = 0
            req.color = r.color
            req.font_size = r.fontSize
            req.line_height = r.lineHeight
            req.scale = r.scale
            req.max_width = r.maxWidth
            let lines = arena.alloc(swr_line_info.self, count: cap)
            lines.initialize(repeating: swr_line_info(), count: cap)
            req.lines_out = lines
            req.lines_cap = UInt32(cap)
            var res = swr_measure_result()
            let rc = withUnsafePointer(to: &req) { rq in withUnsafeMutablePointer(to: &res) { fn(rq, $0) } }
            if rc != 0 { throw BridgeError.status(rc, "swr_measure_text") }
            if Int(res.line_count) > cap {      // more lines than the buffer: retry once, bigger
                _ = api.text_run_release?(res.run)
                cap = Int(res.line_count)
                continue
            }
            let out = (0..<Int(res.lines_written)).map { i -> LineInfo in
                let c = lines[i]
                return LineInfo(utf8Start: c.utf8_start, utf8Len: c.utf8_len, width: c.width, top: c.top, baseline: c.baseline)
            }
            return TextMeasurement(run: TextRunHandle(raw: res.run), width: res.width, height: res.height,
                               firstBaseline: res.first_baseline, lastBaseline: res.last_baseline,
                               lines: out, charCount: res.char_count, cacheHit: res.cache_hit != 0,
                               cacheKey: res.cache_key)
        }
    }

    /// Per-character geometry of a retained run.
    public func cells(of run: TextRunHandle) throws -> [CharCell] {
        guard let fn = api.text_run_cells else { throw BridgeError.status(-3, "text_run_cells") }
        var count: UInt32 = 0
        var rc = fn(run.raw, nil, 0, &count)
        if rc != 0 { throw BridgeError.status(rc, "swr_text_run_cells") }
        if count == 0 { return [] }
        let buf = UnsafeMutablePointer<swr_char_cell>.allocate(capacity: Int(count))
        defer { buf.deallocate() }
        buf.initialize(repeating: swr_char_cell(), count: Int(count))
        rc = fn(run.raw, buf, count, &count)
        if rc != 0 { throw BridgeError.status(rc, "swr_text_run_cells") }
        return (0..<Int(count)).map { i in
            let c = buf[i]
            return CharCell(utf8Offset: c.utf8_offset, utf8Len: c.utf8_len, line: c.line,
                            wordStart: c.flags & 1 != 0, x0: c.x0, x1: c.x1)
        }
    }

    /// Explicit release of a retained run (owner frees). Returns false for a stale handle.
    @discardableResult
    public func release(_ run: TextRunHandle) -> Bool {
        (api.text_run_release?(run.raw) ?? -3) == 0
    }

    public func stats() -> swr_stats {
        var s = swr_stats()
        _ = api.get_stats?(&s)
        return s
    }
}

/// The (single, in v0) renderer window. Handle is generation-tagged: after the window
/// closes every call fails with a stale-handle status.
public final class BridgeWindow {
    public let handle: UInt64
    unowned let bridge: Bridge

    init(bridge: Bridge, handle: UInt64) {
        self.bridge = bridge
        self.handle = handle
    }

    /// Fault-injection helper: a window object for an arbitrary (stale/forged) handle.
    public static func makeForTesting(bridge: Bridge, handle: UInt64) -> BridgeWindow {
        BridgeWindow(bridge: bridge, handle: handle)
    }

    /// One versioned transaction. All-or-nothing; presented after the current callback unwinds.
    public func commit(_ t: Transaction) throws {
        guard let fn = bridge.api.commit else { throw BridgeError.status(-3, "commit") }
        let arena = Arena()
        var tx = cTransaction(t, window: handle, arena: arena)
        let rc = withUnsafePointer(to: &tx) { fn($0) }
        if rc != 0 { throw BridgeError.status(rc, "swr_commit v\(t.version)") }
    }

    public func metrics() throws -> (width: UInt32, height: UInt32, scale: Float, active: Bool) {
        var m = swr_window_metrics()
        let rc = bridge.api.window_get_metrics?(handle, &m) ?? -3
        if rc != 0 { throw BridgeError.status(rc, "swr_window_get_metrics") }
        return (m.width_px, m.height_px, m.scale, m.active != 0)
    }

    /// Display ticks while on (delivered to `Bridge.onTick`).
    public func requestTicks(_ on: Bool) throws {
        let rc = bridge.api.request_ticks?(handle, on ? 1 : 0) ?? -3
        if rc != 0 { throw BridgeError.status(rc, "swr_request_ticks") }
    }

    public func requestClose() throws {
        let rc = bridge.api.window_request_close?(handle) ?? -3
        if rc != 0 { throw BridgeError.status(rc, "swr_window_request_close") }
    }

    public enum ModalButtons: UInt32 { case ok = 1, okCancel = 2, yesNo = 3 }

    /// Opens a message box AFTER the current drain unwinds; the answer arrives as a
    /// `.modalResult` event with `arg == requestID` and `i0` = button code.
    public func requestModal(requestID: UInt64, title: String, message: String, buttons: ModalButtons) throws {
        let arena = Arena()
        var m = swr_modal_request()
        m.struct_size = UInt32(MemoryLayout<swr_modal_request>.size)
        m.kind = 1
        m.request_id = requestID
        let t = arena.string(title); m.title = t.ptr; m.title_len = t.len
        let b = arena.string(message); m.message = b.ptr; m.message_len = b.len
        m.buttons = buttons.rawValue
        let rc = withUnsafePointer(to: &m) { bridge.api.request_modal?(handle, $0) ?? -3 }
        if rc != 0 { throw BridgeError.status(rc, "swr_request_modal") }
    }
}
