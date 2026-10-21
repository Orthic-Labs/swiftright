import Observation
import SwiftRightRuntime
import XCTest

// Issue #60 pass 3: .listStyle(.sidebar) metrics, Button pressed and focused state, the vertical-axis TextField, @Observable in the environment.

private struct SidebarRows: View {
    var body: some View {
        List { ForEach(0..<3, id: \.self) { i in Text("Row \(i)") } }.listStyle(.sidebar).frame(width: 200, height: 160)
    }
}

private struct TwoButtons: View {
    var body: some View { VStack { Button("A") {}; Button("B") {}.disabled(true) } }
}

private struct Notes: View {
    @State var text: String
    var axis: Axis = .vertical
    var limit: Int? = nil
    var body: some View {
        TextField("Notes", text: $text, axis: axis).lineLimit(limit).frame(width: 120)
    }
}

@Observable
@MainActor
private final class Model3 {
    var name: String
    init(_ name: String) { self.name = name }
}

private struct ModelReader: View {
    @Environment(Model3.self) private var model
    var body: some View { Text("name=" + model.name) }
}

private struct ModelHost: View {
    let outer: Model3
    var body: some View { ModelReader().environment(outer) }
}

private struct NestedModelHost: View {
    let outer: Model3
    let inner: Model3
    var body: some View { ModelReader().environment(inner).environment(outer) }
}

@MainActor
final class Issue60Controls3Tests: XCTestCase {
    // MARK: sidebar

    func testSidebarRowsAreThirtyTwoPointsAndStartSixteenPointsIn() throws {
        let graph = i60Graph(SidebarRows())
        let list = try XCTUnwrap(i60Nodes(graph, kind: "List").first)
        XCTAssertEqual(list.listStyle, "SidebarListStyle")
        let rows = list.children
        XCTAssertEqual(rows.count, 3)
        for (i, row) in rows.enumerated() {
            // 10 pt top inset + 32 pt per row, the 16 pt line centred: 10 + 16 + 32 i
            XCTAssertEqual(Double(row.frame.minY - list.frame.minY), 18 + 32 * Double(i), accuracy: 0.5)
            XCTAssertEqual(Double(row.frame.minX - list.frame.minX), 16, accuracy: 1e-9)   // measured on macOS 27
        }
    }

    func testSidebarMetrics() {
        XCTAssertEqual(ListMetrics.rowHeight(forContent: 16, look: .sidebar), 32)
        XCTAssertEqual(ListMetrics.rowHeight(forContent: 16, look: .inset), 24)
        XCTAssertEqual(ListMetrics.rowHeight(forContent: 16, look: .plain), 24)
        XCTAssertEqual(ListMetrics.rowHeight(forContent: 16), 24, "the style-less call is unchanged")
        XCTAssertEqual(ListMetrics.contentInset(.sidebar), 16)
        XCTAssertEqual(ListMetrics.contentInset(.inset), 16)
        XCTAssertEqual(ListMetrics.topInset(.sidebar), 10)
        XCTAssertEqual(ListMetrics.documentHeight(.sidebar, rowHeights: [32, 32, 32]), 116)
    }

    // MARK: Button states

    func testPressedAndFocusedButtonsAreReportedOnTheirNodes() throws {
        let graph = i60Graph(TwoButtons())
        let a = try XCTUnwrap(i60Button(graph, "A")), b = try XCTUnwrap(i60Button(graph, "B"))
        XCTAssertFalse(a.buttonIsPressed); XCTAssertFalse(a.buttonIsFocused)
        XCTAssertTrue(graph.setPressedButton(a.id))
        XCTAssertTrue(try XCTUnwrap(i60Button(graph, "A")).buttonIsPressed)
        XCTAssertFalse(try XCTUnwrap(i60Button(graph, "B")).buttonIsPressed)
        XCTAssertEqual(graph.pressedButton, a.id)
        XCTAssertTrue(graph.setPressedButton(nil))
        XCTAssertFalse(try XCTUnwrap(i60Button(graph, "A")).buttonIsPressed)
        XCTAssertTrue(graph.setFocusedButton(a.id))
        XCTAssertTrue(try XCTUnwrap(i60Button(graph, "A")).buttonIsFocused)
        XCTAssertFalse(try XCTUnwrap(i60Button(graph, "A")).buttonIsPressed, "focus is not a press")
        // a disabled Button takes neither state
        XCTAssertFalse(graph.setPressedButton(b.id)); XCTAssertFalse(graph.setFocusedButton(b.id))
        XCTAssertFalse(try XCTUnwrap(i60Button(graph, "B")).buttonIsPressed)
        // a node that is not a Button is refused
        let text = try XCTUnwrap(i60Text(graph, "A"))
        XCTAssertFalse(graph.setPressedButton(text.id))
        XCTAssertEqual(graph.focusedButton, a.id)
    }

    func testButtonHitTestFindsTheEnabledButtonUnderThePoint() throws {
        let graph = i60Graph(TwoButtons())
        let a = try XCTUnwrap(i60Button(graph, "A")), b = try XCTUnwrap(i60Button(graph, "B"))
        let m = i60Mid(a.frame)
        XCTAssertEqual(graph.buttonID(atX: CGFloat(m.x), y: CGFloat(m.y)), a.id)
        let mb = i60Mid(b.frame)
        XCTAssertNil(graph.buttonID(atX: CGFloat(mb.x), y: CGFloat(mb.y)), "a disabled Button takes no press")
        XCTAssertNil(graph.buttonID(atX: -50, y: -50))
    }

    // MARK: TextField(axis: .vertical)

    func testAVerticalFieldGrowsOneLinePerWrappedLine() throws {
        // the default measurer: 8 pt per character, 16 pt lines. Wrap width 120 - 2 x 6 = 108 pt = 13 characters.
        let one = i60Graph(Notes(text: "aaa bbb"))
        XCTAssertEqual(try XCTUnwrap(i60Nodes(one, kind: "TextField").first).frame.height, 24, "one line is the 24 pt bezel")
        let two = i60Graph(Notes(text: "aaa bbb ccc ddd eee fff"))
        let twoField = try XCTUnwrap(i60Nodes(two, kind: "TextField").first)
        XCTAssertEqual(twoField.frame.height, 8 + 2 * 16, "8 pt of cell inset plus two 16 pt lines")
        XCTAssertEqual(twoField.frame.width, 120)
        let info = try XCTUnwrap(twoField.verticalField)
        XCTAssertEqual(info.lines, 2); XCTAssertEqual(info.wrapWidth, 108); XCTAssertEqual(info.lineHeight, 16); XCTAssertNil(info.lineLimit)
        let four = i60Graph(Notes(text: "aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll"))
        XCTAssertEqual(try XCTUnwrap(i60Nodes(four, kind: "TextField").first).frame.height, 8 + 4 * 16)
    }

    func testAVerticalFieldStopsGrowingAtItsLineLimit() throws {
        let long = "aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll"
        let limited = i60Graph(Notes(text: long, limit: 2))
        let field = try XCTUnwrap(i60Nodes(limited, kind: "TextField").first)
        XCTAssertEqual(field.frame.height, 8 + 2 * 16, "four wrapped lines, two shown")
        let info = try XCTUnwrap(field.verticalField)
        XCTAssertEqual(info.lines, 4); XCTAssertEqual(info.visibleLines, 2); XCTAssertEqual(info.lineLimit, 2)
        XCTAssertEqual(info.textHeight, 64, "the shaped text is still all four lines (the field scrolls)")
        let roomy = i60Graph(Notes(text: "aaa bbb ccc ddd eee fff", limit: 5))
        XCTAssertEqual(try XCTUnwrap(i60Nodes(roomy, kind: "TextField").first).frame.height, 8 + 2 * 16)
    }

    func testAnEmptyVerticalFieldAndAHorizontalFieldKeepTheSingleLineFrame() throws {
        let empty = i60Graph(Notes(text: ""))
        XCTAssertEqual(try XCTUnwrap(i60Nodes(empty, kind: "TextField").first).frame.height, 24)
        let horizontal = i60Graph(Notes(text: "aaa bbb ccc ddd eee fff", axis: .horizontal))
        let field = try XCTUnwrap(i60Nodes(horizontal, kind: "TextField").first)
        XCTAssertEqual(field.frame.height, 24); XCTAssertNil(field.verticalField)
    }

    func testAVerticalFieldIsStillATextFieldThatSubmits() throws {
        let graph = i60Graph(Notes(text: "aaa"))
        let field = try XCTUnwrap(i60Nodes(graph, kind: "TextField").first)
        XCTAssertTrue(graph.isTextField(field.id))
        XCTAssertNotNil(graph.textInput(field.id))
        XCTAssertEqual(graph.textInput(field.id)?.multiline, false, "Return submits; a line break is Option-Return")
    }

    // MARK: .environment(model) / @Environment(Model.self)

    func testAnObservableObjectInTheEnvironmentIsReadByType() throws {
        let model = Model3("one")
        let graph = i60Graph(ModelHost(outer: model))
        XCTAssertEqual(i60Texts(graph), ["name=one"])
        model.name = "two"
        graph.flush()
        XCTAssertEqual(i60Texts(graph), ["name=two"], "the reader's body read a property: a change re-evaluates it")
    }

    func testTheNearestEnvironmentObjectOfATypeWins() throws {
        let outer = Model3("outer"), inner = Model3("inner")
        let graph = i60Graph(NestedModelHost(outer: outer, inner: inner))
        XCTAssertEqual(i60Texts(graph), ["name=inner"])
    }
}
