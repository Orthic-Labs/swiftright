import Foundation
import SwiftRightBridge

// TextGeom06: SR0 snapshot row 6 on the final ABI 0.6 tuple. It re-asks the text-geometry question of
// probes/sr0-b/text-geometry (run 4, 35/35) through the BRIDGE (swr_measure_text, swr_text_run_cells, an editable
// text node with per-line AccessKit TextRun children) instead of a standalone GPUI probe, and adds the
// multi-paragraph / line-break-cell behaviour of 4df7e67 (text.rs).
//
// The host measures text at several proposed widths, commits one editable node (text, selection highlight, caret,
// AX text runs built from the measured cells), logs every expectation to SWR_GM_LOG, and advances one phase each
// time the UIA driver (scripts/drive-textgeom.ps1) drops ack-<phase>.txt into SWR_GM_RUNDIR. The driver reads the
// result back through UIA TextPattern (character/word/line navigation, text-range rectangles, selection, caret
// rectangle through the raw provider array) and compares it with what is logged here. Window-targeted: no input is
// injected; Select() arrives as an AX SetTextSelection event, which this host applies and re-commits.
//
// Phases: A0..A4 = the run-4 text at widths 260/180/340/260/180 (the last two must hit the measurement cache);
// B0..B1 = multi-paragraph text with an empty paragraph and a trailing newline at widths 200/120.
// Exit code: 0 = every host-side check passed, 1 = a failure, 78 = startup diagnostic.
//
// SWR_GM_DRYRUN=1: load the renderer (Windows) and run the pure-logic self-test only; no window.

let env = ProcessInfo.processInfo.environment
let dryRun = env["SWR_GM_DRYRUN"] == "1"
let runDir = env["SWR_GM_RUNDIR"] ?? "."
let timeoutSeconds = Double(env["SWR_GM_TIMEOUT"] ?? "") ?? 120

// MARK: log

var logFile: UnsafeMutablePointer<FILE>?

func openLog() {
    guard let p = env["SWR_GM_LOG"], !p.isEmpty else { return }
    logFile = fopen(p, "ab")
}

func asciiSafe(_ s: String) -> String {
    var out = ""
    for u in s.unicodeScalars {
        out += u.value < 0x80 ? String(u) : "\\u{\(String(u.value, radix: 16))}"
    }
    return out
}

/// One line to the log file (UTF-8, flushed at once: the driver reads it while the host runs) and to stdout (ASCII only).
func glog(_ s: String) {
    if let f = logFile { fputs(s + "\n", f); fflush(f) }
    print(asciiSafe(s))
    fflush(stdout)
}

func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
}

func f2(_ x: Float) -> String { String(format: "%.2f", Double(x)) }
func f3(_ x: Float) -> String { String(format: "%.3f", Double(x)) }
func fmtRect(_ r: Rect) -> String { "\(f2(r.x)),\(f2(r.y)),\(f2(r.w)),\(f2(r.h))" }
func fmtRects(_ rs: [Rect]) -> String { rs.isEmpty ? "none" : rs.map(fmtRect).joined(separator: "|") }

// MARK: text model (code points; UIA counts code points, so does AccessKit)

func isWide(_ u: Unicode.Scalar) -> Bool { u.value >= 0x3000 }
func isWS(_ u: Unicode.Scalar) -> Bool { u.properties.isWhitespace }

/// The word-start rule of render/swiftright-render/src/text.rs `word_starts_of` (and of the run-4 probe): a non-space
/// code point that follows a space, is wide (>= U+3000) or follows a wide one, or is the first. Newline is whitespace.
func wordStartsExpected(_ c: [Unicode.Scalar]) -> [Bool] {
    var out: [Bool] = []
    for i in 0..<c.count {
        if isWS(c[i]) { out.append(false); continue }
        if i == 0 { out.append(true); continue }
        let p = c[i - 1]
        out.append(isWS(p) || isWide(c[i]) || isWide(p))
    }
    return out
}

func findRange(_ hay: [Unicode.Scalar], _ needle: String) -> (Int, Int)? {
    let n = Array(needle.unicodeScalars)
    if n.isEmpty || hay.count < n.count { return nil }
    for i in 0...(hay.count - n.count) where Array(hay[i..<(i + n.count)]) == n { return (i, i + n.count) }
    return nil
}

struct Variant {
    let name: String
    let text: String
    let scalars: [Unicode.Scalar]
    var samples: [(label: String, a: Int, b: Int)] = []
    var carets: [(name: String, idx: Int)] = []
    var selects: [(name: String, a: Int, b: Int)] = []
}

func makeVariants() -> [Variant] {
    // A: the run-4 text (74 code points, 77 UTF-16 units, 103 UTF-8 bytes).
    let textA = "Alpha beta 日本語のテキスト 🙂 gamma delta 漢字 epsilon zeta 🙂🙂 eta theta iota kappa."
    var a = Variant(name: "A", text: textA, scalars: Array(textA.unicodeScalars))
    for label in ["Alpha", "日本語", "🙂", "gamma delta", "kappa."] {
        if let r = findRange(a.scalars, label) { a.samples.append((label: label, a: r.0, b: r.1)) }
    }
    if let r = findRange(a.scalars, "beta") { a.carets.append((name: "beta", idx: r.0)) }
    if let r = findRange(a.scalars, "Alpha") { a.selects.append((name: "alpha", a: r.0, b: r.1)) }

    // B: five paragraphs (the 4th ends the text with a newline, so the last visual line is empty), one of them empty.
    let textB = "alpha 日本語のテキスト\nbeta gamma 🙂 delta epsilon zeta eta theta\n\nz 漢字\n"
    var b = Variant(name: "B", text: textB, scalars: Array(textB.unicodeScalars))
    for label in ["alpha", "日本語", "beta gamma", "🙂", "z 漢字"] {
        if let r = findRange(b.scalars, label) { b.samples.append((label: label, a: r.0, b: r.1)) }
    }
    if let r = findRange(b.scalars, "theta\n\nz") {
        b.carets.append((name: "blank", idx: r.0 + 6))          // the newline of the empty paragraph
        b.selects.append((name: "span", a: r.0, b: r.0 + 8))     // "theta\n\nz": crosses two paragraph breaks
    }
    if let nl = b.scalars.firstIndex(of: "\n") { b.carets.append((name: "p2start", idx: nl + 1)) }
    b.carets.append((name: "end", idx: b.scalars.count))
    return [a, b]
}

struct PhaseSpec {
    let variant: Int
    let widthDIP: Float
    let expectHit: Bool
}

let phaseSpecs: [PhaseSpec] = [
    PhaseSpec(variant: 0, widthDIP: 260, expectHit: false),
    PhaseSpec(variant: 0, widthDIP: 180, expectHit: false),
    PhaseSpec(variant: 0, widthDIP: 340, expectHit: false),
    PhaseSpec(variant: 0, widthDIP: 260, expectHit: true),
    PhaseSpec(variant: 0, widthDIP: 180, expectHit: true),
    PhaseSpec(variant: 1, widthDIP: 200, expectHit: false),
    PhaseSpec(variant: 1, widthDIP: 120, expectHit: false),
]

// MARK: geometry (my own small types, so the arithmetic can be self-tested without a renderer)

struct GCell { var line: Int; var x0: Float; var x1: Float; var isBreak: Bool }

/// Client-px rectangles of the code-point range [a, b), one per visual line it touches: what the renderer paints
/// (cells are line-relative x0/x1; the line top comes from swr_line_info.top).
func rectsFromCells(_ cells: [GCell], lineTops: [Float], origin: (x: Float, y: Float), lh: Float, _ a: Int, _ b: Int) -> [Rect] {
    var out: [Rect] = []
    var i = max(0, a)
    let end = min(b, cells.count)
    while i < end {
        let line = cells[i].line
        var j = i
        while j + 1 < end && cells[j + 1].line == line { j += 1 }
        let top = line < lineTops.count ? lineTops[line] : Float(line) * lh
        out.append(Rect(x: origin.x + cells[i].x0, y: origin.y + top, w: cells[j].x1 - cells[i].x0, h: lh))
        i = j + 1
    }
    return out
}

/// The same rectangles computed from the AX text runs exactly as they are committed (what AccessKit publishes).
func rectsFromRuns(_ runs: [AXTextRun], _ a: Int, _ b: Int) -> [Rect] {
    var out: [Rect] = []
    var base = 0
    for r in runs {
        let n = r.charLengths.count
        let lo = max(a, base), hi = min(b, base + n)
        if lo < hi {
            let i0 = lo - base, i1 = hi - base
            let x0 = r.bounds.x + r.charPositions[i0]
            let x1 = r.bounds.x + r.charPositions[i1 - 1] + r.charWidths[i1 - 1]
            out.append(Rect(x: x0, y: r.bounds.y, w: x1 - x0, h: r.bounds.h))
        }
        base += n
    }
    return out
}

func maxRectErr(_ a: [Rect], _ b: [Rect]) -> Float {
    if a.count != b.count { return .infinity }
    var m: Float = 0
    for (p, q) in zip(a, b) { m = max(m, abs(p.x - q.x), abs(p.y - q.y), abs(p.w - q.w), abs(p.h - q.h)) }
    return m
}

// MARK: pure-logic self-test (dry run)

func selfTestPureLogic() -> Bool {
    var fails: [String] = []
    let vs = makeVariants()
    let a = vs[0]
    if a.scalars.count != 74 { fails.append("A chars \(a.scalars.count) != 74") }
    if a.text.utf8.count != 103 { fails.append("A bytes \(a.text.utf8.count) != 103") }
    if a.text.utf16.count != 77 { fails.append("A utf16 \(a.text.utf16.count) != 77") }
    let ws = wordStartsExpected(a.scalars)
    let interior = ws.enumerated().filter { $0.offset > 0 && $0.element }.count
    if interior != 22 { fails.append("A word starts after index 0 = \(interior) != 22") }
    if !ws[0] { fails.append("A word start at 0") }
    if a.samples.count != 5 || a.carets.count != 1 || a.selects.count != 1 { fails.append("A named ranges \(a.samples.count)/\(a.carets.count)/\(a.selects.count)") }
    if a.carets.first?.idx != 6 { fails.append("A caret idx \(String(describing: a.carets.first?.idx)) != 6") }
    let b = vs[1]
    let newlines = b.scalars.filter { $0 == "\n" }.count
    if newlines != 4 { fails.append("B newlines \(newlines) != 4") }
    if b.samples.count != 5 || b.carets.count != 3 || b.selects.count != 1 { fails.append("B named ranges \(b.samples.count)/\(b.carets.count)/\(b.selects.count)") }
    if let blank = b.carets.first(where: { $0.name == "blank" }) {
        if b.scalars[blank.idx] != "\n" || b.scalars[blank.idx - 1] != "\n" { fails.append("B blank caret is not between two newlines") }
    } else { fails.append("B blank caret missing") }
    if let sp = b.selects.first {
        let s = String(String.UnicodeScalarView(b.scalars[sp.a..<sp.b]))
        if s != "theta\n\nz" { fails.append("B span text [\(esc(s))]") }
    }
    if wordStartsExpected(b.scalars).enumerated().contains(where: { $0.element && isWS(b.scalars[$0.offset]) }) { fails.append("B word start on whitespace") }

    // geometry arithmetic on hand-made cells: two lines of text plus an empty line with only a newline
    let cells = [
        GCell(line: 0, x0: 0, x1: 10, isBreak: false), GCell(line: 0, x0: 10, x1: 20, isBreak: false),
        GCell(line: 0, x0: 20, x1: 20, isBreak: true), GCell(line: 1, x0: 0, x1: 8, isBreak: false),
        GCell(line: 2, x0: 0, x1: 0, isBreak: true),
    ]
    let tops: [Float] = [0, 24, 48]
    let origin: (x: Float, y: Float) = (5, 7)
    let runs = [
        AXTextRun(id: 100, text: "ab\n", charLengths: [1, 1, 1], charPositions: [0, 10, 20], charWidths: [10, 10, 0], wordStarts: [0],
                  bounds: Rect(x: 5, y: 7, w: 20, h: 24)),
        AXTextRun(id: 101, text: "c", charLengths: [1], charPositions: [0], charWidths: [8], wordStarts: [0],
                  bounds: Rect(x: 5, y: 31, w: 8, h: 24)),
        AXTextRun(id: 102, text: "\n", charLengths: [1], charPositions: [0], charWidths: [0], wordStarts: [],
                  bounds: Rect(x: 5, y: 55, w: 0, h: 24)),
    ]
    for (lo, hi) in [(0, 5), (1, 4), (2, 3), (3, 4), (4, 5), (1, 2)] {
        let c = rectsFromCells(cells, lineTops: tops, origin: origin, lh: 24, lo, hi)
        let r = rectsFromRuns(runs, lo, hi)
        if maxRectErr(c, r) > 0.001 { fails.append("rect math [\(lo),\(hi)) cells=\(fmtRects(c)) runs=\(fmtRects(r))") }
    }
    let span = rectsFromCells(cells, lineTops: tops, origin: origin, lh: 24, 1, 4)
    if fmtRects(span) != "15.00,7.00,10.00,24.00|5.00,31.00,8.00,24.00" { fails.append("span rects \(fmtRects(span))") }
    if esc("a\nb\\") != "a\\nb\\\\" { fails.append("esc") }
    for f in fails { glog("DRYRUN logic FAIL \(f)") }
    glog("DRYRUN logic \(fails.isEmpty ? "PASS" : "FAIL") (A chars=\(a.scalars.count) B chars=\(b.scalars.count) B newlines=\(newlines))")
    return fails.isEmpty
}

// MARK: host

struct HostCheck { let name: String; let ok: Bool; let detail: String }

struct PhaseEvidence {
    var rendered = false
    var cacheHit = false
    var expectHit = false
    var physOK = false
    var physDetail = ""
    var selfOK = false
    var selfDetail = ""
}

let firstRunID: NodeID = 1000      // run ids [1000, 1000 + axTextRunBlockSize); node id 3 is the editable node

final class Geo {
    let bridge: Bridge
    let variants = makeVariants()
    var scale: Float = 1
    var version: UInt64 = 0
    var phase = -1
    var phaseReady = false
    var finishing = false
    var timedOut = false
    var closed = false
    let started = Date()

    // current layout
    var scalars: [Unicode.Scalar] = []
    var cells: [CharCell] = []
    var gcells: [GCell] = []
    var lines: [LineInfo] = []
    var runs: [AXTextRun] = []
    var origin: (x: Float, y: Float) = (0, 0)
    var lineHeightPx: Float = 24
    var maxW: Float = 0
    var anchor = 0
    var focus = 0

    // evidence
    var evidence: [PhaseEvidence] = Array(repeating: PhaseEvidence(), count: phaseSpecs.count)
    var reselects = 0
    var reselectHits = 0
    var measureFailures = 0
    var commitFailures = 0
    var actionsSeen = 0
    var selectionsApplied = 0
    var staleEvents = 0
    var unknownNodeEvents = 0
    var closeCalls = 0
    var cleanupRan = false
    var cleanupLiveNodes: UInt64?
    var cleanupShutdownRC: Int32?
    var closedAt: Date?
    var lastHandle: UInt64 = 0
    var ticks = 0
    var phasesCompleted = 0
    var checks: [HostCheck] = []

    init(bridge: Bridge) { self.bridge = bridge }

    func add(_ name: String, _ ok: Bool, _ detail: String = "") {
        checks.append(HostCheck(name: name, ok: ok, detail: detail))
    }

    // MARK: measurement and commit

    func measure(_ text: String, widthPhys: Float, scale sc: Float) -> TextMeasurement? {
        do {
            return try bridge.measure(MeasureRequest(text: text, scale: sc, maxWidth: widthPhys))
        } catch {
            glog("MEASURE FAILED \(error)")
            measureFailures += 1
            return nil
        }
    }

    func rects(_ a: Int, _ b: Int) -> [Rect] {
        rectsFromCells(gcells, lineTops: lines.map { $0.top }, origin: origin, lh: lineHeightPx, a, b)
    }

    func caret(at idx: Int) -> Rect {
        caretRect(cells: cells, lines: lines, index: idx, origin: origin, lineHeightPx: lineHeightPx, width: max(1, 1.5 * scale))
    }

    /// (run, character-in-run) of a code-point index, the way the committed runs lay out the text. After a trailing
    /// newline the position is the start of the next (empty) run, matching `caretRect`.
    func axPos(_ idx: Int) -> TextSelectionPosition {
        if cells.isEmpty { return TextSelectionPosition(run: firstRunID, character: 0) }
        if idx >= cells.count {
            let last = cells[cells.count - 1]
            if last.lineBreak {
                let k = min(Int(last.line) + 1, runs.count - 1)
                return TextSelectionPosition(run: runs[k].id, character: 0)
            }
            let k = Int(last.line)
            return TextSelectionPosition(run: runs[k].id, character: UInt32(cells.filter { Int($0.line) == k }.count))
        }
        let k = Int(cells[idx].line)
        var first = idx
        while first > 0 && Int(cells[first - 1].line) == k { first -= 1 }
        return TextSelectionPosition(run: runs[k].id, character: UInt32(idx - first))
    }

    struct Rendered { var ok = false; var cacheHit = false; var lineCount = 0; var height: Float = 0; var width: Float = 0; var charCount: UInt32 = 0; var line0Width: Float = 0 }

    /// Measures the current phase's text at its width, rebuilds cells and AX runs, commits one transaction.
    @discardableResult
    func render() -> Rendered {
        var info = Rendered()
        guard let win = bridge.window, phase >= 0 else { return info }
        let spec = phaseSpecs[phase]
        let v = variants[spec.variant]
        scalars = v.scalars
        let s = scale
        lineHeightPx = 24 * s
        origin = (x: 12 * s, y: 12 * s)
        maxW = spec.widthDIP * s
        guard let m = measure(v.text, widthPhys: maxW, scale: s) else { return info }
        var got: [CharCell] = []
        do { got = try bridge.cells(of: m.run) } catch {
            glog("CELLS FAILED \(error)")
            measureFailures += 1
            bridge.release(m.run)
            return info
        }
        cells = got
        gcells = got.map { GCell(line: Int($0.line), x0: $0.x0, x1: $0.x1, isBreak: $0.lineBreak) }
        lines = m.lines
        runs = makeAXTextRuns(text: v.text, measurement: m, cells: got, origin: origin, lineHeightPx: lineHeightPx, firstRunID: firstRunID)
        let n = scalars.count
        anchor = min(anchor, n)
        focus = min(focus, n)
        let nodeBounds = Rect(x: origin.x, y: origin.y, w: maxW, h: max(m.height, lineHeightPx))
        var prims: [Primitive] = [.rect(nodeBounds, color: 0xFFFFFFFF)]
        let lo = min(anchor, focus), hi = max(anchor, focus)
        if lo < hi { for r in rects(lo, hi) { prims.append(.rect(r, color: 0xB4D5FEFF)) } }
        prims.append(.text(m.run, x: origin.x, y: origin.y))
        if lo == hi { prims.append(.rect(caret(at: focus), color: 0x111111FF)) }
        var sem = SemanticNode(role: .textField, label: "SR0 text geometry input", value: v.text,
                               actions: [.focus, .setValue, .setSelection], multiline: true, runs: runs,
                               identifier: "textgeom/input")
        sem.selection = (anchor: axPos(anchor), focus: axPos(focus))
        let node = NodeUpsert(id: 3, order: 1, flags: [.hitTarget, .focusable, .editable], bounds: nodeBounds,
                              primitives: prims, semantic: sem)
        version += 1
        do { try win.commit(Transaction(version: version, focus: 3, upserts: [node])) } catch {
            commitFailures += 1
            glog("COMMIT FAILED v\(version) \(error)")
        }
        bridge.release(m.run)
        info.ok = true
        info.cacheHit = m.cacheHit
        info.lineCount = m.lineCount
        info.height = m.height
        info.width = m.width
        info.charCount = m.charCount
        info.line0Width = m.lines.first?.width ?? 0
        return info
    }

    // MARK: per-phase self-check (host side: the cells, lines and AX runs the renderer returned and we committed)

    func selfCheck(_ v: Variant, charCount: UInt32) -> [String] {
        var fails: [String] = []
        let text = v.text
        let utf8 = Array(text.utf8)
        if cells.count != v.scalars.count { fails.append("cells \(cells.count) != chars \(v.scalars.count)") }
        if Int(charCount) != v.scalars.count { fails.append("char_count \(charCount) != \(v.scalars.count)") }
        // lines partition the text (the newline belongs to the line it ends)
        var pos: UInt32 = 0
        for (k, l) in lines.enumerated() {
            if l.utf8Start != pos { fails.append("line \(k) starts at \(l.utf8Start), expected \(pos)"); break }
            pos = l.utf8Start + l.utf8Len
        }
        if Int(pos) != utf8.count { fails.append("lines cover \(pos) of \(utf8.count) bytes") }
        // every cell: offset/length of its code point, inside its line
        var off: UInt32 = 0
        for (i, c) in cells.enumerated() where i < v.scalars.count {
            let len = UInt32(String(v.scalars[i]).utf8.count)
            if c.utf8Offset != off || c.utf8Len != len { fails.append("cell \(i) offset/len \(c.utf8Offset)/\(c.utf8Len), expected \(off)/\(len)"); break }
            let li = Int(c.line)
            if li >= lines.count || off < lines[li].utf8Start || off >= lines[li].utf8Start + lines[li].utf8Len {
                fails.append("cell \(i) (byte \(off)) is outside its line \(c.line)"); break
            }
            off += len
        }
        // line widths are the largest cell right edge on the line
        for k in 0..<lines.count {
            let mx = cells.filter { Int($0.line) == k }.map { $0.x1 }.max() ?? 0
            if abs(mx - lines[k].width) > 0.01 { fails.append("line \(k) width \(lines[k].width) vs cells \(mx)"); break }
        }
        // newline cells: one per '\n', zero width, at the end of the line they terminate, the last cell of that line
        let newlines = v.scalars.filter { $0 == "\n" }.count
        let breaks = cells.enumerated().filter { $0.element.lineBreak }
        if breaks.count != newlines { fails.append("line-break cells \(breaks.count) != newlines \(newlines)") }
        for (i, c) in breaks {
            if i >= v.scalars.count || v.scalars[i] != "\n" { fails.append("line-break cell \(i) is not a newline"); break }
            if c.x0 != c.x1 { fails.append("line-break cell \(i) is not zero width"); break }
            if Int(c.line) < lines.count && abs(c.x0 - lines[Int(c.line)].width) > 0.01 { fails.append("line-break cell \(i) not at the end of its line"); break }
            if i + 1 < cells.count && cells[i + 1].line == c.line { fails.append("line-break cell \(i) is not the last cell of its line"); break }
        }
        // word-start flags equal the independent rule
        let ws = wordStartsExpected(v.scalars)
        for (i, c) in cells.enumerated() where i < ws.count && c.wordStart != ws[i] { fails.append("word start flag differs at \(i)"); break }
        // AX runs: one per visual line, text/lengths/positions/widths/word starts equal the cells
        if runs.count != lines.count { fails.append("runs \(runs.count) != lines \(lines.count)") }
        if runs.map({ $0.text }).joined() != text { fails.append("run texts do not concatenate to the text") }
        var base = 0
        for (k, r) in runs.enumerated() where k < lines.count {
            let lc = cells.filter { Int($0.line) == k }
            if r.charLengths.count != lc.count || r.charPositions.count != lc.count || r.charWidths.count != lc.count {
                fails.append("run \(k) array lengths"); break
            }
            for (i, c) in lc.enumerated() {
                if r.charPositions[i] != c.x0 || abs(r.charWidths[i] - (c.x1 - c.x0)) > 0.001 || UInt32(r.charLengths[i]) != c.utf8Len {
                    fails.append("run \(k) char \(i) differs from its cell"); break
                }
            }
            let wantWords = lc.enumerated().filter { $0.element.wordStart }.map { UInt8($0.offset) }
            if r.wordStarts != wantWords { fails.append("run \(k) word starts \(r.wordStarts) != \(wantWords)") }
            if abs(r.bounds.x - origin.x) > 0.01 || abs(r.bounds.y - (origin.y + lines[k].top)) > 0.01
                || abs(r.bounds.w - lines[k].width) > 0.01 || abs(r.bounds.h - lineHeightPx) > 0.01 {
                fails.append("run \(k) bounds \(fmtRect(r.bounds))"); break
            }
            base += lc.count
        }
        if base != cells.count && runs.count == lines.count { fails.append("runs hold \(base) chars, cells \(cells.count)") }
        // the sample ranges: painted (cells) rectangles equal the published (AX runs) rectangles
        for (i, sm) in v.samples.enumerated() {
            let e = maxRectErr(rects(sm.a, sm.b), rectsFromRuns(runs, sm.a, sm.b))
            if e > 0.01 { fails.append("range \(i) cells vs AX runs err \(e)") }
        }
        return fails
    }

    // MARK: phases

    func logSession(_ win: BridgeWindow) {
        glog("START pid=\(ProcessInfo.processInfo.processIdentifier) abi=\(bridge.info.abi_major).\(bridge.info.abi_minor) fn_count=\(bridge.info.fn_count) stats_size=\(bridge.info.stats_size) scale=\(f3(scale)) dpi=\(f3(scale * 96))")
        for (vi, v) in variants.enumerated() {
            let ws = wordStartsExpected(v.scalars)
            let interior = ws.enumerated().filter { $0.offset > 0 && $0.element }.count
            let nextWord = ws.enumerated().first(where: { $0.offset > 0 && $0.element })?.offset ?? v.scalars.count
            let firstWord = String(String.UnicodeScalarView(v.scalars[0..<nextWord]))
            glog("VARIANT \(vi) name=\(v.name) chars=\(v.scalars.count) bytes=\(v.text.utf8.count) utf16=\(v.text.utf16.count) words=\(interior) firstword=\(esc(firstWord)) text=\(esc(v.text))")
            for (i, sm) in v.samples.enumerated() {
                glog("RANGE \(vi) \(i) a=\(sm.a) b=\(sm.b) label=\(esc(sm.label)) text=\(esc(String(String.UnicodeScalarView(v.scalars[sm.a..<sm.b]))))")
            }
            for c in v.carets { glog("CARETIDX \(vi) name=\(c.name) idx=\(c.idx)") }
            for s in v.selects {
                glog("SELECT \(vi) name=\(s.name) a=\(s.a) b=\(s.b) text=\(esc(String(String.UnicodeScalarView(v.scalars[s.a..<s.b]))))")
            }
        }
        glog("PHASES \(phaseSpecs.map { "\($0.variant):\(Int($0.widthDIP))" }.joined(separator: ","))")
    }

    func startPhase(_ p: Int) {
        phase = p
        phaseReady = false
        let spec = phaseSpecs[p]
        let v = variants[spec.variant]
        let vi = spec.variant
        let info = render()
        evidence[p].expectHit = spec.expectHit
        guard info.ok else {
            glog("PHASE \(p) render failed")
            return
        }
        evidence[p].rendered = true
        evidence[p].cacheHit = info.cacheHit
        // physical-px commit: the same text at scale 1 and the logical width must give lines that are exactly the
        // physical lines divided by the scale (shaping is in logical px; every output is logical x scale)
        let s = scale
        var physOK = false
        var physDetail = "scale-1 measure failed"
        var expectPhys: Float = 0
        if let m1 = measure(v.text, widthPhys: spec.widthDIP, scale: 1) {
            var diffs: [String] = []
            if m1.lineCount != info.lineCount { diffs.append("lines \(m1.lineCount) vs \(info.lineCount)") }
            else {
                for k in 0..<m1.lineCount {
                    if m1.lines[k].utf8Start != lines[k].utf8Start || m1.lines[k].utf8Len != lines[k].utf8Len { diffs.append("line \(k) bytes differ") }
                    let want = m1.lines[k].width * s
                    if abs(want - lines[k].width) > 0.02 { diffs.append("line \(k) width \(f3(lines[k].width)) vs logical*scale \(f3(want))") }
                }
            }
            physOK = diffs.isEmpty
            expectPhys = (m1.lines.first?.width ?? 0) * s
            physDetail = "width=\(Int(spec.widthDIP)) scale=\(f3(s)) lines=\(info.lineCount) line0_phys=\(f3(info.line0Width)) expect_phys=\(f3(expectPhys))" + (diffs.isEmpty ? "" : " DIFFS \(diffs.joined(separator: "; "))")
            bridge.release(m1.run)
        }
        evidence[p].physOK = physOK
        evidence[p].physDetail = physDetail
        let fails = selfCheck(v, charCount: info.charCount)
        evidence[p].selfOK = fails.isEmpty
        evidence[p].selfDetail = "chars=\(cells.count) lines=\(lines.count) runs=\(runs.count) breaks=\(cells.filter { $0.lineBreak }.count)" + (fails.isEmpty ? "" : " FAILS \(fails.joined(separator: "; "))")

        glog("COMMIT phase=\(p) version=\(version) variant=\(vi) width=\(Int(spec.widthDIP)) scale=\(f3(s)) dpi=\(f3(s * 96)) maxw_phys=\(f3(maxW)) lines=\(info.lineCount) chars=\(cells.count) cache=\(info.cacheHit ? "hit" : "miss") line0_w_phys=\(f3(info.line0Width)) expect_phys=\(f3(expectPhys))")
        for (i, sm) in v.samples.enumerated() {
            glog("RECT phase=\(p) r=\(i) kind=cells rects=\(fmtRects(rects(sm.a, sm.b)))")
            glog("RECT phase=\(p) r=\(i) kind=ax rects=\(fmtRects(rectsFromRuns(runs, sm.a, sm.b)))")
        }
        glog("CARET phase=\(p) idx=\(focus) rect=\(fmtRect(caret(at: focus)))")
        for c in v.carets { glog("CARETX phase=\(p) name=\(c.name) idx=\(c.idx) rect=\(fmtRect(caret(at: c.idx)))") }
        // per visual line (first code point, code-point count, expected text and rectangle): the multi-paragraph variant
        var firstIdx = 0
        for k in 0..<lines.count {
            let cnt = cells.filter { Int($0.line) == k }.count
            let lineText = runs[k].text
            let r = Rect(x: origin.x, y: origin.y + lines[k].top, w: lines[k].width, h: lineHeightPx)
            glog("LINE phase=\(p) k=\(k) first=\(cnt > 0 ? firstIdx : -1) count=\(cnt) rect=\(fmtRect(r)) text=\(esc(lineText))")
            firstIdx += cnt
        }
        for (i, c) in cells.enumerated() where c.lineBreak {
            let top = lines[Int(c.line)].top
            glog("NL phase=\(p) idx=\(i) line=\(c.line) rect=\(fmtRect(Rect(x: origin.x + c.x0, y: origin.y + top, w: 0, h: lineHeightPx)))")
        }
        glog("SELFCHECK phase=\(p) \(evidence[p].selfDetail) pass=\(evidence[p].selfOK)")
        glog("PHYS phase=\(p) \(physDetail) pass=\(physOK)")
        phaseReady = true
        glog("PHASE \(p) ready")
    }

    func ackPath(_ p: Int) -> String { runDir + "/ack-\(p).txt" }

    /// Idempotent: called from display ticks and from a 50 ms main-queue timer.
    func pump() {
        if finishing || closed { return }
        if Date().timeIntervalSince(started) > timeoutSeconds {
            glog("TIMEOUT after \(timeoutSeconds)s at phase \(phase)")
            timedOut = true
            finishing = true
            bridge.requestQuit()
            return
        }
        guard phaseReady, phase >= 0 else { return }
        if FileManager.default.fileExists(atPath: ackPath(phase)) {
            phaseReady = false
            phasesCompleted += 1
            if phase + 1 < phaseSpecs.count {
                startPhase(phase + 1)
            } else {
                glog("DONE phases=\(phaseSpecs.count)")
                finishing = true
                bridge.requestQuit()
            }
        }
    }

    func armTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            pump()
            if !closed { armTimer() }
        }
    }

    // MARK: events

    func handle(_ ev: BridgeEvent) {
        if ev.window != 0, ev.window != bridge.window?.handle { staleEvents += 1; return }
        switch ev.kind {
        case .axAction:
            if ev.node != 3 { unknownNodeEvents += 1; glog("EVENT unknown node=\(ev.node)"); return }
            if ev.axAction == .setSelection {
                actionsSeen += 1
                glog("ACTION setSelection node=\(ev.node) anchor=\(ev.i0) focus=\(ev.i1) snapshot=\(ev.snapshot) current=\(version)")
                applySelection(Int(ev.i0), Int(ev.i1))
            } else {
                glog("ACTION other action=\(ev.action) node=\(ev.node)")
            }
        case .windowMetrics:
            if ev.x > 0, ev.x != scale {
                glog("SCALE changed \(f3(scale)) -> \(f3(ev.x)); expectations of this run are void")
                scale = ev.x
                render()
            }
        default:
            break
        }
    }

    func applySelection(_ a: Int, _ f: Int) {
        let n = scalars.count
        anchor = max(0, min(a, n))
        focus = max(0, min(f, n))
        let info = render()
        reselects += 1
        if info.ok && info.cacheHit { reselectHits += 1 }
        selectionsApplied += 1
        glog("APPLY select anchor=\(anchor) focus=\(focus) phase=\(phase) cache=\(info.cacheHit ? "hit" : "miss")")
        let lo = min(anchor, focus), hi = max(anchor, focus)
        glog("SELRECT phase=\(phase) anchor=\(anchor) focus=\(focus) rects=\(fmtRects(rects(lo, hi)))")
        glog("CARET phase=\(phase) idx=\(focus) rect=\(fmtRect(caret(at: focus)))")
    }

    func onClosed() {
        closeCalls += 1
        closed = true
        closedAt = Date()
        glog("WINDOW_CLOSED")
        let b = bridge
        DispatchQueue.main.async { [self] in
            cleanupRan = true
            cleanupLiveNodes = b.stats().live_nodes
            do { try b.shutdownComplete(); cleanupShutdownRC = 0 }
            catch BridgeError.status(let rc, _) { cleanupShutdownRC = rc }
            catch { cleanupShutdownRC = -999 }
        }
    }

    // MARK: summary

    func finish(runResult: String) -> Int32 {
        let st = bridge.stats()
        let b = bridge
        add("startup validation", b.info.abi_major == 0 && b.info.abi_minor == 6 && b.info.fn_count == 16 && b.info.stats_size == 200,
            "abi \(b.info.abi_major).\(b.info.abi_minor) fn_count=\(b.info.fn_count) stats_size=\(b.info.stats_size)")
        add("run returned ok", runResult == "ok", runResult)
        add("all phases ran and acknowledged", phasesCompleted == phaseSpecs.count && !timedOut, "completed=\(phasesCompleted)/\(phaseSpecs.count) timed_out=\(timedOut)")
        let missing = evidence.enumerated().filter { !$0.element.rendered }.map { $0.offset }
        add("every phase measured, laid out and committed", missing.isEmpty && measureFailures == 0 && commitFailures == 0,
            "not_rendered=\(missing) measure_failures=\(measureFailures) commit_failures=\(commitFailures)")
        let cacheBad = evidence.enumerated().filter { $0.element.rendered && $0.element.cacheHit != $0.element.expectHit }.map { "phase\($0.offset) hit=\($0.element.cacheHit) want=\($0.element.expectHit)" }
        add("measurement cache: miss on a new (text, width), hit on repeat; re-measure after a selection hits",
            cacheBad.isEmpty && reselects == reselectHits,
            "wrong=\(cacheBad) reselects=\(reselects) reselect_hits=\(reselectHits) renderer measure_calls=\(st.measure_calls) cache_hits=\(st.measure_cache_hits)")
        let physBad = evidence.enumerated().filter { $0.element.rendered && !$0.element.physOK }.map { "phase\($0.offset): \($0.element.physDetail)" }
        add("physical-px commit (logical x scale, per phase)", physBad.isEmpty && !evidence.isEmpty, physBad.isEmpty ? "all \(phaseSpecs.count) phases" : physBad.joined(separator: " ; "))
        let selfBad = evidence.enumerated().filter { $0.element.rendered && !$0.element.selfOK }.map { "phase\($0.offset): \($0.element.selfDetail)" }
        add("cells, lines, newline cells and AX runs self-consistent (per phase)", selfBad.isEmpty, selfBad.isEmpty ? "all \(phaseSpecs.count) phases" : selfBad.joined(separator: " ; "))
        add("AX set-selection requests received and applied", actionsSeen >= 1 && selectionsApplied == actionsSeen, "received=\(actionsSeen) applied=\(selectionsApplied)")
        add("no stale or unknown-node events", staleEvents == 0 && unknownNodeEvents == 0, "stale=\(staleEvents) unknown=\(unknownNodeEvents) rust_dropped_stale=\(st.events_dropped_stale)")
        add("no thread violations or host panics", st.thread_violations == 0 && st.host_panics == 0, "thread_violations=\(st.thread_violations) host_panics=\(st.host_panics)")
        add("commits all accepted (no injected faults here)", st.commits_rejected == 0 && st.commits_accepted >= UInt64(phaseSpecs.count),
            "accepted=\(st.commits_accepted) rejected=\(st.commits_rejected) deferred_in_ime=\(st.commits_deferred)")
        add("window_closed delivered once", b.windowClosedCalls == 1 && closeCalls == 1, "calls=\(b.windowClosedCalls)")
        add("live nodes zero after teardown", cleanupLiveNodes == 0 && st.live_nodes == 0, "at cleanup=\(cleanupLiveNodes.map { String($0) } ?? "none") after run=\(st.live_nodes)")
        let sinceClose = closedAt.map { Date().timeIntervalSince($0) } ?? 0
        add("post-close pump ended by swr_shutdown_complete, not the timeout", cleanupRan && cleanupShutdownRC == 0 && st.post_close_timeouts == 0 && sinceClose < 4.5,
            "shutdown=\(statusName(cleanupShutdownRC ?? -99)) timeouts=\(st.post_close_timeouts) run returned \(String(format: "%.2f", sinceClose))s after window_closed")
        glog("renderer stats: paints=\(st.paints) commits=\(st.commits_accepted) measure_calls=\(st.measure_calls) cache_hits=\(st.measure_cache_hits) events=\(st.events_pushed) ax_enqueued=\(st.ax_actions_enqueued) ax_rejected=\(st.ax_actions_rejected) live_nodes=\(st.live_nodes) ticks=\(ticks)")
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
    let geo = Geo(bridge: bridge)
    bridge.onWindowClosed = { geo.onClosed() }
    var runResult = "ok"

    bridge.onReady = { win in
        do {
            let m = try win.metrics()
            geo.scale = m.scale
            geo.lastHandle = win.handle
            glog("ready: window=\(String(win.handle, radix: 16)) client=\(m.width)x\(m.height)px scale=\(m.scale)")
        } catch {
            glog("metrics failed: \(error)")
        }
        // Like run 4, the caret starts inside the text (at "beta"), so phase 0 has a degenerate selection to read back.
        if let c = geo.variants[0].carets.first { geo.anchor = c.idx; geo.focus = c.idx }
        geo.logSession(win)
        geo.startPhase(0)
        try? win.requestTicks(true)
        geo.armTimer()
    }
    bridge.onEvent = { ev in geo.handle(ev) }
    bridge.onTick = { _, _ in
        geo.ticks += 1
        geo.pump()
    }

    do {
        try bridge.run(title: "SwiftRight TextGeom06", width: 640, height: 480)
    } catch {
        runResult = "run failed: \(error)"
    }
    exit(geo.finish(runResult: runResult))
} catch BridgeError.startup(let message) {
    glog(message)
    exit(78)
} catch {
    glog("SWR_STARTUP_ERROR: \(error)")
    exit(78)
}
