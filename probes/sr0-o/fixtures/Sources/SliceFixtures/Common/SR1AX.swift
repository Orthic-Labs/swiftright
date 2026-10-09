#if os(macOS)
import AppKit
import ApplicationServices
import Foundation

/// In-process accessibility reads and pid-posted keyboard input for the SR1 fixtures.
/// Reads use the same AX API an external client uses, scoped to this process only (AXUIElementCreateApplication(getpid())).
/// Keyboard events are posted with postToPid, never through the global HID tap.
@MainActor
enum SR1AX {
    static func application() -> AXUIElement {
        AXUIElementCreateApplication(getpid())
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func parent(_ element: AXUIElement) -> AXUIElement? {
        guard let value = copy(element, "AXParent"), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func children(_ element: AXUIElement, _ attribute: String = "AXChildren") -> [AXUIElement] {
        (copy(element, attribute) as? [AXUIElement]) ?? []
    }

    static func role(_ element: AXUIElement) -> String? { string(element, "AXRole") }
    static func identifier(_ element: AXUIElement) -> String? { string(element, "AXIdentifier") }

    /// Pre-order, depth-first walk from the application root. Bounded so a runaway tree cannot hang a run.
    /// The same element can be reachable through AXChildren and AXWindows, so visits are deduplicated by CFEqual.
    static func everything(limit: Int = 6000) -> [AXUIElement] {
        var out: [AXUIElement] = []
        var seen: [CFHashCode: [AXUIElement]] = [:]
        var stack: [AXUIElement] = [application()]
        while let element = stack.popLast(), out.count < limit {
            let hash = CFHash(element)
            if seen[hash]?.contains(where: { CFEqual($0, element) }) == true { continue }
            seen[hash, default: []].append(element)
            out.append(element)
            stack.append(contentsOf: children(element).reversed())
            stack.append(contentsOf: children(element, "AXWindows").reversed())
        }
        return out
    }

    /// First element in the tree whose AXIdentifier matches exactly.
    static func find(identifier wanted: String) -> AXUIElement? {
        everything().first { identifier($0) == wanted }
    }

    /// First element with the given AXTitle (or AXDescription) and, optionally, a role.
    static func find(title wanted: String, role wantedRole: String? = nil) -> AXUIElement? {
        everything().first { element in
            if let wantedRole, role(element) != wantedRole { return false }
            return string(element, "AXTitle") == wanted || string(element, "AXDescription") == wanted
        }
    }

    /// Table-like containers (SwiftUI List on macOS maps to AXTable or AXOutline), in tree order.
    static func tables() -> [AXUIElement] {
        everything().filter { ["AXTable", "AXOutline", "AXList"].contains(role($0) ?? "") }
    }

    /// Descendant (or self) of the given element with a text role, if any.
    static func textElement(in root: AXUIElement) -> AXUIElement? {
        var stack = [root]
        while let element = stack.popLast() {
            if ["AXTextArea", "AXTextField"].contains(role(element) ?? "") { return element }
            stack.append(contentsOf: children(element).reversed())
        }
        return nil
    }

    static func press(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, "AXPress" as CFString)
    }

    static func showMenu(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, "AXShowMenu" as CFString)
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    static func setFocused(_ element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, "AXFocused" as CFString, kCFBooleanTrue)
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = copy(element, "AXSelectedTextRange"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    @discardableResult
    static func setSelectedRange(_ element: AXUIElement, location: Int, length: Int) -> AXError {
        var range = CFRange(location: location, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else { return .failure }
        return AXUIElementSetAttributeValue(element, "AXSelectedTextRange" as CFString, value)
    }

    @discardableResult
    static func setSelectedRows(_ table: AXUIElement, rows: [AXUIElement]) -> AXError {
        AXUIElementSetAttributeValue(table, "AXSelectedRows" as CFString, rows as CFArray)
    }

    /// Indices (into AXRows) of the table's currently selected rows.
    static func selectedRowIndices(_ table: AXUIElement) -> [Int] {
        let rows = children(table, "AXRows")
        let selected = children(table, "AXSelectedRows")
        return selected.compactMap { chosen in rows.firstIndex { CFEqual($0, chosen) } }
    }

    /// Stable text form of an AX attribute value. Object addresses are never emitted.
    static func describe(_ value: CFTypeRef?) -> String {
        guard let value else { return "nil" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        if CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = value as! AXValue
            switch AXValueGetType(axValue) {
            case .cfRange:
                var range = CFRange(location: 0, length: 0)
                AXValueGetValue(axValue, .cfRange, &range)
                return "range(\(range.location),\(range.length))"
            default:
                return "axvalue"
            }
        }
        return "cftype(\(CFGetTypeID(value)))"
    }

    // MARK: Input (pid-posted)

    enum Key: String {
        case space, returnKey, delete, escape, a, e, l, s
        var code: CGKeyCode {
            switch self {
            case .space: 49
            case .returnKey: 36
            case .delete: 51
            case .escape: 53
            case .a: 0
            case .e: 14
            case .l: 37
            case .s: 1
            }
        }
    }

    static func tap(_ key: Key, flags: CGEventFlags = []) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key.code, keyDown: down) else { continue }
            event.flags = flags
            event.postToPid(getpid())
        }
    }

    static func typeText(_ text: String) {
        for unit in text.utf16 {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                var character = unit
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
                event.postToPid(getpid())
            }
        }
    }
}
#endif
