import Foundation
import Observation

// Text input for TextField, shaped after the bridge text store (SwiftRightBridge `TextStore`: selection,
// markedRange, replace, replaceAndMark, unmark), with UTF-16 ranges throughout.
//
// Decisions (SR0-S F7 oracle, headless form):
//   - The bound String holds committed text only. Marked (composing) text is shown in `display` but is
//     written to the binding only when the composition is committed (`unmark`, `replace`, or an edit that
//     leaves the marked range, or `setSelection` outside it).
//   - While composing, an edit replaces the whole marked text. A replacement range that reaches outside
//     the marked text first commits the composition, so it always targets committed text.
//   - Replacing a non-empty selection to start a composition removes the selected text from the binding
//     at once. That removal is a commit, not marked text.
//   - Selection and marked ranges are in displayed-text coordinates (committed text with the composition
//     inserted at `compositionLocation`), as the bridge text store addresses its buffer.

/// A range of UTF-16 code units, as the bridge's `UTF16Span` addresses text.
public struct UTF16Range: Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    var end: Int { location + length }

    func contains(_ other: UTF16Range) -> Bool {
        other.location >= location && other.end <= end
    }
}

/// Per-TextField input state. It is owned by the field's graph node, so composition and selection
/// survive re-evaluation and reinsertion of the field's surroundings.
@MainActor
@Observable
public final class TextInputState {
    @ObservationIgnored var binding: Binding<String>
    /// True for TextEditor (Return inserts a line break), false for TextField.
    public let multiline: Bool
    /// Marked (composing) text. Nil when there is no composition; never empty when set.
    public private(set) var composition: String?
    /// UTF-16 offset in the committed text where the composition is inserted.
    public private(set) var compositionLocation = 0
    /// Caret or selection in displayed-text coordinates.
    public private(set) var selection = UTF16Range(location: 0, length: 0)

    /// Committed text as this state last saw it (read at creation, refreshed after each of its own writes). A bound value that
    /// differs on a later evaluation was set from outside (a model write, an AX `SetValue`).
    @ObservationIgnored private var lastCommitted: String

    init(binding: Binding<String>, multiline: Bool = false) {
        self.binding = binding
        self.multiline = multiline
        self.lastCommitted = binding.wrappedValue
    }

    /// Takes the binding's current value. When it changed without an edit through this state, the caret goes to the end of the
    /// new text (macOS oracle, SR0-O F5: the focused row 1 field reads caret 15 = end of "Row 1 updated 0" after an async
    /// model update, where the caret stood at 5 before). Composition is left alone; its location clamps to the new text.
    func adoptExternalText() {
        let now = binding.wrappedValue
        guard now != lastCommitted else { return }
        lastCommitted = now
        if composition == nil {
            selection = UTF16Range(location: now.utf16.count, length: 0)
        }
    }

    private func noteOwnWrite() {
        lastCommitted = binding.wrappedValue
    }

    /// The bound value: committed text only.
    public var committed: String { binding.wrappedValue }

    /// The displayed text: committed text with the composition inserted.
    public var display: String {
        guard let composition else { return committed }
        let base = Array(committed.utf16)
        let at = clampedLocation(base.count)
        return string(base[0..<at] + Array(composition.utf16) + base[at...])
    }

    /// The marked range in displayed text, nil when not composing.
    public var markedRange: UTF16Range? {
        guard let composition else { return nil }
        return UTF16Range(location: clampedLocation(committed.utf16.count), length: composition.utf16.count)
    }

    /// The text in `range` of the displayed text, nil when the range is out of bounds.
    public func substring(_ range: UTF16Range) -> String? {
        let units = Array(display.utf16)
        guard range.location >= 0, range.length >= 0, range.end <= units.count else { return nil }
        return string(units[range.location..<range.end])
    }

    /// Bridge `replaceAndMark`: replaces `range` (nil: the marked text while composing, else the
    /// selection) with `text` and marks the inserted text. `newSelection` is relative to the inserted text
    /// (NSTextInputClient / GPUI semantics: 0..<count is inside the composition); by default the caret goes to the end of the inserted text. An empty `text` ends
    /// the composition. Returns false when the range is out of bounds.
    @discardableResult
    public func replaceAndMark(range: UTF16Range? = nil, text: String, newSelection: UTF16Range? = nil) -> Bool {
        guard let target = editTarget(range) else { return false }
        var units = Array(display.utf16)
        let inserted = Array(text.utf16)
        units.replaceSubrange(target.location..<target.end, with: inserted)
        let markStart = target.location
        let markEnd = markStart + inserted.count
        let newCommitted = string(Array(units[0..<markStart]) + Array(units[markEnd...]))
        if newCommitted != committed { binding.wrappedValue = newCommitted; noteOwnWrite() }
        composition = inserted.isEmpty ? nil : text
        compositionLocation = markStart
        let relative = newSelection.map { UTF16Range(location: markStart + $0.location, length: $0.length) }
        selection = clamped(relative ?? UTF16Range(location: markEnd, length: 0), count: units.count)
        return true
    }

    /// Bridge `unmark`: commits the composition as displayed. Returns false when not composing.
    @discardableResult
    public func unmark() -> Bool {
        guard composition != nil else { return false }
        let shown = display
        composition = nil
        compositionLocation = 0
        if shown != committed { binding.wrappedValue = shown; noteOwnWrite() }
        return true
    }

    /// Bridge `replace`: replaces `range` (nil: the marked text while composing, else the selection)
    /// with committed `text`, and ends any composition. Returns false when the range is out of bounds.
    @discardableResult
    public func replace(range: UTF16Range? = nil, text: String) -> Bool {
        guard let target = editTarget(range) else { return false }
        var units = Array(display.utf16)
        units.replaceSubrange(target.location..<target.end, with: Array(text.utf16))
        let newCommitted = string(units)
        composition = nil
        compositionLocation = 0
        if newCommitted != committed { binding.wrappedValue = newCommitted; noteOwnWrite() }
        selection = UTF16Range(location: target.location + text.utf16.count, length: 0)
        return true
    }

    /// Return key. While composing it commits the composition, as an IME does, and inserts nothing. Otherwise a
    /// multi-line field replaces the selection with a line break. A single-line field returns false.
    /// Apple: https://developer.apple.com/documentation/swiftui/texteditor
    @discardableResult
    public func insertLineBreak() -> Bool {
        if composition != nil { return unmark() }
        guard multiline else { return false }
        return replace(text: "\n")
    }

    /// Bridge `setSelection`: moves the caret or selection. Leaving the marked text commits it first.
    /// Returns false when the range is out of bounds.
    @discardableResult
    public func setSelection(_ range: UTF16Range) -> Bool {
        if let marked = markedRange, !marked.contains(range) { unmark() }
        let count = display.utf16.count
        guard range.location >= 0, range.length >= 0, range.end <= count else { return false }
        selection = range
        return true
    }

    // MARK: Helpers

    /// The range an edit replaces, or nil when it is out of bounds. While composing, the marked text
    /// is the target; a range outside it commits the composition first, and then targets committed text.
    private func editTarget(_ range: UTF16Range?) -> UTF16Range? {
        let requested = range ?? markedRange ?? selection
        if let marked = markedRange {
            if marked.contains(requested) { return marked }
            unmark()
        }
        let count = display.utf16.count
        guard requested.location >= 0, requested.length >= 0, requested.end <= count else { return nil }
        return requested
    }

    private func clampedLocation(_ count: Int) -> Int {
        min(max(compositionLocation, 0), count)
    }

    private func clamped(_ range: UTF16Range, count: Int) -> UTF16Range {
        let location = min(max(range.location, 0), count)
        let length = min(max(range.length, 0), count - location)
        return UTF16Range(location: location, length: length)
    }

    private func string<C: Collection>(_ units: C) -> String where C.Element == UInt16 {
        String(decoding: units, as: UTF16.self)
    }
}
