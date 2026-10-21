import CSwiftRight
import Foundation
#if os(Windows)
import CDispatchPrivate
import WinSDK
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
    /// The ABI view this bridge negotiated with the renderer (0.6, or 0.7 when the renderer exports it).
    public let revision: BridgeRevision
    /// ABI 0.7 font entries; nil on a 0.6 renderer.
    let fonts: FontEntryPoints?
    /// ABI 0.8 text-extension entries; nil on a 0.6 or 0.7 renderer.
    let textExtension: TextExtensionEntryPoints?

    public var onReady: ((BridgeWindow) -> Void)?
    public var onTick: ((BridgeWindow, UInt64) -> Void)?
    /// Called for every event that passes the window-generation check.
    public var onEvent: ((BridgeEvent) -> Void)?
    public var onWindowClosed: (() -> Void)?
    public var textStore: TextStore?
    /// Folder name under %LOCALAPPDATA% for the out-of-package repair guard (W08 Tier 2); defaults to the window title.
    public var repairGuardName: String?

    /// Same events as `onEvent`, as an AsyncStream (iterate it on the MainActor). The stream is made on first access and buffers
    /// from then on: a host that only uses `onEvent` never reads it, and an unbounded buffer nobody reads grows with every event
    /// of the run (R10 memory diagnosis), so nothing is buffered until the stream is asked for.
    public var events: AsyncStream<BridgeEvent> {
        if let stream = eventStream { return stream }
        var cont: AsyncStream<BridgeEvent>.Continuation!
        let stream = AsyncStream(BridgeEvent.self, bufferingPolicy: .unbounded) { cont = $0 }
        eventStream = stream
        eventContinuation = cont
        if windowClosedCalls > 0 { cont.finish() }
        return stream
    }
    private var eventStream: AsyncStream<BridgeEvent>?
    private var eventContinuation: AsyncStream<BridgeEvent>.Continuation?
    /// Events delivered to `onEvent` so far (diagnostics).
    public private(set) var eventsDelivered = 0

    public private(set) var window: BridgeWindow?
    public private(set) var staleEventsDropped = 0
    public private(set) var drainReentryRefused = 0
    public private(set) var drainCalls = 0
    /// Result of `swr_selftest_reentry` from inside the first drain: 1 = nested drain refused.
    public private(set) var reentrySelftest: Int32 = -99
    public private(set) var windowClosedCalls = 0
    private var draining = false

    init(api: swr_api, info: swr_bootstrap_info, revision: BridgeRevision = .v06, fonts: FontEntryPoints? = nil,
         textExtension: TextExtensionEntryPoints? = nil) {
        self.api = api
        self.info = info
        self.revision = revision
        self.fonts = fonts
        self.textExtension = textExtension
    }

    /// Rev 0.9 (decision H1): the renderer honours `SemanticNode.range` (slider RangeValue). False on a 0.6 to 0.8 renderer.
    public var supportsSliderRange: Bool { revision >= .v09 }
    /// Rev 0.9 (decision H3): the renderer emits SWR_PTR_MOVE to a host that asks (`run(pointerMoves: true)`).
    public var supportsPointerMoves: Bool { revision >= .v09 }
    /// Rev 0.10 (decision H17): the renderer accepts an explicit render scale in `run(renderScale:)`. False on a 0.6 to 0.9 renderer.
    public var supportsRenderScale: Bool { revision >= .v10 }
    /// Rev 0.11 (issue #31): the renderer emits SWR_PTR_WHEEL to a host that asks (`run(pointerWheel: true)`), and accepts a
    /// `.scrollBar` node with a range. False on a 0.6 to 0.10 renderer: a scroll bar node is then published without a range.
    public var supportsPointerWheel: Bool { revision >= .v11 }
    public var supportsScrollBar: Bool { revision >= .v11 }
    /// Rev 0.12 (issue #52): the renderer paints `Primitive.path` (SWR_PRIM_PATH) and path clips. False on a 0.6 to 0.11 renderer: a host
    /// then draws shapes as bitmaps and clips by rectangle bands.
    public var supportsPaths: Bool { revision >= .v12 }
    /// The explicit render scale `run` was given, nil when the window's DPI decides. Set by `run` before the window opens.
    public internal(set) var renderScale: Float?

    // MARK: bootstrap validation (platform neutral; order as in bridge-faults)

    static func archName(_ info: swr_bootstrap_info) -> String {
        var i = info
        return withUnsafeBytes(of: &i.arch) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Validates identity BEFORE any other symbol is resolved or any callback installed.
    public static func validate(_ i: swr_bootstrap_info) throws {
        try validateIdentity(i, minor: UInt32(SWR_ABI_MINOR), apiTableSize: MemoryLayout<swr_api>.size, fnCount: UInt32(SWR_API_FN_COUNT))
    }

    /// Shared identity check: major/minor, arch, pointer width, every struct size and the function count
    /// against what this bridge was built with. `apiTableSize` / `fnCount` differ between the 0.6 and 0.7 views.
    static func validateIdentity(_ i: swr_bootstrap_info, minor: UInt32, apiTableSize: Int, fnCount: UInt32) throws {
        if i.abi_major != UInt32(SWR_ABI_MAJOR) || i.abi_minor != minor {
            throw BridgeError.startup("SWR_STARTUP_ERROR: abi mismatch expected \(SWR_ABI_MAJOR).\(minor) got \(i.abi_major).\(i.abi_minor)")
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
            ("api_table", i.api_table_size, apiTableSize),
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
        if i.fn_count != fnCount {
            throw BridgeError.startup("SWR_STARTUP_ERROR: function count mismatch expected \(fnCount) got \(i.fn_count)")
        }
    }

    // MARK: running

    /// Opens the window, runs the renderer loop, and blocks until the post-close pump ends
    /// (`shutdownComplete()` or the renderer's timeout, rev 0.5). `onReady` fires once
    /// (UI thread, outside all renderer borrows). `onWindowClosed` runs teardown; late
    /// main-queue work is still drained after it.
    @discardableResult
    /// `pointerMoves`: ask for SWR_PTR_MOVE events (hover and drag; rev 0.9, decision H3). Ignored, never guessed, on a renderer below 0.9:
    /// check `supportsPointerMoves`.
    ///
    /// `renderScale` (rev 0.10, decision H17): an explicit render scale S (a device scale factor, like a forced device scale
    /// factor in a browser: 2.5 is 240 dpi), used instead of the window's DPI. The window's client area is `width * S` by
    /// `height * S` physical px, `BridgeWindow.metrics().scale` reports S, and `measure` uses S whatever scale the request names. nil (the
    /// default) keeps the window's DPI, byte-for-byte as before. A value outside [0.25, 16] or not finite, or a renderer below
    /// 0.10 (check `supportsRenderScale`), throws: a requested scale is never silently dropped. If the window moves to a display
    /// with another DPI the scale stays S (see swiftright.h, REVISION 0.10).
    ///
    /// `pointerWheel` (rev 0.11, issue #31): ask for SWR_PTR_WHEEL events (`BridgeEvent.wheel`). Like `pointerMoves`, ignored on a
    /// renderer below 0.11 (check `supportsPointerWheel`); a host that does not ask never receives a wheel event, and the renderer
    /// then leaves WM_MOUSEWHEEL to the window as before.
    public func run(title: String, width: UInt32, height: UInt32, pointerMoves: Bool = false, renderScale: Float? = nil,
                    pointerWheel: Bool = false) throws -> Int32 {
        let wireScale = try Bridge.runOptionsScale(requested: renderScale, rendererSupports: supportsRenderScale, revision: revision)
        self.renderScale = renderScale
        #if os(Windows)
        RepairGuard.installIfNeeded(appName: repairGuardName ?? title)
        let wake = _dispatch_get_main_queue_handle_4CF()
        guard let runFn = api.run else { throw BridgeError.startup("SWR_STARTUP_ERROR: missing function run") }
        var cb = makeCallbacks()
        let arena = Arena()
        let t = arena.string(title)
        var opts10 = Bridge.makeRunOptions(title: t.ptr, titleLen: t.len, wake: wake, width: width, height: height,
                                           pointerMoves: pointerMoves && supportsPointerMoves, renderScale: wireScale,
                                           pointerWheel: pointerWheel && supportsPointerWheel)
        let rc = withUnsafePointer(to: &opts10) { o in
            o.withMemoryRebound(to: swr_run_options.self, capacity: 1) { base in withUnsafePointer(to: &cb) { runFn(base, $0) } }
        }
        if rc != 0 { throw BridgeError.status(rc, "swr_run") }
        return rc
        #else
        throw BridgeError.unsupportedPlatform
        #endif
    }

    /// The render scale word to put on the wire for `run`. nil requested: 0 (none). Pure policy, so it is unit-tested on every host.
    static func runOptionsScale(requested: Float?, rendererSupports: Bool, revision: BridgeRevision) throws -> Float {
        guard let s = requested else { return 0 }
        guard s.isFinite, s >= 0.25, s <= 16 else {
            throw BridgeError.startup("SWR_STARTUP_ERROR: render scale \(s) is outside 0.25 to 16")
        }
        guard rendererSupports else {
            throw BridgeError.startup("SWR_STARTUP_ERROR: renderer is ABI \(revision), an explicit render scale needs 0.10")
        }
        return s
    }

    /// Builds the run options. With no render scale (`renderScale` 0) the struct_size is the 0.9 size, so the renderer sees exactly
    /// the options an older host sends; with one it is the 0.10 size and the scale word is read.
    static func makeRunOptions(title: UnsafePointer<CChar>?, titleLen: UInt32, wake: UnsafeMutableRawPointer?, width: UInt32, height: UInt32,
                               pointerMoves: Bool, renderScale: Float, pointerWheel: Bool = false) -> swr_run_options_v10 {
        var v = swr_run_options_v10()
        v.base.struct_size = UInt32(renderScale == 0 ? MemoryLayout<swr_run_options>.size : MemoryLayout<swr_run_options_v10>.size)
        v.base.title = title
        v.base.title_len = titleLen
        v.base.host_wake_handle = wake
        v.base.width_dip = width
        v.base.height_dip = height
        v.base.flags = (pointerMoves ? UInt32(SWR_RUN_POINTER_MOVES) : 0) | (pointerWheel ? UInt32(SWR_RUN_POINTER_WHEEL) : 0)
        v.render_scale = renderScale
        return v
    }

    /// Windows lines per wheel notch (SPI_GETWHEELSCROLLLINES), 3 when the query fails or off Windows. 0 = the user turned wheel
    /// scrolling off. `wheelScrollsPages` is true when the setting is WHEEL_PAGESCROLL (one page per notch); `wheelScrollLines` is then 3.
    public static var wheelScrollLines: Int { wheelScrollSetting().lines }
    public static var wheelScrollsPages: Bool { wheelScrollSetting().page }

    /// Pure mapping of the raw SPI value (so it is unit-tested on every host): 0xFFFFFFFF (WHEEL_PAGESCROLL) is a page, anything
    /// above a sane bound is the default, else the value.
    static func wheelScrollSetting(raw: UInt32?) -> (lines: Int, page: Bool) {
        guard let raw else { return (3, false) }
        if raw == UInt32.max { return (3, true) }
        if raw > 1000 { return (3, false) }
        return (Int(raw), false)
    }

    static func wheelScrollSetting() -> (lines: Int, page: Bool) {
        #if os(Windows)
        var v: UInt32 = 3
        let ok: Bool = SystemParametersInfoW(0x0068, 0, &v, 0) == true // SPI_GETWHEELSCROLLLINES (BOOL imports as Bool/WindowsBool)
        return wheelScrollSetting(raw: ok ? v : nil)
        #else
        return wheelScrollSetting(raw: nil)
        #endif
    }

    /// The scale a measurement uses: the render scale when one is set (one scale source), else the request's own.
    static func measureScale(requested: Float, renderScale: Float?) -> Float { renderScale ?? requested }

    /// Drains the main dispatch queue once, from the calling (main) thread, for a host that has no renderer loop (the headless
    /// benchmark and soak, which run `MainActor` work and `Task`s without a window). Not for use from inside a renderer callback
    /// (the drain callback does this itself, with a re-entry guard). Windows only; elsewhere the run loop does it.
    public static func drainMainQueueHeadless() {
        #if os(Windows)
        _dispatch_main_queue_callback_4CF(nil)
        #else
        RunLoop.main.run(mode: .default, before: Date())
        #endif
    }

    /// Builds the C transaction `BridgeWindow.commit` would send, then frees it, without calling the renderer: the host-side
    /// allocation pattern of one commit, for a benchmark or soak that has no window. Returns the node count marshalled.
    @discardableResult
    public static func marshalOnly(_ t: Transaction) -> Int {
        let arena = Arena()
        let tx = cTransaction(t, window: 1, arena: arena)
        return Int(tx.upsert_count) + Int(tx.primitive_count)
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
            // The window-metrics payload is authoritative: latch it before the host sees the event, so BridgeWindow.metrics()
            // already equals it inside `onEvent`.
            if ev.kind == .windowMetrics { window?.metricsLatch.apply(ev) }
            eventsDelivered += 1
            onEvent?(ev)
            eventContinuation?.yield(ev)
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
        eventContinuation?.finish()
    }

    // MARK: measurement and runs (UI thread)

    /// Synchronous measurement. Returns a RETAINED run handle: call `release(_:)` when done.
    public func measure(_ request: MeasureRequest) throws -> TextMeasurement {
        var r = request
        r.scale = Bridge.measureScale(requested: request.scale, renderScale: renderScale)
        if let ext = r.extension ?? (r.maxLines != nil ? TextExtension() : nil) {
            guard let te = textExtension else {
                throw BridgeError.status(-15, "swr_measure_text_v08 (renderer ABI \(revision) has no text extension; send the request without `extension` to measure the 0.6 way)")
            }
            return try measureV08(r, ext: ext, entry: te)
        }
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
            return measurement(from: res, lines: lines, report: nil)
        }
    }

    private func measureV08(_ r: MeasureRequest, ext: TextExtension, entry: TextExtensionEntryPoints) throws -> TextMeasurement {
        var cap = 64
        while true {
            let arena = Arena()
            let lines = arena.alloc(swr_line_info.self, count: cap)
            lines.initialize(repeating: swr_line_info(), count: cap)
            var res = swr_measure_result_v08()
            res.struct_size = UInt32(MemoryLayout<swr_measure_result_v08>.size)
            let rc = try withV08Request(r, ext: ext, lines: lines, cap: cap, arena: arena) { rq in
                withUnsafeMutablePointer(to: &res) { entry.measure(rq, $0) }
            }
            if rc != 0 { throw BridgeError.status(rc, "swr_measure_text_v08") }
            if Int(res.base.line_count) > cap {
                _ = api.text_run_release?(res.base.run)
                cap = Int(res.base.line_count)
                continue
            }
            return measurement(from: res.base, lines: lines, report: TextExtensionReport(res))
        }
    }

    private func measurement(from res: swr_measure_result, lines: UnsafeMutablePointer<swr_line_info>, report: TextExtensionReport?) -> TextMeasurement {
        let out = (0..<Int(res.lines_written)).map { i -> LineInfo in
            let c = lines[i]
            return LineInfo(utf8Start: c.utf8_start, utf8Len: c.utf8_len, width: c.width, top: c.top, baseline: c.baseline)
        }
        var m = TextMeasurement(run: TextRunHandle(raw: res.run), width: res.width, height: res.height,
                                firstBaseline: res.first_baseline, lastBaseline: res.last_baseline,
                                lines: out, charCount: res.char_count, cacheHit: res.cache_hit != 0,
                                cacheKey: res.cache_key)
        m.extensionReport = report
        return m
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
                            wordStart: c.flags & 0x1 != 0, lineBreak: c.flags & 0x2 != 0, x0: c.x0, x1: c.x1)
        }
    }

    /// Explicit release of a retained run (owner frees). Returns false for a stale handle.
    @discardableResult
    public func release(_ run: TextRunHandle) -> Bool {
        (api.text_run_release?(run.raw) ?? -3) == 0
    }

    /// ABI rev 0.6. Copies `width * height` RGBA8 pixels (straight alpha, byte order R,G,B,A;
    /// `stride` bytes per row, 0 = tightly packed) into a retained image. Release it with
    /// `release(_:)`. UI thread only.
    public func registerImage(width: UInt32, height: UInt32, rgba: [UInt8], stride: UInt32 = 0) throws -> ImageHandle {
        guard let fn = api.image_register else { throw BridgeError.status(-3, "image_register") }
        let rowBytes = stride == 0 ? Int(width) * 4 : Int(stride)
        // The renderer reads (height - 1) * rowBytes + width * 4 bytes; refuse a short buffer here.
        let need = height == 0 ? 0 : (Int(height) - 1) * rowBytes + Int(width) * 4
        if rgba.count < need { throw BridgeError.status(-1, "swr_image_register (buffer shorter than \(need) bytes)") }
        var out: swr_image = 0
        let rc = rgba.withUnsafeBufferPointer { fn($0.baseAddress, width, height, stride, &out) }
        if rc != 0 { throw BridgeError.status(rc, "swr_image_register") }
        return ImageHandle(raw: out)
    }

    /// Explicit release of a retained image (owner frees). Returns false for a stale handle.
    @discardableResult
    public func release(_ image: ImageHandle) -> Bool {
        (api.image_release?(image.raw) ?? -3) == 0
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
    /// Last delivered window-metrics event (authoritative over the renderer getter). Per window, so a new window starts empty.
    var metricsLatch = MetricsLatch()
    /// The version of the last transaction sent (a split transaction uses several, so the host's next version may already be taken).
    var lastVersion: UInt64 = 0

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
        // The renderer accepts at most 4096 upserts, 4096 removes and 65536 primitives per transaction (`render/swiftright-render/src/abi.rs` MAX_UPSERTS, MAX_REMOVES,
        // MAX_PRIMITIVES: more is SWR_E_TOO_LARGE). A page whose tree is larger (the hub's Monitor and General sections: 4700+ nodes) is sent as consecutive transactions: the removes
        // first, then the upserts in tree order (a parent is always upserted before its children, so every prefix is a consistent tree), the focus on the last one. They are
        // presented together, after the current callback unwinds. A transaction within the limits is sent as it is.
        for chunk in Self.split(t, lastVersion: lastVersion) { try send(chunk) }
    }

    /// The renderer's per-transaction limits.
    static let maxUpserts = 4096, maxRemoves = 4096, maxPrimitives = 65536

    /// `t` as the transactions the renderer accepts, versions strictly increasing from `max(t.version, lastVersion + 1)`. Pure (testable without a renderer).
    static func split(_ t: Transaction, lastVersion: UInt64) -> [Transaction] {
        var version = max(t.version, lastVersion &+ 1)
        let primitiveCount = t.upserts.reduce(0) { $0 + $1.primitives.count }
        if t.upserts.count <= maxUpserts, t.removes.count <= maxRemoves, primitiveCount <= maxPrimitives {
            return [Transaction(version: version, focus: t.focus, upserts: t.upserts, removes: t.removes)]
        }
        var out: [Transaction] = []
        var removes = t.removes[...]
        while !removes.isEmpty {
            let n = min(maxRemoves, removes.count)
            out.append(Transaction(version: version, removes: Array(removes.prefix(n)))); version &+= 1
            removes = removes.dropFirst(n)
        }
        var upserts: [NodeUpsert] = [], prims = 0
        for u in t.upserts {
            if !upserts.isEmpty, upserts.count >= maxUpserts || prims + u.primitives.count > maxPrimitives {
                out.append(Transaction(version: version, upserts: upserts)); version &+= 1
                upserts = []; prims = 0
            }
            upserts.append(u); prims += u.primitives.count
        }
        out.append(Transaction(version: version, focus: t.focus, upserts: upserts))
        return out
    }

    private func send(_ t: Transaction) throws {
        guard let fn = bridge.api.commit else { throw BridgeError.status(-3, "commit") }
        let arena = Arena()
        let table: PathTable? = bridge.supportsPaths ? PathTable() : nil
        var tx = cTransaction(t, window: handle, arena: arena, table: table)
        let rc: Int32
        if bridge.supportsPaths, let table {
            // Rev 0.12: the 128-byte transaction carries the range table and the path table (possibly empty).
            let ranges = cRanges(t, scrollBars: bridge.supportsScrollBar)
            var tx12 = swr_transaction_v12()
            tx12.base.base = tx
            tx12.base.base.struct_size = UInt32(MemoryLayout<swr_transaction_v12>.size)
            tx12.base.ranges = arena.array(ranges)
            tx12.base.range_count = UInt32(ranges.count)
            tx12.paths = arena.array(table.entries)
            tx12.path_count = UInt32(table.entries.count)
            tx12.path_cmds = arena.array(table.commands)
            tx12.path_cmd_total = UInt32(table.commands.count)
            tx12.path_pts = arena.array(table.points)
            tx12.path_pt_total = UInt32(table.points.count / 2)
            rc = withUnsafePointer(to: &tx12) { p in
                p.withMemoryRebound(to: swr_transaction.self, capacity: 1) { fn($0) }
            }
        } else if bridge.supportsSliderRange {
            // Rev 0.9: the 88-byte transaction carries the range table (possibly empty).
            let ranges = cRanges(t, scrollBars: bridge.supportsScrollBar)
            var tx9 = swr_transaction_v09()
            tx9.base = tx
            tx9.base.struct_size = UInt32(MemoryLayout<swr_transaction_v09>.size)
            tx9.ranges = arena.array(ranges)
            tx9.range_count = UInt32(ranges.count)
            rc = withUnsafePointer(to: &tx9) { p in
                p.withMemoryRebound(to: swr_transaction.self, capacity: 1) { fn($0) }
            }
        } else {
            rc = withUnsafePointer(to: &tx) { fn($0) }
        }
        if rc != 0 { throw BridgeError.status(rc, "swr_commit v\(t.version)") }
        lastVersion = t.version
    }

    /// Window metrics in physical px. Before any `.windowMetrics` event this is the renderer's value at ready (the settled
    /// client size). Once the bridge has delivered a `.windowMetrics` event, the event's size and scale are authoritative
    /// and this returns exactly them (`active` still comes from the renderer). Never lays out from a stale getter value.
    public func metrics() throws -> (width: UInt32, height: UInt32, scale: Float, active: Bool) {
        var m = swr_window_metrics()
        let rc = bridge.api.window_get_metrics?(handle, &m) ?? -3
        if rc != 0 { throw BridgeError.status(rc, "swr_window_get_metrics") }
        return metricsLatch.resolve(getter: (m.width_px, m.height_px, m.scale, m.active != 0))
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

    /// One entry of a popup menu or one custom dialog button (ABI rev 0.6). `id` is host-chosen,
    /// non-zero and unique within the request; separators ignore `text` and `id`.
    public struct ModalItem {
        public var id: UInt32
        public var text: String
        public var disabled: Bool
        public var checked: Bool
        public var separator: Bool
        public init(id: UInt32, text: String, disabled: Bool = false, checked: Bool = false,
                    separator: Bool = false) {
            self.id = id; self.text = text; self.disabled = disabled
            self.checked = checked; self.separator = separator
        }
        public static var separatorItem: ModalItem { ModalItem(id: 0, text: "", separator: true) }
    }

    /// Opens a message box AFTER the current drain unwinds; the answer arrives as a
    /// `.modalResult` event with `arg == requestID` and `i0` = button code.
    public func requestModal(requestID: UInt64, title: String, message: String, buttons: ModalButtons) throws {
        try sendModal(kind: 1, requestID: requestID, title: title, message: message,
                      buttons: buttons.rawValue, items: [], x: 0, y: 0, defaultItem: 0)
    }

    /// ABI rev 0.6: popup menu (TrackPopupMenu) at `x`, `y` (physical px, window client coordinates;
    /// both negative = at the pointer). Opened AFTER the current drain unwinds. The answer arrives
    /// as a `.modalResult` event (`BridgeEvent.modalChoice`; nil choice = dismissed).
    public func requestMenu(requestID: UInt64, items: [ModalItem], x: Float, y: Float) throws {
        try sendModal(kind: 2, requestID: requestID, title: "", message: "", buttons: 0,
                      items: items, x: x, y: y, defaultItem: 0)
    }

    /// ABI rev 0.6: task dialog with 1...8 custom buttons (TaskDialogIndirect). `title` is the window
    /// title, `message` the content. The answer arrives as a `.modalResult` event
    /// (`BridgeEvent.modalChoice`; nil choice = closed without pressing a button).
    public func requestDialog(requestID: UInt64, title: String, message: String, buttons: [ModalItem],
                              defaultIndex: Int = 0) throws {
        try sendModal(kind: 3, requestID: requestID, title: title, message: message, buttons: 0,
                      items: buttons, x: 0, y: 0, defaultItem: UInt32(max(defaultIndex, 0)))
    }

    private func sendModal(kind: UInt32, requestID: UInt64, title: String, message: String, buttons: UInt32,
                           items: [ModalItem], x: Float, y: Float, defaultItem: UInt32) throws {
        let arena = Arena()
        var m = swr_modal_request()
        m.struct_size = UInt32(MemoryLayout<swr_modal_request>.size)
        m.kind = kind
        m.request_id = requestID
        let t = arena.string(title); m.title = t.ptr; m.title_len = t.len
        let b = arena.string(message); m.message = b.ptr; m.message_len = b.len
        m.buttons = buttons
        var cItems: [swr_modal_item] = []
        for it in items {
            var c = swr_modal_item()
            let s = arena.string(it.text)
            c.text = s.ptr; c.text_len = s.len
            c.id = it.id
            c.flags = (it.disabled ? 0x1 : 0) | (it.separator ? 0x2 : 0) | (it.checked ? 0x4 : 0)
            cItems.append(c)
        }
        m.items = arena.array(cItems)
        m.item_count = UInt32(cItems.count)
        m.x = x; m.y = y
        m.default_item = defaultItem
        let rc = withUnsafePointer(to: &m) { bridge.api.request_modal?(handle, $0) ?? -3 }
        if rc != 0 { throw BridgeError.status(rc, "swr_request_modal") }
    }
}
