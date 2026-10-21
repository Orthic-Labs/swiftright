import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: Picker (menu by default, segmented, inline) and .pickerStyle.

private struct MenuPickerScreen: View {
    @State private var selection = "a"
    var body: some View {
        VStack {
            Text("sel=\(selection)")
            Picker("Mode", selection: $selection) {
                Text("Alpha").tag("a")
                Text("Beta").tag("b")
            }
        }
    }
}

private struct ForEachPickerScreen: View {
    @State private var n = 2
    var body: some View {
        Picker("N", selection: $n) {
            ForEach([1, 2, 3], id: \.self) { Text("n\($0)") }
        }
    }
}

private struct HiddenLabelScreen: View {
    @State private var selection = "a"
    var body: some View {
        Picker("Mode", selection: $selection) { Text("Alpha").tag("a") }.labelsHidden()
    }
}

private struct SegmentedScreen: View {
    @State private var selection = "a"
    var body: some View {
        VStack {
            Text("sel=\(selection)")
            Picker("Mode", selection: $selection) {
                Text("Alpha").tag("a")
                Text("Beta").tag("b")
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct InlineScreen: View {
    @State private var selection = "b"
    var body: some View {
        VStack {
            Text("sel=\(selection)")
            Picker("Mode", selection: $selection) {
                Text("Alpha").tag("a")
                Text("Beta").tag("b")
            }
            .pickerStyle(.inline)
        }
    }
}

private struct ConditionalOptionsScreen: View {
    @State private var selection = 1
    var body: some View {
        Picker(selection: $selection, content: {
            Text("One").tag(1)
            if selection == 1 { Text("Two").tag(2) }
            Text("Three").tag(3)
        }, label: { Text("Pick") })
    }
}

@MainActor
final class Issue60PickerTests: XCTestCase {
    func testMenuPickerShowsLabelAndSelectedOptionAndListsItemsInTheMenu() throws {
        let graph = i60Graph(MenuPickerScreen())
        XCTAssertNotNil(i60Text(graph, "Mode"))
        XCTAssertNotNil(i60Text(graph, "Alpha"), "the popup button shows the selected option")
        XCTAssertNil(i60Text(graph, "Beta"), "options are menu items, not drawn until the menu opens")
        let menu = try XCTUnwrap(i60Nodes(graph, kind: "Menu").first)
        XCTAssertEqual(menu.menu?.map(\.title), ["Alpha", "Beta"])
    }

    func testChoosingAMenuItemWritesTheSelectionAndUpdatesThePopup() throws {
        let graph = i60Graph(MenuPickerScreen())
        let menuID = try XCTUnwrap(graph.ids(ofKind: "Menu").first)
        XCTAssertTrue(graph.performMenuItem(menuID, path: [1])); graph.flush()
        XCTAssertNotNil(i60Text(graph, "sel=b"))
        XCTAssertNotNil(i60Text(graph, "Beta"))
        XCTAssertNil(i60Text(graph, "Alpha"))
    }

    func testPopupButtonIs22PointsTallWithAChevron() throws {
        let graph = i60Graph(MenuPickerScreen())
        let menu = try XCTUnwrap(i60Nodes(graph, kind: "Menu").first)
        XCTAssertEqual(menu.frame.height, 22)
        XCTAssertNotNil(i60Nodes(graph, kind: "Image").first { $0.image == .system("chevron.up.chevron.down") })
        let label = try XCTUnwrap(i60Text(graph, "Mode"))
        XCTAssertLessThan(Double(label.frame.minX), Double(menu.frame.minX), "label first, popup after")
    }

    func testForEachRowsWithoutTagsUseTheirIdAsTag() throws {
        let graph = i60Graph(ForEachPickerScreen())
        XCTAssertNotNil(i60Text(graph, "n2"))
        let menu = try XCTUnwrap(i60Nodes(graph, kind: "Menu").first)
        XCTAssertEqual(menu.menu?.map(\.title), ["n1", "n2", "n3"])
    }

    func testLabelsHiddenDropsTheLabel() {
        let graph = i60Graph(HiddenLabelScreen())
        XCTAssertNil(i60Text(graph, "Mode"))
        XCTAssertNotNil(i60Text(graph, "Alpha"))
    }

    func testOptionsFollowConditionalContent() throws {
        let graph = i60Graph(ConditionalOptionsScreen())
        XCTAssertEqual(i60Nodes(graph, kind: "Menu").first?.menu?.map(\.title), ["One", "Two", "Three"])
        let menuID = try XCTUnwrap(graph.ids(ofKind: "Menu").first)
        XCTAssertTrue(graph.performMenuItem(menuID, path: [2])); graph.flush()
        XCTAssertEqual(i60Nodes(graph, kind: "Menu").first?.menu?.map(\.title), ["One", "Three"])
    }

    func testSegmentedShowsEveryOptionAndTheSelectedCellIsAccentFilled() throws {
        let graph = i60Graph(SegmentedScreen())
        let alpha = try XCTUnwrap(i60Text(graph, "Alpha")), beta = try XCTUnwrap(i60Text(graph, "Beta"))
        XCTAssertLessThan(Double(alpha.frame.minX), Double(beta.frame.minX))
        func accentCells() -> [ResolvedNode] { i60Nodes(graph, kind: "Rectangle").filter { $0.shape?.paint?.color == .semantic("accentColor") } }
        XCTAssertEqual(accentCells().count, 1)
        XCTAssertLessThan(Double(accentCells()[0].frame.minX), Double(beta.frame.minX), "the first cell is the selected one")
        XCTAssertEqual(accentCells()[0].frame.height, 22)
        XCTAssertEqual(alpha.style.foreground, .semantic("white"))
        XCTAssertEqual(beta.style.foreground, .semantic("label"))
    }

    func testTappingASegmentSelectsIt() throws {
        let graph = i60Graph(SegmentedScreen())
        let beta = try XCTUnwrap(i60Text(graph, "Beta"))
        let point = i60Mid(beta.frame)
        XCTAssertTrue(graph.tapGesture(atX: CGFloat(point.x), y: CGFloat(point.y))); graph.flush()
        XCTAssertNotNil(i60Text(graph, "sel=b"))
        let accent = i60Nodes(graph, kind: "Rectangle").filter { $0.shape?.paint?.color == .semantic("accentColor") }
        XCTAssertEqual(accent.count, 1)
        XCTAssertGreaterThan(Double(accent[0].frame.minX), Double(try XCTUnwrap(i60Text(graph, "Alpha")).frame.minX))
    }

    func testInlineStyleMarksTheSelectedRowAndTapSelects() throws {
        let graph = i60Graph(InlineScreen())
        func filled() -> Int { i60Nodes(graph, kind: "Image").filter { $0.image == .system("largecircle.fill.circle") }.count }
        XCTAssertEqual(filled(), 1)
        let alpha = try XCTUnwrap(i60Text(graph, "Alpha"))
        let point = i60Mid(alpha.frame)
        XCTAssertTrue(graph.tapGesture(atX: CGFloat(point.x), y: CGFloat(point.y))); graph.flush()
        XCTAssertNotNil(i60Text(graph, "sel=a"))
        XCTAssertEqual(filled(), 1)
        XCTAssertEqual(i60Nodes(graph, kind: "Menu").count, 0, "inline is not a popup")
    }
}
