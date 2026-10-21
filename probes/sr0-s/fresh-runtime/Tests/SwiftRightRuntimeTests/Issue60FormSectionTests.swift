import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: Form and Section.

private struct FormScreen: View {
    @State private var on = true
    var body: some View {
        Form {
            Section("General") { Toggle("Enabled", isOn: $on) }
            Section(header: Text("More")) { Text("x") }
        }
    }
}

private struct FooterScreen: View {
    var body: some View {
        Form {
            Section(content: { Text("body") }, header: { Text("Head") }, footer: { Text("Foot") })
            Section(footer: Text("Only foot")) { Text("rows") }
        }
    }
}

private struct SpacingScreen: View {
    var body: some View { Form { Text("a"); Text("b") } }
}

private struct SectionedList: View {
    @State private var selection: String? = nil
    var body: some View {
        List(selection: $selection) {
            Section("Fruit") {
                Text("apple").tag("apple")
                Text("pear").tag("pear")
            }
            Section(header: Text("Veg"), footer: Text("end")) {
                Text("leek").tag("leek")
            }
        }
        .frame(width: 200, height: 200)
    }
}

@MainActor
final class Issue60FormSectionTests: XCTestCase {
    func testFormShowsSectionsInOrderInsideAScrollView() {
        let graph = i60Graph(FormScreen())
        XCTAssertEqual(i60Nodes(graph, kind: "ScrollView").count, 1)
        XCTAssertEqual(i60Nodes(graph, kind: "Toggle").count, 1)
        let texts = i60Texts(graph)
        XCTAssertLessThan(texts.firstIndex(of: "General") ?? -1, texts.firstIndex(of: "More") ?? -2)
        XCTAssertNotNil(i60Text(graph, "x"))
    }

    func testHeaderIsHeadlineAndFooterIsSecondaryCaption() throws {
        let graph = i60Graph(FooterScreen())
        XCTAssertEqual(try XCTUnwrap(i60Text(graph, "Head")).style.font, Font.headline)
        let foot = try XCTUnwrap(i60Text(graph, "Foot"))
        XCTAssertEqual(foot.style.font, Font.caption)
        XCTAssertEqual(foot.style.foreground, Color.secondary.resolvedColor)
        let texts = i60Texts(graph)
        XCTAssertEqual(texts.filter { ["Head", "body", "Foot", "rows", "Only foot"].contains($0) }, ["Head", "body", "Foot", "rows", "Only foot"])
    }

    func testFormPaddingAndRowSpacing() throws {
        let graph = i60Graph(SpacingScreen())
        let a = try XCTUnwrap(i60Text(graph, "a")), b = try XCTUnwrap(i60Text(graph, "b"))
        XCTAssertEqual(a.frame.minX, 20)
        XCTAssertEqual(a.frame.minY, 20)
        XCTAssertEqual(Double(b.frame.minY), Double(a.frame.minY) + Double(a.frame.height) + 10, accuracy: 0.5)
        XCTAssertEqual(b.frame.minX, 20, "leading aligned")
    }

    func testFormFillsTheProposal() throws {
        let graph = i60Graph(SpacingScreen())
        let scroll = try XCTUnwrap(i60Nodes(graph, kind: "ScrollView").first)
        XCTAssertEqual(scroll.frame.width, 300)
        XCTAssertEqual(scroll.frame.height, 200)
    }

    func testSectionInAListSplicesItsPartsAsRows() throws {
        let graph = i60Graph(SectionedList())
        let list = try XCTUnwrap(i60Nodes(graph, kind: "List").first)
        let rowTexts = list.children.compactMap { everyNode($0).first { $0.kind == "Text" }?.text }
        XCTAssertEqual(rowTexts, ["Fruit", "apple", "pear", "Veg", "leek", "end"])
    }

    func testRowsInASectionStaySelectable() throws {
        let graph = i60Graph(SectionedList())
        XCTAssertTrue(graph.selectRow(try XCTUnwrap(sr1RowID(graph, containing: "pear")))); graph.flush()
        XCTAssertEqual(sr1Node(graph, try XCTUnwrap(sr1RowID(graph, containing: "pear")))?.accessibility.isSelected, true)
        XCTAssertEqual(sr1Node(graph, try XCTUnwrap(sr1RowID(graph, containing: "leek")))?.accessibility.isSelected, false)
        let list = try XCTUnwrap(graph.ids(ofKind: "List").first)
        XCTAssertTrue(graph.navigateList(list, .down)); graph.flush()
        XCTAssertEqual(sr1Node(graph, try XCTUnwrap(sr1RowID(graph, containing: "leek")))?.accessibility.isSelected, true, "down crosses the section boundary")
    }

    func testFormStyleIsAcceptedAndChangesNothing() {
        let plain = i60Graph(SpacingScreen())
        let styled = i60Graph(Form { Text("a"); Text("b") }.formStyle(.grouped))
        XCTAssertEqual(i60Text(plain, "b")?.frame, i60Text(styled, "b")?.frame)
    }
}
