import Foundation
import SwiftRightBridge

// BridgeSmoke: end-to-end ABI rev 0.6 check (rev 0.6 additions: Smoke.runRev06Checks). Opens a window, commits a hand-authored tree
// (label, wrapped paragraph, button, editable text node, status), measures and wraps text
// at two widths, handles an AX Invoke and a typed character (driven from outside by
// scripts/drive-smoke.ps1: UIA Invoke + virtual-key input), then quits and prints a
// PASS/FAIL summary. Exit code 0 = PASS, 1 = FAIL, 78 = startup diagnostic.

let env = ProcessInfo.processInfo.environment
let expectEdgeClick = env["SWR_SMOKE_EXPECT_EDGE_CLICK"] == "1"
/// SWR_SMOKE_SKIP_SHUTDOWN=1: the app never calls swr_shutdown_complete after close, so the
/// post-close pump must end by its 5 s bound (post_close_timeouts == 1).
let skipShutdown = env["SWR_SMOKE_SKIP_SHUTDOWN"] == "1"
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

    // post-close evidence (rev 0.5)
    var closeCalls = 0
    var lateCommitRC: Int32?
    var lateMeasureRC: Int32?
    var cleanupRan = false
    var cleanupLiveNodes: UInt64?
    var cleanupShutdownRC: Int32?
    var cleanupRepeatRC: Int32?          // second swr_shutdown_complete in the same pump (idempotence)
    var earlyShutdownRC: Int32?          // swr_shutdown_complete while the window is still open
    var earlyDrainsBefore: UInt64 = 0
    var closedAt: Date?

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
    let lingerTicks = Int(ProcessInfo.processInfo.environment["SWR_SMOKE_LINGER_TICKS"] ?? "") ?? 90
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

    // MARK: rev 0.6 checks (roles, state, images, multi-paragraph text, modal argument validation)
    //
    // No modal is ever OPENED here (a real menu or task dialog needs a human or a UIA driver);
    // only requests the renderer must reject before queueing are sent. Exactly ONE commit is
    // rejected on purpose (stale image handle): see the commits_rejected expectation.

    func status(_ body: () throws -> Void) -> Int32 {
        do { try body(); return 0 } catch BridgeError.status(let rc, _) { return rc } catch { return -999 }
    }

    func runRev06Checks(_ win: BridgeWindow) {
        let b = bridge
        let s = scale
        let lh = 24 * s

        // ---- images ----
        var px: [UInt8] = []
        for i in 0..<16 { px += [UInt8(i * 16), UInt8(255 - i * 16), 128, 255] }   // 4x4 RGBA
        let live0 = b.stats().live_nodes
        var image: ImageHandle?
        let regRC = status { image = try b.registerImage(width: 4, height: 4, rgba: px) }
        let live1 = b.stats().live_nodes
        add("image registered (handle, live_nodes +1)", regRC == 0 && image != nil && live1 == live0 + 1,
            "rc=\(statusName(regRC)) live_nodes \(live0)->\(live1)")
        if let image {
            let cx = 460 * s
            let before = b.stats()
            version += 1
            let node = NodeUpsert(id: 7, order: 7, bounds: Rect(x: cx, y: 20 * s, w: 64 * s, h: 64 * s),
                                  primitives: [.image(image, Rect(x: cx, y: 20 * s, w: 64 * s, h: 64 * s), radius: 8 * s)],
                                  semantic: SemanticNode(role: .image, label: "swatch", identifier: "image/swatch"))
            let rc = status { try win.commit(Transaction(version: version, upserts: [node])) }
            let after = b.stats()
            add("SWR_PRIM_IMAGE accepted (scaled 4x4 -> 64 DIP)", rc == 0 && after.commits_accepted == before.commits_accepted + 1,
                "rc=\(statusName(rc)); limitation: painting is not asserted (no per-primitive draw counter)")
            // Lifetime (ABI 0.6): a committed node keeps the image alive; release drops only the host handle.
            let liveCommitted = b.stats().live_nodes
            let rel1 = b.release(image)
            let rel2 = b.release(image)
            let liveReleased = b.stats().live_nodes
            add("release drops the host handle only; second release is stale; committed node keeps the image alive",
                rel1 && !rel2 && liveReleased == liveCommitted && liveCommitted == live0 + 2,
                "release=\(rel1) again=\(rel2) live_nodes \(live0) -> committed \(liveCommitted) -> released \(liveReleased) (image + node still alive)")
            // Re-committing node 7 without the image primitive (same semantic node, so the UIA swatch
            // stays) drops the last reference: the image is freed and leaves live_nodes.
            version += 1
            let bare = NodeUpsert(id: 7, order: 7, bounds: Rect(x: cx, y: 20 * s, w: 64 * s, h: 64 * s), primitives: [],
                                  semantic: SemanticNode(role: .image, label: "swatch", identifier: "image/swatch"))
            let rmRC = status { try win.commit(Transaction(version: version, upserts: [bare])) }
            let liveFreed = b.stats().live_nodes
            add("image freed once released and unreferenced (live_nodes: node stays, image gone)", rmRC == 0 && liveFreed == live0 + 1,
                "re-commit rc=\(statusName(rmRC)) live_nodes \(liveFreed) (baseline \(live0) + node 7)")
            // A commit that references the released handle is rejected (the ONE intended commit rejection).
            version += 1
            let stale = NodeUpsert(id: 8, order: 8, bounds: Rect(x: cx, y: 100 * s, w: 16, h: 16),
                                   primitives: [.image(image, Rect(x: cx, y: 100 * s, w: 16, h: 16))])
            let staleRC = status { try win.commit(Transaction(version: version, upserts: [stale])) }
            add("commit with a released image handle rejected", staleRC == -6, statusName(staleRC))
        }
        let zeroRC = status { _ = try b.registerImage(width: 0, height: 4, rgba: []) }
        let hugeRC = status { _ = try b.registerImage(width: 8193, height: 1, rgba: [UInt8](repeating: 0, count: 8193 * 4)) }
        let strideRC = status { _ = try b.registerImage(width: 4, height: 2, rgba: [UInt8](repeating: 0, count: 64), stride: 4) }
        add("image argument errors typed", zeroRC == -1 && hugeRC == -8 && strideRC == -1,
            "zero_width=\(statusName(zeroRC)) 8193px=\(statusName(hugeRC)) stride<row=\(statusName(strideRC))")
        // Left registered on purpose: closing the window must drop it (live_nodes -> 0 is asserted at teardown).
        let leaked = try? b.registerImage(width: 2, height: 2, rgba: [UInt8](repeating: 255, count: 16))
        add("image left registered for teardown check", leaked != nil, "dropped with the window; see live nodes zero after teardown")

        // ---- roles and semantic state, one transaction ----
        let cx = 460 * s
        func box(_ id: UInt64, _ y: Float, _ sem: SemanticNode, hit: Bool = false) -> NodeUpsert {
            NodeUpsert(id: id, order: UInt32(id), flags: hit ? [.hitTarget, .focusable] : [],
                       bounds: Rect(x: cx, y: y * s, w: 150 * s, h: 20 * s), semantic: sem)
        }
        let roleNodes: [NodeUpsert] = [
            box(10, 120, SemanticNode(role: .checkbox, label: "Check", actions: [.invoke, .focus], identifier: "r06/checkbox", toggled: .on)),
            box(11, 145, SemanticNode(role: .switchControl, label: "Switch", actions: [.invoke, .focus], identifier: "r06/switch", toggled: .off)),
            box(12, 170, SemanticNode(role: .checkbox, label: "Mixed", actions: [.invoke], identifier: "r06/mixed", toggled: .mixed)),
            box(13, 195, SemanticNode(role: .menu, label: "Menu", identifier: "r06/menu")),
            box(14, 220, SemanticNode(role: .menuItem, label: "Menu item", actions: [.invoke], identifier: "r06/menuitem", selected: false)),
            box(15, 245, SemanticNode(role: .alert, label: "Alert", identifier: "r06/alert")),
            box(16, 270, SemanticNode(role: .dialog, label: "Dialog", identifier: "r06/dialog")),
            box(17, 295, SemanticNode(role: .listItem, label: "Row", actions: [.invoke], identifier: "r06/row-selected", selected: true)),
            box(18, 320, SemanticNode(role: .button, label: "Off", actions: [.invoke, .focus], identifier: "r06/disabled", disabled: true), hit: true),
        ]
        let before = b.stats()
        version += 1
        let rolesRC = status { try win.commit(Transaction(version: version, upserts: roleNodes)) }
        let after = b.stats()
        add("rev 0.6 roles, toggled, selected and disabled accepted in one commit",
            rolesRC == 0 && after.commits_accepted == before.commits_accepted + 1,
            "rc=\(statusName(rolesRC)); UIA mapping is checked by scripts/drive-smoke.ps1 (see README-abi-v0.md rev 0.6)")

        // ---- multi-paragraph text ----
        let multi = "alpha\nbeta gamma\n\nz\n"          // 5 visual lines, trailing '\n'
        if let m = measure(multi) {
            let cells = (try? b.cells(of: m.run)) ?? []
            let breaks = cells.filter { $0.lineBreak }
            let bytes = m.lines.reduce(0) { $0 + Int($1.utf8Len) }
            let contiguous = zip(m.lines, m.lines.dropFirst()).allSatisfy { $0.utf8Start + $0.utf8Len == $1.utf8Start }
            add("multi-paragraph measure: lines partition the text, '\\n' is a zero-width cell",
                m.lineCount == 5 && bytes == multi.utf8.count && contiguous && breaks.count == 4
                    && cells.count == Int(m.charCount) && breaks.allSatisfy { $0.x0 == $0.x1 }
                    && abs(m.height - 5 * lh) < 0.5,
                "lines=\(m.lineCount) bytes=\(bytes)/\(multi.utf8.count) breaks=\(breaks.count) cells=\(cells.count)/\(m.charCount) height=\(m.height)")
            let runs = makeAXTextRuns(text: multi, measurement: m, cells: cells, origin: (x: 0, y: 0), lineHeightPx: lh, firstRunID: 500)
            add("per-line AX text runs keep the line break", runs.count == 5 && runs[0].text == "alpha\n" && runs[1].text == "beta gamma\n"
                && runs[2].text == "\n" && runs[4].text == "",
                "runs=\(runs.map { $0.text })")
            let after = caretRect(cells: cells, lines: m.lines, index: cells.count, origin: (x: 0, y: 0), lineHeightPx: lh, width: 2)
            add("caret after a trailing newline starts the next line", abs(after.y - 4 * lh) < 0.5 && after.x == 0, "y=\(after.y) x=\(after.x)")
            b.release(m.run)
        } else {
            add("multi-paragraph measure", false, "measure threw")
        }
        let narrowText = "aaaa bbbb cccc\ndddd eeee ffff"
        let paraA = "aaaa bbbb cccc", paraB = "dddd eeee ffff"
        if let m = measure(narrowText, width: 60 * s), let one = measure(paraA, width: 60 * s),
           let two = measure(paraB, width: 60 * s) {
            // Each paragraph wraps as it does alone: same lines (offsets shifted by the first paragraph + '\n').
            let shift = UInt32(paraA.utf8.count + 1)
            let expected = one.lines.map { ($0.utf8Start, $0.utf8Len) } + two.lines.map { ($0.utf8Start + shift, $0.utf8Len) }
            var got = m.lines.map { ($0.utf8Start, $0.utf8Len) }
            if let li = one.lines.indices.last, got.indices.contains(li) { got[li].1 -= 1 }   // '\n' belongs to the last line of paragraph 1
            let same = got.count == expected.count && zip(got, expected).allSatisfy { $0 == $1 }
            func dump(_ l: [LineInfo]) -> String { l.map { "[\($0.utf8Start)+\($0.utf8Len)]" }.joined() }
            add("each paragraph wraps on its own", same && one.lineCount > 1 && two.lineCount > 1
                    && m.lineCount == one.lineCount + two.lineCount,
                "A alone=\(one.lineCount) \(dump(one.lines)); B alone=\(two.lineCount) \(dump(two.lines)); together=\(m.lineCount) \(dump(m.lines))")
            b.release(m.run); b.release(one.run); b.release(two.run)
        }
        let crRC = status { _ = try b.measure(MeasureRequest(text: "a\r\nb", scale: s)) }
        add("'\\r' still rejected (SWR_E_UNSUPPORTED)", crRC == -15, statusName(crRC))

        // ---- modal arguments the renderer must reject before queueing (nothing is opened) ----
        typealias Item = BridgeWindow.ModalItem
        let ok2 = [Item(id: 1, text: "Yes"), Item(id: 2, text: "No")]
        let r1 = status { try win.requestDialog(requestID: 9001, title: "t", message: "m", buttons: []) }
        let r2 = status { try win.requestDialog(requestID: 9002, title: "t", message: "m",
                                                buttons: (1...9).map { Item(id: UInt32($0), text: "b\($0)") }) }
        let r3 = status { try win.requestDialog(requestID: 9003, title: "t", message: "m",
                                                buttons: [Item(id: 5, text: "a"), Item(id: 5, text: "b")]) }
        let r4 = status { try win.requestDialog(requestID: 9004, title: "t", message: "m", buttons: ok2, defaultIndex: 2) }
        let r5 = status { try win.requestMenu(requestID: 9005, items: [.separatorItem], x: 10, y: 10) }
        let r6 = status { try win.requestMenu(requestID: 9006, items: (1...65).map { Item(id: UInt32($0), text: "i\($0)") }, x: 10, y: 10) }
        add("menu and dialog arguments validated before queueing",
            r1 == -1 && r2 == -8 && r3 == -1 && r4 == -1 && r5 == -1 && r6 == -8,
            "0 buttons=\(statusName(r1)) 9 buttons=\(statusName(r2)) duplicate ids=\(statusName(r3)) default out of range=\(statusName(r4)) only separators=\(statusName(r5)) 65 items=\(statusName(r6)); opening a real menu/dialog needs a human or UIA driver")
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
            doneAtTick = ticks + lingerTicks  // default 90 ticks (~1.5 s); the UIA driver sets SWR_SMOKE_LINGER_TICKS so its lookups finish first
        }
    }

    /// window_closed (rev 0.5). Teardown happens here. The renderer then runs the post-close
    /// pump, which drains the main queue: a late result posted to the main queue must be
    /// rejected, and the cleanup job runs there and ends the pump with swr_shutdown_complete.
    func onClosed() {
        closeCalls += 1
        closedAt = Date()
        let b = bridge
        let handle = lastHandle
        DispatchQueue.main.async { [self] in
            // Late async result: a finished request tries to commit and measure after close.
            let win = BridgeWindow.makeForTesting(bridge: b, handle: handle)
            do {
                try win.commit(Transaction(version: 200_000))
                self.lateCommitRC = 0
            } catch BridgeError.status(let rc, _) {
                self.lateCommitRC = rc
            } catch {
                self.lateCommitRC = -999
            }
            do {
                _ = try b.measure(MeasureRequest(text: "late", scale: 1))
                self.lateMeasureRC = 0
            } catch BridgeError.status(let rc, _) {
                self.lateMeasureRC = rc
            } catch {
                self.lateMeasureRC = -999
            }
        }
        DispatchQueue.main.async { [self] in
            // Cleanup in the post-close pump: the closed window must retain no nodes or runs.
            self.cleanupRan = true
            self.cleanupLiveNodes = b.stats().live_nodes
            if skipShutdown { return }   // timeout mode: leave the pump to its 5 s bound
            func call() -> Int32 {
                do { try b.shutdownComplete(); return 0 }
                catch BridgeError.status(let rc, _) { return rc }
                catch { return -999 }
            }
            self.cleanupShutdownRC = call()
            self.cleanupRepeatRC = call()   // already ended: must stay SWR_OK (idempotent)
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

/// swr_shutdown_complete from the (still UI) thread after swr_run returned.
func lateShutdownRC(_ b: Bridge) -> Int32 {
    do { try b.shutdownComplete(); return 0 }
    catch BridgeError.status(let rc, _) { return rc }
    catch { return -999 }
}

func summarize(_ smoke: Smoke, runResult: String) -> Int32 {
    let st = smoke.bridge.stats()
    let b = smoke.bridge
    smoke.add("startup validation", true, "abi \(b.info.abi_major).\(b.info.abi_minor) fn_count=\(b.info.fn_count) stats_size=\(b.info.stats_size)")
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
    smoke.add("commits accepted; only the 5 injected faults rejected", st.commits_accepted >= 2 && st.commits_rejected == 5,
              "accepted=\(st.commits_accepted) rejected=\(st.commits_rejected) deferred_in_ime=\(st.commits_deferred)")
    smoke.add("window_closed delivered once", b.windowClosedCalls == 1 && smoke.closeCalls == 1, "calls=\(b.windowClosedCalls)")
    let lateOK = smoke.lateCommitRC == -13 && smoke.lateMeasureRC == -13
    smoke.add("late async result after close rejected", lateOK,
              "commit=\(statusName(smoke.lateCommitRC ?? 0)) measure=\(statusName(smoke.lateMeasureRC ?? 0))")
    let liveAtCleanup = smoke.cleanupLiveNodes.map { String($0) } ?? "none"
    smoke.add("cleanup ran in post-close pump", smoke.cleanupRan && st.post_close_drains >= 1,
              "post_close_drains=\(st.post_close_drains)")
    smoke.add("live nodes zero after teardown", smoke.cleanupLiveNodes == 0 && st.live_nodes == 0,
              "at cleanup=\(liveAtCleanup) after run=\(st.live_nodes)")
    smoke.add("swr_shutdown_complete before close returns SWR_E_STATE and has no effect",
              smoke.earlyShutdownRC == -4 && smoke.earlyDrainsBefore == 0 && smoke.closeCalls == 1 && smoke.cleanupRan,
              "rc=\(statusName(smoke.earlyShutdownRC ?? -99)) post_close_drains_at_call=\(smoke.earlyDrainsBefore) window kept running: close_calls=\(smoke.closeCalls)")
    let sinceClose = smoke.closedAt.map { Date().timeIntervalSince($0) } ?? 0
    if skipShutdown {
        smoke.add("timeout mode: app never called swr_shutdown_complete", smoke.cleanupShutdownRC == nil && smoke.cleanupRepeatRC == nil, "")
        smoke.add("pump ended by the 5 s timeout [SKIP_SHUTDOWN]",
                  st.post_close_timeouts == 1 && sinceClose >= 4.5 && sinceClose < 15,
                  "timeouts=\(st.post_close_timeouts) run returned \(String(format: "%.2f", sinceClose))s after window_closed (bound=5s)")
        let lateRC = lateShutdownRC(b)
        smoke.add("swr_shutdown_complete after timeout-ended run", lateRC == 0, "rc=\(statusName(lateRC)) (documented: idempotent, valid once window_closed entered)")
    } else {
        smoke.add("pump ended by swr_shutdown_complete, not the timeout",
                  smoke.cleanupShutdownRC == 0 && st.post_close_timeouts == 0 && sinceClose < 4.5,
                  "shutdown=\(statusName(smoke.cleanupShutdownRC ?? -99)) timeouts=\(st.post_close_timeouts) run returned \(String(format: "%.2f", sinceClose))s after window_closed")
        smoke.add("repeat swr_shutdown_complete is idempotent (in pump and after run returned)",
                  smoke.cleanupRepeatRC == 0 && lateShutdownRC(b) == 0,
                  "second call in pump=\(statusName(smoke.cleanupRepeatRC ?? -99)) after run=\(statusName(lateShutdownRC(b)))")
    }
    smoke.add("no stale or unknown-node events", smoke.staleEvents == 0 && smoke.unknownNodeEvents == 0,
              "stale=\(smoke.staleEvents) unknown=\(smoke.unknownNodeEvents) rust_dropped_stale=\(st.events_dropped_stale)")
    print("frames_while_not_foreground: ticks_with_inactive_window=\(smoke.ticksInactive) of \(smoke.ticks)")
    print("renderer stats: paints=\(st.paints) commits=\(st.commits_accepted) measure_calls=\(st.measure_calls) cache_hits=\(st.measure_cache_hits) events=\(st.events_pushed) ax_enqueued=\(st.ax_actions_enqueued) ax_rejected=\(st.ax_actions_rejected) ime_calls=\(st.ime_calls) ime_busy=\(st.ime_busy_rejected) live_nodes=\(st.live_nodes) post_close_drains=\(st.post_close_drains) post_close_timeouts=\(st.post_close_timeouts)")
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
    bridge.onWindowClosed = { smoke.onClosed() }
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
        // swr_shutdown_complete while the window is open: SWR_E_STATE, no effect on the run.
        smoke.earlyDrainsBefore = bridge.stats().post_close_drains
        do { try bridge.shutdownComplete(); smoke.earlyShutdownRC = 0 }
        catch BridgeError.status(let rc, _) { smoke.earlyShutdownRC = rc }
        catch { smoke.earlyShutdownRC = -999 }
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
        // SWR_PRIM_UNDERLINE (ABI 0.5): an IME marked-text underline as its own node, committed live.
        do {
            let before = bridge.stats()
            let us = smoke.scale
            smoke.version += 1
            let ul = NodeUpsert(id: 6, order: 6, bounds: Rect(x: 20 * us, y: 440 * us, w: 120 * us, h: 3 * us),
                                primitives: [.underline(Rect(x: 20 * us, y: 440 * us, w: 120 * us, h: max(1, 2 * us)), color: 0xD97706FF)])
            try win.commit(Transaction(version: smoke.version, upserts: [ul]))
            let after = bridge.stats()
            let ok = after.commits_accepted == before.commits_accepted + 1 && after.commits_rejected == before.commits_rejected
            smoke.add("underline primitive (IME marked text) accepted", ok,
                      "accepted \(before.commits_accepted)->\(after.commits_accepted) rejected \(before.commits_rejected)->\(after.commits_rejected); limitation: the renderer exposes no per-primitive draw counter, so painting is not asserted (stats.paints only counts frames)")
        } catch {
            smoke.add("underline primitive (IME marked text) accepted", false, "\(error)")
        }
        smoke.runRev06Checks(win)
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
