import CSwiftRight
import Foundation

/// Owns every C allocation a request needs, so borrowed pointers stay valid for the
/// whole renderer call and are freed afterwards (the renderer copies what it keeps).
final class Arena {
    private var blocks: [UnsafeMutableRawPointer] = []

    func alloc<T>(_ type: T.Type, count: Int) -> UnsafeMutablePointer<T> {
        let p = UnsafeMutablePointer<T>.allocate(capacity: max(count, 1))
        blocks.append(UnsafeMutableRawPointer(p))
        return p
    }

    func array<T>(_ a: [T]) -> UnsafePointer<T>? {
        if a.isEmpty { return nil }
        let p = alloc(T.self, count: a.count)
        p.initialize(from: a, count: a.count)
        return UnsafePointer(p)
    }

    func string(_ s: String) -> (ptr: UnsafePointer<CChar>?, len: UInt32) {
        let u = Array(s.utf8)
        if u.isEmpty { return (nil, 0) }
        let p = alloc(CChar.self, count: u.count + 1)
        for (i, b) in u.enumerated() { p[i] = CChar(bitPattern: b) }
        p[u.count] = 0
        return (UnsafePointer(p), UInt32(u.count))
    }

    deinit {
        for b in blocks { b.deallocate() }
    }
}

func cRect(_ r: Rect) -> swr_rect { swr_rect(x: r.x, y: r.y, w: r.w, h: r.h) }

func cPrimitive(_ p: Primitive) -> swr_primitive {
    var c = swr_primitive()
    switch p {
    case .rect(let r, let color, let radius, let borderColor, let borderWidth):
        c.kind = 1; c.rect = cRect(r); c.color = color
        c.radius = radius; c.border_color = borderColor; c.border_width = borderWidth
    case .text(let run, let x, let y):
        c.kind = 2; c.text_run = run.raw; c.rect = swr_rect(x: x, y: y, w: 0, h: 0)
    case .image(let id, let r):
        c.kind = 3; c.image_id = id; c.rect = cRect(r)
    case .path:
        c.kind = 4
    case .clipPush(let r):
        c.kind = 5; c.rect = cRect(r)
    case .clipPop:
        c.kind = 6
    case .translatePush(let dx, let dy):
        c.kind = 7; c.m = (1, 0, 0, 1, dx, dy)
    case .translatePop:
        c.kind = 8
    case .underline(let r, let color):
        c.kind = 9; c.rect = cRect(r); c.color = color
    }
    return c
}

func cSemantic(_ s: SemanticNode, _ arena: Arena) -> swr_semantic {
    var c = swr_semantic()
    c.role = s.role.rawValue
    c.actions = s.actions.rawValue
    c.flags = (s.multiline ? 0x2 : 0) | (s.selection != nil ? 0x1 : 0)
    let label = arena.string(s.label)
    c.label = label.ptr; c.label_len = label.len
    let value = arena.string(s.value)
    c.value = value.ptr; c.value_len = value.len
    let identifier = arena.string(s.identifier)
    c.identifier = identifier.ptr; c.identifier_len = identifier.len
    var runs: [swr_ax_text_run] = []
    for r in s.runs {
        var cr = swr_ax_text_run()
        cr.id = r.id
        let t = arena.string(r.text)
        cr.text = t.ptr; cr.text_len = t.len
        cr.char_lengths = arena.array(r.charLengths)
        cr.char_positions = arena.array(r.charPositions)
        cr.char_widths = arena.array(r.charWidths)
        cr.char_count = UInt32(r.charLengths.count)
        cr.word_starts = arena.array(r.wordStarts)
        cr.word_start_count = UInt32(r.wordStarts.count)
        cr.bounds = cRect(r.bounds)
        runs.append(cr)
    }
    c.runs = arena.array(runs)
    c.run_count = UInt32(runs.count)
    if let sel = s.selection {
        c.sel_anchor_run = sel.anchor.run; c.sel_anchor_char = sel.anchor.character
        c.sel_focus_run = sel.focus.run; c.sel_focus_char = sel.focus.character
    }
    return c
}

/// Builds a C transaction in `arena` and returns it. Valid until `arena` dies.
func cTransaction(_ t: Transaction, window: UInt64, arena: Arena) -> swr_transaction {
    var prims: [swr_primitive] = []
    var nodes: [swr_node] = []
    for n in t.upserts {
        var c = swr_node()
        c.id = n.id
        c.parent = n.parent
        c.bounds = cRect(n.bounds)
        c.order = n.order
        c.flags = n.flags.rawValue
        c.prim_offset = UInt32(prims.count)
        c.prim_count = UInt32(n.primitives.count)
        for p in n.primitives { prims.append(cPrimitive(p)) }
        if let s = n.semantic {
            c.has_semantic = 1
            c.semantic = cSemantic(s, arena)
        }
        nodes.append(c)
    }
    var tx = swr_transaction()
    tx.struct_size = UInt32(MemoryLayout<swr_transaction>.size)
    tx.window = window
    tx.version = t.version
    tx.focus = t.focus
    tx.upserts = arena.array(nodes)
    tx.upsert_count = UInt32(nodes.count)
    tx.removes = arena.array(t.removes)
    tx.remove_count = UInt32(t.removes.count)
    tx.primitives = arena.array(prims)
    tx.primitive_count = UInt32(prims.count)
    return tx
}

func decodeEvent(_ e: swr_event) -> BridgeEvent {
    var ev = e
    let bytes: [UInt8] = withUnsafeBytes(of: &ev.text) { Array($0) }
    let used = min(Int(e.text_len), bytes.count)
    var text = "", typed = ""
    if e.kind == 1 {                       // KEY: name then typed char
        let nameLen = min(Int(max(e.i1, 0)), used)
        text = String(decoding: bytes[0..<nameLen], as: UTF8.self)
        typed = String(decoding: bytes[nameLen..<used], as: UTF8.self)
    } else {
        text = String(decoding: bytes[0..<used], as: UTF8.self)
    }
    return BridgeEvent(kindRaw: e.kind, action: e.action, window: e.window, node: e.node,
                       snapshot: e.snapshot, seq: e.seq, arg: e.arg, x: e.x, y: e.y,
                       i0: e.i0, i1: e.i1, modifiers: e.modifiers, text: text, typed: typed)
}

// MARK: helpers for hosts that lay out text

/// Splits a measured run into per-visual-line AccessKit text runs (UTF-8 lengths, line-local
/// positions/widths, word starts). `origin` is the run's top-left in physical window px;
/// run ids are `firstRunID + lineIndex`.
/// Empty text publishes ONE zero-length run (id `firstRunID`) at the origin: accesskit_consumer
/// `supports_text_ranges` needs a text run before an editable node exposes UIA TextPattern.
public func makeAXTextRuns(text: String, measurement m: TextMeasurement, cells: [CharCell],
                           origin: (x: Float, y: Float), lineHeightPx: Float,
                           firstRunID: NodeID) -> [AXTextRun] {
    if cells.isEmpty {
        return [AXTextRun(id: firstRunID, text: "", charLengths: [], charPositions: [],
                          charWidths: [], wordStarts: [],
                          bounds: Rect(x: origin.x, y: origin.y, w: 0, h: lineHeightPx))]
    }
    let utf8 = Array(text.utf8)
    var runs: [AXTextRun] = []
    for (k, line) in m.lines.enumerated() {
        let lineCells = cells.filter { Int($0.line) == k }
        let start = Int(line.utf8Start), end = min(start + Int(line.utf8Len), utf8.count)
        let slice = String(decoding: utf8[start..<max(start, end)], as: UTF8.self)
        var words: [UInt8] = []
        for (i, c) in lineCells.enumerated() where c.wordStart && i < 256 { words.append(UInt8(i)) }
        runs.append(AXTextRun(
            id: firstRunID + UInt64(k),
            text: slice,
            charLengths: lineCells.map { UInt8(clamping: $0.utf8Len) },
            charPositions: lineCells.map { $0.x0 },
            charWidths: lineCells.map { $0.x1 - $0.x0 },
            wordStarts: words,
            bounds: Rect(x: origin.x, y: origin.y + line.top, w: line.width, h: lineHeightPx)))
    }
    return runs
}

/// Window-px caret rectangle before character `index` (or at the end of the text), of the
/// given width, for a run whose top-left is `origin`.
public func caretRect(cells: [CharCell], lines: [LineInfo], index: Int,
                      origin: (x: Float, y: Float), lineHeightPx: Float, width: Float) -> Rect {
    if cells.isEmpty {
        return Rect(x: origin.x, y: origin.y, w: width, h: lineHeightPx)
    }
    let line: Int, x: Float
    if index < cells.count {
        line = Int(cells[index].line); x = cells[index].x0
    } else {
        let last = cells[cells.count - 1]
        line = Int(last.line); x = last.x1
    }
    let top = line < lines.count ? lines[line].top : Float(line) * lineHeightPx
    return Rect(x: origin.x + x, y: origin.y + top, w: width, h: lineHeightPx)
}
