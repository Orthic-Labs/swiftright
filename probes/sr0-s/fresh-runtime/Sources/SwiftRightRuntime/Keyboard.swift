import Foundation

// Keyboard shortcuts. The view modifier, KeyEquivalent and EventModifiers keep the SwiftUI shape:
// https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:modifiers:)
// https://developer.apple.com/documentation/swiftui/keyequivalent
// https://developer.apple.com/documentation/swiftui/eventmodifiers
//
// The runtime owns a registry the backend can query and dispatch into. Native chords are mapped to logical
// commands per CONTRACT section 4. `.command` in a logical chord is the platform's primary modifier (Cmd on
// Mac, Ctrl on Windows); the backend translates native modifiers before dispatch.

/// A key, as SwiftUI names it: one character, or a name for a non-character key.
public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    public let value: String

    public init(_ character: Character) { value = String(character) }

    public init(extendedGraphemeClusterLiteral value: String) { self.value = value }

    init(named: String) { value = named }

    public static let `return` = KeyEquivalent(named: "return")
    public static let escape = KeyEquivalent(named: "escape")
    public static let tab = KeyEquivalent(named: "tab")
    public static let space = KeyEquivalent(named: "space")
    public static let delete = KeyEquivalent(named: "delete")
    public static let upArrow = KeyEquivalent(named: "upArrow")
    public static let downArrow = KeyEquivalent(named: "downArrow")
    public static let leftArrow = KeyEquivalent(named: "leftArrow")
    public static let rightArrow = KeyEquivalent(named: "rightArrow")
}

public struct EventModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = EventModifiers(rawValue: 1 << 0)
    public static let shift = EventModifiers(rawValue: 1 << 1)
    public static let option = EventModifiers(rawValue: 1 << 2)
    public static let control = EventModifiers(rawValue: 1 << 3)
}

/// A key with its modifiers. Apple: https://developer.apple.com/documentation/swiftui/keyboardshortcut
public struct KeyboardShortcut: Hashable, Sendable {
    public let key: KeyEquivalent
    public let modifiers: EventModifiers
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) { self.key = key; self.modifiers = modifiers }
    /// Return, no modifiers: the default button of a window.
    public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
    /// Escape, no modifiers: the cancel button.
    public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])
}

extension KeyboardShortcut {
    /// True for the shortcut that makes a Button the window's default button.
    var isDefaultAction: Bool { key == KeyEquivalent.return && modifiers.isEmpty }
}

public struct KeyboardChord: Hashable, Sendable {
    public let key: KeyEquivalent
    public let modifiers: EventModifiers

    public init(key: KeyEquivalent, modifiers: EventModifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum KeyboardPlatform: Hashable, Sendable {
    case mac
    case windows
}

/// Logical commands from CONTRACT section 4 (SR0 slice inventory).
public enum LogicalCommand: Hashable, Sendable, CaseIterable {
    case copy
    case paste
    case undo
    case redo
    case selectAll
    case moveFocusForward
    case moveFocusBackward
    case activate
}

public enum KeyboardChords {
    /// Native chord for a logical command, per CONTRACT section 4. Redo differs: Shift-Cmd-Z on Mac,
    /// Ctrl-Y on Windows. Every other command uses the same logical chord on both platforms.
    public static func chord(for command: LogicalCommand, on platform: KeyboardPlatform) -> KeyboardChord {
        switch command {
        case .copy: return KeyboardChord(key: "c", modifiers: .command)
        case .paste: return KeyboardChord(key: "v", modifiers: .command)
        case .undo: return KeyboardChord(key: "z", modifiers: .command)
        case .redo:
            switch platform {
            case .mac: return KeyboardChord(key: "z", modifiers: [.command, .shift])
            case .windows: return KeyboardChord(key: "y", modifiers: .command)
            }
        case .selectAll: return KeyboardChord(key: "a", modifiers: .command)
        case .moveFocusForward: return KeyboardChord(key: .tab, modifiers: [])
        case .moveFocusBackward: return KeyboardChord(key: .tab, modifiers: .shift)
        case .activate: return KeyboardChord(key: .space, modifiers: [])
        }
    }

    /// The logical command a chord maps to on a platform, or nil when the chord is not a CONTRACT command.
    public static func command(for chord: KeyboardChord, on platform: KeyboardPlatform) -> LogicalCommand? {
        LogicalCommand.allCases.first { self.chord(for: $0, on: platform) == chord }
    }

    static func command(for key: KeyEquivalent, modifiers: EventModifiers, on platform: KeyboardPlatform) -> LogicalCommand? {
        command(for: KeyboardChord(key: key, modifiers: modifiers), on: platform)
    }
}

/// A shortcut as resolved into the commit record.
public struct ResolvedShortcut: Equatable, Sendable {
    public let chord: KeyboardChord
    public let logical: LogicalCommand?
}

/// One registry entry: a `.keyboardShortcut` modifier, the live button it invokes, and whether it is enabled.
public struct KeyboardShortcutEntry: Equatable, Sendable {
    public let nodeID: String
    public let shortcut: ResolvedShortcut
    /// The button the shortcut invokes. Nil when the shortcut's content has no button.
    public let actionID: String?
    public let isEnabled: Bool
}

extension Graph {
    /// Every `.keyboardShortcut` in the live tree, in path order.
    public func keyboardShortcuts() -> [KeyboardShortcutEntry] {
        orderedNodes().compactMap { node -> KeyboardShortcutEntry? in
            guard case .modifier(.keyboardShortcut(let key, let modifiers)) = node.kind else { return nil }
            let shortcut = ResolvedShortcut(
                chord: KeyboardChord(key: key, modifiers: modifiers),
                logical: KeyboardChords.command(for: key, modifiers: modifiers, on: keyboardPlatform)
            )
            return KeyboardShortcutEntry(
                nodeID: node.id.description,
                shortcut: shortcut,
                actionID: firstButtonID(in: node),
                isEnabled: node.environment.isEnabled
            )
        }
    }

    /// Dispatches a key chord to the first enabled shortcut that names it. Returns false when none applies.
    @discardableResult
    public func performKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers) -> Bool {
        let chord = KeyboardChord(key: key, modifiers: modifiers)
        guard let entry = keyboardShortcuts().first(where: {
            $0.shortcut.chord == chord && $0.isEnabled && $0.actionID != nil
        }), let actionID = entry.actionID else { return false }
        return tapButton(actionID)
    }

    /// The first button inside a node's single-child chain or subtree, in document order.
    private func firstButtonID(in node: Node) -> String? {
        if case .button = node.kind { return node.id.description }
        for child in childNodes(node) {
            if let id = firstButtonID(in: child) { return id }
        }
        return nil
    }
}
