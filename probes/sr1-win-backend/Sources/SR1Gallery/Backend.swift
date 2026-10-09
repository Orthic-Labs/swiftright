import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// GalleryBackend: runtime commit records -> ABI 0.5 transactions, and bridge events -> runtime actions.
//
// Coordinates: runtime frames are logical points with the window client top-left at 0,0. ABI geometry is physical
// pixels, so the runtime's `pixelFrame` is used directly. Node ids: each runtime node id string maps to a stable
// non-zero bridge id (0 = window root); overlay and text-run ids live in the same namespace.
//
// ABI 0.5 MAPPING (gaps are counted, see GalleryBackend.gapCounters and the RESULT notes):
//   Button            -> rect + text, role button (disabled: grey, no invoke action; SWR_SEM_DISABLED not marshalled)
//   Toggle            -> box rect (+ check glyph text run when on), role button, value "1"/"0" (no checkbox role,
//                        no toggled state in ABI 0.5)
//   Image             -> placeholder rect, role group + label (no image primitive: SWR_PRIM_IMAGE unsupported)
//   TextField         -> rect + text run + caret, role textField (single line; AX text runs)
//   TextEditor        -> rect + one text run per paragraph (ABI rejects '\n' in measure), role textField multiline,
//                        no AX text runs
//   Label             -> role group + label (children draw normally)
//   Divider           -> hairline rect, no semantics
//   Menu / context    -> host rect or hit target; the popup is an IN-WINDOW OVERLAY (ABI 0.5 has no popup-menu kind)
//   List / list-item  -> role list / listItem; selected row drawn with a highlight (no selected state in ABI 0.5)
//   Alert / dialog    -> modal plan: <=2 actions map to MessageBox OK / OK-Cancel / YES-NO; 3+ actions unsupported
//   keyboardShortcut  -> key events dispatched through the runtime, Ctrl -> .command (CONTRACT section 4)

enum GalleryStyle {
    static let fontFamily = "Segoe UI"
    static let lineHeightDIP: Float = 24
    static let textColor: UInt32 = 0x1F1F1FFF
    static let labelColor: UInt32 = 0xFFFFFFFF
    static let redColor: UInt32 = 0xD70015FF
    static let buttonFill: UInt32 = 0x2563EBFF
    static let disabledFill: UInt32 = 0xB8B8B8FF
    static let fieldFill: UInt32 = 0xFFFFFFFF
    static let fieldBorder: UInt32 = 0x888888FF
    static let caretColor: UInt32 = 0x111111FF
    static let checkFill: UInt32 = 0xFFFFFFFF
    static let checkOn: UInt32 = 0x2563EBFF
    static let placeholderFill: UInt32 = 0xDDDDDDFF
    static let dividerColor: UInt32 = 0xC8C8C8FF
    static let menuFill: UInt32 = 0xFAFAFAFF
    static let rowSelected: UInt32 = 0x2563EB33
    static let runBlock: UInt64 = 32
}

/// Scales the alpha byte of a 0xRRGGBBAA colour by `opacity` (the ABI has no layer opacity).
func faded(_ color: UInt32, _ opacity: Double) -> UInt32 {
    let clamped = min(max(opacity, 0), 1)
    let alpha = UInt32((Double(color & 0xFF) * clamped).rounded())
    return (color & 0xFFFFFF00) | alpha
}

/// Concatenated text of a node's Text descendants, in document order.
func galleryText(_ node: ResolvedNode) -> String {
    var out = node.text ?? ""
    for child in node.children {
        out += galleryText(child)
    }
    return out
}

/// Runtime font id -> DIPs. Only the ids the gallery uses are sized; everything else is body size.
func galleryFontDIP(_ font: Font?) -> Float {
    switch font?.id {
    case "textStyle.title": return 22
    case "textStyle.largeTitle": return 28
    case "textStyle.caption": return 12
    default: return 16
    }
}

/// Runtime foreground -> 0xRRGGBBAA. Semantic names the gallery uses are mapped; others take the fallback.
func galleryColor(_ foreground: ResolvedColor?, fallback: UInt32) -> UInt32 {
    guard let foreground else { return fallback }
    switch foreground {
    case .semantic("system.red"): return GalleryStyle.redColor
    case .semantic: return fallback
    case .rgba(let r, let g, let b, let a):
        func byte(_ v: Double) -> UInt32 { UInt32(min(max(v, 0), 1) * 255 + 0.5) }
        return (byte(r) << 24) | (byte(g) << 16) | (byte(b) << 8) | byte(a)
    }
}

/// Bridge modifier bits (SWR_MOD_*) -> runtime modifiers. Ctrl is the primary modifier on Windows (CONTRACT section 4).
func galleryModifiers(_ raw: UInt32) -> EventModifiers {
    var out: EventModifiers = []
    if raw & 0x1 != 0 { out.insert(.command) }
    if raw & 0x2 != 0 { out.insert(.option) }
    if raw & 0x4 != 0 { out.insert(.shift) }
    return out
}

/// GPUI key name (SWR key event text) -> runtime key equivalent.
func galleryKey(_ name: String) -> KeyEquivalent? {
    switch name {
    case "enter", "return": return .return
    case "escape": return .escape
    case "tab": return .tab
    case "space": return .space
    case "delete": return .delete
    case "up": return .upArrow
    case "down": return .downArrow
    case "left": return .leftArrow
    case "right": return .rightArrow
    default:
        return name.count == 1 ? KeyEquivalent(Character(name)) : nil
    }
}

/// Modal plan for a presented alert or dialog, against the ABI 0.5 MessageBox kinds only.
struct GalleryModalPlan {
    /// "alert" or "confirmationDialog".
    let kind: String
    /// Action index answered by YES (or by OK for a single action).
    var yesIndex: Int?
    /// Action index answered by NO / CANCEL; nil when the plan dismisses instead.
    var noIndex: Int?
    /// Human-readable plan status, recorded for the self-test.
    var status: String
    var unsupported: Bool { status.hasPrefix("unsupported") }
}

func galleryPlanModal(_ p: ResolvedPresentation) -> GalleryModalPlan {
    let actions = p.actions
    switch actions.count {
    case 0:
        return GalleryModalPlan(kind: p.kind, yesIndex: nil, noIndex: nil, status: "unsupported-0-actions")
    case 1:
        return GalleryModalPlan(kind: p.kind, yesIndex: 0, noIndex: nil, status: "ok")
    case 2:
        let cancel = actions.firstIndex { $0.role == .cancel }
        if let cancel {
            let other = cancel == 0 ? 1 : 0
            return GalleryModalPlan(kind: p.kind, yesIndex: other, noIndex: cancel, status: "yes-no")
        }
        return GalleryModalPlan(kind: p.kind, yesIndex: 0, noIndex: 1, status: "yes-no")
    default:
        return GalleryModalPlan(kind: p.kind, yesIndex: nil, noIndex: nil,
                                status: "unsupported-\(actions.count)-actions")
    }
}

/// Bridge measurement of runtime text. Synchronous; returned handles are released by the owner.
@MainActor
final class GalleryTextMeasurer: TextMeasurer {
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
                text: request.text, fontFamily: GalleryStyle.fontFamily,
                fontSize: 16, lineHeight: GalleryStyle.lineHeightDIP,
                scale: scale, maxWidth: maxWidth))
            bridge.release(m.run)
            return SwiftRightRuntime.TextMeasurement(
                size: LayoutSize(width: CGFloat(m.width / scale), height: CGFloat(m.height / scale)),
                baseline: CGFloat(m.firstBaseline / scale),
                lineCount: m.lineCount)
        } catch {
            failures += 1
            lastError = "\(error)"
            let lines = max(1, request.text.split(separator: " ").count)
            return SwiftRightRuntime.TextMeasurement(
                size: LayoutSize(width: CGFloat(request.text.count) * 8, height: CGFloat(lines) * 24),
                baseline: 18, lineCount: lines)
        }
    }
}

struct GalleryFieldGeometry {
    let origin: (x: Float, y: Float)
    let cells: [CharCell]
    let lines: [LineInfo]
    let lineHeightPx: Float
}

@MainActor
final class GalleryBackend {
    let bridge: Bridge
    let model: GalleryModel
    let screen: String
    let liveModal: Bool
    private(set) var window: BridgeWindow?
    private(set) var graph: Graph?
    private(set) var measurer: GalleryTextMeasurer?
    private(set) var scale: Float = 1
    private(set) var isReady = false
    private var version: UInt64 = 0
    private var nextID: UInt64 = 1
    private var idByKey: [String: UInt64] = [:]
    private var liveParent: [UInt64: UInt64] = [:]
    private var dirty = false
    private var closedFlag = false
    private var nextModalRequest: UInt64 = 1

    // Per-commit maps, rebuilt from the resolved tree on every commit.
    private var buttons: [UInt64: (runtimeID: String, enabled: Bool)] = [:]
    private var toggles: [UInt64: (runtimeID: String, enabled: Bool)] = [:]
    private var fields: [UInt64: String] = [:]
    private var fieldGeometry: [UInt64: GalleryFieldGeometry] = [:]
    private var rows: [UInt64: String] = [:]
    private var lists: [UInt64: String] = [:]
    private var menuHosts: [UInt64: String] = [:]
    private var overlayItems: [UInt64: (host: String, index: Int)] = [:]
    private(set) var focusTarget: UInt64 = 0
    private(set) var runtimeFocus: String?
    private var openMenuHost: String?
    private var activePresentationKey: String?
    private var activePresentationHost: String?
    private var activePlan: GalleryModalPlan?
    private var presentationSeen = false

    // Renderer and input bookkeeping (read by the self-test).
    private(set) var commitCount = 0
    private(set) var commitErrors: [String] = []
    private(set) var measureFailures = 0
    private(set) var kindCounts: [String: Int] = [:]
    private(set) var unknownKinds: Set<String> = []
    private(set) var imagePlaceholders = 0
    private(set) var toggleGlyphs = 0
    private(set) var editorParagraphs = 0
    private(set) var overlayItemsCommitted = 0
    private(set) var invokesSent = 0
    private(set) var invokesSuppressed = 0
    private(set) var pointerEvents = 0
    private(set) var keyEvents = 0
    private(set) var shortcutDispatches = 0
    private(set) var listKeyActions = 0
    private(set) var highlightedRows = 0
    private(set) var rowSelectCalls = 0
    private(set) var menuOpens = 0
    private(set) var menuPicks = 0
    private(set) var modalPlans: [String] = []
    private(set) var modalRequests = 0
    private(set) var modalResults: [Int32] = []
    private(set) var closedCalls = 0
    private(set) var afterCloseCommits = 0

    /// ABI 0.5 gap uses: each counter is how often the gallery drew a control the ABI cannot describe natively.
    var abiGapUses: [String: Int] {
        [
            "image-primitive (placeholder drawn)": imagePlaceholders,
            "checkbox-role-and-toggled-state (button + value)": toggleGlyphs,
            "multi-paragraph text (per-paragraph runs, no AX runs)": editorParagraphs,
            "popup-menu kind (in-window overlay items)": overlayItemsCommitted,
            "list selected state (highlight only)": highlightedRows,
        ]
    }

    /// Called after each bridge event and each tick; the self-test advances its stages here.
    var afterInput: (() -> Void)?
    /// Called once, from the window-closed callback.
    var afterClose: (() -> Void)?

    init(bridge: Bridge, model: GalleryModel, screen: String, liveModal: Bool) {
        self.bridge = bridge
        self.model = model
        self.screen = screen
        self.liveModal = liveModal
    }

    // MARK: lifecycle (UI thread)

    func ready(_ win: BridgeWindow) {
        window = win
        do {
            let metrics = try win.metrics()
            scale = metrics.scale
            let meas = GalleryTextMeasurer(bridge: bridge, scale: scale)
            measurer = meas
            let g = Graph(GalleryRoot(model: model, screen: screen), measurer: meas, scale: CGFloat(scale))
            g.keyboardPlatform = .windows
            g.rootProposal = ProposedViewSize(width: CGFloat(metrics.width) / CGFloat(scale),
                                              height: CGFloat(metrics.height) / CGFloat(scale))
            g.commitSink = { [weak self] record in
                MainActor.assumeIsolated { self?.commit(record) }
            }
            graph = g
            isReady = true
            try win.requestTicks(true)
            g.flush()
        } catch {
            commitErrors.append("ready: \(error)")
        }
    }

    func tick(timestampNS: UInt64) {
        guard let graph else { return }
        graph.tick(now: Double(timestampNS) / 1_000_000_000)
    }

    /// Window closed: the renderer already refuses commits and frees its tree. The host runs the runtime teardown
    /// and drops its ledger; nothing is sent to the renderer after this point.
    func closed() {
        closedCalls += 1
        closedFlag = true
        graph?.tearDown()
        window = nil
        graph = nil
        measurer = nil
        isReady = false
        afterClose?()
    }

    /// Runs the runtime flush (one commit per flush) when dirty.
    func flushIfDirty() {
        guard dirty, let graph else { return }
        dirty = false
        graph.flush()
    }

    /// Marks the runtime dirty and flushes once. The self-test calls this after each stage.
    func flushNow() {
        dirty = true
        flushIfDirty()
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
        nextID += GalleryStyle.runBlock
        idByKey["\(key)#runs"] = base
        return base
    }

    private struct Builder {
        var upserts: [NodeUpsert] = []
        var parents: [UInt64: UInt64] = [:]
        var releasable: [TextRunHandle] = []
        var overlay: (hostBridge: UInt64, hostRuntime: String, items: [ResolvedMenuItem], rect: Rect)?
        var presentation: (host: String, value: ResolvedPresentation)?
    }

    private func measure(_ text: String, color: UInt32, fontDIP: Float, maxWidth: Float,
                         into releasable: inout [TextRunHandle]) -> SwiftRightBridge.TextMeasurement? {
        do {
            let m = try bridge.measure(MeasureRequest(
                text: text, fontFamily: GalleryStyle.fontFamily, color: color,
                fontSize: fontDIP, lineHeight: fontDIP * 1.5,
                scale: scale, maxWidth: maxWidth))
            releasable.append(m.run)
            return m
        } catch {
            measureFailures += 1
            return nil
        }
    }

    /// Converts one commit record into one ABI transaction (full upsert of the resolved tree; removes are the
    /// top-most ids that left the tree). A nil root is the runtime teardown and removes every node.
    func commit(_ record: CommitRecord) {
        guard let window, !closedFlag else {
            if closedFlag, record.root != nil { afterCloseCommits += 1 }
            return
        }
        guard let root = record.root else {
            liveParent = [:]
            buttons = [:]
            toggles = [:]
            fields = [:]
            fieldGeometry = [:]
            rows = [:]
            lists = [:]
            menuHosts = [:]
            overlayItems = [:]
            return
        }
        buttons = [:]
        toggles = [:]
        fields = [:]
        fieldGeometry = [:]
        rows = [:]
        lists = [:]
        menuHosts = [:]
        overlayItems = [:]
        // Gap counters describe the tree of the latest commit, so they restart here.
        imagePlaceholders = 0
        toggleGlyphs = 0
        editorParagraphs = 0
        overlayItemsCommitted = 0
        highlightedRows = 0
        runtimeFocus = record.focused
        presentationSeen = false

        var b = Builder()
        walk(root, parent: 0, order: 0, inAffordance: false, into: &b)
        if let overlay = b.overlay {
            emitOverlay(overlay, into: &b)
        }
        // A presentation is planned once per (kind, title) while it is presented.
        if let presentation = b.presentation {
            notePresentation(presentation.value, host: presentation.host)
        } else if !presentationSeen {
            activePresentationKey = nil
            activePresentationHost = nil
            activePlan = nil
        }

        focusTarget = runtimeFocus.flatMap { id in fields.first { $0.value == id }?.key } ?? 0
        var removes: [UInt64] = []
        for (id, parent) in liveParent where b.parents[id] == nil {
            if parent == 0 || b.parents[parent] != nil { removes.append(id) }
        }

        version += 1
        let transaction = Transaction(version: version, focus: focusTarget, upserts: b.upserts, removes: removes)
        do {
            try window.commit(transaction)
            commitCount += 1
            liveParent = b.parents
        } catch {
            commitErrors.append("commit v\(version): \(error)")
        }
        for handle in b.releasable { bridge.release(handle) }
    }

    private func walk(_ node: ResolvedNode, parent: UInt64, order: UInt32, inAffordance: Bool, into b: inout Builder) {
        let id = bridgeID(node.id)
        b.parents[id] = parent
        kindCounts[node.kind, default: 0] += 1
        let s = scale
        let alpha = node.opacity
        let pf = node.pixelFrame
        var bounds = Rect(x: Float(pf.x), y: Float(pf.y), w: Float(pf.width), h: Float(pf.height))
        var prims: [Primitive] = []
        var semantic: SemanticNode?
        var flags: NodeFlags = []
        var childInside = inAffordance
        let enabled = node.accessibility.isEnabled
        let label = galleryText(node)
        let inkColor = galleryColor(node.style.foreground, fallback: inAffordance ? GalleryStyle.labelColor : GalleryStyle.textColor)
        let fontDIP = galleryFontDIP(node.style.font)

        if node.accessibility.role == "list-item" {
            // List rows are the runtime's list-item nodes; the selected one is highlighted (no selected state in ABI 0.5).
            rows[id] = node.id
            if node.accessibility.isSelected {
                prims.append(.rect(bounds, color: faded(GalleryStyle.rowSelected, alpha), radius: 4 * s))
                highlightedRows += 1
            }
            flags = [.hitTarget]
            semantic = SemanticNode(role: .listItem, label: label)
        } else {
            switch node.kind {
            case "Button":
                bounds = Rect(x: bounds.x - 12 * s, y: bounds.y - 6 * s, w: bounds.w + 24 * s, h: bounds.h + 12 * s)
                let fill = enabled ? GalleryStyle.buttonFill : GalleryStyle.disabledFill
                prims.append(.rect(bounds, color: faded(fill, alpha), radius: 6 * s))
                buttons[id] = (node.id, enabled)
                flags = enabled ? [.hitTarget, .focusable] : []
                semantic = SemanticNode(role: .button, label: label,
                                        actions: enabled ? [.invoke, .focus] : [],
                                        identifier: "sr1/\(screen)/button/\(label)")
                childInside = true

            case "Text":
                let text = node.text ?? ""
                if !text.isEmpty, let m = measure(text, color: faded(inkColor, alpha), fontDIP: fontDIP,
                                                 maxWidth: Float(pf.width) + 1, into: &b.releasable) {
                    prims.append(.text(m.run, x: Float(pf.x), y: Float(pf.y)))
                }
                if !inAffordance {
                    semantic = SemanticNode(role: .staticText, label: text)
                }

            case "TextField", "TextEditor":
                let multiline = node.kind == "TextEditor"
                let text = node.text ?? ""
                let field = Rect(x: bounds.x - 6 * s, y: bounds.y, w: bounds.w + 12 * s, h: bounds.h)
                bounds = field
                prims.append(.rect(field, color: faded(GalleryStyle.fieldFill, alpha), radius: 3 * s,
                                   borderColor: faded(GalleryStyle.fieldBorder, alpha), borderWidth: max(1, s)))
                fields[id] = node.id
                let origin = (x: Float(pf.x), y: Float(pf.y))
                let lh = GalleryStyle.lineHeightDIP * s
                var runs: [AXTextRun] = []
                var selection: (anchor: TextSelectionPosition, focus: TextSelectionPosition)?
                if multiline {
                    // ABI 0.5 measures one paragraph per call (no '\n'): each paragraph is its own run, stacked.
                    var y = origin.y
                    for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
                        let para = String(paragraph)
                        if para.isEmpty {
                            y += lh
                            continue
                        }
                        if let m = measure(para, color: faded(GalleryStyle.textColor, alpha), fontDIP: 16,
                                           maxWidth: Float(pf.width), into: &b.releasable) {
                            prims.append(.text(m.run, x: origin.x, y: y))
                            y += m.height
                            editorParagraphs += 1
                        }
                    }
                } else if !text.isEmpty,
                          let m = measure(text, color: faded(GalleryStyle.textColor, alpha), fontDIP: 16,
                                          maxWidth: 0, into: &b.releasable) {
                    let cells = (try? bridge.cells(of: m.run)) ?? []
                    prims.append(.text(m.run, x: origin.x, y: origin.y))
                    let caretEnd = node.selection.map { $0.location + $0.length } ?? text.utf16.count
                    let caretIndex = min(caretEnd, cells.count)
                    if node.id == runtimeFocus {
                        let caret = caretRect(cells: cells, lines: m.lines, index: caretIndex, origin: origin,
                                              lineHeightPx: lh, width: max(1, 1.5 * s))
                        prims.append(.rect(caret, color: faded(GalleryStyle.caretColor, alpha)))
                    }
                    runs = makeAXTextRuns(text: text, measurement: m, cells: cells, origin: origin,
                                          lineHeightPx: lh, firstRunID: runBlock(node.id))
                    if !runs.isEmpty {
                        let line = caretIndex < cells.count ? Int(cells[caretIndex].line) : Int(cells.last?.line ?? 0)
                        let inLine = cells.prefix(caretIndex).filter { Int($0.line) == line }.count
                        let position = TextSelectionPosition(run: runBlock(node.id) + UInt64(min(line, runs.count - 1)),
                                                             character: UInt32(inLine))
                        selection = (anchor: position, focus: position)
                    }
                    fieldGeometry[id] = GalleryFieldGeometry(origin: origin, cells: cells, lines: m.lines, lineHeightPx: lh)
                }
                semantic = SemanticNode(role: .textField, label: "", value: text,
                                        actions: [.focus, .setValue, .setSelection], multiline: multiline,
                                        runs: runs, selection: selection,
                                        identifier: "sr1/\(screen)/field/\(multiline ? "editor" : "title")")
                flags = [.hitTarget, .focusable, .editable]

            case "Toggle":
                let on = node.accessibility.value == "1"
                let inset: Float = (Float(pf.height) - 16 * s) / 2
                let box = Rect(x: Float(pf.x), y: Float(pf.y) + inset, w: 16 * s, h: 16 * s)
                let fill = on ? (enabled ? GalleryStyle.checkOn : GalleryStyle.disabledFill) : GalleryStyle.checkFill
                prims.append(.rect(box, color: faded(fill, alpha), radius: 3 * s,
                                   borderColor: faded(enabled ? GalleryStyle.fieldBorder : GalleryStyle.disabledFill, alpha),
                                   borderWidth: max(1, s)))
                if on, let m = measure("\u{2713}", color: faded(0xFFFFFFFF, alpha), fontDIP: 12, maxWidth: 0,
                                       into: &b.releasable) {
                    prims.append(.text(m.run, x: box.x + (box.w - m.width) / 2, y: box.y + (box.h - m.height) / 2))
                    toggleGlyphs += 1
                }
                toggles[id] = (node.id, enabled)
                flags = enabled ? [.hitTarget, .focusable] : []
                semantic = SemanticNode(role: .button, label: label, value: on ? "1" : "0",
                                        actions: enabled ? [.invoke, .focus] : [],
                                        identifier: "sr1/\(screen)/toggle/\(label)")

            case "Image":
                let name = node.image?.name ?? "image"
                prims.append(.rect(bounds, color: faded(GalleryStyle.placeholderFill, alpha), radius: 2 * s,
                                   borderColor: faded(GalleryStyle.fieldBorder, alpha), borderWidth: max(1, s)))
                imagePlaceholders += 1
                semantic = SemanticNode(role: .group, label: node.accessibility.label ?? name,
                                        identifier: "sr1/\(screen)/image/\(name)")

            case "Label":
                semantic = SemanticNode(role: .group, label: label)

            case "Divider":
                let vertical = pf.height > pf.width
                let rect = vertical
                    ? Rect(x: Float(pf.x), y: Float(pf.y), w: max(1, s), h: Float(pf.height))
                    : Rect(x: Float(pf.x), y: Float(pf.y), w: Float(pf.width), h: max(1, s))
                prims.append(.rect(rect, color: faded(GalleryStyle.dividerColor, alpha)))
                bounds = rect

            case "List":
                lists[id] = node.id
                semantic = SemanticNode(role: .list, identifier: "sr1/\(screen)/list")

            case "Menu":
                bounds = Rect(x: bounds.x - 12 * s, y: bounds.y - 6 * s, w: bounds.w + 24 * s, h: bounds.h + 12 * s)
                prims.append(.rect(bounds, color: faded(GalleryStyle.buttonFill, alpha), radius: 6 * s))
                flags = [.hitTarget, .focusable]
                semantic = SemanticNode(role: .button, label: label, actions: [.invoke, .focus],
                                        identifier: "sr1/\(screen)/menu/\(label)")
                childInside = true

            default:
                // Stacks, spacers and other layout nodes carry no primitive and no semantics here.
                if !["VStack", "HStack", "ZStack", "Spacer", "Group", "Scroll", "Padding"].contains(node.kind) {
                    unknownKinds.insert(node.kind)
                }
            }
        }

        if let presentation = node.presentation {
            b.presentation = (node.id, presentation)
        }
        if let items = node.menu {
            menuHosts[id] = node.id
            flags.insert(.hitTarget)
            if openMenuHost == node.id {
                b.overlay = (id, node.id, items, Rect(x: bounds.x, y: bounds.y + bounds.h, w: 220 * s, h: 0))
            }
        }

        b.upserts.append(NodeUpsert(id: id, parent: parent, order: order, flags: flags, bounds: bounds,
                                    primitives: prims, semantic: semantic))
        for (index, child) in node.children.enumerated() {
            walk(child, parent: id, order: UInt32(index), inAffordance: childInside, into: &b)
        }
    }

    /// Popup overlay for an open menu host: one row per top-level item, below the host. Disabled and divider rows
    /// are drawn without an invoke action. ABI 0.5 has no popup-menu kind; this is an in-window list.
    private func emitOverlay(_ overlay: (hostBridge: UInt64, hostRuntime: String, items: [ResolvedMenuItem], rect: Rect),
                             into b: inout Builder) {
        let s = scale
        let rowH = 26 * s
        var y = overlay.rect.y
        for (index, item) in overlay.items.enumerated() {
            let oid = bridgeID("overlay/\(overlay.hostRuntime)/\(index)")
            let rect = Rect(x: overlay.rect.x, y: y, w: overlay.rect.w, h: rowH)
            y += rowH
            var prims: [Primitive] = []
            if item.kind == .divider {
                prims.append(.rect(Rect(x: rect.x, y: rect.y + rowH / 2, w: rect.w, h: max(1, s)),
                                   color: faded(GalleryStyle.dividerColor, 1)))
                b.upserts.append(NodeUpsert(id: oid, parent: 0, order: UInt32(1000 + index), flags: [],
                                            bounds: rect, primitives: prims, semantic: nil))
                b.parents[oid] = 0
                continue
            }
            let enabled = !item.isDisabled && item.kind == .action
            prims.append(.rect(rect, color: faded(GalleryStyle.menuFill, 1), radius: 0,
                               borderColor: faded(GalleryStyle.fieldBorder, 1), borderWidth: max(1, s)))
            let suffix = item.kind == .submenu ? "  >" : ""
            if let m = measure(item.title + suffix, color: faded(enabled ? GalleryStyle.textColor : 0x888888FF, 1),
                               fontDIP: 16, maxWidth: 0, into: &b.releasable) {
                prims.append(.text(m.run, x: rect.x + 8 * s, y: rect.y + (rowH - m.height) / 2))
            }
            if enabled {
                overlayItems[oid] = (overlay.hostRuntime, index)
            }
            overlayItemsCommitted += 1
            b.parents[oid] = 0
            b.upserts.append(NodeUpsert(
                id: oid, parent: 0, order: UInt32(1000 + index),
                flags: enabled ? [.hitTarget, .focusable] : [], bounds: rect, primitives: prims,
                semantic: SemanticNode(role: .button, label: item.title,
                                       actions: enabled ? [.invoke, .focus] : [],
                                       identifier: "sr1/\(screen)/menu-item/\(item.title)")))
        }
    }

    private func notePresentation(_ p: ResolvedPresentation, host: String) {
        presentationSeen = true
        let key = "\(p.kind):\(p.title)"
        activePresentationHost = host
        if key == activePresentationKey { return }
        activePresentationKey = key
        let plan = galleryPlanModal(p)
        activePlan = plan
        modalPlans.append("\(p.kind):\(plan.status)")
        guard !plan.unsupported else { return }
        // The self-test never opens a MessageBox (it would block on a human). Live runs (--live-modal) do.
        guard liveModal, let window else { return }
        do {
            let buttons: BridgeWindow.ModalButtons
            switch plan.status {
            case "ok": buttons = .ok
            case "yes-no": buttons = .yesNo
            default: buttons = .okCancel
            }
            try window.requestModal(requestID: nextModalRequest, title: p.title, message: p.message ?? "", buttons: buttons)
            nextModalRequest += 1
            modalRequests += 1
        } catch {
            commitErrors.append("requestModal: \(error)")
        }
    }

    // MARK: bridge events -> runtime (UI thread)

    func handle(_ ev: BridgeEvent) {
        guard let kind = ev.kind else { return }
        switch kind {
        case .pointer:
            if ev.action == 1 {
                pointerDown(node: ev.node, modifiers: ev.modifiers)
            }
        case .key:
            if ev.action == 1 {
                keyDown(name: ev.text, modifiers: ev.modifiers)
            }
        case .axAction:
            switch ev.axAction {
            case .invoke?:
                invoke(node: ev.node)
            default:
                break
            }
        case .modalResult:
            modalResult(code: ev.i0)
        case .windowMetrics:
            applyMetrics(width: ev.i0, height: ev.i1, scale: ev.x)
        case .focus, .ime:
            break
        }
        flushIfDirty()
        afterInput?()
    }

    /// Activates a bridge node: button, toggle, menu host or overlay item. Disabled nodes are not sent to the runtime.
    func invoke(node: UInt64) {
        if let button = buttons[node] {
            guard button.enabled else {
                invokesSuppressed += 1
                return
            }
            invokesSent += 1
            _ = graph?.tapButton(button.runtimeID)
        } else if let toggle = toggles[node] {
            guard toggle.enabled else {
                invokesSuppressed += 1
                return
            }
            invokesSent += 1
            _ = graph?.activateToggle(toggle.runtimeID)
        } else if let host = menuHosts[node] {
            toggleMenu(host)
        } else if let item = overlayItems[node] {
            menuPicks += 1
            closeMenu()
            _ = graph?.performMenuItem(item.host, path: [item.index])
        }
    }

    private func pointerDown(node: UInt64, modifiers: UInt32) {
        pointerEvents += 1
        if overlayItems[node] == nil, openMenuHost != nil, menuHosts[node] == nil {
            // A press outside the open menu closes it, then the press is handled normally.
            closeMenu()
        }
        if let row = rows[node] {
            rowSelectCalls += 1
            _ = graph?.selectRow(row, modifiers: galleryModifiers(modifiers))
            return
        }
        invoke(node: node)
    }

    private func toggleMenu(_ host: String) {
        menuOpens += 1
        openMenuHost = openMenuHost == host ? nil : host
        dirty = true
    }

    /// Opens or closes a menu host's overlay (the self-test and pointer both come here).
    func openMenu(hostRuntimeID: String) {
        openMenuHost = hostRuntimeID
        menuOpens += 1
        dirty = true
    }

    func closeMenu() {
        openMenuHost = nil
        dirty = true
    }

    /// Key-down path (also driven by the self-test with the same bridge modifier bits the renderer sends).
    func keyDown(name: String, modifiers: UInt32) {
        keyEvents += 1
        let mods = galleryModifiers(modifiers)
        if name == "escape" {
            if openMenuHost != nil {
                closeMenu()
                return
            }
            if let host = activePresentationHost, activePresentationKey != nil {
                _ = graph?.dismissPresentation(host)
                return
            }
        }
        if let key = galleryKey(name), graph?.performKeyboardShortcut(key, modifiers: mods) == true {
            shortcutDispatches += 1
            return
        }
        guard let list = lists.values.first else { return }
        switch name {
        case "up", "down":
            listKeyActions += 1
            _ = graph?.navigateList(list, name == "up" ? .up : .down, extending: mods.contains(.shift))
        case "delete":
            listKeyActions += 1
            _ = graph?.deleteSelection(in: list)
        default:
            break
        }
    }

    /// Presentation answer from the MessageBox (live runs only). Code values: SWR_MODAL_RESULT_* (YES 6, NO 7, OK 1,
    /// CANCEL 2). YES runs the affirmative action; NO or CANCEL runs the cancel action or dismisses.
    private func modalResult(code: Int32) {
        modalResults.append(code)
        guard let host = activePresentationHost, let plan = activePlan else { return }
        switch code {
        case 6, 1:
            if let yes = plan.yesIndex {
                _ = graph?.performPresentationAction(host, index: yes)
            } else {
                _ = graph?.dismissPresentation(host)
            }
        default:
            if let no = plan.noIndex {
                _ = graph?.performPresentationAction(host, index: no)
            } else {
                _ = graph?.dismissPresentation(host)
            }
        }
    }

    private func applyMetrics(width: Int32, height: Int32, scale newScale: Float) {
        guard width > 0, height > 0 else { return }
        graph?.rootProposal = ProposedViewSize(width: CGFloat(width) / CGFloat(scale),
                                               height: CGFloat(height) / CGFloat(scale))
        dirty = true
    }

    // MARK: queries for the self-test

    func runtimeIDOfFocusedField() -> String? { runtimeFocus }
    func isClosed() -> Bool { closedFlag }
    func measurerFailures() -> Int { measurer?.failures ?? 0 }
}
