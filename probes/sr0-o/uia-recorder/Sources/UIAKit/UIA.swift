#if os(Windows)
import Foundation
import CUIA

// Swift side of the UIA recorder. All COM vtable calls live in the CUIA C shim (Sources/CUIA/shim.c);
// see RESULT.md "Why a C shim under Swift".

public struct UIAError: Error, CustomStringConvertible {
    let what: String
    public var description: String { what }
    static func hr(_ code: Int32, _ what: String) -> UIAError {
        UIAError(what: "\(what) failed hr=0x\(String(UInt32(bitPattern: code), radix: 16))")
    }
}

let controlTypeNames: [Int: String] = [
    50000: "Button", 50001: "Calendar", 50002: "CheckBox", 50003: "ComboBox", 50004: "Edit", 50005: "Hyperlink",
    50006: "Image", 50007: "ListItem", 50008: "List", 50009: "Menu", 50010: "MenuBar", 50011: "MenuItem",
    50012: "ProgressBar", 50013: "RadioButton", 50014: "ScrollBar", 50015: "Slider", 50016: "Spinner",
    50017: "StatusBar", 50018: "Tab", 50019: "TabItem", 50020: "Text", 50021: "ToolBar", 50022: "ToolTip",
    50023: "Tree", 50024: "TreeItem", 50025: "Custom", 50026: "Group", 50027: "Thumb", 50028: "DataGrid",
    50029: "DataItem", 50030: "Document", 50031: "SplitButton", 50032: "Window", 50033: "Pane", 50034: "Header",
    50035: "HeaderItem", 50036: "Table", 50037: "TitleBar", 50038: "Separator", 50039: "SemanticZoom", 50040: "AppBar",
]

let patternNames: [Int32: String] = [
    10000: "InvokePattern", 10001: "SelectionPattern", 10002: "ValuePattern", 10003: "RangeValuePattern",
    10004: "ScrollPattern", 10005: "ExpandCollapsePattern", 10009: "WindowPattern", 10010: "SelectionItemPattern",
    10014: "TextPattern", 10015: "TogglePattern", 10016: "TransformPattern", 10017: "ScrollItemPattern",
    10018: "LegacyIAccessiblePattern", 10032: "TextEditPattern",
]

/// Owns one IUIAutomationElement reference.
public final class UIAElement {
    let h: cuia_el
    init(_ h: cuia_el) { self.h = h }
    deinit { cuia_release(h) }

    private func string(_ which: Int32) -> String? {
        var buf = [UInt16](repeating: 0, count: 8192)
        let n = cuia_string(h, which, &buf, Int32(buf.count))
        if n < 0 { return nil }
        if Int(n) > buf.count {   // longer than the buffer: retry once at the exact size
            var big = [UInt16](repeating: 0, count: Int(n))
            _ = cuia_string(h, which, &big, n)
            return String(decoding: big, as: UTF16.self)
        }
        return String(decoding: buf.prefix(Int(n)), as: UTF16.self)
    }

    var automationId: String { string(Int32(CUIA_AUTOMATION_ID)) ?? "" }
    var name: String { string(Int32(CUIA_NAME)) ?? "" }
    var className: String { string(Int32(CUIA_CLASS_NAME)) ?? "" }
    func valueString() -> String? { string(Int32(CUIA_VALUE)) }
    var controlTypeId: Int { Int(cuia_control_type(h)) }
    var hasFocus: Bool { cuia_has_focus(h) != 0 }
    var bounds: PixelRect? {
        var r: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
        let ok = withUnsafeMutablePointer(to: &r) {
            $0.withMemoryRebound(to: Int32.self, capacity: 4) { cuia_bounds(h, $0) }
        }
        guard ok == 0 else { return nil }
        return PixelRect(x: Int(r.0), y: Int(r.1), w: Int(r.2 - r.0), h: Int(r.3 - r.1))
    }

    func supportedPatterns() -> [String] {
        let mask = cuia_pattern_mask(h)
        var out: [String] = []
        for i in 0..<cuia_pattern_count() where mask & (1 << UInt32(i)) != 0 {
            out.append(patternNames[cuia_pattern_id(i)] ?? "Pattern\(cuia_pattern_id(i))")
        }
        return out
    }

    func setFocus() throws { let hr = cuia_set_focus(h); if hr < 0 { throw UIAError.hr(hr, "SetFocus") } }
    func invoke() throws { let hr = cuia_invoke(h); if hr < 0 { throw UIAError.hr(hr, "InvokePattern.Invoke") } }
    func setValue(_ s: String) throws {
        let u = Array(s.utf16)
        let hr = u.withUnsafeBufferPointer { cuia_set_value(h, $0.baseAddress, Int32(u.count)) }
        if hr < 0 { throw UIAError.hr(hr, "ValuePattern.SetValue") }
    }
    func selectRange(location: Int, length: Int) throws {
        let hr = cuia_text_select(h, Int32(location), Int32(length))
        if hr < 0 { throw UIAError.hr(hr, "TextPattern select") }
    }

    func textState() -> TextState? {
        var loc: Int32 = 0, len: Int32 = 0, tlen: Int32 = 0, hasCaret: Int32 = 0
        var buf = [UInt16](repeating: 0, count: 4096)
        var caret = [Double](repeating: 0, count: 4)
        let rc = cuia_text_state(h, &loc, &len, &buf, Int32(buf.count), &tlen, &caret, &hasCaret)
        guard rc == 0 else { return nil }
        return TextState(selection: WRange(location: Int(loc), length: Int(len)),
                         selectionText: String(decoding: buf.prefix(min(Int(tlen), buf.count)), as: UTF16.self),
                         caretRect: hasCaret != 0 ? caret : nil)
    }
}

struct TextState {
    var selection: WRange
    var selectionText: String
    var caretRect: [Double]?
}

public final class Automation {
    public private(set) var handles: [Int: UIAElement] = [:]

    public init() throws {
        let hr = cuia_init()
        if hr != 0 { throw UIAError.hr(hr, "cuia_init") }
    }

    public func element(fromWindow hwnd: UnsafeMutableRawPointer) throws -> UIAElement {
        var e: cuia_el?
        let hr = cuia_element_from_window(hwnd, &e)
        if hr != 0 || e == nil { throw UIAError.hr(hr, "ElementFromHandle") }
        return UIAElement(e!)
    }

    /// Walks RawView under `root`; fills `handles` (DFS index -> live element).
    public func walk(_ root: UIAElement, maxDepth: Int = 40) -> UIANode {
        handles = [:]
        var counter = 0
        return walkNode(root, depth: 0, maxDepth: maxDepth, counter: &counter)
    }

    private func walkNode(_ el: UIAElement, depth: Int, maxDepth: Int, counter: inout Int) -> UIANode {
        let idx = counter
        counter += 1
        handles[idx] = el
        let tid = el.controlTypeId
        var node = UIANode(index: idx, controlType: controlTypeNames[tid] ?? "ControlType\(tid)", controlTypeId: tid,
                           automationId: el.automationId, name: el.name, className: el.className,
                           value: el.valueString(), patterns: el.supportedPatterns(), bounds: el.bounds, hasFocus: el.hasFocus)
        if depth < maxDepth, var cur = cuia_first_child(el.h) {
            while true {
                let child = UIAElement(cur)
                node.children.append(walkNode(child, depth: depth + 1, maxDepth: maxDepth, counter: &counter))
                guard let next = cuia_next_sibling(child.h) else { break }
                cur = next
            }
        }
        return node
    }
}
#endif
