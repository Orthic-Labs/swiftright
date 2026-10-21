import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: List(data, id:), List(data), List(range) and the selection forms.

private struct Fruit: Identifiable {
    let id: Int
    let name: String
}

private struct DataListScreen: View {
    let items = ["a", "b", "c"]
    var body: some View { List(items, id: \.self) { Text($0) }.frame(width: 200, height: 150) }
}

private struct IdentifiableListScreen: View {
    let fruits = [Fruit(id: 1, name: "apple"), Fruit(id: 2, name: "pear")]
    var body: some View { List(fruits) { Text($0.name) }.frame(width: 200, height: 150) }
}

private struct RangeListScreen: View {
    var body: some View { List(0..<3) { Text("row \($0)") }.frame(width: 200, height: 150) }
}

private struct SingleSelectionScreen: View {
    @State private var selection: String? = "b"
    let items = ["a", "b", "c"]
    var body: some View {
        VStack {
            Text("sel=\(selection ?? "none")")
            List(items, id: \.self, selection: $selection) { Text($0) }.frame(width: 200, height: 120)
        }
    }
}

private struct MultiSelectionScreen: View {
    @State private var selection: Set<Int> = [1]
    let fruits = [Fruit(id: 1, name: "apple"), Fruit(id: 2, name: "pear"), Fruit(id: 3, name: "plum")]
    var body: some View {
        VStack {
            Text("sel=\(selection.sorted().map(String.init).joined(separator: ","))")
            List(fruits, selection: $selection) { Text($0.name) }.frame(width: 200, height: 120)
        }
    }
}

@MainActor
final class Issue60ListDataTests: XCTestCase {
    private func rowTexts(_ graph: Graph) -> [String] {
        guard let list = i60Nodes(graph, kind: "List").first else { return [] }
        return list.children.compactMap { everyNode($0).first { $0.kind == "Text" }?.text }
    }

    func testDataWithKeyPathIdMakesOneRowPerElement() {
        let graph = i60Graph(DataListScreen())
        XCTAssertEqual(rowTexts(graph), ["a", "b", "c"])
        XCTAssertEqual(i60Nodes(graph, kind: "List").first?.children.count, 3)
    }

    func testIdentifiableDataNeedsNoId() {
        XCTAssertEqual(rowTexts(i60Graph(IdentifiableListScreen())), ["apple", "pear"])
    }

    func testRangeOfRows() {
        XCTAssertEqual(rowTexts(i60Graph(RangeListScreen())), ["row 0", "row 1", "row 2"])
    }

    func testDataRowsLayOutLikeForEachRows() throws {
        // the same rows as ListLayoutTests: 10 pt down, 24 pt tall, 16 pt in
        let graph = i60Graph(DataListScreen())
        let list = try XCTUnwrap(i60Nodes(graph, kind: "List").first)
        for (index, row) in list.children.enumerated() {
            XCTAssertEqual(Double(row.frame.minY) + Double(row.frame.height) / 2 - Double(list.frame.minY), 22 + 24 * Double(index), accuracy: 0.5)
            XCTAssertEqual(Double(row.frame.minX - list.frame.minX), 16, accuracy: 1e-9)
        }
    }

    func testSingleSelectionByIdSelectsRowsAndWritesTheBinding() throws {
        let graph = i60Graph(SingleSelectionScreen())
        XCTAssertNotNil(i60Text(graph, "sel=b"))
        XCTAssertEqual(sr1Node(graph, try XCTUnwrap(sr1RowID(graph, containing: "b")))?.accessibility.isSelected, true)
        XCTAssertEqual(sr1Node(graph, try XCTUnwrap(sr1RowID(graph, containing: "a")))?.accessibility.isSelected, false)
        XCTAssertTrue(graph.selectRow(try XCTUnwrap(sr1RowID(graph, containing: "c")))); graph.flush()
        XCTAssertNotNil(i60Text(graph, "sel=c"))
        XCTAssertEqual(sr1Node(graph, try XCTUnwrap(sr1RowID(graph, containing: "c")))?.accessibility.isSelected, true)
        let list = try XCTUnwrap(graph.ids(ofKind: "List").first)
        XCTAssertTrue(graph.navigateList(list, .up)); graph.flush()
        XCTAssertNotNil(i60Text(graph, "sel=b"))
    }

    func testMultipleSelectionOverIdentifiableData() throws {
        let graph = i60Graph(MultiSelectionScreen())
        XCTAssertNotNil(i60Text(graph, "sel=1"))
        XCTAssertTrue(graph.selectRow(try XCTUnwrap(sr1RowID(graph, containing: "plum")), modifiers: .command)); graph.flush()
        XCTAssertNotNil(i60Text(graph, "sel=1,3"))
        XCTAssertEqual(sr1Node(graph, try XCTUnwrap(sr1RowID(graph, containing: "pear")))?.accessibility.isSelected, false)
        let list = try XCTUnwrap(graph.ids(ofKind: "List").first)
        XCTAssertTrue(graph.navigateList(list, .selectAll)); graph.flush()
        XCTAssertNotNil(i60Text(graph, "sel=1,2,3"))
    }
}
