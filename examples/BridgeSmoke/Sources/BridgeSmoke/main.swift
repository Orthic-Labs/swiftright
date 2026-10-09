import Foundation
import SwiftRightBridge

// BridgeSmoke: end-to-end ABI v0 check. Opens a window, commits a hand-authored tree
// (label, wrapped paragraph, button, editable text node, status), measures and wraps text
// at two widths, handles an AX Invoke and a typed character (driven from outside by
// scripts/drive-smoke.ps1: UIA Invoke + virtual-key input), then quits and prints a
// PASS/FAIL summary. Exit code 0 = PASS, 1 = FAIL, 78 = startup diagnostic.

let env = ProcessInfo.processInfo.environment
let expectEdgeClick = env["SWR_SMOKE_EXPECT_EDGE_CLICK"] == "1"
let timeoutSeconds = Double(env["SWR_SMOKE_TIMEOUT"] ?? "") ?? 45

let paragraph = "The quick brown fox jumps over the lazy dog while SwiftRight wraps this text."

struct CheckResult { let name: String; let ok: Bool; let detail: String }

func utf16Offset(toScalarIndex units: [UInt16], _ off: Int) -> Int {
    let s = String(decoding: units, as: UTF16.self)
    var u16 = 0, n = 0
    for sc in s.unicodeScalars {
        if u16 >= off { break }
        u16 += sc.value > 0xFFFF ? 2 : 1
        n += 1
    }
    return n
}

final class Smoke: TextStore {
    let bridge: Bridge
    var scale: Float = 1
    var version: UInt64 = 0
    var started = Date()
    var checks: [CheckResult] = []

    // model
    var units: [UInt16] = []
    var sel = UTF16Span(start: 0, end: 0)
    var marked: UTF16Span?
    var axInvokes = 0
    var typed = ""
    var imeReplaceCalls = 0
    var keyEvents = 0
    var pointerEvents = 0
    var edgeClickSeen = false
    var staleEvents = 0
    var unknownNodeEvents = 0
    var firstAXWindow: UInt64 = 0
    var metricsEvents = 0

    // measurement evidence
    var wrapWide: TextMeasurement?
    var wrapNarrow: TextMeasurement?
    var cacheHitOnRepeat = false
    var heightConsistent = false
    var wrapCoversText = false

    // frame evidence
    var ticks = 0
    var ticksInactive = 0
    var doneAtTick: Int?
    var finishing = false
    var lastTickNs: UInt64 = 0
    var maxTickGapMs = 0.0

    // geometry of the edit node from the last render (for caret bounds)
    var editCells: [CharCell] = []
    var editLines: [LineInfo] = []
    var editOrigin: (x: Float, y: Float) = (0, 0)
    var lineHeightPx: Float = 24

    init(bridge: Bridge) { self.bridge = bridge }

    func add(_ name: String, _ ok: Bool, _ detail: String = "") {
        checks.append(CheckResult(name: name, ok: ok, detail: detail))
    }

    // MARK: rendering

    func measure(_ text: String, width: Float = 0, color: UInt32 = 0x1F1F1FFF) -> TextMeasurement? {
        do {
            return try bridge.measure(MeasureRequest(text: text, color: color, scale: scale, maxWidth: width))
        } catch {
            print("measure failed: \(error)")
            return nil
        }
    }

    /// Builds the whole tree and commits it as one transaction.
    func render() {
        guard let win = bridge.window else { return }
        let s = scale
        let lh = 24 * s
        lineHeightPx = lh
        var release: [TextRunHandle] = []
        var nodes: [NodeUpsert] = []

        // 1 label
        let labelText = "Hello SwiftRight: bridge ABI v0"
        if let m = measure(labelText) {
            release.append(m.run)
            nodes.append(NodeUpsert(
                id: 1, order: 1, bounds: Rect(x: 20 * s, y: 20 * s, w: m.width, h: m.height),
                primitives: [.text(m.run, x: 20 * s, y: 20 * s)],
                semantic: SemanticNode(role: .staticText, label: labelText, identifier: "title/hello")))
        }

        // 4 wrapped paragraph (200 DIP wide)
        var y = 60 * s
        if let m = measure(paragraph, width: 200 * s) {
            release.append(m.run)
            nodes.append(NodeUpsert(
                id: 4, order: 2, bounds: Rect(x: 20 * s, y: y, w: 200 * s, h: m.height),
                primitives: [.text(m.run, x: 20 * s, y: y)],
                semantic: SemanticNode(role: .staticText, label: paragraph, identifier: "text/paragraph")))
            y += m.height + 20 * s
        }

        // 2 button
        let by = y
        let bw = 160 * s, bh = 40 * s
        var buttonPrims: [Primitive] = [.rect(Rect(x: 20 * s, y: by, w: bw, h: bh), color: 0x2563EBFF, radius: 6 * s)]
        if let m = measure("Press me", color: 0xFFFFFFFF) {
            release.append(m.run)
            buttonPrims.append(.text(m.run, x: 20 * s + (bw - m.width) / 2, y: by + (bh - m.height) / 2))
        }
        nodes.append(NodeUpsert(
            id: 2, order: 3, flags: [.hitTarget, .focusable],
            bounds: Rect(x: 20 * s, y: by, w: bw, h: bh), primitives: buttonPrims,
            semantic: SemanticNode(role: .button, label: "Press me", actions: [.invoke, .focus],
                                       identifier: "toolbar/press")))
        y = by + bh + 20 * s

        // 3 editable text node
        let ey = y
        let ew = 400 * s, eh = 36 * s
        let text = String(decoding: units, as: UTF16.self)
        var editPrims: [Primitive] = [
            .rect(Rect(x: 20 * s, y: ey, w: ew, h: eh), color: 0xFFFFFFFF, radius: 4 * s,
                  borderColor: 0x888888FF, borderWidth: max(1, s)),
        ]
        var editSem = SemanticNode(role: .textField, label: "Edit", value: text,
                                   actions: [.focus, .setValue, .setSelection],
                                   identifier: "field/edit")
        let origin = (x: 20 * s + 8 * s, y: ey + (eh - lh) / 2)
        editOrigin = origin
        if let m = measure(text) {
            release.append(m.run)
            let cells = (try? bridge.cells(of: m.run)) ?? []
            editCells = cells
            editLines = m.lines
            editPrims.append(.text(m.run, x: origin.x, y: origin.y))
            let caretIndex = utf16Offset(toScalarIndex: units, Int(sel.end))
            let caret = caretRect(cells: cells, lines: m.lines, index: caretIndex, origin: origin,
                                  lineHeightPx: lh, width: max(1, 1.5 * s))
            editPrims.append(.rect(caret, color: 0x111111FF))
            let runs = makeAXTextRuns(text: text, measurement: m, cells: cells, origin: origin,
                                      lineHeightPx: lh, firstRunID: 100)
            editSem.runs = runs
            if !runs.isEmpty {
                var line = 0, idxInLine = 0
                if cells.isEmpty {
                    line = 0; idxInLine = 0          // empty text: the zero-length run, character 0
                } else if caretIndex < cells.count {
                    line = Int(cells[caretIndex].line)
                    idxInLine = cells[..<caretIndex].filter { Int($0.line) == line }.count
                } else {
                    line = Int(cells[cells.count - 1].line)
                    idxInLine = cells.filter { Int($0.line) == line }.count
                }
                let pos = TextSelectionPosition(run: runs[min(line, runs.count - 1)].id, character: UInt32(idxInLine))
                editSem.selection = (anchor: pos, focus: pos)
            }
        }
        nodes.append(NodeUpsert(
            id: 3, order: 4, flags: [.hitTarget, .focusable, .editable],
            bounds: Rect(x: 20 * s, y: ey, w: ew, h: eh), primitives: editPrims, semantic: editSem))
        y = ey + eh + 20 * s

        // 5 status
        let status = "AX invokes: \(axInvokes)  typed: [\(typed)]"
        if let m = measure(status) {
            release.append(m.run)
            nodes.append(NodeUpsert(
                id: 5, order: 5, bounds: Rect(x: 20 * s, y: y, w: m.width, h: m.height),
                primitives: [.text(m.run, x: 20 * s, y: y)],
                semantic: SemanticNode(role: .staticText, label: status, identifier: "status/ax")))
        }

        version += 1
        do {
            try win.commit(Transaction(version: version, focus: 3, upserts: nodes))
        } catch {
            print("commit failed: \(error)")
        }
        for r in release { bridge.release(r) }
    }

    // MARK: measurement checks

    func runMeasurementChecks() {
        let s = scale
        let wide = 420 * s, narrow = 200 * s
        guard let a = measure(paragraph, width: wide), let b = measure(paragraph, width: narrow) else {
            add("measure two widths", false, "measure threw")
            return
        }
        wrapWide = a
        wrapNarrow = b
        let lh = 24 * s
        heightConsistent = abs(a.height - Float(a.lineCount) * lh) < 0.5 && abs(b.height - Float(b.lineCount) * lh) < 0.5
        let total = paragraph.utf8.count
        let coverA = a.lines.reduce(0) { $0 + Int($1.utf8Len) }
        let coverB = b.lines.reduce(0) { $0 + Int($1.utf8Len) }
        wrapCoversText = coverA == total && coverB == total
        let fits = a.lines.allSatisfy { $0.width <= wide + 0.5 } && b.lines.allSatisfy { $0.width <= narrow + 0.5 }
        add("wrap at 2 widths", b.lineCount > a.lineCount && fits,
            "wide(\(Int(wide))px)=\(a.lineCount) lines \(String(format: "%.1f", a.width))x\(String(format: "%.1f", a.height)); narrow(\(Int(narrow))px)=\(b.lineCount) lines \(String(format: "%.1f", b.width))x\(String(format: "%.1f", b.height))")
        add("height = lines x line height", heightConsistent, "")
        add("line breaks cover all bytes", wrapCoversText, "utf8 \(total) wide=\(coverA) narrow=\(coverB)")
        if let again = measure(paragraph, width: wide) {
            cacheHitOnRepeat = again.cacheHit && again.cacheKey == a.cacheKey
            add("cache hit on repeat measure", cacheHitOnRepeat, "key \(String(a.cacheKey, radix: 16))")
            bridge.release(again.run)
        }
        let cells = (try? bridge.cells(of: b.run)) ?? []
        let sum = cells.reduce(0) { $0 + Int($1.utf8Len) }
        let lineOfLast = cells.last.map { Int($0.line) } ?? -1
        add("char cells", cells.count == Int(b.charCount) && sum == total && lineOfLast == b.lineCount - 1,
            "\(cells.count) cells, last on line \(lineOfLast)")
        bridge.release(a.run)
        bridge.release(b.run)
        // Stale handle after release must fail with a typed error.
        let stale = bridge.release(a.run)
        add("stale run handle rejected", !stale, "second release returned \(stale)")
    }

    // MARK: events

    func handle(_ ev: BridgeEvent) {
        if ev.window != 0, ev.window != bridge.window?.handle { staleEvents += 1; return }
        switch ev.kind {
        case .axAction:
            if ev.node != 2 && ev.node != 3 { unknownNodeEvents += 1; return }
            if ev.axAction == .invoke && ev.node == 2 {
                axInvokes += 1
                if firstAXWindow == 0 { firstAXWindow = ev.window }
                print("event: AX invoke node=\(ev.node) window=\(String(ev.window, radix: 16)) snapshot=\(ev.snapshot) (current \(version))")
                render()
            } else {
                print("event: AX action=\(ev.action) node=\(ev.node)")
            }
        case .key:
            keyEvents += 1
            print("event: key \(ev.text) typed=\(ev.typed) mods=\(ev.modifiers)")
        case .pointer:
            pointerEvents += 1
            if ev.action == 1 {
                let w = Float(lastWidth)
                if ev.x <= 8 || ev.x >= w - 8 || ev.y <= 8 { edgeClickSeen = true }
                print("event: pointer down x=\(ev.x) y=\(ev.y) hit=\(ev.node) snapshot=\(ev.snapshot) window_w=\(lastWidth)")
            }
        case .windowMetrics:
            metricsEvents += 1
            lastWidth = UInt32(max(0, ev.i0))
            let ns = ev.x
            if ns > 0, ns != scale { scale = ns; render() }
        case .ime, .focus, .modalResult, .none:
            break
        }
        evaluateDone()
    }

    var lastWidth: UInt32 = 0
    var lastHandle: UInt64 = 0

    func evaluateDone() {
        if doneAtTick == nil, axInvokes >= 1, typed.contains("a"), !expectEdgeClick || edgeClickSeen {
            doneAtTick = ticks + 90        // keep presenting ~1.5 s more to gather frame evidence
        }
    }

    func onTick(_ win: BridgeWindow, _ ts: UInt64) {
        ticks += 1
        if lastTickNs != 0 { maxTickGapMs = max(maxTickGapMs, Double(ts &- lastTickNs) / 1e6) }
        lastTickNs = ts
        if windowActive == 0 { ticksInactive += 1 }
        if !finishing {
            let expired = Date().timeIntervalSince(started) > timeoutSeconds
            if let d = doneAtTick, ticks >= d { finishing = true; bridge.requestQuit() }
            else if expired { finishing = true; add("timeout", false, "no completion after \(timeoutSeconds)s"); bridge.requestQuit() }
        }
    }

    var windowActive: UInt32 = 1

    // MARK: TextStore (UTF-16; called from inside native input handling)

    func selection(node: NodeID) -> (range: UTF16Span, reversed: Bool)? { (sel, false) }
    func markedRange(node: NodeID) -> UTF16Span? { marked }

    func clamp(_ r: UTF16Span) -> UTF16Span {
        let n = UInt32(units.count)
        let s = min(r.start, n)
        return UTF16Span(start: s, end: max(s, min(r.end, n)))
    }

    func text(node: NodeID, range: UTF16Span) -> (units: [UInt16], adjusted: UTF16Span)? {
        let r = clamp(range)
        return (Array(units[Int(r.start)..<Int(r.end)]), r)
    }

    func apply(_ range: UTF16Span?, _ text: [UInt16]) -> UTF16Span {
        let target = clamp(range ?? marked ?? sel)
        units.replaceSubrange(Int(target.start)..<Int(target.end), with: text)
        return UTF16Span(start: target.start, end: target.start + UInt32(text.count))
    }

    func replace(node: NodeID, range: UTF16Span?, text: [UInt16]) -> Bool {
        imeReplaceCalls += 1
        let ins = apply(range, text)
        sel = UTF16Span(start: ins.end, end: ins.end)
        marked = nil
        typed += String(decoding: text, as: UTF16.self)
        render()          // measure + commit inside the native callback: commit is deferred
        evaluateDone()
        return true
    }

    func replaceAndMark(node: NodeID, range: UTF16Span?, text: [UInt16], newSelection: UTF16Span?) -> Bool {
        let ins = apply(range, text)
        marked = text.isEmpty ? nil : ins
        if let ns = newSelection {
            sel = clamp(UTF16Span(start: ins.start + ns.start, end: ins.start + ns.end))
        } else {
            sel = UTF16Span(start: ins.end, end: ins.end)
        }
        render()
        return true
    }

    func unmark(node: NodeID) -> Bool {
        marked = nil
        render()
        return true
    }

    func caretBounds(node: NodeID, range: UTF16Span) -> Rect? {
        let idx = utf16Offset(toScalarIndex: units, Int(range.start))
        return caretRect(cells: editCells, lines: editLines, index: idx, origin: editOrigin,
                         lineHeightPx: lineHeightPx, width: 2)
    }
}

// MARK: main

func summarize(_ smoke: Smoke, runResult: String) -> Int32 {
    let st = smoke.bridge.stats()
    let b = smoke.bridge
    smoke.add("startup validation", true, "abi \(b.info.abi_major).\(b.info.abi_minor) fn_count=\(b.info.fn_count)")
    smoke.add("AX Invoke handled", smoke.axInvokes >= 1, "invokes=\(smoke.axInvokes) window gen tag ok=\(smoke.firstAXWindow != 0)")
    smoke.add("typed character reached the text store", smoke.typed.contains("a"),
              "typed=[\(smoke.typed)] ime_replace_calls=\(smoke.imeReplaceCalls) key_events=\(smoke.keyEvents)")
    if expectEdgeClick {
        smoke.add("click 2px inside the client edge reached the window", smoke.edgeClickSeen,
                  "pointer_events=\(smoke.pointerEvents)")
    }
    smoke.add("display ticks delivered", smoke.ticks > 30, "ticks=\(smoke.ticks) max_gap_ms=\(String(format: "%.1f", smoke.maxTickGapMs)) paints=\(st.paints)")
    smoke.add("non-reentrant drain", b.reentrySelftest == 1 && b.drainReentryRefused == 0 && st.reentry_refused == 0,
              "selftest=\(b.reentrySelftest) swift_refused=\(b.drainReentryRefused) rust_refused=\(st.reentry_refused) drains=\(b.drainCalls)")
    smoke.add("no thread violations or host panics", st.thread_violations == 0 && st.host_panics == 0,
              "thread_violations=\(st.thread_violations) host_panics=\(st.host_panics)")
    smoke.add("commits accepted; only the 3 injected faults rejected", st.commits_accepted >= 2 && st.commits_rejected == 3,
              "accepted=\(st.commits_accepted) rejected=\(st.commits_rejected) deferred_in_ime=\(st.commits_deferred)")
    smoke.add("window_closed delivered once", b.windowClosedCalls == 1, "calls=\(b.windowClosedCalls)")
    smoke.add("no stale or unknown-node events", smoke.staleEvents == 0 && smoke.unknownNodeEvents == 0,
              "stale=\(smoke.staleEvents) unknown=\(smoke.unknownNodeEvents) rust_dropped_stale=\(st.events_dropped_stale)")
    print("frames_while_not_foreground: ticks_with_inactive_window=\(smoke.ticksInactive) of \(smoke.ticks)")
    print("renderer stats: paints=\(st.paints) commits=\(st.commits_accepted) measure_calls=\(st.measure_calls) cache_hits=\(st.measure_cache_hits) events=\(st.events_pushed) ax_enqueued=\(st.ax_actions_enqueued) ax_rejected=\(st.ax_actions_rejected) ime_calls=\(st.ime_calls) ime_busy=\(st.ime_busy_rejected)")
    print("run: \(runResult)")
    var pass = true
    for c in smoke.checks {
        print("\(c.ok ? "PASS" : "FAIL") \(c.name)\(c.detail.isEmpty ? "" : " [\(c.detail)]")")
        if !c.ok { pass = false }
    }
    print("SMOKE \(pass ? "PASS" : "FAIL") (\(smoke.checks.filter { $0.ok }.count)/\(smoke.checks.count))")
    return pass ? 0 : 1
}

do {
    let bridge = try Bridge.load()
    let smoke = Smoke(bridge: bridge)
    bridge.textStore = smoke
    var runResult = "ok"

    bridge.onReady = { win in
        do {
            let m = try win.metrics()
            smoke.scale = m.scale
            smoke.lastWidth = m.width
            smoke.lastHandle = win.handle
            print("ready: window=\(String(win.handle, radix: 16)) client=\(m.width)x\(m.height)px scale=\(m.scale)")
        } catch {
            print("metrics failed: \(error)")
        }
        smoke.runMeasurementChecks()
        smoke.render()
        // Post-run style check while live: an old snapshot version must be rejected.
        do {
            try win.commit(Transaction(version: 1))
            smoke.add("stale commit version rejected", false, "accepted")
        } catch BridgeError.status(let rc, _) {
            smoke.add("stale commit version rejected", rc == -11, statusName(rc))
        } catch {
            smoke.add("stale commit version rejected", false, "\(error)")
        }
        let bogus = BridgeWindow.makeForTesting(bridge: bridge, handle: win.handle ^ (1 << 40))
        do {
            try bogus.commit(Transaction(version: 9999))
            smoke.add("bogus window generation rejected", false, "accepted")
        } catch BridgeError.status(let rc, _) {
            smoke.add("bogus window generation rejected", rc == -6, statusName(rc))
        } catch {
            smoke.add("bogus window generation rejected", false, "\(error)")
        }
        try? win.requestTicks(true)
        Task { @MainActor in
            for await ev in bridge.events { smoke.handle(ev) }
        }
    }
    bridge.onTick = { win, ts in
        smoke.windowActive = ((try? win.metrics())?.active ?? true) ? 1 : 0
        smoke.onTick(win, ts)
    }

    do {
        try bridge.run(title: "SwiftRight BridgeSmoke", width: 640, height: 480)
    } catch {
        runResult = "run failed: \(error)"
        smoke.add("run", false, "\(error)")
    }

    // After close: new work must be rejected with a typed error, never touch a dead window.
    do {
        let win = BridgeWindow.makeForTesting(bridge: bridge, handle: smoke.lastHandle)
        do {
            try win.commit(Transaction(version: 100_000))
            smoke.add("commit after close rejected", false, "accepted")
        } catch BridgeError.status(let rc, _) {
            smoke.add("commit after close rejected", rc == -13 || rc == -6, statusName(rc))
        } catch {
            smoke.add("commit after close rejected", false, "\(error)")
        }
    }
    exit(summarize(smoke, runResult: runResult))
} catch BridgeError.startup(let message) {
    print(message)
    fflush(stdout)
    exit(78)
} catch {
    print("SWR_STARTUP_ERROR: \(error)")
    exit(78)
}
