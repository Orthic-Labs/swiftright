import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// BridgeBackend: the runtime's commit sink -> ABI v0 transactions, and bridge events -> runtime actions.
//
// Coordinates: runtime frames are absolute logical points (DIP) with the window client top-left at 0,0.
// ABI geometry is physical pixels = DIP * scale, so the runtime's `pixelFrame` is used directly.
// Node ids: each runtime node id string maps to a stable non-zero bridge id (0 = window root).
// Text runs reserve a 32-id block per node so AX text-run ids never collide with node ids.

enum FreshStyle {
    static let fontFamily = "Segoe UI"
    static let fontSizeDIP: Float = 16
    static let lineHeightDIP: Float = 24
    static let textColor: UInt32 = 0x1F1F1FFF
    static let labelColor: UInt32 = 0xFFFFFFFF
    static let buttonFill: UInt32 = 0x2563EBFF
    static let fieldFill: UInt32 = 0xFFFFFFFF
    static let fieldBorder: UInt32 = 0x888888FF
    static let caretColor: UInt32 = 0x111111FF
    /// Visual padding around runtime frames. The runtime sizes a TextField to its text only and has no
    /// padding modifier for buttons (v0 runtime gap), so the backend draws the box with these insets.
    static let fieldInsetX: Float = 6
    static let buttonInsetX: Float = 12
    static let buttonInsetY: Float = 6
    static let runBlock: UInt64 = 32
}

/// Logical text measurement through the bridge. Synchronous; returned run handles are released at once
/// (the renderer caches shaped runs, so the drawing pass re-measures as a cache hit).
@MainActor
final class BridgeTextMeasurer: TextMeasurer {
    let bridge: Bridge
    let scale: Float
    private(set) var calls = 0
    private(set) var failures = 0
    private(set) var lastError = ""

    init(bridge: Bridge, scale: Float) {
        self.bridge = bridge
        self.scale = scale
    }

    func measure(_ request: TextMeasureRequest) -> SwiftRightRuntime.TextMeasurement {
        calls += 1
        guard !request.text.isEmpty else {
            return SwiftRightRuntime.TextMeasurement(size: .zero, baseline: 0, lineCount: 0)
        }
        let maxWidth = Float(request.proposedWidth ?? 0) * scale
        do {
            let m = try bridge.measure(MeasureRequest(
                text: request.text, fontFamily: FreshStyle.fontFamily,
                fontSize: FreshStyle.fontSizeDIP, lineHeight: FreshStyle.lineHeightDIP,
                scale: scale, maxWidth: maxWidth))
            bridge.release(m.run)
            return SwiftRightRuntime.TextMeasurement(
                size: LayoutSize(width: CGFloat(m.width / scale), height: CGFloat(m.height / scale)),
                baseline: CGFloat(m.firstBaseline / scale),
                lineCount: m.lineCount)
        } catch {
            failures += 1
            lastError = "\(error)"
            // Deterministic fallback so layout still completes; counted as a failure in the self-test.
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

@MainActor
final class BridgeBackend {
    let bridge: Bridge
    let model: RowModel
    let log: EventLog
    private(set) var window: BridgeWindow?
    private(set) var graph: Graph?
    private(set) var measurer: BridgeTextMeasurer?
    private(set) var scale: Float = 1
    private var version: UInt64 = 0
    private var nextID: UInt64 = 1
    private var idByKey: [String: UInt64] = [:]
    private var liveParent: [UInt64: UInt64] = [:]
    private var dirty = false

    // Maps rebuilt on every commit from the resolved tree.
    private var textFieldByRow: [UUID: UInt64] = [:]
    private var rowByTextField: [UInt64: UUID] = [:]
    private var buttonRuntimeID: [UInt64: String] = [:]
    private var fieldGeometry: [UUID: FieldGeometry] = [:]
    private(set) var focusedRow: UUID?
    private(set) var focusTarget: UInt64 = 0

    // Input and renderer bookkeeping (read by the self-test).
    private var caret: [UUID: UTF16Span] = [:]
    private(set) var keystrokes: [String] = []
    private(set) var axInvokes = 0
    private(set) var axFocusEvents = 0
    private(set) var axSetValues = 0
    private(set) var pointerDowns = 0
    private(set) var keyEvents = 0
    private(set) var commitCount = 0
    private(set) var commitErrors: [String] = []
    private(set) var drawFailures = 0
    private(set) var scaleChanges = 0
    private(set) var metricsEvents = 0
    private(set) var lastDrawError = ""

    /// Called after each bridge event and each tick; the self-test advances its stages here.
    var afterInput: (() -> Void)?

    init(bridge: Bridge, model: RowModel, log: EventLog) {
        self.bridge = bridge
        self.model = model
        self.log = log
    }

    // MARK: lifecycle (UI thread)

    func ready(_ win: BridgeWindow) {
        window = win
        do {
            let metrics = try win.metrics()
            scale = metrics.scale
            let meas = BridgeTextMeasurer(bridge: bridge, scale: scale)
            measurer = meas
            let g = Graph(F1Root(model: model), measurer: meas, scale: CGFloat(scale))
            g.rootProposal = proposal(width: metrics.width, height: metrics.height)
            g.commitSink = { [weak self] record in
                MainActor.assumeIsolated { self?.commit(record) }
            }
            graph = g
            model.onMutate = { [weak self] in
                MainActor.assumeIsolated { self?.dirty = true }
            }
            try win.requestTicks(true)
            g.flush()
            log.emit("lifecycle", node: "window", payload: [
                "phase": "ready", "scale": Double(scale), "width_px": Int(metrics.width), "height_px": Int(metrics.height),
            ])
        } catch {
            commitErrors.append("ready: \(error)")
            log.emit("lifecycle", node: "window", payload: ["phase": "ready-failed", "error": "\(error)"])
        }
    }

    func tick() {
        flushIfDirty()
    }

    func closed() {
        window = nil
        log.emit("lifecycle", node: "window", payload: ["phase": "closed"])
    }

    private func proposal(width: UInt32, height: UInt32) -> ProposedViewSize {
        ProposedViewSize(width: CGFloat(width) / CGFloat(scale), height: CGFloat(height) / CGFloat(scale))
    }

    /// Runs the runtime flush when a model mutation is pending. Flush always emits one commit record.
    func flushIfDirty() {
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
        nextID += FreshStyle.runBlock
        idByKey["\(key)#runs"] = base
        return base
    }

    private func inflate(_ r: Rect, dx: Float, dy: Float) -> Rect {
        Rect(x: r.x - dx, y: r.y - dy, w: r.w + 2 * dx, h: r.h + 2 * dy)
    }

    private func measure(_ text: String, color: UInt32, maxWidth: Float, into releasable: inout [TextRunHandle]) -> SwiftRightBridge.TextMeasurement? {
        do {
            let m = try bridge.measure(MeasureRequest(
                text: text, fontFamily: FreshStyle.fontFamily, color: color,
                fontSize: FreshStyle.fontSizeDIP, lineHeight: FreshStyle.lineHeightDIP,
                scale: scale, maxWidth: maxWidth))
            releasable.append(m.run)
            return m
        } catch {
            drawFailures += 1
            lastDrawError = "\(error)"
            return nil
        }
    }

    /// Converts one commit record into one ABI transaction. Full upsert of the resolved tree each time;
    /// removes are the top-most ids that left the tree.
    func commit(_ record: CommitRecord) {
        guard let window, let root = record.root else { return }
        textFieldByRow = [:]
        rowByTextField = [:]
        buttonRuntimeID = [:]
        fieldGeometry = [:]
        focusedRow = record.focused.flatMap(rowUUID(in:))

        var upserts: [NodeUpsert] = []
        var parents: [UInt64: UInt64] = [:]
        var releasable: [TextRunHandle] = []
        walk(root, parent: 0, order: 0, insideAffordance: false, upserts: &upserts, parents: &parents, releasable: &releasable)

        focusTarget = focusedRow.flatMap { textFieldByRow[$0] } ?? 0
        var removes: [UInt64] = []
        for (id, parent) in liveParent where parents[id] == nil {
            if parent == 0 || parents[parent] != nil { removes.append(id) }
        }

        version += 1
        let transaction = Transaction(version: version, focus: focusTarget, upserts: upserts, removes: removes)
        do {
            try window.commit(transaction)
            commitCount += 1
            liveParent = parents
        } catch {
            commitErrors.append("commit v\(version): \(error)")
            log.emit("lifecycle", node: "bridge", payload: ["phase": "commit-rejected", "error": "\(error)"])
        }
        // The renderer keeps what it needs from the commit; the owner frees its run handles now.
        for handle in releasable { bridge.release(handle) }
    }

    private func walk(_ node: ResolvedNode, parent: UInt64, order: UInt32, insideAffordance: Bool,
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
            bounds = inflate(bounds, dx: FreshStyle.buttonInsetX * s, dy: FreshStyle.buttonInsetY * s)
            prims.append(.rect(bounds, color: FreshStyle.buttonFill, radius: 6 * s))
            flags = [.hitTarget, .focusable]
            buttonRuntimeID[id] = node.id
            let label = node.children.first?.text ?? ""
            semantic = SemanticNode(role: .button, label: label, actions: [.invoke, .focus])
            childInside = true

        case "Text":
            let text = node.text ?? ""
            if !text.isEmpty, let m = measure(text, color: insideAffordance ? FreshStyle.labelColor : FreshStyle.textColor,
                                             maxWidth: Float(pf.width) + 1, into: &releasable) {
                prims.append(.text(m.run, x: Float(pf.x), y: Float(pf.y)))
            }
            if !insideAffordance {
                semantic = SemanticNode(role: .staticText, label: text)
            }

        case "TextField":
            let text = node.text ?? ""
            let field = inflate(bounds, dx: FreshStyle.fieldInsetX * s, dy: 0)
            bounds = field
            prims.append(.rect(field, color: FreshStyle.fieldFill, radius: 3 * s,
                               borderColor: FreshStyle.fieldBorder, borderWidth: max(1, s)))
            let origin = (x: Float(pf.x), y: Float(pf.y))
            let lh = FreshStyle.lineHeightDIP * s
            let row = rowUUID(in: node.id)
            var runs: [AXTextRun] = []
            var selection: (anchor: TextSelectionPosition, focus: TextSelectionPosition)?
            let runBase = runBlock(node.id)
            if !text.isEmpty, let m = measure(text, color: FreshStyle.textColor, maxWidth: 0, into: &releasable) {
                let cells = (try? bridge.cells(of: m.run)) ?? []
                prims.append(.text(m.run, x: origin.x, y: origin.y))
                let caretIndex = min(row.map { caretSpan($0, text).end } ?? UInt32(text.utf16.count), UInt32(cells.count))
                if let row, row == focusedRow {
                    let caretRectPx = caretRect(cells: cells, lines: m.lines, index: Int(caretIndex), origin: origin,
                                                lineHeightPx: lh, width: max(1, 1.5 * s))
                    prims.append(.rect(caretRectPx, color: FreshStyle.caretColor))
                }
                runs = makeAXTextRuns(text: text, measurement: m, cells: cells, origin: origin,
                                      lineHeightPx: lh, firstRunID: runBase)
                if !runs.isEmpty {
                    let line = caretIndex < UInt32(cells.count) ? Int(cells[Int(caretIndex)].line) : Int(cells.last?.line ?? 0)
                    let inLine = cells.prefix(Int(caretIndex)).filter { Int($0.line) == line }.count
                    let position = TextSelectionPosition(run: runBase + UInt64(min(line, runs.count - 1)), character: UInt32(inLine))
                    selection = (anchor: position, focus: position)
                }
                if let row {
                    fieldGeometry[row] = FieldGeometry(origin: origin, cells: cells, lines: m.lines, lineHeightPx: lh)
                }
            } else if let row {
                fieldGeometry[row] = FieldGeometry(origin: origin, cells: [], lines: [], lineHeightPx: lh)
            }
            if let row {
                textFieldByRow[row] = id
                rowByTextField[id] = row
                semantic = SemanticNode(role: .textField, label: "Row \(FreshModelSlot.slot(of: row))", value: text,
                                        actions: [.focus, .setValue, .setSelection], runs: runs, selection: selection)
            }
            flags = [.hitTarget, .focusable, .editable]

        default:
            break
        }

        upserts.append(NodeUpsert(id: id, parent: parent, order: order, flags: flags, bounds: bounds,
                                  primitives: prims, semantic: semantic))
        for (index, child) in node.children.enumerated() {
            walk(child, parent: id, order: UInt32(index), insideAffordance: childInside,
                 upserts: &upserts, parents: &parents, releasable: &releasable)
        }
    }

    private func caretSpan(_ row: UUID, _ text: String) -> UTF16Span {
        let count = UInt32(text.utf16.count)
        if let c = caret[row] { return UTF16Span(start: min(c.start, count), end: min(c.end, count)) }
        return UTF16Span(start: count, end: count)
    }

    // MARK: bridge events -> runtime (UI thread)

    func handle(_ ev: BridgeEvent) {
        guard let kind = ev.kind else { return }
        switch kind {
        case .axAction:
            switch ev.axAction {
            case .invoke?:
                invoke(node: ev.node, source: "ax")
            case .focus?:
                axFocusEvents += 1
                if let row = rowByTextField[ev.node] { focusRow(row, source: "ax") }
            case .setValue?:
                axSetValues += 1
                if let row = rowByTextField[ev.node] {
                    model.editText(row, ev.text)
                    caret[row] = nil
                }
            case .setSelection?, nil:
                break
            }
        case .pointer:
            if ev.action == 1 {
                pointerDowns += 1
                if buttonRuntimeID[ev.node] != nil {
                    invoke(node: ev.node, source: "pointer")
                } else if let row = rowByTextField[ev.node] {
                    focusRow(row, source: "pointer")
                }
            }
        case .key:
            keyEvents += 1
        case .windowMetrics:
            metricsEvents += 1
            applyMetrics(width: ev.i0, height: ev.i1, scale: ev.x)
        case .ime, .focus, .modalResult:
            break
        }
        flushIfDirty()
        afterInput?()
    }

    private func invoke(node: UInt64, source: String) {
        guard let runtimeID = buttonRuntimeID[node] else { return }
        axInvokes += 1
        log.emit("input", node: "toolbar/insert", payload: ["op": "invoke", "source": source, "node": Int(node)])
        _ = graph?.tapButton(runtimeID)
    }

    private func focusRow(_ row: UUID, source: String) {
        model.focusBinding?.wrappedValue = row
        caret[row] = nil
        log.emit("focus", node: "focus", payload: ["focused": row.uuidString, "source": source])
        dirty = true
    }

    private func applyMetrics(width: Int32, height: Int32, scale newScale: Float) {
        if newScale > 0, abs(newScale - scale) > 0.001 {
            // The runtime fixes its scale at construction. A change needs a graph rebuild (not in this probe).
            scaleChanges += 1
            log.emit("lifecycle", node: "window", payload: ["phase": "scale-change-unsupported", "scale": Double(newScale)])
        }
        guard width > 0, height > 0 else { return }
        graph?.rootProposal = proposal(width: UInt32(width), height: UInt32(height))
        dirty = true
    }

    // MARK: text store support (called from inside native input handling; never pumps)

    func storeSelection(node: UInt64) -> (range: UTF16Span, reversed: Bool)? {
        guard let row = rowByTextField[node], let text = model.row(row)?.text else { return nil }
        return (caretSpan(row, text), false)
    }

    func storeMarkedRange(node: UInt64) -> UTF16Span? { nil }

    func storeText(node: UInt64, range: UTF16Span) -> (units: [UInt16], adjusted: UTF16Span)? {
        guard let row = rowByTextField[node], let text = model.row(row)?.text else { return nil }
        let units = Array(text.utf16)
        let n = UInt32(units.count)
        let start = min(range.start, n)
        let end = max(start, min(range.end, n))
        return (Array(units[Int(start)..<Int(end)]), UTF16Span(start: start, end: end))
    }

    func storeReplace(node: UInt64, range: UTF16Span?, text: [UInt16]) -> Bool {
        guard let row = rowByTextField[node], let current = model.row(row)?.text else { return false }
        var units = Array(current.utf16)
        let n = UInt32(units.count)
        let target = range ?? caretSpan(row, current)
        let start = min(target.start, n)
        let end = max(start, min(target.end, n))
        units.replaceSubrange(Int(start)..<Int(end), with: text)
        let inserted = String(decoding: text, as: UTF16.self)
        keystrokes.append(inserted)
        let position = start + UInt32(text.count)
        model.editText(row, String(decoding: units, as: UTF16.self))
        caret[row] = UTF16Span(start: position, end: position)
        log.emit("input", node: "row \(FreshModelSlot.slot(of: row))", payload: [
            "op": "text-store-replace", "inserted": inserted, "row": row.uuidString,
        ])
        // Commit inside the native callback is deferred by the renderer until the callback unwinds.
        flushIfDirty()
        return true
    }

    func storeUnmark(node: UInt64) -> Bool { true }

    func storeCaretBounds(node: UInt64, range: UTF16Span) -> Rect? {
        guard let row = rowByTextField[node], let g = fieldGeometry[row] else { return nil }
        return caretRect(cells: g.cells, lines: g.lines, index: Int(range.start), origin: g.origin,
                         lineHeightPx: g.lineHeightPx, width: 2)
    }

    // MARK: queries for the self-test

    /// Runtime id string of the live node of `kind` for `row` (for instance numbers).
    func runtimeNodeID(kind: String, row: UUID) -> String? {
        guard let root = graph?.snapshot() else { return nil }
        var found: String?
        func visit(_ node: ResolvedNode) {
            if found != nil { return }
            if node.kind == kind, rowUUID(in: node.id) == row {
                found = node.id
                return
            }
            node.children.forEach(visit)
        }
        visit(root)
        return found
    }

    func instanceNumber(kind: String, row: UUID) -> Int? {
        runtimeNodeID(kind: kind, row: row).flatMap { graph?.nodeInstance($0) }
    }

    func textFieldBridgeID(_ row: UUID) -> UInt64? { textFieldByRow[row] }
    func caretOffset(_ row: UUID) -> UInt32? {
        guard let text = model.row(row)?.text else { return nil }
        return caretSpan(row, text).end
    }
    func buttonCount() -> Int { buttonRuntimeID.count }
    func measurerFailures() -> Int { measurer?.failures ?? 0 }
    func measurerCalls() -> Int { measurer?.calls ?? 0 }
    func measurerError() -> String { measurer?.lastError ?? "" }
}

/// Slot number of a row identity, used in AX labels ("Row 5").
enum FreshModelSlot {
    static func slot(of id: UUID) -> Int { RowModel.slot(of: id) }
}

/// The bridge's text store. The renderer calls these from inside native input handling; each one
/// hops to the backend on the UI thread (the bridge calls them only there).
final class FreshTextStore: TextStore {
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
        // Composition is not part of F1; a plain replace keeps the buffer consistent. Gap recorded in RESULT.md.
        MainActor.assumeIsolated { backend.storeReplace(node: node, range: range, text: text) }
    }

    func unmark(node: SwiftRightBridge.NodeID) -> Bool {
        MainActor.assumeIsolated { backend.storeUnmark(node: node) }
    }

    func caretBounds(node: SwiftRightBridge.NodeID, range: UTF16Span) -> Rect? {
        MainActor.assumeIsolated { backend.storeCaretBounds(node: node, range: range) }
    }
}
