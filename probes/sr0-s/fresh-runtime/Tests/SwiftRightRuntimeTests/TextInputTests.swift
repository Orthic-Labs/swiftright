import Foundation
import Observation
import SwiftRightRuntime
import XCTest

// Marked text and the text store operations on TextField (SR0-S F7 oracle: composition on the active row
// stays with its identity when a row is inserted above, and the committed text lands there).

@Observable
@MainActor
final class TextModel {
    var text = "Row 2"
}

struct FieldScreen: View {
    @Bindable var model: TextModel

    var body: some View {
        TextField("Row", text: $model.text)
    }
}

@Observable
@MainActor
final class TextRows {
    var rows: [Row] = []
}

struct TextRowsScreen: View {
    @Bindable var model: TextRows

    var body: some View {
        VStack {
            ForEach($model.rows) { $row in
                TextField("Row", text: $row.text)
            }
        }
    }
}

@MainActor
func fieldID(_ graph: Graph) -> String {
    graph.ids(ofKind: "TextField").first ?? "missing"
}

@MainActor
final class TextInputTests: XCTestCase {

    // Marked text is shown but is not written to the binding until committed.
    func testMarkedTextDoesNotLeakIntoBindingUntilCommitted() {
        let model = TextModel()
        let graph = Graph(FieldScreen(model: model))
        var records: [CommitRecord] = []
        graph.commitSink = { records.append($0) }
        graph.flush()
        let input = graph.textInput(fieldID(graph))!

        XCTAssertTrue(input.setSelection(UTF16Range(location: 5, length: 0)))
        XCTAssertTrue(input.replaceAndMark(text: "ka"))
        graph.flush()
        XCTAssertEqual(input.display, "Row 2ka")
        XCTAssertEqual(input.markedRange, UTF16Range(location: 5, length: 2))
        XCTAssertEqual(model.text, "Row 2", "binding unchanged while composing")
        let field = records.last?.root?.children.first
        XCTAssertEqual(field?.text, "Row 2ka", "the field displays the marked text")
        XCTAssertEqual(field?.marked, UTF16Range(location: 5, length: 2))

        XCTAssertTrue(input.replaceAndMark(range: nil, text: "kana"))
        XCTAssertEqual(input.display, "Row 2kana", "a new composition replaces the marked text")
        XCTAssertEqual(model.text, "Row 2")

        XCTAssertTrue(input.unmark())
        graph.flush()
        XCTAssertNil(input.markedRange)
        XCTAssertEqual(model.text, "Row 2kana", "commit writes the binding")
        XCTAssertEqual(input.selection, UTF16Range(location: 9, length: 0), "caret after the committed text")
    }

    // Replacement and selection in UTF-16 units: an emoji is two units.
    func testUTF16RangesCountSurrogatePairs() {
        let model = TextModel()
        model.text = "a😀b"
        let graph = Graph(FieldScreen(model: model))
        graph.flush()
        let input = graph.textInput(fieldID(graph))!

        XCTAssertTrue(input.setSelection(UTF16Range(location: 3, length: 0)), "after the emoji")
        XCTAssertTrue(input.replaceAndMark(text: "é"))
        XCTAssertEqual(input.display, "a😀éb")
        XCTAssertEqual(input.substring(UTF16Range(location: 1, length: 2)), "😀")
        XCTAssertEqual(input.substring(UTF16Range(location: 3, length: 1)), "é")
        XCTAssertNil(input.substring(UTF16Range(location: 9, length: 1)), "out of bounds")
    }

    // Moving the caret out of the marked text commits it; moving within keeps the composition.
    func testSelectionOutsideCompositionCommits() {
        let model = TextModel()
        let graph = Graph(FieldScreen(model: model))
        graph.flush()
        let input = graph.textInput(fieldID(graph))!

        input.setSelection(UTF16Range(location: 5, length: 0))
        input.replaceAndMark(text: "ka")
        XCTAssertTrue(input.setSelection(UTF16Range(location: 6, length: 0)), "inside the marked text")
        XCTAssertNotNil(input.markedRange)
        XCTAssertEqual(model.text, "Row 2")

        XCTAssertTrue(input.setSelection(UTF16Range(location: 0, length: 0)))
        XCTAssertNil(input.markedRange, "leaving the marked text commits it")
        XCTAssertEqual(model.text, "Row 2ka")
    }

    // Ending the composition with empty text removes the marked text without touching the binding.
    func testEmptyReplaceEndsCompositionWithoutCommit() {
        let model = TextModel()
        let graph = Graph(FieldScreen(model: model))
        graph.flush()
        let input = graph.textInput(fieldID(graph))!

        input.setSelection(UTF16Range(location: 5, length: 0))
        input.replaceAndMark(text: "ka")
        XCTAssertTrue(input.replaceAndMark(text: ""))
        XCTAssertNil(input.markedRange)
        XCTAssertEqual(input.display, "Row 2")
        XCTAssertEqual(model.text, "Row 2")
    }

    // Plain replacement (bridge `replace`) commits text directly and ends any composition.
    func testReplaceCommitsDirectlyAndEndsComposition() {
        let model = TextModel()
        let graph = Graph(FieldScreen(model: model))
        graph.flush()
        let input = graph.textInput(fieldID(graph))!

        input.setSelection(UTF16Range(location: 5, length: 0))
        input.replaceAndMark(text: "ka")
        XCTAssertTrue(input.replace(text: "X"), "replaces the marked text")
        XCTAssertNil(input.markedRange)
        XCTAssertEqual(model.text, "Row 2X")
    }

    // Out-of-range operations are refused and change nothing.
    func testOutOfRangeOperationsAreRefused() {
        let model = TextModel()
        let graph = Graph(FieldScreen(model: model))
        graph.flush()
        let input = graph.textInput(fieldID(graph))!

        XCTAssertFalse(input.setSelection(UTF16Range(location: 99, length: 0)))
        XCTAssertFalse(input.replaceAndMark(range: UTF16Range(location: 0, length: 99), text: "x"))
        XCTAssertEqual(model.text, "Row 2")
        XCTAssertEqual(input.selection, UTF16Range(location: 0, length: 0))
    }

    // F7: a composition on the active row stays on its identity when a row is inserted above it, and
    // the committed text lands on that row.
    func testCompositionStaysWithRowWhenRowInsertedAbove() {
        let model = TextRows()
        let rows = (1...4).map { Row(id: UUID(), text: "Row \($0)") }
        model.rows = rows
        let graph = Graph(TextRowsScreen(model: model))
        graph.flush()

        let active = rows[1]
        let activeID = graph.ids(ofKind: "TextField")[1]
        let input = graph.textInput(activeID)!
        input.setSelection(UTF16Range(location: 5, length: 0))
        input.replaceAndMark(text: "ka")
        graph.flush()

        model.rows.insert(Row(id: UUID(), text: "Engine 0"), at: 0)
        graph.flush()

        let shifted = graph.ids(ofKind: "TextField")[2]
        let same = graph.textInput(shifted)!
        XCTAssertTrue(same === input, "same field state after the insert")
        XCTAssertEqual(same.markedRange, UTF16Range(location: 5, length: 2))
        XCTAssertEqual(model.rows[2].text, "Row 2", "bound text unchanged while composing")
        XCTAssertEqual(model.rows.first?.text, "Engine 0")

        XCTAssertTrue(same.unmark())
        graph.flush()
        XCTAssertEqual(model.rows[2].id, active.id, "active row kept its identity")
        XCTAssertEqual(model.rows[2].text, "Row 2ka", "committed text lands on the active row")
        XCTAssertEqual(model.rows[0].text, "Engine 0")
    }
}
