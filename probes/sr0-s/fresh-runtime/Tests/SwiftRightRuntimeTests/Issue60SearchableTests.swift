import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: .searchable(text:) as a search-field row above the view.

private struct SearchScreen: View {
    @State private var query: String
    let prompt: String?

    init(query: String = "", prompt: String? = nil) {
        _query = State(initialValue: query)
        self.prompt = prompt
    }

    var body: some View {
        let rows = ["apple", "banana", "cherry"].filter { query.isEmpty || $0.contains(query) }
        if let prompt {
            List { ForEach(rows, id: \.self) { Text($0) } }.searchable(text: $query, prompt: prompt)
        } else {
            List { ForEach(rows, id: \.self) { Text($0) } }.searchable(text: $query)
        }
    }
}

@MainActor
final class Issue60SearchableTests: XCTestCase {
    func testASearchFieldRowSitsAboveTheList() throws {
        let graph = i60Graph(SearchScreen())
        let field = try XCTUnwrap(i60Nodes(graph, kind: "TextField").first)
        let list = try XCTUnwrap(i60Nodes(graph, kind: "List").first)
        XCTAssertLessThan(Double(field.frame.minY), Double(list.frame.minY))
        XCTAssertEqual(field.placeholder, "Search")
        XCTAssertEqual(i60Nodes(graph, kind: "Image").compactMap(\.image), [.system("magnifyingglass")], "no clear button while the field is empty")
    }

    func testPromptIsThePlaceholder() throws {
        let graph = i60Graph(SearchScreen(prompt: "Find a fruit"))
        XCTAssertEqual(i60Nodes(graph, kind: "TextField").first?.placeholder, "Find a fruit")
    }

    func testRowMetricsAre22PointsInsideEightPointPadding() throws {
        let graph = i60Graph(SearchScreen())
        let list = try XCTUnwrap(i60Nodes(graph, kind: "List").first)
        XCTAssertEqual(Double(list.frame.minY), 22 + 16, accuracy: 0.5, "22 pt field + 8 pt above and below")
        XCTAssertEqual(list.frame.width, 300)
    }

    func testTheBoundTextShowsInTheFieldAndTheClearButtonEmptiesIt() throws {
        let graph = i60Graph(SearchScreen(query: "an"))
        XCTAssertEqual(i60Nodes(graph, kind: "TextField").first?.text, "an")
        XCTAssertEqual(i60Texts(graph), ["banana"], "the caller filters by the bound text")
        let clear = try XCTUnwrap(i60Nodes(graph, kind: "Image").first { $0.image == .system("xmark.circle.fill") })
        let point = i60Mid(clear.frame)
        XCTAssertTrue(graph.tapGesture(atX: CGFloat(point.x), y: CGFloat(point.y)))
        XCTAssertEqual(i60Nodes(graph, kind: "TextField").first?.text ?? "", "")
        XCTAssertEqual(i60Texts(graph), ["apple", "banana", "cherry"])
        XCTAssertNil(i60Nodes(graph, kind: "Image").first { $0.image == .system("xmark.circle.fill") })
    }
}
