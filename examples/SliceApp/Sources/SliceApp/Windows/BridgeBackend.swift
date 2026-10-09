#if os(Windows)
import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// BridgeBackend (Windows): the runtime's commit sink -> ABI v0 transactions, and bridge events -> runtime
// actions. Ported from probes/sr0-s/fresh-on-bridge (BridgeBackend.swift) with the fixture instrumentation
// removed. Failures are written to stderr; nothing is silently dropped.
//
// Coordinates: runtime frames are logical points with the client top-left at 0,0. ABI geometry is physical
// pixels, so the runtime's pixelFrame is used directly. Each runtime node id maps to a stable non-zero bridge
// id (0 = window root). Each text node reserves an `axTextRunBlockSize` id block so AX text-run ids never collide.

enum SliceStyle {
    static let fontFamily = "Segoe UI"
    static let fontSizeDIP: Float = 16
    static let lineHeightDIP: Float = 24
    static let textColor: UInt32 = 0x1F1F1FFF
    static let labelColor: UInt32 = 0xFFFFFFFF
    static let buttonFill: UInt32 = 0x2563EBFF
    static let fieldFill: UInt32 = 0xFFFFFFFF
    static let fieldBorder: UInt32 = 0x888888FF
    static let caretColor: UInt32 = 0x111111FF
    /// The runtime sizes a TextField and a Button to their content only (no padding modifier for these), so the
    /// backend draws the box with these insets.
    static let fieldInsetX: Float = 6
    static let buttonInsetX: Float = 12
    static let buttonInsetY: Float = 6
}

func reportFailure(_ message: String) {
    fputs("SLICE_RUNTIME_ERROR: \(message)\n", stderr)
    fflush(stderr)
}

/// Logical text measurement through the bridge. Synchronous; returned run handles are released by the caller.
@MainActor
final class BridgeTextMeasurer: TextMeasurer {
    let bridge: Bridge
    let scale: Float

    init(bridge: Bridge, scale: Float) {
        self.bridge = bridge
        self.scale = scale
    }

    func measure(_ request: TextMeasureRequest) -> SwiftRightRuntime.TextMeasurement {
        guard !request.text.isEmpty else {
            return SwiftRightRuntime.TextMeasurement(size: .zero, baseline: 0, lineCount: 0)
        }
        let maxWidth = Float(request.proposedWidth ?? 0) * scale
        do {
            let m = try bridge.measure(MeasureRequest(
                text: request.text, fontFamily: SliceStyle.fontFamily,
                fontSize: SliceStyle.fontSizeDIP, lineHeight: SliceStyle.lineHeightDIP,
                scale: scale, maxWidth: maxWidth))
            _ = bridge.release(m.run)
            return SwiftRightRuntime.TextMeasurement(
                size: LayoutSize(width: CGFloat(m.width / scale), height: CGFloat(m.height / scale)),
                baseline: CGFloat(m.firstBaseline / scale),
                lineCount: m.lineCount)
        } catch {
            reportFailure("measure failed for \(request.text.count) characters: \(error)")
            // Deterministic fallback so layout still completes.
            let lines = max(1, request.text.split(separator: " ").count)
            return SwiftRightRuntime.TextMeasurement(
                size: LayoutSize(width: CGFloat(request.text.count) * 8, height: CGFloat(lines) * 24),
                baseline: 18, lineCount: lines)
        }
    }
}

struct FieldGeometry {
    let origin: (x: Float, y: Float)
    let cells: [CharCell]
    let lines: [LineInfo]
    let lineHeightPx: Float
}

/// Pulls the first UUID out of a runtime node id (ForEach keyed segments render as "[<uuid>]").
func rowUUID(in runtimeID: String) -> UUID? {
    for part in runtimeID.split(separator: "[").dropFirst() {
        if let end = part.firstIndex(of: "]"), let uuid = UUID(uuidString: String(part[..<end])) {
            return uuid
        }
    }
    return nil
}

/// Bridge UTF-16 span <-> runtime range (both are UTF-16 units; an inverted span is empty).
func runtimeRange(_ span: UTF16Span) -> UTF16Range {
    UTF16Range(location: Int(span.start), length: max(0, Int(span.end) - Int(span.start)))
}

func bridgeSpan(_ range: UTF16Range) -> UTF16Span {
    UTF16Span(start: UInt32(range.location), end: UInt32(range.location + range.length))
}

@MainActor
final class BridgeBackend {
    let bridge: Bridge
    let model: EditorModel
    private(set) var window: BridgeWindow?
    private(set) var graph: Graph?
    private var measurer: BridgeTextMeasurer?
    private var scale: Float = 1
    private var version: UInt64 = 0
    private var nextID: UInt64 = 1
    private var idByKey: [String: UInt64] = [:]
    private var liveParent: [UInt64: UInt64] = [:]
    private var dirty = false
    private var isClosed = false

    // Maps rebuilt on every commit from the resolved tree.
    private var textFieldByRow: [UUID: UInt64] = [:]
    private var rowByTextField: [UInt64: UUID] = [:]
    private var runtimeFieldByRow: [UUID: String] = [:]
    private var buttonRuntimeID: [UInt64: String] = [:]
    private var fieldGeometry: [UUID: FieldGeometry] = [:]
    private var focusedRow: UUID?
    private var focusTarget: UInt64 = 0
    /// Bridge id of a button focused through AX/UIA SetFocus (Narrator item navigation). Cleared by any row focus.
    private var axButtonFocus: UInt64 = 0

    init(bridge: Bridge, model: EditorModel) {
        self.bridge = bridge
        self.model = model
    }

    // MARK: lifecycle (UI thread)

    func ready(_ win: BridgeWindow) {
        window = win
        do {
            let metrics = try win.metrics()
            scale = metrics.scale
            let meas = BridgeTextMeasurer(bridge: bridge, scale: scale)
            measurer = meas
            let g = Graph(EditorScreen(model: model), measurer: meas, scale: CGFloat(scale))
            g.rootProposal = proposal(width: metrics.width, height: metrics.height)
            g.commitSink = { [weak self] record in
                MainActor.assumeIsolated { self?.commit(record) }
            }
            graph = g
            model.onMutate = { [weak self] in
                MainActor.assumeIsolated { self?.dirty = true }
            }
            g.flush()
        } catch {
            reportFailure("ready failed: \(error)")
        }
    }

    /// Window closed. The renderer already refuses commits and frees its own tree. The host runs the runtime
    /// teardown (disappear actions, task cancel, tree release), drops its node ledger, then completes shutdown
    /// so the bridge can finish its post-close pump.
    func closed() {
        isClosed = true
        graph?.tearDown()
        window = nil
        graph = nil
        measurer = nil
        liveParent = [:]
        do {
            try bridge.shutdownComplete()
        } catch {
            reportFailure("shutdown_complete failed: \(error)")
        }
    }

    private func proposal(width: UInt32, height: UInt32) -> ProposedViewSize {
        ProposedViewSize(width: CGFloat(width) / CGFloat(scale), height: CGFloat(height) / CGFloat(scale))
    }

    /// Runs the runtime flush when a model mutation is pending.
    private func flushIfDirty() {
        guard dirty, let graph else { return }
        dirty = false
        graph.flush()
    }

    // MARK: runtime -> bridge (commit)

    private func bridgeID(_ key: String) -> UInt64 {
        if let id = idByKey[key] { return id }
        let id = nextID
        nextID += 1
        idByKey[key] = id
        return id
    }

    private func runBlock(_ key: String) -> UInt64 {
        if let base = idByKey["\(key)#runs"] { return base }
        let base = nextID
        nextID += axTextRunBlockSize
        idByKey["\(key)#runs"] = base
        return base
    }

    private func inflate(_ r: Rect, dx: Float, dy: Float) -> Rect {
        Rect(x: r.x - dx, y: r.y - dy, w: r.w + 2 * dx, h: r.h + 2 * dy)
    }

    private func measure(_ text: String, color: UInt32, maxWidth: Float, into releasable: inout [TextRunHandle]) -> SwiftRightBridge.TextMeasurement? {
        do {
            let m = try bridge.measure(MeasureRequest(
                text: text, fontFamily: SliceStyle.fontFamily, color: color,
                fontSize: SliceStyle.fontSizeDIP, lineHeight: SliceStyle.lineHeightDIP,
                scale: scale, maxWidth: maxWidth))
            releasable.append(m.run)
            return m
        } catch {
            reportFailure("draw measure failed: \(error)")
            return nil
        }
    }

    /// Converts one commit record into one ABI transaction. Full upsert of the resolved tree each time;
    /// removes are the top-most ids that left the tree. A nil root (runtime teardown) sends nothing.
    func commit(_ record: CommitRecord) {
        guard let window, !isClosed else { return }
        guard let root = record.root else {
            liveParent = [:]
            buttonRuntimeID = [:]
            fieldGeometry = [:]
            return
        }
        textFieldByRow = [:]
        rowByTextField = [:]
        runtimeFieldByRow = [:]
        buttonRuntimeID = [:]
        fieldGeometry = [:]
        focusedRow = record.focused.flatMap(rowUUID(in:))

        var upserts: [NodeUpsert] = []
        var parents: [UInt64: UInt64] = [:]
        var releasable: [TextRunHandle] = []
        walk(root, parent: 0, order: 0, insideAffordance: false, parentKind: "",
             upserts: &upserts, parents: &parents, releasable: &releasable)

        if axButtonFocus != 0, parents[axButtonFocus] == nil { axButtonFocus = 0 }
        focusTarget = axButtonFocus != 0 ? axButtonFocus : (focusedRow.flatMap { textFieldByRow[$0] } ?? 0)
        var removes: [UInt64] = []
        for (id, parent) in liveParent where parents[id] == nil {
            if parent == 0 || parents[parent] != nil { removes.append(id) }
        }

        version += 1
        let transaction = Transaction(version: version, focus: focusTarget, upserts: upserts, removes: removes)
        do {
            try window.commit(transaction)
            liveParent = parents
        } catch {
            reportFailure("commit v\(version) rejected: \(error)")
        }
        // The renderer keeps what it needs from the commit; the owner frees its run handles now.
        for handle in releasable { _ = bridge.release(handle) }
    }

    private func buttonIdentifier(label: String, runtimeID: String) -> String {
        let slug = label.lowercased().replacingOccurrences(of: " ", with: "-")
        if let row = rowUUID(in: runtimeID) { return "row/\(row.uuidString)/\(slug)" }
        return "toolbar/\(slug)"
    }

    private func walk(_ node: ResolvedNode, parent: UInt64, order: UInt32, insideAffordance: Bool, parentKind: String,
                      upserts: inout [NodeUpsert], parents: inout [UInt64: UInt64], releasable: inout [TextRunHandle]) {
        let id = bridgeID(node.id)
        parents[id] = parent
        let pf = node.pixelFrame
        let s = scale
        var bounds = Rect(x: Float(pf.x), y: Float(pf.y), w: Float(pf.width), h: Float(pf.height))
        var prims: [Primitive] = []
        var semantic: SemanticNode?
        var flags: NodeFlags = []
        var childInside = insideAffordance

        switch node.kind {
        case "Button":
            bounds = inflate(bounds, dx: SliceStyle.buttonInsetX * s, dy: SliceStyle.buttonInsetY * s)
            prims.append(.rect(bounds, color: SliceStyle.buttonFill, radius: 6 * s))
            flags = [.hitTarget, .focusable]
            buttonRuntimeID[id] = node.id
            let label = node.children.first?.text ?? ""
            semantic = SemanticNode(role: .button, label: label, actions: [.invoke, .focus],
                                    identifier: buttonIdentifier(label: label, runtimeID: node.id))
            childInside = true

        case "Text":
            let text = node.text ?? ""
            if !text.isEmpty, let m = measure(text, color: insideAffordance ? SliceStyle.labelColor : SliceStyle.textColor,
                                             maxWidth: Float(pf.width) + 1, into: &releasable) {
                prims.append(.text(m.run, x: Float(pf.x), y: Float(pf.y)))
            }
            if !insideAffordance {
                semantic = SemanticNode(role: .staticText, label: text)
            }

        case "TextField":
            // The displayed text is the committed text with the marked (composing) text inserted.
            let text = node.text ?? ""
            let field = inflate(bounds, dx: SliceStyle.fieldInsetX * s, dy: 0)
            bounds = field
            prims.append(.rect(field, color: SliceStyle.fieldFill, radius: 3 * s,
                               borderColor: SliceStyle.fieldBorder, borderWidth: max(1, s)))
            let origin = (x: Float(pf.x), y: Float(pf.y))
            let lh = SliceStyle.lineHeightDIP * s
            let row = rowUUID(in: node.id)
            if let row {
                runtimeFieldByRow[row] = node.id
            }
            // Every editable node publishes at least one AX text run, empty or not. Empty text has no
            // measurement: it gets the zero-length run at the origin and a degenerate selection at (first run, 0).
            let measurement = text.isEmpty ? nil : measure(text, color: SliceStyle.textColor, maxWidth: 0, into: &releasable)
            let cells = measurement.flatMap { try? bridge.cells(of: $0.run) } ?? []
            let lines = measurement?.lines ?? []
            if let m = measurement {
                prims.append(.text(m.run, x: origin.x, y: origin.y))
            }
            // Caret or selection end, in displayed text (the runtime's TextInputState).
            let caretEnd = node.selection.map { $0.location + $0.length } ?? text.utf16.count
            let caretIndex = min(caretEnd, cells.count)
            if let marked = node.marked, marked.length > 0 {
                let from = min(marked.location, cells.count)
                let to = min(marked.location + marked.length, cells.count)
                if to > from {
                    let thickness = max(1, s)
                    let x0 = origin.x + cells[from].x0
                    let x1 = origin.x + cells[to - 1].x1
                    let y = origin.y + Float(Int(cells[from].line) + 1) * lh - thickness
                    prims.append(.rect(Rect(x: x0, y: y, w: max(1, x1 - x0), h: thickness), color: SliceStyle.caretColor))
                }
            }
            if let row, row == focusedRow {
                let caret = caretRect(cells: cells, lines: lines, index: caretIndex, origin: origin,
                                      lineHeightPx: lh, width: max(1, 1.5 * s))
                prims.append(.rect(caret, color: SliceStyle.caretColor))
            }
            let runBase = runBlock(node.id)
            var runs: [AXTextRun] = []
            do {
                runs = try makeAXTextRunsChecked(text: text, measurement: measurement, cells: cells, origin: origin,
                                                 lineHeightPx: lh, firstRunID: runBase)
            } catch {
                reportFailure("text runs for node \(node.id): \(error)")
            }
            var selection: (anchor: TextSelectionPosition, focus: TextSelectionPosition)?
            if !runs.isEmpty {
                let line = caretIndex < cells.count ? Int(cells[caretIndex].line) : Int(cells.last?.line ?? 0)
                let inLine = cells.prefix(caretIndex).filter { Int($0.line) == line }.count
                let position = TextSelectionPosition(run: runBase + UInt64(min(line, runs.count - 1)), character: UInt32(inLine))
                selection = (anchor: position, focus: position)
            }
            if let row {
                fieldGeometry[row] = FieldGeometry(origin: origin, cells: cells, lines: lines, lineHeightPx: lh)
            }
            if let row {
                textFieldByRow[row] = id
                rowByTextField[id] = row
                semantic = SemanticNode(role: .textField, label: "", value: text,
                                        actions: [.focus, .setValue, .setSelection], runs: runs, selection: selection,
                                        identifier: "row/\(row.uuidString)/field")
            }
            flags = [.hitTarget, .focusable, .editable]

        case "List":
            semantic = SemanticNode(role: .list)

        default:
            // Direct children of a List are its rows.
            if parentKind == "List", rowUUID(in: node.id) != nil {
                semantic = SemanticNode(role: .listItem)
            }
        }

        upserts.append(NodeUpsert(id: id, parent: parent, order: order, flags: flags, bounds: bounds,
                                  primitives: prims, semantic: semantic))
        for (index, child) in node.children.enumerated() {
            walk(child, parent: id, order: UInt32(index), insideAffordance: childInside, parentKind: node.kind,
                 upserts: &upserts, parents: &parents, releasable: &releasable)
        }
    }

    // MARK: bridge events -> runtime (UI thread)

    func handle(_ ev: BridgeEvent) {
        guard let kind = ev.kind else { return }
        switch kind {
        case .axAction:
            switch ev.axAction {
            case .invoke?:
                invoke(node: ev.node)
            case .focus?:
                if let row = rowByTextField[ev.node] { focusRow(row) }
                else if buttonRuntimeID[ev.node] != nil { axButtonFocus = ev.node; dirty = true }
            case .setValue?:
                if let row = rowByTextField[ev.node] {
                    model.editText(row, ev.text)
                    placeCaretAtEnd(row)
                }
            case .setSelection?, nil:
                break
            }
        case .pointer:
            if ev.action == 1 {
                if buttonRuntimeID[ev.node] != nil {
                    invoke(node: ev.node)
                } else if let row = rowByTextField[ev.node] {
                    focusRow(row)
                }
            }
        case .windowMetrics:
            applyMetrics(width: ev.i0, height: ev.i1, scale: ev.x)
        case .key:
            if ev.action == 1 { handleKey(name: ev.text, modifiers: ev.modifiers) }
        case .ime, .focus, .modalResult:
            break
        }
        flushIfDirty()
    }

    /// Native key-down. Tab / Shift-Tab move focus through the runtime (CONTRACT section 4). Bridge modifier bits:
    /// 0x1 control, 0x2 alt, 0x4 shift. Any other chord is left to the field.
    private func handleKey(name: String, modifiers: UInt32) {
        guard name == "tab", modifiers & ~0x4 == 0, let graph else { return }
        // Focus leaving a composing field commits its composition (as the IME does on focus loss).
        if let previous = focusedRow, let state = textState(for: previous) { _ = state.unmark() }
        guard graph.moveFocus(forward: modifiers & 0x4 == 0) else { return }
        if let row = focusedRow { placeCaretAtEnd(row) }
        dirty = true
    }

    private func invoke(node: UInt64) {
        guard let runtimeID = buttonRuntimeID[node] else { return }
        _ = graph?.tapButton(runtimeID)
    }

    private func focusRow(_ row: UUID) {
        axButtonFocus = 0
        // Focus leaving a composing field commits its composition (as the IME does on focus loss).
        if let previous = focusedRow, previous != row, let state = textState(for: previous) {
            _ = state.unmark()
        }
        model.setFocus(row)
        placeCaretAtEnd(row)
        dirty = true
    }

    private func placeCaretAtEnd(_ row: UUID) {
        guard let state = textState(for: row) else { return }
        let end = state.display.utf16.count
        _ = state.setSelection(UTF16Range(location: end, length: 0))
    }

    private func applyMetrics(width: Int32, height: Int32, scale newScale: Float) {
        if newScale > 0, abs(newScale - scale) > 0.001 {
            // The runtime fixes its scale at construction; a scale change needs a graph rebuild (not implemented).
            reportFailure("display scale changed to \(newScale); restart required")
        }
        guard width > 0, height > 0 else { return }
        graph?.rootProposal = proposal(width: UInt32(width), height: UInt32(height))
        dirty = true
    }

    // MARK: text store (called from inside native input handling; never pumps)

    /// Runtime text state of a row's TextField, from the last commit's node id.
    func textState(for row: UUID) -> TextInputState? {
        runtimeFieldByRow[row].flatMap { graph?.textInput($0) }
    }

    private func textState(bridgeNode: UInt64) -> TextInputState? {
        rowByTextField[bridgeNode].flatMap { textState(for: $0) }
    }

    /// The bridge flushes the runtime after every text-store call; the commit is presented after the callback unwinds.
    private func flushAfterTextEdit() {
        dirty = true
        flushIfDirty()
    }

    func storeSelection(node: UInt64) -> (range: UTF16Span, reversed: Bool)? {
        guard let state = textState(bridgeNode: node) else { return nil }
        return (bridgeSpan(state.selection), false)
    }

    func storeMarkedRange(node: UInt64) -> UTF16Span? {
        textState(bridgeNode: node)?.markedRange.map(bridgeSpan)
    }

    func storeText(node: UInt64, range: UTF16Span) -> (units: [UInt16], adjusted: UTF16Span)? {
        guard let state = textState(bridgeNode: node) else { return nil }
        let units = Array(state.display.utf16)
        let n = UInt32(units.count)
        let start = min(range.start, n)
        let end = max(start, min(range.end, n))
        return (Array(units[Int(start)..<Int(end)]), UTF16Span(start: start, end: end))
    }

    func storeReplace(node: UInt64, range: UTF16Span?, text: [UInt16]) -> Bool {
        guard let state = textState(bridgeNode: node) else { return false }
        let ok = state.replace(range: range.map(runtimeRange), text: String(decoding: text, as: UTF16.self))
        flushAfterTextEdit()
        return ok
    }

    func storeReplaceAndMark(node: UInt64, range: UTF16Span?, text: [UInt16], newSelection: UTF16Span?) -> Bool {
        guard let state = textState(bridgeNode: node) else { return false }
        let ok = state.replaceAndMark(range: range.map(runtimeRange), text: String(decoding: text, as: UTF16.self),
                                      newSelection: newSelection.map(runtimeRange))
        flushAfterTextEdit()
        return ok
    }

    func storeUnmark(node: UInt64) -> Bool {
        // A no-op when nothing is composing; the renderer treats that as success.
        _ = textState(bridgeNode: node)?.unmark()
        flushAfterTextEdit()
        return true
    }

    func storeCaretBounds(node: UInt64, range: UTF16Span) -> Rect? {
        guard let row = rowByTextField[node], let g = fieldGeometry[row] else { return nil }
        return caretRect(cells: g.cells, lines: g.lines, index: Int(range.start), origin: g.origin,
                         lineHeightPx: g.lineHeightPx, width: 2)
    }
}

/// The bridge's text store. The renderer calls these from inside native input handling; each hops to the
/// backend on the UI thread (the bridge calls them only there).
final class SliceTextStore: TextStore {
    let backend: BridgeBackend

    init(backend: BridgeBackend) {
        self.backend = backend
    }

    func selection(node: SwiftRightBridge.NodeID) -> (range: UTF16Span, reversed: Bool)? {
        MainActor.assumeIsolated { backend.storeSelection(node: node) }
    }

    func markedRange(node: SwiftRightBridge.NodeID) -> UTF16Span? {
        MainActor.assumeIsolated { backend.storeMarkedRange(node: node) }
    }

    func text(node: SwiftRightBridge.NodeID, range: UTF16Span) -> (units: [UInt16], adjusted: UTF16Span)? {
        MainActor.assumeIsolated { backend.storeText(node: node, range: range) }
    }

    func replace(node: SwiftRightBridge.NodeID, range: UTF16Span?, text: [UInt16]) -> Bool {
        MainActor.assumeIsolated { backend.storeReplace(node: node, range: range, text: text) }
    }

    func replaceAndMark(node: SwiftRightBridge.NodeID, range: UTF16Span?, text: [UInt16], newSelection: UTF16Span?) -> Bool {
        MainActor.assumeIsolated { backend.storeReplaceAndMark(node: node, range: range, text: text, newSelection: newSelection) }
    }

    func unmark(node: SwiftRightBridge.NodeID) -> Bool {
        MainActor.assumeIsolated { backend.storeUnmark(node: node) }
    }

    func caretBounds(node: SwiftRightBridge.NodeID, range: UTF16Span) -> Rect? {
        MainActor.assumeIsolated { backend.storeCaretBounds(node: node, range: range) }
    }
}
#endif
