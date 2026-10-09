import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// BridgeBackend: the runtime's commit sink -> ABI v0 transactions, and bridge events -> runtime actions.
//
// Coordinates: runtime frames are absolute logical points (DIP) with the window client top-left at 0,0.
// ABI geometry is physical pixels = DIP * scale, so the runtime's `pixelFrame` is used directly.
// Node ids: each runtime node id string maps to a stable non-zero bridge id (0 = window root).
// Text runs reserve a 32-id block per node so AX text-run ids never collide with node ids.
//
// SR0-S rev 2 (ABI rev 0.4): the display tick drives `Graph.tick(now:)` (interpolated frames are committed);
// the text store routes every call to the runtime `TextInputState` of the field (marked text included);
// the Windows reduce-motion setting (or a test override) is fed into the runtime environment.

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

/// Scales the alpha byte of a 0xRRGGBBAA colour by `opacity`. The ABI has no layer opacity, so the runtime's
/// presented opacity (fade-in, opacity modifiers) is applied to each primitive colour.
func faded(_ color: UInt32, _ opacity: Double) -> UInt32 {
    let clamped = min(max(opacity, 0), 1)
    let alpha = UInt32((Double(color & 0xFF) * clamped).rounded())
    return (color & 0xFFFFFF00) | alpha
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
    let model: RowModel
    let log: EventLog
    let options: FixtureOptions
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
    private var runtimeFieldByRow: [UUID: String] = [:]
    private var buttonRuntimeID: [UInt64: String] = [:]
    private var insertButtonRuntimeID: String?
    private var fieldGeometry: [UUID: FieldGeometry] = [:]
    private(set) var focusedRow: UUID?
    private(set) var focusTarget: UInt64 = 0

    // Input and renderer bookkeeping (read by the self-test).
    /// Text-store replace calls (the keystroke path: VK input through the renderer).
    private(set) var keystrokes: [String] = []
    /// Programmatic IME calls made through the text-store API: "mark:<text>" or "unmark".
    private(set) var imeCalls: [String] = []
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
    /// Commit records that carried an animation tag.
    private(set) var animationTagCommits = 0
    /// Commit records that showed a field with marked (composing) text.
    private(set) var imeMarkedCommits = 0
    /// Commits in which some node was presented at an intermediate opacity (a fade frame).
    private(set) var interpolatedCommits = 0
    /// Display ticks received, and commits produced by a tick (the runtime emits one while motions run).
    private(set) var tickCount = 0
    private(set) var tickCommits = 0
    /// Commits that reached the renderer after the host window was closed (must stay 0).
    private(set) var commitsAfterClose = 0
    private(set) var closedFlag = false
    /// Reduce motion: the Windows setting (nil when unreadable), the effective value fed to the runtime, and its source.
    private(set) var osReduceMotion: Bool?
    private(set) var reduceMotionEffective = false
    private(set) var reduceMotionSource = "unset"
    /// F9 tree release: the runtime teardown released the tree while the host still held the window, the
    /// teardown commit was accepted by the renderer, and the host ledger of renderer nodes after it.
    private(set) var releasedAtTeardown = false
    private(set) var teardownAccepted = false
    private(set) var ledgerAfterTeardown = -1
    private(set) var clearedViewBindings = 0
    /// Every stable identifier sent in a committed transaction (ABI rev 0.4).
    private(set) var committedIdentifiers: Set<String> = []
    private var inTick = false

    /// Called after each bridge event and each tick; the self-test advances its stages here.
    var afterInput: (() -> Void)?
    /// Called once, from the window-closed callback, after the host close handling.
    var afterClose: (() -> Void)?

    init(bridge: Bridge, model: RowModel, log: EventLog, options: FixtureOptions) {
        self.bridge = bridge
        self.model = model
        self.log = log
        self.options = options
    }

    // MARK: lifecycle (UI thread)

    func ready(_ win: BridgeWindow) {
        window = win
        do {
            let metrics = try win.metrics()
            scale = metrics.scale
            let meas = BridgeTextMeasurer(bridge: bridge, scale: scale)
            measurer = meas
            resolveReduceMotion()
            let g = makeGraph(options: options, model: model, measurer: meas, scale: CGFloat(scale))
            g.rootProposal = proposal(width: metrics.width, height: metrics.height)
            let reduce = reduceMotionEffective
            g.setRootEnvironment { $0.accessibilityReduceMotion = reduce }
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
                "reduce_motion": reduce, "reduce_source": reduceMotionSource,
            ])
        } catch {
            commitErrors.append("ready: \(error)")
            log.emit("lifecycle", node: "window", payload: ["phase": "ready-failed", "error": "\(error)"])
        }
    }

    /// Chooses the effective reduce-motion value: the test override first, then the Windows setting.
    private func resolveReduceMotion() {
        osReduceMotion = systemAnimationsEnabled().map { !$0 }
        if let override = options.reduceMotionOverride {
            reduceMotionEffective = override
            reduceMotionSource = "override"
        } else if let os = osReduceMotion {
            reduceMotionEffective = os
            reduceMotionSource = "os"
        } else {
            reduceMotionEffective = false
            reduceMotionSource = "unavailable"
        }
        model.systemReduceMotion = osReduceMotion
        model.effectiveReduceMotion = reduceMotionEffective
        model.reduceMotionSource = reduceMotionSource
    }

    /// Display tick (bridge `onTick`, QPC nanoseconds of the presented frame). Flushes pending model edits, then
    /// advances running animations to this frame; the runtime commits the interpolated frame.
    func tick(timestampNS: UInt64) {
        tickCount += 1
        flushIfDirty()
        guard let graph else { return }
        inTick = true
        graph.tick(now: Double(timestampNS) / 1_000_000_000)
        inTick = false
    }

    /// Window closed (renderer shuts down after this returns). The host runs the runtime teardown while the
    /// window is still open: disappear actions run, tasks are cancelled, and the tree is released. The teardown
    /// commit (nil root) removes the renderer's nodes. Pending engine results are not pumped after close.
    func closed() {
        closedFlag = true
        log.emit("lifecycle", node: "window", payload: ["phase": "closed"])
        model.markClosed()
        if let graph {
            graph.tearDown()
        }
        releasedAtTeardown = log.events().contains { ($0["node_id"] as? String) == "tree" }
        ledgerAfterTeardown = liveParent.count
        window = nil
        graph = nil
        measurer = nil
        clearedViewBindings = model.releaseViewReferences()
        afterClose?()
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
    /// removes are the top-most ids that left the tree. A nil root (runtime teardown) removes every node.
    func commit(_ record: CommitRecord) {
        guard let window else { return }
        guard let root = record.root else {
            commitTeardown(window)
            return
        }
        textFieldByRow = [:]
        rowByTextField = [:]
        runtimeFieldByRow = [:]
        buttonRuntimeID = [:]
        insertButtonRuntimeID = nil
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
        if record.animation != nil { animationTagCommits += 1 }
        if hasIntermediateOpacity(root) { interpolatedCommits += 1 }
        if inTick { tickCommits += 1 }
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

    /// Teardown commit: removes every top-level node (their descendants go with them).
    private func commitTeardown(_ window: BridgeWindow) {
        version += 1
        let removes = liveParent.compactMap { $0.value == 0 ? $0.key : nil }
        let transaction = Transaction(version: version, focus: 0, upserts: [], removes: removes)
        do {
            try window.commit(transaction)
            commitCount += 1
            liveParent = [:]
            teardownAccepted = true
            log.emit("lifecycle", node: "bridge", payload: ["phase": "teardown-committed", "removed_top": removes.count])
        } catch {
            commitErrors.append("teardown v\(version): \(error)")
            log.emit("lifecycle", node: "bridge", payload: ["phase": "teardown-rejected", "error": "\(error)"])
        }
        textFieldByRow = [:]
        rowByTextField = [:]
        runtimeFieldByRow = [:]
        buttonRuntimeID = [:]
        insertButtonRuntimeID = nil
        fieldGeometry = [:]
        focusedRow = nil
        focusTarget = 0
    }

    private func hasIntermediateOpacity(_ node: ResolvedNode) -> Bool {
        if node.opacity > 0.001 && node.opacity < 0.999 { return true }
        return node.children.contains { hasIntermediateOpacity($0) }
    }

    private func walk(_ node: ResolvedNode, parent: UInt64, order: UInt32, insideAffordance: Bool,
                      upserts: inout [NodeUpsert], parents: inout [UInt64: UInt64], releasable: inout [TextRunHandle]) {
        let id = bridgeID(node.id)
        parents[id] = parent
        let pf = node.pixelFrame
        let s = scale
        let alpha = node.opacity
        var bounds = Rect(x: Float(pf.x), y: Float(pf.y), w: Float(pf.width), h: Float(pf.height))
        var prims: [Primitive] = []
        var semantic: SemanticNode?
        var flags: NodeFlags = []
        var childInside = insideAffordance

        switch node.kind {
        case "Button":
            bounds = inflate(bounds, dx: FreshStyle.buttonInsetX * s, dy: FreshStyle.buttonInsetY * s)
            prims.append(.rect(bounds, color: faded(FreshStyle.buttonFill, alpha), radius: 6 * s))
            flags = [.hitTarget, .focusable]
            buttonRuntimeID[id] = node.id
            let label = node.children.first?.text ?? ""
            let identifier: String
            if label == "Insert above" {
                identifier = "toolbar/insert"
                insertButtonRuntimeID = node.id
            } else if label == "Delete", let row = rowUUID(in: node.id) {
                identifier = "row/\(row.uuidString)/delete"
            } else {
                identifier = ""
            }
            semantic = SemanticNode(role: .button, label: label, actions: [.invoke, .focus], identifier: identifier)
            childInside = true

        case "Text":
            let text = node.text ?? ""
            if !text.isEmpty, let m = measure(text, color: faded(insideAffordance ? FreshStyle.labelColor : FreshStyle.textColor, alpha),
                                             maxWidth: Float(pf.width) + 1, into: &releasable) {
                prims.append(.text(m.run, x: Float(pf.x), y: Float(pf.y)))
            }
            if !insideAffordance {
                semantic = SemanticNode(role: .staticText, label: text)
            }

        case "TextField":
            // The displayed text is the committed text with the marked (composing) text inserted.
            let text = node.text ?? ""
            let field = inflate(bounds, dx: FreshStyle.fieldInsetX * s, dy: 0)
            bounds = field
            prims.append(.rect(field, color: faded(FreshStyle.fieldFill, alpha), radius: 3 * s,
                               borderColor: faded(FreshStyle.fieldBorder, alpha), borderWidth: max(1, s)))
            let origin = (x: Float(pf.x), y: Float(pf.y))
            let lh = FreshStyle.lineHeightDIP * s
            let row = rowUUID(in: node.id)
            if let row {
                runtimeFieldByRow[row] = node.id
            }
            var runs: [AXTextRun] = []
            var selection: (anchor: TextSelectionPosition, focus: TextSelectionPosition)?
            let runBase = runBlock(node.id)
            if !text.isEmpty, let m = measure(text, color: faded(FreshStyle.textColor, alpha), maxWidth: 0, into: &releasable) {
                let cells = (try? bridge.cells(of: m.run)) ?? []
                prims.append(.text(m.run, x: origin.x, y: origin.y))
                // Caret or selection end, in displayed text (the runtime's TextInputState).
                let caretEnd = node.selection.map { $0.location + $0.length } ?? text.utf16.count
                let caretIndex = min(caretEnd, cells.count)
                if let marked = node.marked, marked.length > 0 {
                    imeMarkedCommits += 1
                    let from = min(marked.location, cells.count)
                    let to = min(marked.location + marked.length, cells.count)
                    if to > from {
                        let thickness = max(1, s)
                        let x0 = origin.x + cells[from].x0
                        let x1 = origin.x + cells[to - 1].x1
                        let y = origin.y + Float(Int(cells[from].line) + 1) * lh - thickness
                        prims.append(.rect(Rect(x: x0, y: y, w: max(1, x1 - x0), h: thickness),
                                           color: faded(FreshStyle.caretColor, alpha)))
                    }
                }
                if let row, row == focusedRow {
                    let caretRectPx = caretRect(cells: cells, lines: m.lines, index: caretIndex, origin: origin,
                                                lineHeightPx: lh, width: max(1, 1.5 * s))
                    prims.append(.rect(caretRectPx, color: faded(FreshStyle.caretColor, alpha)))
                }
                runs = makeAXTextRuns(text: text, measurement: m, cells: cells, origin: origin,
                                      lineHeightPx: lh, firstRunID: runBase)
                if !runs.isEmpty {
                    let line = caretIndex < cells.count ? Int(cells[caretIndex].line) : Int(cells.last?.line ?? 0)
                    let inLine = cells.prefix(caretIndex).filter { Int($0.line) == line }.count
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
                                        actions: [.focus, .setValue, .setSelection], runs: runs, selection: selection,
                                        identifier: "row/\(row.uuidString)/field")
            }
            flags = [.hitTarget, .focusable, .editable]

        default:
            break
        }

        if let identifier = semantic?.identifier, !identifier.isEmpty {
            committedIdentifiers.insert(identifier)
        }
        upserts.append(NodeUpsert(id: id, parent: parent, order: order, flags: flags, bounds: bounds,
                                  primitives: prims, semantic: semantic))
        for (index, child) in node.children.enumerated() {
            walk(child, parent: id, order: UInt32(index), insideAffordance: childInside,
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
                invoke(node: ev.node, source: "ax")
            case .focus?:
                axFocusEvents += 1
                if let row = rowByTextField[ev.node] { focusRow(row, source: "ax") }
            case .setValue?:
                axSetValues += 1
                if let row = rowByTextField[ev.node] {
                    model.editText(row, ev.text)
                    placeCaretAtEnd(row)
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

    /// Presses the "Insert above" button through the runtime (the same path as an AX or pointer invoke).
    @discardableResult
    func pressInsertButton() -> Bool {
        guard let runtimeID = insertButtonRuntimeID else { return false }
        return graph?.tapButton(runtimeID) ?? false
    }

    private func focusRow(_ row: UUID, source: String) {
        // Focus leaving a composing field commits its composition (as the IME does on focus loss).
        if let previous = focusedRow, previous != row, let state = textState(for: previous) {
            _ = state.unmark()
        }
        model.setFocus(row, source: source)
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
            // The runtime fixes its scale at construction. A change needs a graph rebuild (not in this probe).
            scaleChanges += 1
            log.emit("lifecycle", node: "window", payload: ["phase": "scale-change-unsupported", "scale": Double(newScale)])
        }
        guard width > 0, height > 0 else { return }
        graph?.rootProposal = proposal(width: UInt32(width), height: UInt32(height))
        dirty = true
    }

    // MARK: text store (called from inside native input handling; never pumps)
    //
    // Every call goes to the runtime TextInputState of the field, the single text model. The bound String
    // holds committed text; marked text is shown in the display and committed by unmark or a leaving edit.

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
        let inserted = String(decoding: text, as: UTF16.self)
        keystrokes.append(inserted)
        let ok = state.replace(range: range.map(runtimeRange), text: inserted)
        if let row = rowByTextField[node] {
            log.emit("input", node: "row \(FreshModelSlot.slot(of: row))", payload: [
                "op": "text-store-replace", "inserted": inserted, "row": row.uuidString,
            ])
        }
        flushAfterTextEdit()
        return ok
    }

    func storeReplaceAndMark(node: UInt64, range: UTF16Span?, text: [UInt16], newSelection: UTF16Span?) -> Bool {
        guard let state = textState(bridgeNode: node) else { return false }
        let inserted = String(decoding: text, as: UTF16.self)
        imeCalls.append(inserted.isEmpty ? "unmark" : "mark:\(inserted)")
        let ok = state.replaceAndMark(range: range.map(runtimeRange), text: inserted,
                                      newSelection: newSelection.map(runtimeRange))
        flushAfterTextEdit()
        return ok
    }

    func storeUnmark(node: UInt64) -> Bool {
        imeCalls.append("unmark")
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
    /// Caret (selection end) of a row's field in UTF-16 units, from the runtime text state.
    func caretOffset(_ row: UUID) -> UInt32? {
        textState(for: row).map { UInt32($0.selection.location + $0.selection.length) }
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
/// hops to the backend on the UI thread (the bridge calls them only there). The self-test calls the
/// same object for programmatic composition (see SelfTest F7).
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
        MainActor.assumeIsolated { backend.storeReplaceAndMark(node: node, range: range, text: text, newSelection: newSelection) }
    }

    func unmark(node: SwiftRightBridge.NodeID) -> Bool {
        MainActor.assumeIsolated { backend.storeUnmark(node: node) }
    }

    func caretBounds(node: SwiftRightBridge.NodeID, range: UTF16Span) -> Rect? {
        MainActor.assumeIsolated { backend.storeCaretBounds(node: node, range: range) }
    }
}
