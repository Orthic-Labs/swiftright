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

    /// The node a window focuses when it is first shown, or nil when it focuses none.
    ///
    /// Rule (macOS oracle, SR0-O cross-compare of all 16 configurations, `probes/sr0-o/f1-cross/cross-evidence/*/mac-ev-n*.jsonl`):
    /// AppKit makes the first key view of the window's key-view loop the first responder. A `List` is itself a key view and
    /// holds no `FocusState` value, so a window whose first key view is a List reports no focus (F1, F2, F3 list, F4, F6, F7,
    /// F8, F9). Any other container (VStack, ScrollView + LazyVStack, a custom Layout) leaves a focus-bound text field first
    /// in tree order, and `@FocusState` reports that field (F3 vstack and lazy, F5: row 1). Tree order is document order,
    /// as for Tab traversal, and disabled fields and Buttons are skipped as there. Only the 16 recorded configurations are
    /// evidence; a field that precedes a List in tree order taking focus ahead of it is the same rule extended, not observed.
    ///
    /// The event comes after every `onAppear` of the first evaluation and before the first `task` body runs (Mac log order:
    /// root-appear, row appears, focus, task-start); a host calls this once, right after it has created the graph and
    /// committed the first record, before it yields to the main actor. `FocusState` already naming a focus-bound field is
    /// left alone.
    private func initialFocusNode() -> Node? {
        var target: Node?
        var decided = false
        func visit(_ node: Node) {
            guard !decided, node.alive else { return }
            if case .stack(let spec) = node.kind, spec.name == "List" {
                decided = true
                return
            }
            if case .modifier(.focus) = node.kind, isTabStop(node) {
                target = node
                decided = true
                return
            }
            childNodes(node).forEach(visit)
        }
        if let root { visit(root) }
        return target
    }

    /// Gives the window's initial focus (see `initialFocusNode`). Returns the id of the focus-bound node that took focus, or
    /// nil when the window focuses nothing, when a focus-bound field already holds focus, or when the graph is torn down. The new
    /// focus is committed (one commit record carrying it), as in `moveFocus`.
    @discardableResult
    public func applyInitialFocus() -> String? {
        guard let node = initialFocusNode(), case .modifier(.focus(let link)) = node.kind else { return nil }
        if focusNodes().contains(where: { stop in
            if case .modifier(.focus(let other)) = stop.kind { return other.isFocused() }
            return false
        }) {
            return nil
        }
        link.focus()
        flush()
        return node.id.description
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
