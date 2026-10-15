import XCTest
@testable import SwiftRightHost
import SwiftRightBridge

private struct Witness_Fields: View {
    @State var one = "ab"
    @State var two = ""
    @State var submitted = 0
    var body: some View {
        VStack {
            TextField("One", text: $one).onSubmit { submitted += 1 }
            TextField("Two", text: $two)
            Text("n=\(submitted)")
        }
    }
}

/// The product text input without a renderer: bridge node ids are runtime instance + 1, as the painter assigns them.
@MainActor
final class HostTextInputTests: XCTestCase {
    private struct Rig {
        let graph: Graph
        let input: HostTextInput
        let one: UInt64, two: UInt64
        let oneID: String, twoID: String
    }

    private func rig() -> Rig {
        let graph = Graph(Witness_Fields(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let root = graph.snapshot()!
        let fields = flatten(root).filter { $0.kind == "TextField" }
        var ids: [UInt64: String] = [:]
        for f in flatten(root) { ids[UInt64(f.instance + 1)] = f.id }
        let input = HostTextInput(graph: graph, runtimeID: { ids[$0] })
        return Rig(graph: graph, input: input, one: UInt64(fields[0].instance + 1), two: UInt64(fields[1].instance + 1), oneID: fields[0].id, twoID: fields[1].id)
    }

    func testPointerPressFocusesTheFieldAndPlacesTheCaret() {
        let r = rig()
        XCTAssertTrue(r.input.pointerDown(node: r.one, x: 0))
        XCTAssertEqual(r.graph.focusedTextFieldID, r.oneID)
        XCTAssertEqual(r.graph.textInput(r.oneID)?.selection, UTF16Range(location: 0, length: 2))   // no painted layout yet: the focus selection (whole text) stays
        XCTAssertEqual(r.input.trace, ["pointer-focus"])
        XCTAssertFalse(r.input.pointerDown(node: 424242, x: 0), "a node the host does not know is not a field")
    }

    func testTypedCharactersArriveAsReplaceAndLandInTheBinding() {
        let r = rig()
        _ = r.input.pointerDown(node: r.one, x: 0)
        XCTAssertTrue(r.input.setCaret(r.one, 2))
        XCTAssertTrue(r.input.replace(node: r.one, range: nil, text: Array("x".utf16)))
        XCTAssertEqual(r.graph.textInput(r.oneID)?.committed, "abx")
        XCTAssertEqual(r.graph.textInput(r.oneID)?.selection, UTF16Range(location: 3, length: 0))
    }

    func testMarkedTextIsShownButNotCommittedUntilUnmark() {
        let r = rig()
        _ = r.input.pointerDown(node: r.one, x: 0)
        XCTAssertTrue(r.input.setCaret(r.one, 2))
        XCTAssertTrue(r.input.replaceAndMark(node: r.one, range: nil, text: Array("ni".utf16), newSelection: nil))
        let s = r.graph.textInput(r.oneID)!
        XCTAssertEqual(s.committed, "ab")
        XCTAssertEqual(s.display, "abni")
        XCTAssertEqual(r.input.markedRange(node: r.one), UTF16Span(start: 2, end: 4))
        XCTAssertTrue(r.input.unmark(node: r.one))
        XCTAssertEqual(s.committed, "abni")
        XCTAssertNil(r.input.markedRange(node: r.one))
        let got = r.input.text(node: r.one, range: UTF16Span(start: 1, end: 100))
        XCTAssertEqual(got.map { String(decoding: $0.units, as: UTF16.self) }, "bni")
        XCTAssertEqual(got?.adjusted, UTF16Span(start: 1, end: 4))
    }

    func testKeysEditAndMoveWithinTheFocusedField() {
        let r = rig()
        _ = r.input.pointerDown(node: r.one, x: 0)
        let s = r.graph.textInput(r.oneID)!
        XCTAssertTrue(r.input.handleKey(name: "end", modifiers: 0))
        XCTAssertEqual(s.selection, UTF16Range(location: 2, length: 0))
        XCTAssertTrue(r.input.handleKey(name: "backspace", modifiers: 0))
        XCTAssertEqual(s.committed, "a")
        XCTAssertTrue(r.input.handleKey(name: "left", modifiers: 0))
        XCTAssertTrue(r.input.handleKey(name: "delete", modifiers: 0))
        XCTAssertEqual(s.committed, "")
        XCTAssertTrue(r.input.replace(node: r.one, range: nil, text: Array("héllo".utf16)))
        XCTAssertTrue(r.input.handleKey(name: "a", modifiers: 0x1))
        XCTAssertEqual(s.selection, UTF16Range(location: 0, length: 5))
        XCTAssertTrue(r.input.handleKey(name: "backspace", modifiers: 0))
        XCTAssertEqual(s.committed, "")
    }

    func testReturnSubmitsAndTabMovesFocus() {
        let r = rig()
        _ = r.input.pointerDown(node: r.one, x: 0)
        XCTAssertTrue(r.input.handleKey(name: "enter", modifiers: 0))
        XCTAssertTrue(flatten(r.graph.snapshot()!).contains { $0.text == "n=1" })
        XCTAssertTrue(r.input.handleKey(name: "tab", modifiers: 0))
        XCTAssertEqual(r.graph.focusedTextFieldID, r.twoID)
        XCTAssertTrue(r.input.handleKey(name: "tab", modifiers: 0x4))
        XCTAssertEqual(r.graph.focusedTextFieldID, r.oneID)
    }

    func testReturnWhileComposingCommitsWithoutSubmitting() {
        let r = rig()
        _ = r.input.pointerDown(node: r.one, x: 0)
        XCTAssertTrue(r.input.replaceAndMark(node: r.one, range: nil, text: Array("z".utf16), newSelection: nil))
        XCTAssertTrue(r.input.handleKey(name: "enter", modifiers: 0))
        XCTAssertEqual(r.graph.textInput(r.oneID)?.committed.hasSuffix("z"), true)
        XCTAssertFalse(flatten(r.graph.snapshot()!).contains { $0.text == "n=1" })
    }

    func testAccessibilityFocusSetValueAndSelection() {
        let r = rig()
        XCTAssertTrue(r.input.accessibility(.focus, node: r.two, i0: 0, i1: 0, text: ""))
        XCTAssertEqual(r.graph.focusedTextFieldID, r.twoID)
        XCTAssertTrue(r.input.accessibility(.setValue, node: r.two, i0: 0, i1: 0, text: "hello"))
        XCTAssertEqual(r.graph.textInput(r.twoID)?.committed, "hello")
        XCTAssertTrue(r.input.accessibility(.setSelection, node: r.two, i0: 4, i1: 1, text: ""))
        XCTAssertEqual(r.graph.textInput(r.twoID)?.selection, UTF16Range(location: 1, length: 3))
        XCTAssertFalse(r.input.accessibility(.invoke, node: r.two, i0: 0, i1: 0, text: ""))
    }

    func testPointerFocusChangeCommitsTheCompositionOfTheFieldItLeaves() {
        // Block 40 focuschange: "ni" is marked in the first field; moving the focus must commit it there, not leave it marked (Flutter 191196)
        let r = rig()
        _ = r.input.pointerDown(node: r.one, x: 0)
        XCTAssertTrue(r.input.setCaret(r.one, 2))
        XCTAssertTrue(r.input.replaceAndMark(node: r.one, range: nil, text: Array("ni".utf16), newSelection: nil))
        XCTAssertTrue(r.input.pointerDown(node: r.two, x: 0))
        let one = r.graph.textInput(r.oneID)!
        XCTAssertEqual(one.committed, "abni")
        XCTAssertEqual(one.display, "abni")
        XCTAssertNil(r.input.markedRange(node: r.one))
        XCTAssertTrue(r.input.trace.contains("focus-ends-composition"))
    }

    func testAccessibilityFocusChangeCommitsTheCompositionOfTheFieldItLeaves() {
        let r = rig()
        _ = r.input.pointerDown(node: r.one, x: 0)
        XCTAssertTrue(r.input.setCaret(r.one, 2))
        XCTAssertTrue(r.input.replaceAndMark(node: r.one, range: nil, text: Array("ni".utf16), newSelection: nil))
        XCTAssertTrue(r.input.accessibility(.focus, node: r.two, i0: 0, i1: 0, text: ""))
        XCTAssertEqual(r.graph.textInput(r.oneID)?.committed, "abni")
        XCTAssertNil(r.input.markedRange(node: r.one))
    }

    func testShiftArrowsExtendAndShrinkTheSelectionFromItsAnchor() {
        // Block 40 reconvert: shift+Left selects the committed text before a reconversion; a plain arrow then collapses the selection to its left end
        let r = rig()
        _ = r.input.pointerDown(node: r.one, x: 0)
        XCTAssertTrue(r.input.handleKey(name: "end", modifiers: 0))
        let s = r.graph.textInput(r.oneID)!
        XCTAssertTrue(r.input.handleKey(name: "left", modifiers: 0x4))
        XCTAssertEqual(s.selection, UTF16Range(location: 1, length: 1))
        XCTAssertTrue(r.input.handleKey(name: "left", modifiers: 0x4))
        XCTAssertEqual(s.selection, UTF16Range(location: 0, length: 2))
        XCTAssertTrue(r.input.handleKey(name: "right", modifiers: 0x4))
        XCTAssertEqual(s.selection, UTF16Range(location: 1, length: 1))
        XCTAssertTrue(r.input.handleKey(name: "left", modifiers: 0))
        XCTAssertEqual(s.selection, UTF16Range(location: 1, length: 0))
    }

    func testShiftHomeAndEndAnchorAtTheCaret() {
        let r = rig()
        _ = r.input.pointerDown(node: r.one, x: 0)
        XCTAssertTrue(r.input.handleKey(name: "end", modifiers: 0))
        let s = r.graph.textInput(r.oneID)!
        XCTAssertTrue(r.input.handleKey(name: "home", modifiers: 0x4))
        XCTAssertEqual(s.selection, UTF16Range(location: 0, length: 2))
        XCTAssertTrue(r.input.handleKey(name: "end", modifiers: 0x4))
        XCTAssertEqual(s.selection, UTF16Range(location: 2, length: 0))
    }

    func testCaretBoundsComeFromThePaintedLayout() {
        let graph = Graph(Witness_Fields(), scale: 2.5)
        graph.flush()
        let layout = TextFieldLayout(bounds: Rect(x: 10, y: 20, w: 300, h: 60), textOriginX: 20, boundaries: [0, 6, 12], lineHeight: 40, textTop: 30)
        let input = HostTextInput(graph: graph, runtimeID: { _ in "x" }, layout: { _ in layout })
        XCTAssertEqual(input.caretBounds(node: 1, range: UTF16Span(start: 1, end: 2)), Rect(x: 26, y: 30, w: 6, h: 40))
        XCTAssertEqual(layout.offset(atX: 27), 1)
        XCTAssertEqual(layout.offset(atX: 500), 2)
    }
}

extension HostTextInput {
    /// Test helper: places the caret in a field's state.
    func setCaret(_ node: UInt64, _ offset: Int) -> Bool {
        guard let id = graph.focusedTextFieldID, let s = graph.textInput(id) else { return false }
        return s.setSelection(UTF16Range(location: offset, length: 0))
    }
}
