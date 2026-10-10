import Foundation
import SwiftRightRuntime
import XCTest

// Initial focus (SR0-O cross-compare of all 16 configurations; Mac logs in probes/sr0-o/f1-cross/cross-evidence):
// the window's first key view takes focus. A List is itself a key view and holds no FocusState value, so a List-first
// window focuses nothing (F1, F2, F3 list, F4, F6, F7, F8, F9); a VStack, ScrollView + LazyVStack or custom Layout leaves
// the first focus-bound text field first, and @FocusState reports it (F3 vstack and lazy, F5).
// Event order on the Mac: every onAppear, then the focus, then the first task body.

/// A row that is one focus-bound text field, like the fixtures' EditableRowView.
struct FieldRow: View {
    let row: Binding<Row>
    let focus: FocusState<UUID?>.Binding
    let store: Store

    var body: some View {
        TextField("t", text: row.text)
            .focused(focus, equals: row.wrappedValue.id)
            .onAppear { store.log.append("appear \(row.wrappedValue.text)") }
            .task { store.log.append("task \(row.wrappedValue.text)") }
    }
}

struct FieldVStackScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?
    var body: some View {
        VStack {
            ForEach($store.rows) { $row in FieldRow(row: $row, focus: $focus, store: store) }
        }
    }
}

struct FieldListScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?
    var body: some View {
        List {
            ForEach($store.rows) { $row in FieldRow(row: $row, focus: $focus, store: store) }
        }
    }
}

struct FieldLazyScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach($store.rows) { $row in FieldRow(row: $row, focus: $focus, store: store) }
            }
        }
    }
}

/// F7 shape: a Text, then a List.
struct TextThenListScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?
    var body: some View {
        VStack {
            Text("IME placeholder")
            List {
                ForEach($store.rows) { $row in FieldRow(row: $row, focus: $focus, store: store) }
            }
        }
    }
}

/// A field before a List: the key-view loop starts with the field (the rule extended, not an observed configuration).
struct FieldThenListScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?
    var body: some View {
        VStack {
            TextField("head", text: Binding(get: { store.rows[0].text }, set: { store.rows[0].text = $0 }))
                .focused($focus, equals: store.rows[0].id)
            List {
                ForEach($store.rows) { $row in FieldRow(row: $row, focus: $focus, store: store) }
            }
        }
    }
}

struct DisabledFirstScreen: View {
    @Bindable var store: Store
    @FocusState var focus: UUID?
    var body: some View {
        VStack {
            ForEach($store.rows) { $row in
                TextField("t", text: $row.text)
                    .focused($focus, equals: row.id)
                    .disabled(row.text == "off")
            }
        }
    }
}

/// A focus-bound Button first: Tab does not stop on buttons, so the field after it takes the initial focus.
struct ButtonFirstScreen: View {
    @FocusState var focus: Int?
    var body: some View {
        VStack {
            Button("b") {}.focused($focus, equals: 0)
            TextField("c", text: Binding(get: { "c" }, set: { _ in })).focused($focus, equals: 1)
        }
    }
}

@MainActor
final class InitialFocusTests: XCTestCase {
    private func make(_ view: some View) -> (Graph, () -> [CommitRecord]) {
        var records: [CommitRecord] = []
        let graph = Graph(view)
        graph.commitSink = { records.append($0) }
        graph.flush()
        return (graph, { records })
    }

    private func focusedRowIndex(_ store: Store, _ records: [CommitRecord]) -> Int? {
        guard let focused = records.last?.focused else { return nil }
        return store.rows.firstIndex { focused.contains("[\($0.id)]") }
    }

    func testVStackFocusesFirstFieldAndCommitsIt() {
        let store = makeStore(4)
        let (graph, records) = make(FieldVStackScreen(store: store))
        XCTAssertNil(records().last?.focused)
        let before = records().count
        let target = graph.applyInitialFocus()
        XCTAssertNotNil(target)
        XCTAssertEqual(records().count, before + 1, "one commit record carries the focus")
        XCTAssertEqual(focusedRowIndex(store, records()), 0)
        XCTAssertTrue(target!.contains("[\(store.rows[0].id)]"))
    }

    func testLazyVStackFocusesFirstField() {
        let store = makeStore(4)
        let (graph, records) = make(FieldLazyScreen(store: store))
        XCTAssertNotNil(graph.applyInitialFocus())
        XCTAssertEqual(focusedRowIndex(store, records()), 0)
    }

    func testListFocusesNothing() {
        let store = makeStore(4)
        let (graph, records) = make(FieldListScreen(store: store))
        let before = records().count
        XCTAssertNil(graph.applyInitialFocus())
        XCTAssertEqual(records().count, before, "no commit when nothing takes focus")
        XCTAssertNil(records().last?.focused)
    }

    func testTextThenListFocusesNothing() {
        let store = makeStore(4)
        let (graph, records) = make(TextThenListScreen(store: store))
        XCTAssertNil(graph.applyInitialFocus())
        XCTAssertNil(records().last?.focused)
    }

    func testFieldBeforeListTakesFocusAheadOfIt() {
        let store = makeStore(4)
        let (graph, records) = make(FieldThenListScreen(store: store))
        XCTAssertNotNil(graph.applyInitialFocus())
        XCTAssertFalse(records().last?.focused?.contains("List") ?? true, "the head field, not a field inside the List: \(records().last?.focused ?? "nil")")
        XCTAssertTrue(graph.focusStops().first?.isFocused ?? false)
    }

    func testDisabledFirstFieldIsSkipped() {
        let store = makeStore(4)
        store.rows[0].text = "off"
        let (graph, records) = make(DisabledFirstScreen(store: store))
        XCTAssertNotNil(graph.applyInitialFocus())
        XCTAssertEqual(focusedRowIndex(store, records()), 1)
    }

    func testButtonsAreNotKeyViewsByDefault() {
        let (graph, records) = make(ButtonFirstScreen())
        let target = graph.applyInitialFocus()
        XCTAssertNotNil(target)
        XCTAssertNotNil(records().last?.focused)
        XCTAssertEqual(graph.focusStops().map(\.isFocused), [true], "the only stop is the field; the button is not a stop")
    }

    func testNoFocusBoundFieldFocusesNothing() {
        let graph = Graph(Text("hi"))
        graph.flush()
        XCTAssertNil(graph.applyInitialFocus())
    }

    func testExistingFocusIsNotStolen() {
        let store = makeStore(4)
        let (graph, records) = make(FieldVStackScreen(store: store))
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(focusedRowIndex(store, records()), 1)
        let before = records().count
        XCTAssertNil(graph.applyInitialFocus())
        XCTAssertEqual(records().count, before)
        XCTAssertEqual(focusedRowIndex(store, records()), 1)
    }

    func testSecondCallDoesNothing() {
        let store = makeStore(3)
        let (graph, records) = make(FieldVStackScreen(store: store))
        XCTAssertNotNil(graph.applyInitialFocus())
        let before = records().count
        XCTAssertNil(graph.applyInitialFocus())
        XCTAssertEqual(records().count, before)
    }

    func testTornDownGraphFocusesNothing() {
        let store = makeStore(3)
        let (graph, _) = make(FieldVStackScreen(store: store))
        graph.tearDown()
        XCTAssertNil(graph.applyInitialFocus())
    }

    // Mac log order: every appear, then the focus, then the first task body (tasks start after the host yields).
    func testFocusComesAfterAllAppearsAndBeforeAnyTaskBody() {
        let store = makeStore(4)
        var logAtFocus: [String]?
        let graph = Graph(FieldVStackScreen(store: store))
        graph.commitSink = { record in
            if record.focused != nil, logAtFocus == nil { logAtFocus = store.log }
        }
        graph.flush()
        XCTAssertNotNil(graph.applyInitialFocus())
        let seen = logAtFocus ?? []
        XCTAssertEqual(seen.filter { $0.hasPrefix("appear") }.count, 4, "all four appears ran before the focus commit")
        XCTAssertTrue(seen.allSatisfy { $0.hasPrefix("appear") }, "no task body ran before the focus commit: \(seen)")
    }

    // Initial focus puts the focus binding on row 1 only; the other rows keep none.
    func testOnlyTheFirstRowReportsFocus() {
        let store = makeStore(4)
        let (graph, _) = make(FieldVStackScreen(store: store))
        graph.applyInitialFocus()
        XCTAssertEqual(graph.focusStops().map(\.isFocused), [true, false, false, false])
    }

    // D2: launch focus selects all of the focused field (Mac 0+5); typing replaces it; later focus keeps caret-at-end.
    func testInitialFocusSelectsAllAndTypingReplaces() {
        let store = makeStore(2)
        store.rows[0].text = "Row 1"
        let (graph, _) = make(FieldVStackScreen(store: store))
        graph.applyInitialFocus()
        let fields = graph.ids(ofKind: "TextField")
        let input = graph.textInput(fields[0])!
        XCTAssertEqual(input.selection, UTF16Range(location: 0, length: 5))
        XCTAssertEqual(graph.textInput(fields[1])!.selection.length, 0, "other rows are untouched")
        XCTAssertTrue(input.replace(text: "x"))
        XCTAssertEqual(input.committed, "x")
        XCTAssertEqual(input.selection, UTF16Range(location: 1, length: 0))
        graph.flush()
        XCTAssertEqual(store.rows[0].text, "x")
    }

    // F5: the focused field's text is set from outside (async row update); the caret then reads the end of the new text.
    func testExternalTextChangeMovesFocusedCaretToEnd() {
        let store = makeStore(2)
        store.rows[0].text = "Row 1"
        let (graph, _) = make(FieldVStackScreen(store: store))
        graph.applyInitialFocus()
        let field = graph.ids(ofKind: "TextField")[0]
        let input = graph.textInput(field)!
        XCTAssertEqual(input.selection, UTF16Range(location: 0, length: 5))
        XCTAssertTrue(input.setSelection(UTF16Range(location: 5, length: 0)))
        store.rows[0].text = "Row 1 updated 0"
        graph.flush()
        XCTAssertEqual(input.selection, UTF16Range(location: 15, length: 0))
        XCTAssertEqual(input.committed, "Row 1 updated 0")
    }

    // An edit through the text state keeps its own caret (here: an insertion in the middle).
    func testOwnEditDoesNotJumpTheCaret() {
        let store = makeStore(2)
        store.rows[0].text = "Row 1"
        let (graph, _) = make(FieldVStackScreen(store: store))
        graph.applyInitialFocus()
        let field = graph.ids(ofKind: "TextField")[0]
        let input = graph.textInput(field)!
        XCTAssertTrue(input.setSelection(UTF16Range(location: 2, length: 0)))
        XCTAssertTrue(input.replace(text: "X"))
        graph.flush()
        XCTAssertEqual(input.committed, "RoXw 1")
        XCTAssertEqual(input.selection, UTF16Range(location: 3, length: 0))
    }

    // An external write while composing leaves the composition and the caret alone.
    func testExternalTextChangeWhileComposingKeepsComposition() {
        let store = makeStore(2)
        store.rows[0].text = "Row 1"
        let (graph, _) = make(FieldVStackScreen(store: store))
        graph.applyInitialFocus()
        let field = graph.ids(ofKind: "TextField")[0]
        let input = graph.textInput(field)!
        XCTAssertTrue(input.setSelection(UTF16Range(location: 5, length: 0)))
        XCTAssertTrue(input.replaceAndMark(text: "n"))
        let caret = input.selection
        store.rows[1].text = "other row"
        graph.flush()
        XCTAssertEqual(input.composition, "n")
        XCTAssertEqual(input.selection, caret)
    }
}
