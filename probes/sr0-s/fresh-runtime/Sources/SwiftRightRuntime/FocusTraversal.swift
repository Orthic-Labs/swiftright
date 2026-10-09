import Foundation

// Tab / Shift-Tab focus traversal (CONTRACT section 4: both OSes move focus forward and backward).
//
// Tab stops are the nodes that carry a `.focused(_:equals:)` binding: the runtime's only focus model is
// FocusState, so a view with no focus binding cannot take focus. Order is the resolved tree order (document
// order, not path-string order), so ForEach rows come out in row order. Disabled stops are skipped, and
// traversal wraps at both ends.
//
// Assumption (macOS "Keyboard navigation" default, System Settings > Keyboard, off): Tab reaches text fields
// and lists but not buttons or toggles. `tabFocusesAllControls` models the setting turned on. ORACLE ITEM
// for R6: verify on the Mac oracle that Tab skips a focus-bound Button with the default setting.

/// One tab stop, in tree order.
public struct FocusStop: Equatable, Sendable {
    public let nodeID: String
    public let isFocused: Bool
}

extension Graph {
    /// Tab stops in tree order. A stop is a `.focused` node whose content is enabled and, unless
    /// `tabFocusesAllControls`, is not a Button or Toggle.
    public func focusStops() -> [FocusStop] {
        focusNodes().map { FocusStop(nodeID: $0.id.description, isFocused: $0.focused) }
    }

    /// Moves focus to the next (Tab) or previous (Shift-Tab) tab stop, wrapping around. With no current
    /// focus, forward picks the first stop and backward the last. Returns false when there is no stop.
    /// The new focus is committed (one commit record carrying it).
    @discardableResult
    public func moveFocus(forward: Bool) -> Bool {
        let stops = focusNodes()
        guard !stops.isEmpty else { return false }
        let current = stops.firstIndex { $0.focused }
        let target: Int
        switch (current, forward) {
        case (nil, true): target = 0
        case (nil, false): target = stops.count - 1
        case (let i?, true): target = (i + 1) % stops.count
        case (let i?, false): target = (i - 1 + stops.count) % stops.count
        }
        guard case .modifier(.focus(let link)) = stops[target].kind else { return false }
        link.focus()
        flush()
        return true
    }

    /// Dispatches a native key to focus traversal: Tab and Shift-Tab with no other modifier.
    /// Returns true when the key was a traversal key and focus moved.
    @discardableResult
    public func performFocusKey(_ key: KeyEquivalent, modifiers: EventModifiers) -> Bool {
        guard let command = KeyboardChords.command(for: key, modifiers: modifiers, on: keyboardPlatform) else {
            return false
        }
        switch command {
        case .moveFocusForward: return moveFocus(forward: true)
        case .moveFocusBackward: return moveFocus(forward: false)
        default: return false
        }
    }

    private func focusNodes() -> [Node] {
        var out: [Node] = []
        func visit(_ node: Node) {
            guard node.alive else { return }
            if case .modifier(.focus) = node.kind, isTabStop(node) { out.append(node) }
            childNodes(node).forEach(visit)
        }
        if let root { visit(root) }
        return out
    }

    private func isTabStop(_ node: Node) -> Bool {
        guard node.environment.isEnabled else { return false }
        var content = childNodes(node).first
        // Look through user bodies and non-focus modifiers to the control the binding wraps.
        while let current = content {
            if !current.environment.isEnabled { return false }
            switch current.kind {
            case .button, .toggle: return tabFocusesAllControls
            case .user, .modifier: content = childNodes(current).first
            default: return true
            }
        }
        return true
    }
}
