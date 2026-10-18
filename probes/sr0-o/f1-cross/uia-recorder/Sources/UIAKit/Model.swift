import Foundation


// MARK: trace schema mirror
// TraceKit's types have no public memberwise initialisers (and the comparator must not be edited), so the
// recorder writes structurally identical Codable mirrors. The JSON is decoded by TraceKit's own types in
// UIACompare and in the tests, which is the compatibility proof.

public struct WPlatform: Codable, Sendable, Equatable { public var os: String, osBuild: String, arch: String, toolchain: String }
public struct WStep: Codable, Sendable, Equatable { public var id: String, logicalAction: String, nativeMapping: String, timestamp: String }
public struct WRange: Codable, Sendable, Equatable { public var location: Int, length: Int }
public struct WLifecycle: Codable, Sendable, Equatable { public var kind: String, node: String }
public struct WNode: Codable, Sendable, Equatable {
    public var id: String, role: String
    public var label: String?, value: String?
    public var actions: [String]
    public var parent: String?
    public var order: Int
}
public struct WObservation: Codable, Sendable, Equatable {
    public var stepId: String
    public var model: [String: String]
    public var focusedNodeId: String?
    public var selection: WRange?
    public var lifecycle: [WLifecycle]
    public var effects: [String]
    public var axNodes: [WNode]?
}
public struct WOrderEdge: Codable, Sendable, Equatable { public var before: String, after: String }
public struct WTrace: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var fixtureId: String
    public var sourceHash: String
    public var platform: WPlatform
    public var steps: [WStep]
    public var observations: [WObservation]
    public var declaredOrder: [WOrderEdge]
}

public func encodeJSON<T: Encodable>(_ v: T) throws -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try e.encode(v)
}

// MARK: raw UIA node (what the recorder reads from the live tree)

public struct PixelRect: Codable, Sendable, Equatable {
    public var x: Int, y: Int, w: Int, h: Int
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
}

/// One RawView node. `index` is the DFS position in the walk that produced it (the live element handle table key).
public struct UIANode: Codable, Sendable, Equatable {
    public var index: Int
    public var controlType: String
    public var controlTypeId: Int
    public var automationId: String
    public var name: String
    public var className: String
    public var value: String?
    public var patterns: [String]
    public var bounds: PixelRect?      // physical px (process is per-monitor-v2 DPI aware)
    public var hasFocus: Bool
    public var children: [UIANode]

    public init(index: Int, controlType: String, controlTypeId: Int = 0, automationId: String = "", name: String = "",
                className: String = "", value: String? = nil, patterns: [String] = [], bounds: PixelRect? = nil,
                hasFocus: Bool = false, children: [UIANode] = []) {
        self.index = index; self.controlType = controlType; self.controlTypeId = controlTypeId
        self.automationId = automationId; self.name = name; self.className = className; self.value = value
        self.patterns = patterns; self.bounds = bounds; self.hasFocus = hasFocus; self.children = children
    }

    public func flatten() -> [UIANode] { [self] + children.flatMap { $0.flatten() } }
}

// MARK: windows normalizer (extends comparator's stub UIANormalizer; see RESULT.md "Normalizer deltas")

private func nonEmpty(_ s: String?) -> String? {
    guard let s, !s.isEmpty else { return nil }
    return s
}

public struct NormalizedTree: Sendable {
    public var nodes: [WNode]
    public var idByIndex: [Int: String]   // UIANode.index -> canonical id (kept nodes only)
}

public enum WinNormalizer {
    /// Same stripped set as the comparator stub plus the UIA containers AccessKit/Win32 add around a window.
    public static let strippedTypes: Set<String> = ["Pane", "Group", "Custom"]

    /// Native window chrome (system menu, minimize/maximize/close): dropped with its whole subtree. It is not fixture
    /// content, and the Mac side's equivalent (AXCloseButton, AXFullScreenButton, AXToolbar) must be dropped by the
    /// Mac normalizer for cross-platform runs (see RESULT.md gaps).
    public static let droppedSubtrees: Set<String> = ["TitleBar"]

    public static let roleMap: [String: String] = [
        "Edit": "text-field", "Button": "button", "List": "list", "ListItem": "list-item",
        "Window": "window", "Text": "static-text",
    ]

    public static let patternMap: [String: String] = [
        "InvokePattern": "activate", "ValuePattern": "set-value", "ExpandCollapsePattern": "expand-collapse",
        "TogglePattern": "toggle", "SelectionItemPattern": "select",
    ]

    /// Patterns that describe a readable surface, not an action. Mac has no action for these either
    /// (AXSelectedTextRange / AXValue are attributes), so listing them would diff on every text field.
    public static let nonActionPatterns: Set<String> = [
        "TextPattern", "TextPattern2", "TextEditPattern", "LegacyIAccessiblePattern", "ItemContainerPattern",
        "VirtualizedItemPattern", "SynchronizedInputPattern", "WindowPattern", "TransformPattern",
        "ScrollItemPattern", "SelectionPattern", "ScrollPattern",
    ]

    public static func normalize(_ root: UIANode) -> NormalizedTree {
        var counts: [String: Int] = [:]
        for n in root.flatten() { if let id = nonEmpty(n.automationId) { counts[id, default: 0] += 1 } }
        let duplicated = Set(counts.filter { $0.value > 1 }.keys)
        var out: [WNode] = []
        var map: [Int: String] = [:]
        var rootOrder = 0
        visit(root, parentId: nil, order: &rootOrder, duplicated: duplicated, out: &out, map: &map)
        return NormalizedTree(nodes: out, idByIndex: map)
    }

    private static func visit(_ n: UIANode, parentId: String?, order: inout Int, duplicated: Set<String>,
                              out: inout [WNode], map: inout [Int: String]) {
        if droppedSubtrees.contains(n.controlType) { return }
        if strippedTypes.contains(n.controlType) {
            for c in n.children { visit(c, parentId: parentId, order: &order, duplicated: duplicated, out: &out, map: &map) }
            return
        }
        let myOrder = order
        order += 1
        let id: String
        if let ident = nonEmpty(n.automationId) {
            id = duplicated.contains(ident) ? "\(ident)~\(parentId ?? "root")#\(myOrder)" : ident
        } else {
            id = "anon:\(parentId ?? "root")#\(myOrder)"
        }
        map[n.index] = id
        let actions = Array(Set(n.patterns.filter { !nonActionPatterns.contains($0) }.map { patternMap[$0] ?? $0 })).sorted()
        out.append(WNode(id: id, role: roleMap[n.controlType] ?? n.controlType, label: nonEmpty(n.name),
                           value: n.value, actions: actions, parent: parentId, order: myOrder))
        var childOrder = 0
        for c in n.children { visit(c, parentId: id, order: &childOrder, duplicated: duplicated, out: &out, map: &map) }
    }
}

// MARK: fixture step file (logical stimuli; replayed, never recorded output)

public struct Selector: Codable, Sendable, Equatable {
    public var id: String?        // AutomationId or canonical id
    public var name: String?
    public var type: String?      // UIA control type name, e.g. "Button"
    public var nth: Int?          // pick the nth match (0-based) when several match
    public var after: String?     // only nodes after (document order) the node with this AutomationId / canonical id
    public init(id: String? = nil, name: String? = nil, type: String? = nil, nth: Int? = nil, after: String? = nil) {
        self.id = id; self.name = name; self.type = type; self.nth = nth; self.after = after
    }
    public var summary: String {
        var parts: [String] = []
        if let id { parts.append("id=\(id)") }
        if let type { parts.append("type=\(type)") }
        if let name { parts.append("name=\(name)") }
        if let nth { parts.append("nth=\(nth)") }
        if let after { parts.append("after=\(after)") }
        return parts.joined(separator: ",")
    }
}

/// op: focus | type | key | command | invoke | setValue | select | wait | waitFor (target + optional expected `value`, `ms` = timeout)
public struct Op: Codable, Sendable, Equatable {
    public var op: String
    public var target: Selector?
    public var text: String?       // type: text; key: chord like "ctrl+c" or "tab"; command: copy|paste|undo|redo|selectAll
    public var value: String?      // setValue
    public var location: Int?      // select (UTF-16)
    public var length: Int?
    public var ms: Int?            // wait
    public var width: Int?         // resize: client width in DIP
    public var height: Int?        // resize: client height in DIP
    public var absent: Bool?       // waitFor: wait until the node is gone instead of present
    public init(op: String, target: Selector? = nil, text: String? = nil, value: String? = nil,
                location: Int? = nil, length: Int? = nil, ms: Int? = nil, width: Int? = nil, height: Int? = nil, absent: Bool? = nil) {
        self.op = op; self.target = target; self.text = text; self.value = value
        self.location = location; self.length = length; self.ms = ms; self.width = width; self.height = height; self.absent = absent
    }
}

public struct StepSpec: Codable, Sendable, Equatable {
    public var id: String
    public var logicalAction: String
    public var ops: [Op]
    public var capture: Bool?      // include the canonical AX tree in this step's observation
    public var settleMs: Int?      // wait after the ops before observing (default 300)
}

public struct FixtureSteps: Codable, Sendable, Equatable {
    public var fixtureId: String
    public var sourceHash: String
    /// model key -> node whose Value (else Name) is that key's text, e.g. {"node/edit": {type: Edit}}
    public var modelNodes: [String: Selector]?
    public var declaredOrder: [WOrderEdge]?
    public var steps: [StepSpec]
    public init(fixtureId: String, sourceHash: String, modelNodes: [String: Selector]? = nil,
                declaredOrder: [WOrderEdge]? = nil, steps: [StepSpec] = []) {
        self.fixtureId = fixtureId; self.sourceHash = sourceHash; self.modelNodes = modelNodes
        self.declaredOrder = declaredOrder; self.steps = steps
    }
}

// MARK: native mapping text (CONTRACT §4 vocabulary) for the trace's `nativeMapping`

public enum NativeMapping {
    public static func describe(_ ops: [Op]) -> String {
        if ops.isEmpty { return "UIA tree walk (RawView) from window root" }
        return ops.map(one).joined(separator: "; ")
    }

    static func one(_ o: Op) -> String {
        let t = o.target.map { " [\($0.summary)]" } ?? ""
        switch o.op {
        case "focus": return "UIA SetFocus\(t)"
        case "invoke": return "UIA InvokePattern.Invoke\(t)"
        case "setValue": return "UIA ValuePattern.SetValue(\(o.value ?? ""))\(t)"
        case "type": return "type '\(o.text ?? "")'\(t) (SendInput VK keys, or WM_CHAR posted to the window when SR0O_KEY_DELIVERY=targeted)"
        case "key": return "SendInput VK \(o.text ?? "")\(t)"
        case "command":
            let m = ["copy": "Ctrl-C", "paste": "Ctrl-V", "undo": "Ctrl-Z", "redo": "Ctrl-Y", "selectAll": "Ctrl-A"]
            return "SendInput \(m[o.text ?? ""] ?? o.text ?? "?")\(t)"
        case "select": return "UIA TextPattern select UTF-16 \(o.location ?? 0)+\(o.length ?? 0)\(t)"
        case "wait": return "wait \(o.ms ?? 0) ms"
        case "resize": return "MoveWindow client \(o.width ?? 0)x\(o.height ?? 0) DIP (window-targeted)"
        case "close": return "WM_CLOSE posted to the fixture window"
        case "touch": return "harness release signal file (fake-engine release)"
        case "waitFor": return "UIA poll until node \(o.absent == true ? "absent" : "present")\(t) (settlement, timeout \(o.ms ?? 10000) ms)"
        default: return o.op
        }
    }
}

// MARK: selector resolution over a walked tree

public enum Resolve {
    public static func find(_ s: Selector, in root: UIANode, ids: [Int: String]) -> UIANode? {
        let all = root.flatten()
        var start = 0
        if let anchor = s.after {
            guard let at = all.firstIndex(where: { $0.automationId == anchor || ids[$0.index] == anchor }) else { return nil }
            start = at + 1
        }
        let hits = all[start...].filter { n in
            if let id = s.id, n.automationId != id, ids[n.index] != id { return false }
            if let t = s.type, n.controlType != t { return false }
            if let nm = s.name, n.name != nm { return false }
            return true
        }
        let k = s.nth ?? 0
        return k < hits.count ? hits[k] : nil
    }
}

// MARK: extra (non-schema) per-step data written to the sidecar

public struct OpResult: Codable, Sendable, Equatable {
    public var op: String
    public var ok: Bool
    public var detail: String
}

public struct StepExtra: Codable, Sendable, Equatable {
    public var stepId: String
    public var opResults: [OpResult]
    public var focusedAutomationId: String?
    public var focusedControlType: String?
    public var focusedValue: String?
    public var selectionText: String?
    public var caretRect: [Double]?      // [x, y, w, h] physical px of the one-character range at the caret
    public var tree: UIANode?            // raw RawView tree with BoundingRectangle
    public var monoStartNs: UInt64?      // DispatchTime uptime at the first op of the step (same clock as the target's mono_ns)
    public var monoEndNs: UInt64?        // DispatchTime uptime when the observation was taken
    public var foregroundAtSnapshot: Bool?  // target process owned the foreground when the tree was read (activated first if not)
    public var focusSettleMs: Int?          // ms waited for a focused node to appear (0 when present at once; nil when none appeared)
}

public struct Sidecar: Codable, Sendable, Equatable {
    public var windowHandle: Int64
    public var pid: Int
    public var dpi: Int?
    public var steps: [StepExtra]
}

// MARK: trace assembly

public enum TraceAssembly {
    public static func platform(toolchain: String) -> WPlatform {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(x86_64)
        let arch = "x64"
        #elseif arch(arm64)
        let arch = "arm64"
        #else
        let arch = "unknown"
        #endif
        #if os(Windows)
        let os = "windows"
        #else
        let os = "macos"
        #endif
        return WPlatform(os: os, osBuild: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)", arch: arch, toolchain: toolchain)
    }

    public static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
