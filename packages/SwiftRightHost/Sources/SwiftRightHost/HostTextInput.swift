import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Native text input for the product host: the bridge's IME text store over the runtime's `TextInputState`, and the pointer, key and
/// accessibility events that reach a TextField. A host creates one per window:
///
///     let input = HostTextInput(graph: graph, runtimeID: { runtimeIDs[$0] }, layout: { painter.fieldLayouts[$0] })
///     bridge.textStore = input
///     bridge.onEvent = { event in if input.handle(event) { ... } }     // after painter.commit(..., focused: record.focused)
///
/// Typed characters arrive as `ime_replace` calls (the renderer turns WM_CHAR into them for the focused editable node) and compositions as
/// `ime_replace_and_mark` / `ime_unmark`; Backspace, Delete, arrows, Home, End, Tab, Return and Ctrl-A arrive as key events.
/// The text model is the runtime's (`TextInputState`): the bound String holds committed text, marked text is displayed only.
@MainActor
public final class HostTextInput: @preconcurrency TextStore {
    public let graph: Graph
    private let runtimeID: (UInt64) -> String?
    private let layout: (String) -> TextFieldLayout?
    /// The fixed end of a shift-extended selection per field, kept with the selection it produced: an anchor applies only while the selection is still that one.
    private var shiftAnchors: [String: (anchor: Int, selection: UTF16Range)] = [:]
    /// What the input did, in order (`ime-replace`, `ime-mark`, `key:backspace`, `pointer-focus`, ...), for host diagnostics and tests.
    public private(set) var trace: [String] = []

    public init(graph: Graph, runtimeID: @escaping (UInt64) -> String?, layout: @escaping (String) -> TextFieldLayout? = { _ in nil }) {
        self.graph = graph
        self.runtimeID = runtimeID
        self.layout = layout
    }

    private func state(_ node: UInt64) -> TextInputState? {
        runtimeID(node).flatMap { graph.textInput($0) }
    }

    private func range(_ span: UTF16Span) -> UTF16Range {
        UTF16Range(location: Int(span.start), length: Int(span.end) - Int(span.start))
    }

    // MARK: TextStore (called from inside native input handling)

    public func selection(node: UInt64) -> (range: UTF16Span, reversed: Bool)? {
        guard let s = state(node) else { return nil }
        return (UTF16Span(start: UInt32(s.selection.location), end: UInt32(s.selection.location + s.selection.length)), false)
    }

    public func markedRange(node: UInt64) -> UTF16Span? {
        guard let m = state(node)?.markedRange else { return nil }
        return UTF16Span(start: UInt32(m.location), end: UInt32(m.location + m.length))
    }

    public func text(node: UInt64, range requested: UTF16Span) -> (units: [UInt16], adjusted: UTF16Span)? {
        guard let s = state(node) else { return nil }
        let units = Array(s.display.utf16)
        let start = min(Int(requested.start), units.count), end = min(max(Int(requested.end), start), units.count)
        return (Array(units[start..<end]), UTF16Span(start: UInt32(start), end: UInt32(end)))
    }

    public func replace(node: UInt64, range requested: UTF16Span?, text: [UInt16]) -> Bool {
        guard let s = state(node) else { return false }
        let ok = s.replace(range: requested.map(range), text: String(decoding: text, as: UTF16.self))
        trace.append("ime-replace")
        graph.flush()
        return ok
    }

    public func replaceAndMark(node: UInt64, range requested: UTF16Span?, text: [UInt16], newSelection: UTF16Span?) -> Bool {
        guard let s = state(node) else { return false }
        let ok = s.replaceAndMark(range: requested.map(range), text: String(decoding: text, as: UTF16.self), newSelection: newSelection.map(range))
        trace.append("ime-mark")
        graph.flush()
        return ok
    }

    public func unmark(node: UInt64) -> Bool {
        guard let s = state(node) else { return false }
        let ok = s.unmark()
        trace.append("ime-unmark")
        graph.flush()
        return ok
    }

    public func caretBounds(node: UInt64, range requested: UTF16Span) -> Rect? {
        guard let id = runtimeID(node), let l = layout(id) else { return nil }
        let x0 = l.x(ofOffset: Int(requested.start)), x1 = l.x(ofOffset: Int(requested.end))
        return Rect(x: x0, y: l.textTop, w: max(1, x1 - x0), h: l.lineHeight)
    }

    // MARK: events

    /// Routes one bridge event. Returns true when it was a text-input event the input consumed (the runtime has already been flushed).
    @discardableResult
    public func handle(_ event: BridgeEvent) -> Bool {
        guard let kind = event.kind else { return false }
        switch kind {
        case .pointer:
            guard event.action == 1 else { return false }
            return pointerDown(node: event.node, x: event.x)
        case .axAction:
            guard let action = event.axAction else { return false }
            return accessibility(action, node: event.node, i0: event.i0, i1: event.i1, text: event.text)
        case .key:
            guard event.action == 1 else { return false }
            return handleKey(name: event.text, modifiers: event.modifiers)
        default:
            return false
        }
    }

    /// A pointer press on bridge node `node` at window pixel `x`: a TextField takes the focus and the caret goes to the nearest character boundary.
    public func pointerDown(node: UInt64, x: Float) -> Bool {
        guard let id = runtimeID(node), graph.isTextField(id) else { return false }
        let wasFocused = graph.focusedTextFieldID == id
        let previous = graph.focusedTextFieldID
        guard graph.focusTextField(id) else { return false }
        endComposition(of: previous, leaving: id)
        if let l = layout(id), let s = graph.textInput(id) {
            _ = s.setSelection(UTF16Range(location: min(l.offset(atX: x), s.display.utf16.count), length: 0))
        }
        trace.append(wasFocused ? "pointer-caret" : "pointer-focus")
        graph.flush()
        return true
    }

    public func accessibility(_ action: BridgeEvent.AXAction, node: UInt64, i0: Int32, i1: Int32, text: String) -> Bool {
        guard let id = runtimeID(node), let s = graph.textInput(id), graph.isTextField(id) else { return false }
        switch action {
        case .focus:
            let wasFocused = graph.focusedTextFieldID == id
            let previous = graph.focusedTextFieldID
            guard graph.focusTextField(id) else { return false }
            endComposition(of: previous, leaving: id)
            // an accessibility focus keeps the caret at the end; an echo on the focused field leaves the selection alone
            if !wasFocused { _ = s.setSelection(UTF16Range(location: s.display.utf16.count, length: 0)) }
            trace.append("ax-focus")
        case .setValue:
            _ = s.replace(range: UTF16Range(location: 0, length: s.display.utf16.count), text: text)
            trace.append("ax-set-value")
        case .setSelection:
            let a = Int(i0), f = Int(i1)
            _ = s.setSelection(UTF16Range(location: min(a, f), length: abs(f - a)))
            trace.append("ax-set-selection")
        case .invoke:
            return false
        }
        graph.flush()
        return true
    }

    /// A key-down. Tab moves focus; the rest edit the focused field.
    public func handleKey(name: String, modifiers: UInt32) -> Bool {
        let shift = modifiers & 0x4 != 0, ctrl = modifiers & 0x1 != 0
        if name == "tab", modifiers & ~0x4 == 0 {
            trace.append("key:tab")
            if let id = graph.focusedTextFieldID, let s = graph.textInput(id) { _ = s.unmark() }
            let moved = graph.moveFocus(forward: !shift)
            return moved
        }
        guard let id = graph.focusedTextFieldID, let s = graph.textInput(id) else { return false }
        trace.append("key:\(name)")
        if shift, !ctrl, ["left", "right", "home", "end"].contains(name) {
            extendSelection(id, s, key: name)
            graph.flush()
            return true
        }
        shiftAnchors[id] = nil
        switch name {
        case "enter", "return":
            _ = graph.pressReturn(inTextField: id)
        case "backspace":
            deleteBackward(s)
        case "delete":
            deleteForward(s)
        case "left":
            move(s, to: s.selection.length > 0 ? s.selection.location : boundary(s.display, before: s.selection.location))
        case "right":
            move(s, to: s.selection.length > 0 ? s.selection.location + s.selection.length : boundary(s.display, after: s.selection.location + s.selection.length))
        case "home":
            move(s, to: 0)
        case "end":
            move(s, to: s.display.utf16.count)
        case "a" where ctrl:
            _ = s.setSelection(UTF16Range(location: 0, length: s.display.utf16.count))
        default:
            return false
        }
        graph.flush()
        return true
    }

    /// A focus change ends the composition of the field it leaves (as Tab does and as AppKit does for its field editor): the marked text is committed to that
    /// field's binding, so nothing stays marked in a field that no longer has the focus (Flutter 191196).
    private func endComposition(of previous: String?, leaving id: String) {
        guard let previous, previous != id, let s = graph.textInput(previous) else { return }
        _ = s.unmark()
        trace.append("focus-ends-composition")
    }

    /// Shift + Left/Right/Home/End: the anchor stays where the selection began and the other end moves (a selection that began elsewhere is anchored at its start).
    private func extendSelection(_ id: String, _ s: TextInputState, key: String) {
        let sel = s.selection
        let anchor = shiftAnchors[id].flatMap { $0.selection == sel ? $0.anchor : nil } ?? sel.location
        let focus = anchor == sel.location ? sel.location + sel.length : sel.location
        let next: Int
        switch key {
        case "left": next = boundary(s.display, before: focus)
        case "right": next = boundary(s.display, after: focus)
        case "home": next = 0
        default: next = s.display.utf16.count
        }
        _ = s.setSelection(UTF16Range(location: min(anchor, next), length: abs(next - anchor)))
        shiftAnchors[id] = (anchor, s.selection)
        trace.append("key:shift-\(key)")
    }

    private func move(_ s: TextInputState, to offset: Int) {
        _ = s.setSelection(UTF16Range(location: offset, length: 0))
    }

    private func deleteBackward(_ s: TextInputState) {
        if s.selection.length > 0 { _ = s.replace(range: s.selection, text: ""); return }
        let end = s.selection.location, start = boundary(s.display, before: end)
        guard start < end else { return }
        _ = s.replace(range: UTF16Range(location: start, length: end - start), text: "")
    }

    private func deleteForward(_ s: TextInputState) {
        if s.selection.length > 0 { _ = s.replace(range: s.selection, text: ""); return }
        let start = s.selection.location, end = boundary(s.display, after: start)
        guard end > start else { return }
        _ = s.replace(range: UTF16Range(location: start, length: end - start), text: "")
    }

    /// The UTF-16 offset of the grapheme boundary before / after `offset`.
    func boundary(_ text: String, before offset: Int) -> Int {
        guard offset > 0 else { return 0 }
        let index = String.Index(utf16Offset: min(offset, text.utf16.count), in: text)
        guard index > text.startIndex else { return 0 }
        return text.index(before: index).utf16Offset(in: text)
    }

    func boundary(_ text: String, after offset: Int) -> Int {
        let count = text.utf16.count
        guard offset < count else { return count }
        let index = String.Index(utf16Offset: offset, in: text)
        return text.index(after: index).utf16Offset(in: text)
    }
}
