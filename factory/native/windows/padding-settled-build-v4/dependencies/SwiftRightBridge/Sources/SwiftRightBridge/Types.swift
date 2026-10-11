import CSwiftRight
import Foundation

// Platform-neutral value types of the bridge. Geometry is PHYSICAL pixels, origin at the
// window client top-left (swiftright.h, UNITS). Node ids are Swift-owned and non-zero;
// 0 is the window root. AX text-run ids live in the same namespace as node ids.

public typealias NodeID = UInt64

public struct Rect: Equatable {
    public var x: Float, y: Float, w: Float, h: Float
    public init(x: Float, y: Float, w: Float, h: Float) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
    public static let zero = Rect(x: 0, y: 0, w: 0, h: 0)
    public func contains(_ px: Float, _ py: Float) -> Bool {
        px >= x && py >= y && px < x + w && py < y + h
    }
}

public enum NodeRole: UInt32 {
    case none = 0, window, button, staticText, textField, list, listItem, group
    /// ABI rev 0.6. AccessKit roles: CheckBox, Switch, Image, Menu, MenuItem, AlertDialog, Dialog.
    case checkbox = 8, switchControl, image, menu, menuItem, alert, dialog
}

/// ABI rev 0.6: checked / pressed / on state (AccessKit Toggled, UIA TogglePattern).
public enum ToggledState: UInt32 {
    case none = 0, off, on, mixed
}

public struct AXActions: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let invoke = AXActions(rawValue: 0x1)
    public static let focus = AXActions(rawValue: 0x2)
    public static let setValue = AXActions(rawValue: 0x4)
    public static let setSelection = AXActions(rawValue: 0x8)
}

public struct NodeFlags: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let hitTarget = NodeFlags(rawValue: 0x1)
    public static let focusable = NodeFlags(rawValue: 0x2)
    public static let editable = NodeFlags(rawValue: 0x4)
}

/// Retained shaped-text handle returned by `Bridge.measure`. Release it explicitly with
/// `Bridge.release(_:)` (owner frees). Opaque, generation-tagged.
public struct TextRunHandle: Hashable {
    public let raw: UInt64
    public init(raw: UInt64) { self.raw = raw }
}

/// Retained RGBA8 image (ABI rev 0.6). Create with `Bridge.registerImage`, release with
/// `Bridge.release(_:)` (owner frees). Opaque, generation-tagged; dropped when the window closes.
public struct ImageHandle: Hashable {
    public let raw: UInt64
    public init(raw: UInt64) { self.raw = raw }
}

/// Retained-primitive vocabulary. `.path` is declared by ABI v0 and rejected by the
/// renderer with `unsupported` until a later revision.
public enum Primitive {
    case rect(Rect, color: UInt32, radius: Float = 0, borderColor: UInt32 = 0, borderWidth: Float = 0)
    case text(TextRunHandle, x: Float, y: Float)
    /// rev 0.6: the image scaled to fill the rect, with an optional corner radius (physical px).
    case image(ImageHandle, Rect, radius: Float = 0)
    case path
    case clipPush(Rect)
    case clipPop
    /// v0: translation only.
    case translatePush(dx: Float, dy: Float)
    case translatePop
    /// rev 0.5: solid bar. `rect` gives the origin (x, y), the length (w) and the thickness
    /// (h, physical px, > 0). Used for IME marked-text underlines.
    case underline(Rect, color: UInt32)
}

/// One visual line of a text node, published as an AccessKit TextRun child.
public struct AXTextRun {
    public var id: NodeID
    public var text: String
    public var charLengths: [UInt8]
    public var charPositions: [Float]
    public var charWidths: [Float]
    public var wordStarts: [UInt8]
    public var bounds: Rect
    public init(id: NodeID, text: String, charLengths: [UInt8], charPositions: [Float],
                charWidths: [Float], wordStarts: [UInt8], bounds: Rect) {
        self.id = id; self.text = text; self.charLengths = charLengths
        self.charPositions = charPositions; self.charWidths = charWidths
        self.wordStarts = wordStarts; self.bounds = bounds
    }
}

public struct TextSelectionPosition {
    public var run: NodeID
    public var character: UInt32
    public init(run: NodeID, character: UInt32) { self.run = run; self.character = character }
}

public struct SemanticNode {
    public var role: NodeRole
    public var label: String
    public var value: String
    public var actions: AXActions
    public var multiline: Bool
    public var runs: [AXTextRun]
    public var selection: (anchor: TextSelectionPosition, focus: TextSelectionPosition)?
    /// Stable automation identifier (ABI rev 0.4): Windows UIA AutomationId; the Mac
    /// counterpart is AXIdentifier. Host-owned, UTF-8, at most 256 bytes, empty = none.
    /// Keep it unique among siblings.
    public var identifier: String
    /// ABI rev 0.6: toggle state. `.none` = not a toggle. Checkbox, switch and toggle buttons
    /// publish AccessKit Toggled (UIA TogglePattern).
    public var toggled: ToggledState
    /// ABI rev 0.6: nil = the concept does not apply; true/false publish AccessKit `selected`
    /// (UIA SelectionItemPattern for list items).
    public var selected: Bool?
    /// ABI rev 0.6: SWR_SEM_DISABLED. UIA IsEnabled = false and no invoke/toggle/select; the
    /// renderer also swallows pointer presses on a disabled node (event node 0).
    public var disabled: Bool
    public init(role: NodeRole, label: String = "", value: String = "", actions: AXActions = [],
                multiline: Bool = false, runs: [AXTextRun] = [],
                selection: (anchor: TextSelectionPosition, focus: TextSelectionPosition)? = nil,
                identifier: String = "", toggled: ToggledState = .none, selected: Bool? = nil,
                disabled: Bool = false) {
        self.role = role; self.label = label; self.value = value; self.actions = actions
        self.multiline = multiline; self.runs = runs; self.selection = selection
        self.identifier = identifier; self.toggled = toggled; self.selected = selected
        self.disabled = disabled
    }
}

public struct NodeUpsert {
    public var id: NodeID
    public var parent: NodeID
    public var order: UInt32
    public var flags: NodeFlags
    public var bounds: Rect
    public var primitives: [Primitive]
    public var semantic: SemanticNode?
    public init(id: NodeID, parent: NodeID = 0, order: UInt32 = 0, flags: NodeFlags = [],
                bounds: Rect, primitives: [Primitive] = [], semantic: SemanticNode? = nil) {
        self.id = id; self.parent = parent; self.order = order; self.flags = flags
        self.bounds = bounds; self.primitives = primitives; self.semantic = semantic
    }
}

/// One versioned commit. Removes apply first (descendants go with them), then upserts.
public struct Transaction {
    public var version: UInt64
    public var focus: NodeID
    public var upserts: [NodeUpsert]
    public var removes: [NodeID]
    public init(version: UInt64, focus: NodeID = 0, upserts: [NodeUpsert] = [], removes: [NodeID] = []) {
        self.version = version; self.focus = focus; self.upserts = upserts; self.removes = removes
    }
}

// MARK: measurement

public struct MeasureRequest {
    /// Rev 0.6: '\n' separates paragraphs (each wraps on its own); '\r' is rejected.
    public var text: String
    public var fontFamily: String
    public var locale: String
    public var weight: UInt32
    public var color: UInt32            // 0xRRGGBBAA, baked into the shaped run
    public var fontSize: Float          // DIPs
    public var lineHeight: Float        // DIPs
    public var scale: Float             // dpi / 96
    public var maxWidth: Float          // physical px, <= 0 unbounded
    public init(text: String, fontFamily: String = "Segoe UI", locale: String = "en-US",
                weight: UInt32 = 400, color: UInt32 = 0x1F1F1FFF, fontSize: Float = 16,
                lineHeight: Float = 24, scale: Float, maxWidth: Float = 0) {
        self.text = text; self.fontFamily = fontFamily; self.locale = locale; self.weight = weight
        self.color = color; self.fontSize = fontSize; self.lineHeight = lineHeight
        self.scale = scale; self.maxWidth = maxWidth
    }
}

public struct LineInfo: Equatable {
    public var utf8Start: UInt32, utf8Len: UInt32
    public var width: Float, top: Float, baseline: Float
}

public struct TextMeasurement {
    public var run: TextRunHandle
    public var width: Float, height: Float
    public var firstBaseline: Float, lastBaseline: Float
    public var lines: [LineInfo]
    public var charCount: UInt32
    public var cacheHit: Bool
    public var cacheKey: UInt64
    public var lineCount: Int { lines.count }
}

public struct CharCell: Equatable {
    public var utf8Offset: UInt32, utf8Len: UInt32
    public var line: UInt32
    public var wordStart: Bool
    /// Rev 0.6: this cell is the '\n' character (zero width, at the end of the line it ends).
    public var lineBreak: Bool
    public var x0: Float, x1: Float      // physical px, relative to the start of the line
}

// MARK: events

public struct BridgeEvent {
    public enum Kind: UInt32 {
        case key = 1, pointer, focus, ime, axAction, modalResult, windowMetrics
    }
    public enum AXAction: UInt32 { case invoke = 1, focus, setValue, setSelection }

    public var kindRaw: UInt32
    public var action: UInt32
    public var window: UInt64
    public var node: NodeID
    public var snapshot: UInt64
    public var seq: UInt64
    public var arg: UInt64
    public var x: Float, y: Float
    public var i0: Int32, i1: Int32
    public var modifiers: UInt32
    /// KEY: key name. AX_SET_VALUE: new value.
    public var text: String
    /// KEY only: the typed character (may be empty).
    public var typed: String

    /// Rev 0.6 `.modalResult` of a menu or custom-button dialog: the chosen item's host id and
    /// its index, or nil when dismissed (and for plain message boxes, which report `i0`).
    public var modalChoice: (itemID: UInt32, index: Int)? {
        guard kind == .modalResult, action == 2 || action == 3, i1 >= 0, i0 > 0 else { return nil }
        return (UInt32(i0), Int(i1))
    }
    /// Rev 0.6: true when a menu / dialog could not be shown at all (i1 == -2).
    public var modalFailed: Bool { kind == .modalResult && (action == 2 || action == 3) && i1 == -2 }

    public var kind: Kind? { Kind(rawValue: kindRaw) }
    public var axAction: AXAction? { kind == .axAction ? AXAction(rawValue: action) : nil }
}

// MARK: errors

public enum BridgeError: Error, CustomStringConvertible {
    /// Deterministic startup diagnostic, text begins with `SWR_STARTUP_ERROR:`.
    case startup(String)
    /// A typed renderer failure.
    case status(Int32, String)
    case unsupportedPlatform

    public var description: String {
        switch self {
        case .startup(let m): return m
        case .status(let c, let w): return "SWR failure \(statusName(c)) (\(c)) in \(w)"
        case .unsupportedPlatform: return "SwiftRightBridge: renderer loading is only implemented on Windows"
        }
    }
}

public func statusName(_ c: Int32) -> String {
    switch c {
    case 1: return "SWR_EMPTY"
    case 0: return "SWR_OK"
    case -1: return "SWR_E_BAD_ARG"
    case -2: return "SWR_E_PANIC"
    case -3: return "SWR_E_NOT_READY"
    case -4: return "SWR_E_STATE"
    case -5: return "SWR_E_PLATFORM"
    case -6: return "SWR_E_STALE_HANDLE"
    case -7: return "SWR_E_QUEUE_FULL"
    case -8: return "SWR_E_TOO_LARGE"
    case -9: return "SWR_E_BUSY"
    case -10: return "SWR_E_WRONG_THREAD"
    case -11: return "SWR_E_STALE_VERSION"
    case -12: return "SWR_E_NOT_FOUND"
    case -13: return "SWR_E_SHUTDOWN"
    case -14: return "SWR_E_ABI"
    case -15: return "SWR_E_UNSUPPORTED"
    default: return "rc\(c)"
    }
}

// MARK: IME text store (UTF-16 ranges; host owns buffer, selection, composition)

public struct UTF16Span: Equatable {
    public var start: UInt32, end: UInt32
    public init(start: UInt32, end: UInt32) { self.start = start; self.end = end }
}

/// The host's text store for the focused editable node. Called from inside native input
/// handling (see swiftright.h THREADING): edit your own buffer, measure and commit are
/// allowed (commit is presented after the callback unwinds); never pump or open modals.
public protocol TextStore: AnyObject {
    func selection(node: NodeID) -> (range: UTF16Span, reversed: Bool)?
    func markedRange(node: NodeID) -> UTF16Span?
    func text(node: NodeID, range: UTF16Span) -> (units: [UInt16], adjusted: UTF16Span)?
    /// `range == nil`: replace the marked range, else the selection.
    func replace(node: NodeID, range: UTF16Span?, text: [UInt16]) -> Bool
    func replaceAndMark(node: NodeID, range: UTF16Span?, text: [UInt16], newSelection: UTF16Span?) -> Bool
    func unmark(node: NodeID) -> Bool
    /// Physical px client rect of the glyph range (caret-anchored candidate window).
    func caretBounds(node: NodeID, range: UTF16Span) -> Rect?
}
