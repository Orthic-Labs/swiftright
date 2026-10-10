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
// the text store routes every call to the runtime `TextInputState` of the field (marked text included).
//
// 2026-10-10 parity pass (SR0-O cross-compare, Mac SwiftUI as oracle):
//   - initial focus: `ready` calls `Graph.applyInitialFocus()` once, after the first commit and before the main actor is
//     yielded (so after every appear and before any task body), and logs it as a `focus` event with source `initial`;
//   - a UIA Invoke on a button no longer moves the focus: the AX `focus` action UIA sends in front of it is held by a
//     `ButtonFocusGate` and dropped when the invoke follows (a real SetFocus on a button, Narrator, still lands);
//   - reduce motion: the Windows "Animation effects" value is read and logged but is NOT fed into the runtime. The default is
//     animations on; only `--reduce-motion-override on` and the reduced-motion variant force reduced (RESULT.md 2026-10-10).

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
    /// Bridge id of a button focused through AX/UIA SetFocus (Narrator item navigation). Cleared by any row focus.
    /// It is the screen reader's focus: it moves the tree focus the renderer reports to UIA, and leaves the runtime
    /// `FocusState` (the keyboard focus, `focusedRow`) alone, as VoiceOver's cursor does on the Mac.
    private var axButtonFocus: UInt64 = 0
    /// Holds a button focus request until it is clear that no invoke of the same button follows (see `ButtonFocusGate`).
    private var buttonFocusGate = ButtonFocusGate()
    /// Button focus requests dropped because an invoke of the same node followed at once (diagnostic, read by the self-test).
    private(set) var coalescedButtonFocus = 0
    /// The initial focus the window gave (runtime node id, row), nil when it focused nothing.
    private(set) var initialFocusNode: String?
    private(set) var initialFocusRow: UUID?

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
    /// Reduce motion: the Windows setting (nil when unreadable; read and logged only), the effective value fed to the
    /// runtime (an explicit override or variant, else false), and its source (override, variant or default).
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
    /// Caret (selection end) per row at window close, kept after the runtime state is torn down.
    private var caretAtClose: [UUID: UInt32] = [:]

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
            giveInitialFocus(g)
            log.emit("lifecycle", node: "window", payload: [
                "phase": "ready", "scale": Double(scale), "width_px": Int(metrics.width), "height_px": Int(metrics.height),
                "reduce_motion": reduce, "reduce_source": reduceMotionSource,
            ])
        } catch {
            commitErrors.append("ready: \(error)")
            log.emit("lifecycle", node: "window", payload: ["phase": "ready-failed", "error": "\(error)"])
        }
    }

    /// Chooses the effective reduce-motion value. DECISION 2026-10-10 (Adrian: "Our animations have to work on a system even if
    /// it has animations turned off"): the Windows "Animation effects" setting (SPI_GETCLIENTAREAANIMATION) is still read and
    /// logged (`system_reduce`, `osReduceMotion`) but does NOT set `accessibilityReduceMotion`. The default is false (animate).
    /// An explicit test or app override (`--reduce-motion-override on|off`) and the reduced-motion variant still decide it.
    /// Order: override, then variant, then the default.
    private func resolveReduceMotion() {
        osReduceMotion = systemAnimationsEnabled().map { !$0 }
        if let override = options.reduceMotionOverride {
            reduceMotionEffective = override
            reduceMotionSource = "override"
        } else if options.reducedVariant {
            reduceMotionEffective = true
            reduceMotionSource = "variant"
        } else {
            reduceMotionEffective = false
            reduceMotionSource = "default"
        }
        model.systemReduceMotion = osReduceMotion
        model.effectiveReduceMotion = reduceMotionEffective
        model.reduceMotionSource = reduceMotionSource
    }

    /// Gives the window's initial focus (runtime rule: `Graph.applyInitialFocus`, from the Mac oracle). Runs once from `ready`,
    /// after the first commit and before the main actor is yielded, so the event follows every `appear` and precedes every
    /// task start, the Mac log order. The caret goes to the end of the field, as for any other focus.
    private func giveInitialFocus(_ g: Graph) {
        guard let node = g.applyInitialFocus(), let row = rowUUID(in: node) else { return }
        initialFocusNode = node
        initialFocusRow = row
        placeCaretAtEnd(row)
        model.logFocus(row, source: "initial")
        dirty = true
        flushIfDirty()
    }

    /// Display tick (bridge `onTick`, QPC nanoseconds of the presented frame). Flushes pending model edits, then
    /// advances running animations to this frame; the runtime commits the interpolated frame.
    func tick(timestampNS: UInt64) {
        tickCount += 1
        let now = monotonicNS()
        let held = buttonFocusGate.age(at: now) ?? 0
        if let node = buttonFocusGate.expired(at: now) { applyButtonFocus(node, heldNS: held) }
        flushIfDirty()
        guard let graph else { return }
        inTick = true
        graph.tick(now: Double(timestampNS) / 1_000_000_000)
        inTick = false
    }

    /// Window closed. The renderer already refuses commits (SWR_E_SHUTDOWN) and frees its own tree. The host
    /// runs the runtime teardown (disappear actions, task cancel, tree release); its nil-root commit record is
    /// not sent to the renderer. The main queue is pumped after this returns until `shutdownComplete` (rev 0.5).
    func closed() {
        closedFlag = true
        log.emit("lifecycle", node: "window", payload: ["phase": "closed"])
        model.markClosed()
        // Snapshot the live text state before teardown drops it (the self-test reads it after close).
        for (row, node) in runtimeFieldByRow {
            if let state = graph?.textInput(node) { caretAtClose[row] = UInt32(state.selection.location + state.selection.length) }
        }
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
        // After close nothing is sent: a pending commit is dropped and counted, not an error.
        guard let window, !closedFlag else {
            if closedFlag, record.root != nil { commitsAfterClose += 1 }
            return
        }
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

        if axButtonFocus != 0, parents[axButtonFocus] == nil { axButtonFocus = 0 }
        focusTarget = axButtonFocus != 0 ? axButtonFocus : (focusedRow.flatMap { textFieldByRow[$0] } ?? 0)
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

    /// Teardown commit: the renderer rejects commits from the moment the window closes (SWR_E_SHUTDOWN: its
    /// SHUTDOWN flag is set before `window_closed` is entered) and frees its own tree, so nothing is sent.
    /// The host only drops its node ledger. Last-commit evidence (focus, caret) is kept for the self-test.
    private func commitTeardown(_ window: BridgeWindow) {
        liveParent = [:]
        buttonRuntimeID = [:]
        insertButtonRuntimeID = nil
        fieldGeometry = [:]
        log.emit("lifecycle", node: "bridge", payload: ["phase": "teardown-no-commit", "reason": "renderer-shutdown"])
    }

    private func hasIntermediateOpacity(_ node: ResolvedNode) -> Bool {
        if node.opacity > 0.001 && node.opacity < 0.999 { return true }
        return node.children.contains { hasIntermediateOpacity($0) }
    }

    private func walk(_ node: ResolvedNode, parent: UInt64, order: UInt32, insideAffordance: Bool, parentKind: String = "",
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
                semantic = SemanticNode(role: .textField, label: "", value: text,
                                        actions: [.focus, .setValue, .setSelection], runs: runs, selection: selection,
                                        identifier: "row/\(row.uuidString)/field")
            }
            flags = [.hitTarget, .focusable, .editable]

        case "List":
            semantic = SemanticNode(role: .list)

        default:
            // Direct children of a List are its rows (the Mac AXOutlineRow / UIA ListItem).
            if parentKind == "List", rowUUID(in: node.id) != nil {
                semantic = SemanticNode(role: .listItem)
            }
        }

        if let identifier = semantic?.identifier, !identifier.isEmpty {
            committedIdentifiers.insert(identifier)
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
                // UIA sends a focus request on the button right in front of an Invoke; an activation alone must not move the
                // focus (Mac AXPress does not), so that request is dropped. Any other held request stands first.
                if buttonFocusGate.cancelForInvoke(of: ev.node, at: monotonicNS()) {
                    coalescedButtonFocus += 1
                    log.emit("ax-focus-coalesced", node: "focus", payload: [
                        "node": Int(ev.node), "reason": "focus-request-in-front-of-invoke", "source": "ax",
                    ])
                } else {
                    confirmButtonFocus()
                }
                invoke(node: ev.node, source: "ax")
            case .focus?:
                axFocusEvents += 1
                if let row = rowByTextField[ev.node] {
                    confirmButtonFocus()
                    focusRow(row, source: "ax")
                } else if buttonRuntimeID[ev.node] != nil {
                    let now = monotonicNS()
                    let held = buttonFocusGate.age(at: now) ?? 0
                    if let earlier = buttonFocusGate.request(ev.node, at: now) { applyButtonFocus(earlier, heldNS: held) }
                }
            case .setValue?:
                confirmButtonFocus()
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
                confirmButtonFocus()
                pointerDowns += 1
                if buttonRuntimeID[ev.node] != nil {
                    invoke(node: ev.node, source: "pointer")
                } else if let row = rowByTextField[ev.node] {
                    focusRow(row, source: "pointer")
                }
            }
        case .key:
            keyEvents += 1
            if ev.action == 1 {
                confirmButtonFocus()
                handleKey(name: ev.text, modifiers: ev.modifiers)
            }
        case .windowMetrics:
            metricsEvents += 1
            applyMetrics(width: ev.i0, height: ev.i1, scale: ev.x)
        case .ime, .focus, .modalResult:
            break
        }
        flushIfDirty()
        afterInput?()
    }

    private func monotonicNS() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// Makes `node` the screen reader's focus (the tree focus the renderer reports), logged as `ax-button-focus`. A node that
    /// left the tree in the meantime is ignored.
    private func applyButtonFocus(_ node: UInt64, heldNS: UInt64) {
        guard buttonRuntimeID[node] != nil else { return }
        axButtonFocus = node
        dirty = true
        log.emit("ax-button-focus", node: "focus", payload: [
            "focused": "button:\(node)", "source": "ax", "held_ms": Int(heldNS / 1_000_000),
        ])
    }

    /// Another input arrived while a button focus request was held: the request stood on its own, so it lands now.
    private func confirmButtonFocus() {
        let held = buttonFocusGate.age(at: monotonicNS()) ?? 0
        if let node = buttonFocusGate.confirm() { applyButtonFocus(node, heldNS: held) }
    }

    /// Native key-down. Tab / Shift-Tab move focus through the runtime (CONTRACT section 4); the bridge's
    /// modifier bits are 0x1 control (Cmd's Windows counterpart), 0x2 alt, 0x4 shift (see galleryModifiers
    /// in probes/sr1-win-backend). Any other chord is left to the field.
    private func handleKey(name: String, modifiers: UInt32) {
        guard name == "tab", modifiers & ~0x4 == 0, let graph else { return }
        let forward = modifiers & 0x4 == 0
        let previous = focusedRow
        // Focus leaving a composing field commits its composition (as the IME does on focus loss).
        if let previous, let state = textState(for: previous) { _ = state.unmark() }
        guard graph.moveFocus(forward: forward) else { return }
        // The runtime committed the new focus; focusedRow now names it.
        if let row = focusedRow {
            placeCaretAtEnd(row)
            log.emit("focus", node: "focus", payload: [
                "focused": row.uuidString, "source": forward ? "tab" : "shift-tab",
                "previous": previous?.uuidString ?? "none",
            ])
        }
        dirty = true
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
        axButtonFocus = 0
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
        guard let row = rowByTextField[node], let g = fieldGeometry[row] else {
            log.emit("ime", node: "caret-bounds", payload: [
                "start": Int(range.start), "end": Int(range.end), "bounds": "nil", "node": Int(node),
            ])
            return nil
        }
        let rect = caretRect(cells: g.cells, lines: g.lines, index: Int(range.start), origin: g.origin,
                             lineHeightPx: g.lineHeightPx, width: 2)
        // Candidate-window placement evidence: the rectangle returned to the renderer for the IME (physical px,
        // window client space). The driver compares it with the IME's candidate window.
        log.emit("ime", node: "caret-bounds", payload: [
            "row": row.uuidString, "node": Int(node), "start": Int(range.start), "end": Int(range.end),
            "x": Double(rect.x), "y": Double(rect.y), "w": Double(rect.w), "h": Double(rect.h),
            "scale": Double(scale),
        ])
        return rect
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
        textState(for: row).map { UInt32($0.selection.location + $0.selection.length) } ?? caretAtClose[row]
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
