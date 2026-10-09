import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// GalleryBackend: runtime commit records -> ABI 0.6 transactions, and bridge events -> runtime actions.
//
// Coordinates: runtime frames are logical points with the window client top-left at 0,0. ABI geometry is physical
// pixels, so the runtime's `pixelFrame` is used directly. Node ids: each runtime node id string maps to a stable
// non-zero bridge id (0 = window root); overlay, presentation and text-run ids live in the same namespace.
//
// ABI 0.6 MAPPING (the 0.5 workarounds are gone; RESULT.md has the full table):
//   Button            -> rect + text, role button, actions invoke/focus, SWR_SEM_DISABLED when disabled.
//                        The grey fill is visual only; the renderer refuses invoke and swallows presses.
//   Toggle            -> box rect (+ check glyph when on), role checkbox, toggled on/off (UIA TogglePattern),
//                        actions invoke/focus, disabled flag.
//   Image             -> SWR_PRIM_IMAGE of a generated RGBA test pattern (registered at ready, released at close),
//                        role image + label. No asset files.
//   TextField         -> rect + text run + caret, role textField (single line; AX text runs).
//   TextEditor        -> rect + ONE multi-paragraph text node ('\n' kept as line-break cells), role textField
//                        multiline, one AX text run per visual line (a paragraph's run ends with its '\n').
//   Label             -> role group + label (children draw normally).
//   Divider           -> hairline rect, no semantics.
//   List / list-item  -> role list / listItem; list items carry selectable + selected flags. The selected row is also
//                        highlighted (visual only).
//   Menu / context    -> host button; invoke opens the menu. Live runs (--live-modal) open a native popup
//                        (requestMenu at the pointer). Result -2 (could not be shown), or a run without --live-modal,
//                        draws the in-window overlay instead (role menu, rows role menuItem).
//   Alert / dialog    -> requestDialog (TaskDialogIndirect), one custom button per action, item id = action index + 1,
//                        answered through performPresentationAction (live runs only). The presentation is also
//                        exposed as role alert (alert) or dialog (confirmationDialog) covering the window.
//   keyboardShortcut  -> key events dispatched through the runtime, Ctrl -> .command (CONTRACT section 4).

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
    static let dividerColor: UInt32 = 0xC8C8C8FF
    static let menuFill: UInt32 = 0xFAFAFAFF
    static let rowSelected: UInt32 = 0x2563EB33
    static let runBlock: UInt64 = 32
    static let patternSize = 32
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

/// A generated 32x32 RGBA8 test pattern (straight alpha, byte order R, G, B, A). No asset files: the gradient
/// stands in for symbol images, the checker for asset images.
func galleryPattern(gradient: Bool) -> [UInt8] {
    let size = GalleryStyle.patternSize
    var pixels = [UInt8](repeating: 255, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let i = (y * size + x) * 4
            if gradient {
                pixels[i] = UInt8(x * 255 / (size - 1))
                pixels[i + 1] = UInt8(y * 255 / (size - 1))
                pixels[i + 2] = 0x80
            } else if ((x / 4) + (y / 4)) % 2 == 0 {
                pixels[i] = 0x25
                pixels[i + 1] = 0x63
                pixels[i + 2] = 0xEB
            } else {
                pixels[i] = 0xFF
                pixels[i + 1] = 0xFF
                pixels[i + 2] = 0xFF
            }
        }
    }
    return pixels
}

/// Native dialog plan for a presented alert or confirmation dialog: one custom button per action, item id = action
/// index + 1 (non-zero, unique). The ABI task dialog takes 1 to 8 buttons.
struct GalleryModalPlan {
    /// "alert" or "confirmationDialog".
    let kind: String
    var buttons: [BridgeWindow.ModalItem]
    /// Human-readable plan status, recorded for the self-test.
    var status: String
    var unsupported: Bool { status.hasPrefix("unsupported") }
}

func galleryPlanModal(_ p: ResolvedPresentation) -> GalleryModalPlan {
    let actions = p.actions
    guard (1...8).contains(actions.count) else {
        return GalleryModalPlan(kind: p.kind, buttons: [], status: "unsupported-\(actions.count)-actions")
    }
    let buttons = actions.enumerated().map { index, action in
        BridgeWindow.ModalItem(id: UInt32(index + 1), text: action.title, disabled: action.isDisabled)
    }
    return GalleryModalPlan(kind: p.kind, buttons: buttons, status: "buttons-\(actions.count)")
}

/// Native popup items for a menu host: one item per top-level entry, id = entry index + 1, so a pick maps back to the
/// entry with `id - 1`. Dividers are separators. Submenus are shown disabled (the native popup here is flat).
func galleryMenuItems(_ items: [ResolvedMenuItem]) -> [BridgeWindow.ModalItem] {
    items.enumerated().map { index, item in
        if item.kind == .divider { return BridgeWindow.ModalItem.separatorItem }
        let suffix = item.kind == .submenu ? "  >" : ""
        let enabled = !item.isDisabled && item.kind == .action
        return BridgeWindow.ModalItem(id: UInt32(index + 1), text: item.title + suffix, disabled: !enabled)
    }
}

/// What the backend sent for one runtime node (or overlay / presentation node) in the latest commit. The self-test
/// reads these back to check the ABI 0.6 semantics that reached the renderer.
struct CommittedSemantic: Equatable {
    let role: NodeRole
    let label: String
    let toggled: ToggledState
    let selected: Bool?
    let disabled: Bool
    let runTexts: [String]
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
    private var windowPx = Rect.zero
    /// Test patterns registered at ready ("gradient", "checker"). Released at close.
    private var patterns: [String: ImageHandle] = [:]

    // Per-commit maps, rebuilt from the resolved tree on every commit.
    private var buttons: [UInt64: String] = [:]
    private var toggles: [UInt64: String] = [:]
    private var fields: [UInt64: String] = [:]
    private var fieldGeometry: [UInt64: GalleryFieldGeometry] = [:]
    private var rows: [UInt64: String] = [:]
    private var lists: [UInt64: String] = [:]
    private var menuHosts: [UInt64: String] = [:]
    private var menuItemsByHost: [String: [ResolvedMenuItem]] = [:]
    private var overlayItems: [UInt64: (host: String, index: Int)] = [:]
    private(set) var committed: [String: CommittedSemantic] = [:]
    private(set) var focusTarget: UInt64 = 0
    private(set) var runtimeFocus: String?

    // In-window menu overlay (fallback) and native modal state.
    private(set) var openMenuHost: String?
    private var pendingMenus: [UInt64: String] = [:]
    private var activePresentationKey: String?
    private var activePresentationHost: String?
    private(set) var activePlan: GalleryModalPlan?
    private(set) var activeDialogRequestID: UInt64?
    private var presentationSeen = false

    // Renderer and input bookkeeping (read by the self-test).
    private(set) var commitCount = 0
    private(set) var commitErrors: [String] = []
    private(set) var measureFailures = 0
    private(set) var kindCounts: [String: Int] = [:]
    private(set) var unknownKinds: Set<String> = []
    private(set) var imagePrimitives = 0
    private(set) var editorLines = 0
    private(set) var editorRuns = 0
    private(set) var overlayRowsCommitted = 0
    private(set) var highlightedRows = 0
    private(set) var invokesSent = 0
    private(set) var pointerEvents = 0
    private(set) var keyEvents = 0
    private(set) var shortcutDispatches = 0
    private(set) var listKeyActions = 0
    private(set) var rowSelectCalls = 0
    private(set) var menuOpens = 0
    private(set) var overlayOpens = 0
    private(set) var menuPicks = 0
    private(set) var nativeMenuRequests = 0
    private(set) var menuFailures = 0
    private(set) var modalPlans: [String] = []
    private(set) var nativeDialogRequests = 0
    private(set) var dialogFailures = 0
    private(set) var modalResults: [Int] = []
    private(set) var staleModalResults = 0
    private(set) var closedCalls = 0
    private(set) var afterCloseCommits = 0

    /// Native modal requests actually sent to the renderer (zero in a self-test without --live-modal).
    var modalRequests: Int { nativeMenuRequests + nativeDialogRequests }

    /// Registered test patterns (expected 2 after ready, 0 after close).
    var registeredPatternCount: Int { patterns.count }

    /// ABI 0.6 features the latest commit used (logged by the self-test).
    var abiUses: [String: Int] {
        [
            "image primitive (SWR_PRIM_IMAGE)": imagePrimitives,
            "checkbox role + toggled state": committed.values.filter { $0.toggled != .none }.count,
            "list selectable + selected flags": committed.values.filter { $0.selected != nil }.count,
            "disabled flag (SWR_SEM_DISABLED)": disabledNodes,
            "multi-paragraph text runs": editorRuns,
            "native menu requests (requestMenu)": nativeMenuRequests,
            "native dialog requests (requestDialog)": nativeDialogRequests,
            "overlay menu rows (no native popup)": overlayRowsCommitted,
        ]
    }

    /// Count of committed nodes with the disabled flag.
    var disabledNodes: Int { committed.values.filter(\.disabled).count }

    /// Native popup items the Menu host at `host` would send (self-test check; sends nothing).
    func nativeMenuItems(host: String) -> [BridgeWindow.ModalItem] {
        galleryMenuItems(menuItemsByHost[host] ?? [])
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
            windowPx = Rect(x: 0, y: 0, w: Float(metrics.width), h: Float(metrics.height))
            registerPatterns()
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

    private func registerPatterns() {
        do {
            patterns["gradient"] = try bridge.registerImage(
                width: UInt32(GalleryStyle.patternSize), height: UInt32(GalleryStyle.patternSize),
                rgba: galleryPattern(gradient: true))
            patterns["checker"] = try bridge.registerImage(
                width: UInt32(GalleryStyle.patternSize), height: UInt32(GalleryStyle.patternSize),
                rgba: galleryPattern(gradient: false))
        } catch {
            commitErrors.append("registerImage: \(error)")
        }
    }

    func tick(timestampNS: UInt64) {
        guard let graph else { return }
        graph.tick(now: Double(timestampNS) / 1_000_000_000)
    }

    /// Window closed: the renderer already refuses commits and frees its tree. The host releases its test images,
    /// runs the runtime teardown and drops its ledger; nothing is sent to the renderer after this point.
    func closed() {
        closedCalls += 1
        closedFlag = true
        for handle in patterns.values {
            bridge.release(handle)
        }
        patterns = [:]
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
        var committed: [String: CommittedSemantic] = [:]
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

    /// Pattern for an image node: the symbol gets the gradient, every other image the checker.
    private func patternHandle(for name: String) -> ImageHandle? {
        name == "star.fill" ? patterns["gradient"] : patterns["checker"]
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
            menuItemsByHost = [:]
            overlayItems = [:]
            committed = [:]
            return
        }
        buttons = [:]
        toggles = [:]
        fields = [:]
        fieldGeometry = [:]
        rows = [:]
        lists = [:]
        menuHosts = [:]
        menuItemsByHost = [:]
        overlayItems = [:]
        // Counters describe the tree of the latest commit, so they restart here.
        imagePrimitives = 0
        editorLines = 0
        editorRuns = 0
        overlayRowsCommitted = 0
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
            emitPresentation(presentation, into: &b)
        } else if !presentationSeen {
            activePresentationKey = nil
            activePresentationHost = nil
            activePlan = nil
            activeDialogRequestID = nil
        }
        committed = b.committed

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
            // List rows are the runtime's list-item nodes. The selected flag is published; the highlight is drawn too.
            rows[id] = node.id
            let selected = node.accessibility.isSelected
            if selected {
                prims.append(.rect(bounds, color: faded(GalleryStyle.rowSelected, alpha), radius: 4 * s))
                highlightedRows += 1
            }
            flags = [.hitTarget]
            semantic = SemanticNode(role: .listItem, label: label, selected: selected)
        } else {
            switch node.kind {
            case "Button":
                bounds = Rect(x: bounds.x - 12 * s, y: bounds.y - 6 * s, w: bounds.w + 24 * s, h: bounds.h + 12 * s)
                let fill = enabled ? GalleryStyle.buttonFill : GalleryStyle.disabledFill
                prims.append(.rect(bounds, color: faded(fill, alpha), radius: 6 * s))
                buttons[id] = node.id
                flags = [.hitTarget, .focusable]
                semantic = SemanticNode(role: .button, label: label, actions: [.invoke, .focus],
                                        identifier: "sr1/\(screen)/button/\(label)", disabled: !enabled)
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
                // One text node per field. The editor is multi-line: one measurement holds every paragraph.
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
                if !text.isEmpty,
                   let m = measure(text, color: faded(GalleryStyle.textColor, alpha), fontDIP: 16,
                                   maxWidth: multiline ? Float(pf.width) : 0, into: &b.releasable) {
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
                    if multiline {
                        editorLines = m.lineCount
                        editorRuns = runs.count
                    }
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
                }
                toggles[id] = node.id
                flags = [.hitTarget, .focusable]
                semantic = SemanticNode(role: .checkbox, label: label,
                                        actions: [.invoke, .focus],
                                        identifier: "sr1/\(screen)/toggle/\(label)",
                                        toggled: on ? .on : .off, disabled: !enabled)

            case "Image":
                let name = node.image?.name ?? "image"
                if let handle = patternHandle(for: name) {
                    prims.append(.image(handle, bounds, radius: 2 * s))
                    imagePrimitives += 1
                }
                semantic = SemanticNode(role: .image, label: node.accessibility.label ?? name,
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

        if let semantic {
            b.committed[node.id] = CommittedSemantic(
                role: semantic.role, label: semantic.label, toggled: semantic.toggled,
                selected: semantic.selected, disabled: semantic.disabled,
                runTexts: semantic.runs.map(\.text))
        }
        if let presentation = node.presentation {
            b.presentation = (node.id, presentation)
        }
        if let items = node.menu {
            menuHosts[id] = node.id
            menuItemsByHost[node.id] = items
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

    /// In-window menu (fallback only: a result of -2, or a run without --live-modal). One role-menu container with one
    /// role-menuItem row per top-level entry, below the host.
    private func emitOverlay(_ overlay: (hostBridge: UInt64, hostRuntime: String, items: [ResolvedMenuItem], rect: Rect),
                             into b: inout Builder) {
        let s = scale
        let rowH = 26 * s
        let containerID = bridgeID("overlay-menu/\(overlay.hostRuntime)")
        let total = Rect(x: overlay.rect.x, y: overlay.rect.y, w: overlay.rect.w, h: rowH * Float(overlay.items.count))
        b.parents[containerID] = 0
        let containerRole = NodeRole.menu
        b.upserts.append(NodeUpsert(id: containerID, parent: 0, order: 1000, flags: [], bounds: total,
                                    primitives: [], semantic: SemanticNode(role: containerRole,
                                                                           identifier: "sr1/\(screen)/menu-popup")))
        b.committed["overlay-menu/\(overlay.hostRuntime)"] = CommittedSemantic(
            role: containerRole, label: "", toggled: .none, selected: nil, disabled: false, runTexts: [])
        var y = overlay.rect.y
        for (index, item) in overlay.items.enumerated() {
            let oid = bridgeID("overlay/\(overlay.hostRuntime)/\(index)")
            let rect = Rect(x: overlay.rect.x, y: y, w: overlay.rect.w, h: rowH)
            y += rowH
            b.parents[oid] = containerID
            var prims: [Primitive] = []
            if item.kind == .divider {
                prims.append(.rect(Rect(x: rect.x, y: rect.y + rowH / 2, w: rect.w, h: max(1, s)),
                                   color: faded(GalleryStyle.dividerColor, 1)))
                b.upserts.append(NodeUpsert(id: oid, parent: containerID, order: UInt32(index), flags: [],
                                            bounds: rect, primitives: prims, semantic: nil))
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
            overlayRowsCommitted += 1
            let semantic = SemanticNode(role: .menuItem, label: item.title,
                                        actions: enabled ? [.invoke, .focus] : [],
                                        identifier: "sr1/\(screen)/menu-item/\(item.title)",
                                        disabled: !enabled)
            b.committed["overlay/\(overlay.hostRuntime)/\(index)"] = CommittedSemantic(
                role: .menuItem, label: item.title, toggled: .none, selected: nil, disabled: !enabled, runTexts: [])
            b.upserts.append(NodeUpsert(
                id: oid, parent: containerID, order: UInt32(index),
                flags: enabled ? [.hitTarget, .focusable] : [], bounds: rect, primitives: prims,
                semantic: semantic))
        }
    }

    /// The presented alert or dialog as a semantic node (role alert or dialog) covering the window. No primitives and
    /// no hit target: the native dialog is the visible surface.
    private func emitPresentation(_ p: (host: String, value: ResolvedPresentation), into b: inout Builder) {
        let id = bridgeID("presentation/\(p.host)")
        let role: NodeRole = p.value.kind == "alert" ? .alert : .dialog
        b.parents[id] = 0
        b.upserts.append(NodeUpsert(id: id, parent: 0, order: 2000, flags: [], bounds: windowPx, primitives: [],
                                    semantic: SemanticNode(role: role, label: p.value.title)))
        b.committed["presentation/\(p.host)"] = CommittedSemantic(
            role: role, label: p.value.title, toggled: .none, selected: nil, disabled: false, runTexts: [])
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
        guard !plan.unsupported else {
            activeDialogRequestID = nil
            return
        }
        // The request id is taken even when nothing is sent, so the self-test can answer it through modalResult.
        let requestID = nextModalRequest
        nextModalRequest += 1
        activeDialogRequestID = requestID
        // The self-test never opens a task dialog (it would block on a human). Live runs (--live-modal) do.
        guard liveModal, let window else { return }
        do {
            try window.requestDialog(requestID: requestID, title: p.title, message: p.message ?? "",
                                     buttons: plan.buttons, defaultIndex: 0)
            nativeDialogRequests += 1
        } catch {
            commitErrors.append("requestDialog: \(error)")
            activeDialogRequestID = nil
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
            if ev.axAction == .invoke {
                invoke(node: ev.node)
            }
        case .modalResult:
            let choice = ev.modalChoice
            let index = ev.modalFailed ? -2 : (choice?.index ?? -1)
            modalResult(requestID: ev.arg, kind: ev.action, itemID: choice?.itemID ?? 0, index: index)
        case .windowMetrics:
            applyMetrics(width: ev.i0, height: ev.i1, scale: ev.x)
        case .focus, .ime:
            break
        }
        flushIfDirty()
        afterInput?()
    }

    /// Activates a bridge node: button, toggle, menu host or overlay item. Disabled nodes are refused by the renderer
    /// (no event reaches here) and by the runtime (tapButton / activateToggle return false).
    func invoke(node: UInt64) {
        if let runtimeID = buttons[node] {
            invokesSent += 1
            _ = graph?.tapButton(runtimeID)
        } else if let runtimeID = toggles[node] {
            invokesSent += 1
            _ = graph?.activateToggle(runtimeID)
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
            // A press outside the open overlay closes it, then the press is handled normally.
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
        if openMenuHost == host {
            closeMenu()
        } else {
            openMenu(hostRuntimeID: host)
        }
    }

    /// Opens a menu host: a native popup at the pointer on live runs, otherwise (and when the popup could not be shown)
    /// the in-window overlay.
    func openMenu(hostRuntimeID: String) {
        menuOpens += 1
        if liveModal, let window, let items = menuItemsByHost[hostRuntimeID] {
            let requestID = nextModalRequest
            nextModalRequest += 1
            do {
                try window.requestMenu(requestID: requestID, items: galleryMenuItems(items), x: -1, y: -1)
                pendingMenus[requestID] = hostRuntimeID
                nativeMenuRequests += 1
                return
            } catch {
                commitErrors.append("requestMenu: \(error)")
            }
        }
        showOverlay(hostRuntimeID)
    }

    private func showOverlay(_ host: String) {
        overlayOpens += 1
        openMenuHost = host
        dirty = true
    }

    func closeMenu() {
        openMenuHost = nil
        dirty = true
    }

    /// Answer from a native popup (kind 2, requestMenu) or task dialog (kind 3, requestDialog). `index` is -1 when the
    /// user dismissed it and -2 when it could not be shown; otherwise `itemID` names the chosen item (id - 1 = index).
    /// Also driven by the self-test with the same arguments the renderer sends.
    func modalResult(requestID: UInt64, kind: UInt32, itemID: UInt32, index: Int) {
        modalResults.append(index)
        switch kind {
        case 2:
            guard let host = pendingMenus.removeValue(forKey: requestID) else {
                staleModalResults += 1
                return
            }
            if index == -2 {
                // The popup could not be shown: fall back to the in-window overlay.
                menuFailures += 1
                showOverlay(host)
                return
            }
            guard index >= 0, itemID > 0 else { return }
            menuPicks += 1
            _ = graph?.performMenuItem(host, path: [Int(itemID) - 1])
        case 3:
            guard requestID == activeDialogRequestID, let host = activePresentationHost else {
                staleModalResults += 1
                return
            }
            activeDialogRequestID = nil
            if index == -2 {
                dialogFailures += 1
                _ = graph?.dismissPresentation(host)
            } else if index >= 0, itemID > 0 {
                _ = graph?.performPresentationAction(host, index: Int(itemID) - 1)
            } else {
                _ = graph?.dismissPresentation(host)
            }
        default:
            staleModalResults += 1
        }
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

    private func applyMetrics(width: Int32, height: Int32, scale newScale: Float) {
        guard width > 0, height > 0 else { return }
        windowPx = Rect(x: 0, y: 0, w: Float(width), h: Float(height))
        graph?.rootProposal = ProposedViewSize(width: CGFloat(width) / CGFloat(scale),
                                               height: CGFloat(height) / CGFloat(scale))
        dirty = true
    }

    // MARK: queries for the self-test

    func runtimeIDOfFocusedField() -> String? { runtimeFocus }
    func isClosed() -> Bool { closedFlag }
    func measurerFailures() -> Int { measurer?.failures ?? 0 }
}
