import Foundation

// Issue #60 pass 3: the pressed and focused states of a Button.
//
// A Button is pressed from the pointer going down on it until the pointer comes up or leaves its frame (AppKit highlights an NSButton while the press is inside and tracks the
// pointer out and back in). The runtime owns no pointer stream, so the host reports it: `buttonID(atX:y:)` names the Button under the pointer, `setPressedButton(_:)` records
// the held one (nil on release or when the pointer leaves it) and the snapshot's Button node then says `buttonIsPressed`; the host paints the darkened body. The action still runs
// through `tapButton` on release, as before. Focus: a Button has keyboard focus when it is the one `setFocusedButton(_:)` named (the host's full-keyboard-access tab stop) or sits under
// a `.focused` modifier whose binding holds the focus; the host paints the focus ring. A mouse click never focuses a Button on macOS, so a pointer press sets only the pressed state.

extension Graph {
    func buttonIsPressed(_ node: Node) -> Bool {
        guard let pressed = pressedButtonID, pressed == node.idString else { return false }
        return node.environment.isEnabled
    }

    func buttonIsFocused(_ node: Node) -> Bool {
        guard node.environment.isEnabled else { return false }
        if let focused = focusedButtonID, focused == node.idString { return true }
        // a `.focused` modifier directly around the button (only modifiers between them)
        var ancestor = node.parent
        while let a = ancestor, case .modifier = a.kind {
            if case .modifier(.focus) = a.kind, a.focused { return true }
            ancestor = a.parent
        }
        return false
    }

    /// The runtime id of the enabled Button whose frame holds the point (logical points, the graph's coordinates), nil when none does. A Button under
    /// `.allowsHitTesting(false)` takes no press. When Buttons overlap the smallest wins.
    public func buttonID(atX x: CGFloat, y: CGFloat) -> String? {
        var best: Node?
        for candidate in nodes.values where candidate.alive {
            guard case .button = candidate.kind, candidate.environment.isEnabled, candidate.environment.allowsHitTesting else { continue }
            let f = candidate.frame
            guard x >= f.minX, x < f.maxX, y >= f.minY, y < f.maxY else { continue }
            if let current = best, current.frame.width * current.frame.height <= f.width * f.height { continue }
            best = candidate
        }
        return best?.idString
    }

    /// Records the Button the pointer is held down on (nil: none). Returns false, and records nothing, when `id` is not a live enabled Button.
    @discardableResult
    public func setPressedButton(_ id: String?) -> Bool {
        guard let id else { pressedButtonID = nil; return true }
        guard let target = node(id), target.alive, case .button = target.kind, target.environment.isEnabled else { return false }
        pressedButtonID = id
        return true
    }

    /// Records the Button with keyboard focus (nil: none). Returns false, and records nothing, when `id` is not a live enabled Button.
    @discardableResult
    public func setFocusedButton(_ id: String?) -> Bool {
        guard let id else { focusedButtonID = nil; return true }
        guard let target = node(id), target.alive, case .button = target.kind, target.environment.isEnabled else { return false }
        focusedButtonID = id
        return true
    }

    public var pressedButton: String? { pressedButtonID }
    public var focusedButton: String? { focusedButtonID }
}
