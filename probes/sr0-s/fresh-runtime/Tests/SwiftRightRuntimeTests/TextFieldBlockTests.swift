import Foundation
import SwiftRightRuntime
import XCTest

// SR1 block 13 (swiftui.textfield) and the runtime side of block 14 focus. Numbers and orders are measured on macOS 27 SwiftUI
// (factory/pipeline/blocks-6-10/swiftui.textfield/FACTS.md).

private final class SubmitTape { var calls: [String] = [] }

private struct FieldsScreen: View {
    @State var one = "ab"
    @State var two = ""
    @FocusState var focus: Int?
    let tape: SubmitTape
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("First", text: $one).focused($focus, equals: 1).onSubmit { tape.calls.append("inner") }
            TextField("Second", text: $two, prompt: Text("Enter")).textFieldStyle(.plain).focused($focus, equals: 2)
        }
        .onSubmit { tape.calls.append("outer") }
    }
}

private struct SizedField: View {
    let style: String
    @State var text = ""
    var body: some View {
        switch style {
        case "plain": TextField("Name", text: $text).textFieldStyle(.plain).frame(width: 120)
        case "rounded": TextField("Name", text: $text).textFieldStyle(.roundedBorder).frame(width: 120)
        default: TextField("Name", text: $text).frame(width: 120)
        }
    }
}

private struct Selected: View {
    @State var a = "hello"
    @FocusState var focus: Int?
    var body: some View {
        VStack {
            TextField("a", text: $a).focused($focus, equals: 1)
            Button("go") { focus = 1 }
        }
    }
}

private struct MixedFields: View {
    @State var a = "one"
    @State var b = "two"
    @State var c = "three"
    @FocusState var focus: Int?
    var body: some View {
        VStack {
            TextField("A", text: $a)
            TextField("B", text: $b).focused($focus, equals: 2)
            TextField("C", text: $c)
        }
    }
}

private struct BoolFocus: View {
    @State var a = "one"
    @State var b = "two"
    @FocusState var aFocused: Bool
    @FocusState var bFocused: Bool
    var body: some View {
        VStack {
            TextField("A", text: $a).focused($aFocused)
            TextField("B", text: $b).focused($bFocused)
            Text("a=\(aFocused) b=\(bFocused)")
            Button("focus b") { bFocused = true }
            Button("blur") { aFocused = false; bFocused = false }
        }
    }
}

@MainActor
final class TextFieldBlockTests: XCTestCase {
    private func nodes(_ graph: Graph) -> [ResolvedNode] { everyNode(graph.snapshot()) }

    func testBezeledFieldIs24PointsTallAndFillsItsFrame() throws {
        for style in ["automatic", "rounded"] {
            let graph = Graph(SizedField(style: style)); graph.flush()
            let field = try XCTUnwrap(nodes(graph).first { $0.kind == "TextField" })
            XCTAssertEqual(field.frame.width, 120, style)
            XCTAssertEqual(field.frame.height, 24, style)
        }
    }

    func testPlainFieldHasNoBezelHeightOrInset() throws {
        let graph = Graph(SizedField(style: "plain")); graph.flush()
        let field = try XCTUnwrap(nodes(graph).first { $0.kind == "TextField" })
        XCTAssertEqual(field.frame.width, 120)
        XCTAssertEqual(field.fieldStyle, "PlainTextFieldStyle")
        XCTAssertGreaterThanOrEqual(field.frame.height, 16)
        XCTAssertLessThan(field.frame.height, 24)
        XCTAssertEqual(TextFieldMetrics.artwork(forStyle: field.fieldStyle), .plain)
    }

    func testStyleMetadataAndArtworkSelection() {
        XCTAssertEqual(TextFieldMetrics.artwork(forStyle: nil), .bezel)
        XCTAssertEqual(TextFieldMetrics.artwork(forStyle: "RoundedBorderTextFieldStyle"), .bezel)
        XCTAssertEqual(TextFieldMetrics.artwork(forStyle: "SquareBorderTextFieldStyle"), .bezel)
        XCTAssertEqual(TextFieldMetrics.artwork(forStyle: "DefaultTextFieldStyle"), .bezel)
        XCTAssertEqual(TextFieldMetrics.artwork(forStyle: "PlainTextFieldStyle"), .plain)
    }

    func testIdealWidthIsTextPlusBezelInsetAndEmptyUsesThePlaceholder() throws {
        struct Empty: View { @State var t = ""; var body: some View { TextField("Name", text: $t) } }
        struct Filled: View { @State var t = "Name"; var body: some View { TextField("Other", text: $t) } }
        let a = Graph(Empty()); a.flush()
        let b = Graph(Filled()); b.flush()
        let wa = try XCTUnwrap(nodes(a).first { $0.kind == "TextField" }).frame.width
        let wb = try XCTUnwrap(nodes(b).first { $0.kind == "TextField" }).frame.width
        XCTAssertEqual(wa, wb, "an empty field measures its placeholder, as the same text typed")
        XCTAssertGreaterThan(wa, 8)
    }

    func testPlaceholderIsThePromptElseTheTitle() throws {
        let graph = Graph(FieldsScreen(tape: SubmitTape())); graph.flush()
        let fields = nodes(graph).filter { $0.kind == "TextField" }
        XCTAssertEqual(fields.map(\.placeholder), ["First", "Enter"])
        XCTAssertEqual(fields.map(\.accessibility.label), ["First", "Second"])
    }

    func testSubmitRunsOuterActionBeforeInner() {
        let tape = SubmitTape()
        let graph = Graph(FieldsScreen(tape: tape)); graph.flush()
        let first = graph.ids(ofKind: "TextField")[0]
        XCTAssertTrue(graph.pressReturn(inTextField: first))
        XCTAssertEqual(tape.calls, ["outer", "inner"])
        let second = graph.ids(ofKind: "TextField")[1]
        tape.calls = []
        XCTAssertTrue(graph.pressReturn(inTextField: second))
        XCTAssertEqual(tape.calls, ["outer"])
    }

    func testReturnWhileComposingCommitsAndDoesNotSubmit() {
        let tape = SubmitTape()
        let graph = Graph(FieldsScreen(tape: tape)); graph.flush()
        let id = graph.ids(ofKind: "TextField")[0]
        let input = graph.textInput(id)!
        XCTAssertTrue(input.setSelection(UTF16Range(location: 2, length: 0)))
        XCTAssertTrue(input.replaceAndMark(text: "ni"))
        XCTAssertTrue(graph.pressReturn(inTextField: id))
        XCTAssertNil(input.composition)
        XCTAssertEqual(input.committed, "abni")
        XCTAssertEqual(tape.calls, [])
    }

    func testReturnWithoutSubmitActionIsNotHandled() {
        struct Bare: View { @State var t = "x"; var body: some View { TextField("t", text: $t) } }
        let graph = Graph(Bare()); graph.flush()
        XCTAssertFalse(graph.pressReturn(inTextField: graph.ids(ofKind: "TextField")[0]))
    }

    func testTabIntoAFieldSelectsItsWholeText() {
        let graph = Graph(FieldsScreen(tape: SubmitTape())); graph.flush()
        XCTAssertTrue(graph.moveFocus(forward: true))
        let first = graph.textInput(graph.ids(ofKind: "TextField")[0])!
        XCTAssertEqual(first.selection, UTF16Range(location: 0, length: 2))
    }

    func testFocusStateAssignmentSelectsWholeTextButPointerPlacementStays() {
        let graph = Graph(Selected()); graph.flush()
        let field = graph.textInput(graph.ids(ofKind: "TextField")[0])!
        XCTAssertEqual(field.selection, UTF16Range(location: 0, length: 0))
        XCTAssertTrue(graph.tapButton(graph.ids(ofKind: "Button")[0])); graph.flush()
        XCTAssertEqual(field.selection, UTF16Range(location: 0, length: 5))
        // a later caret placement (a pointer click does it after the focus) sticks
        XCTAssertTrue(field.setSelection(UTF16Range(location: 5, length: 0)))
        graph.flush()
        XCTAssertEqual(field.selection, UTF16Range(location: 5, length: 0))
    }

    // A TextField without a focus binding still takes focus (macOS: any TextField does); Tab visits bound and unbound fields in tree order.
    func testUnboundFieldsAreTabStopsAndTakeImplicitFocus() {
        let graph = Graph(MixedFields()); graph.flush()
        let ids = graph.ids(ofKind: "TextField")
        XCTAssertEqual(graph.focusStops().count, 3)
        XCTAssertNil(graph.focusedTextFieldID)
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(graph.focusedTextFieldID, ids[0])
        XCTAssertEqual(graph.textInput(ids[0])?.selection, UTF16Range(location: 0, length: 3))
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(graph.focusedTextFieldID, ids[1])           // the bound one: the implicit focus left the first field
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(graph.focusedTextFieldID, ids[2])
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(graph.focusedTextFieldID, ids[0])           // wraps
        XCTAssertTrue(graph.moveFocus(forward: false))
        XCTAssertEqual(graph.focusedTextFieldID, ids[2])
    }

    func testFocusTextFieldMovesBetweenBoundAndImplicitFocus() {
        let graph = Graph(MixedFields()); graph.flush()
        var focusedIDs: [String?] = []
        graph.commitSink = { focusedIDs.append($0.focused) }
        let ids = graph.ids(ofKind: "TextField")
        XCTAssertTrue(graph.focusTextField(ids[1]))                // bound: through FocusState
        XCTAssertEqual(graph.focusedTextFieldID, ids[1])
        XCTAssertTrue(graph.focusTextField(ids[2]))                // unbound: the FocusState is released
        XCTAssertEqual(graph.focusedTextFieldID, ids[2])
        XCTAssertEqual(graph.focusStops().filter(\.isFocused).count, 1)
        XCTAssertTrue(graph.focusTextField(ids[0]))
        XCTAssertEqual(graph.focusedTextFieldID, ids[0])
        XCTAssertEqual(focusedIDs.last ?? nil, ids[0], "the commit record reports the focused field")
        XCTAssertFalse(graph.focusTextField("missing"))
    }

    // `@FocusState var x: Bool` with `.focused($x)`: the Bool form of the focus binding (macOS oracle: focus = true takes focus, false releases it).
    func testBoolFocusStateFollowsFocusAndTab() {
        let graph = Graph(BoolFocus()); graph.flush()
        func status() -> String? { nodes(graph).compactMap(\.text).first { $0.hasPrefix("a=") } }
        XCTAssertEqual(status(), "a=false b=false")
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(status(), "a=true b=false")
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(status(), "a=false b=true")
        let buttons = graph.ids(ofKind: "Button")
        XCTAssertTrue(graph.tapButton(buttons[1])); graph.flush()
        XCTAssertEqual(status(), "a=false b=false")
        XCTAssertNil(graph.focusedTextFieldID)
        XCTAssertTrue(graph.tapButton(buttons[0])); graph.flush()
        XCTAssertEqual(status(), "a=false b=true")
        XCTAssertEqual(graph.textInput(graph.ids(ofKind: "TextField")[1])?.selection, UTF16Range(location: 0, length: 3))
    }
}
