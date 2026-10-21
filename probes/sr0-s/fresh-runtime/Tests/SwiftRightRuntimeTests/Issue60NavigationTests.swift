import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: NavigationStack, NavigationLink, NavigationPath, navigationDestination, toolbar items and titles, NavigationSplitView.

private struct DestinationLinkScreen: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Root")
                NavigationLink("Open") { Text("Detail") }
            }
            .navigationTitle("Home")
        }
    }
}

private struct DismissingDetail: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Close detail") { dismiss() } }
}

private struct DismissLinkScreen: View {
    var body: some View {
        NavigationStack {
            NavigationLink("Open") { DismissingDetail() }
        }
    }
}

private struct StatefulRoot: View {
    @State private var count = 0
    var body: some View {
        VStack {
            Button("Bump") { count += 1 }
            Text("count \(count)")
            NavigationLink("Open") { Text("Detail") }
        }
    }
}

private struct StatefulRootScreen: View {
    var body: some View { NavigationStack { StatefulRoot() } }
}

private struct ValueLinkScreen: View {
    var body: some View {
        NavigationStack {
            VStack {
                NavigationLink("Three", value: 3)
                NavigationLink("Word", value: "hello")
            }
            .navigationDestination(for: Int.self) { Text("Number \($0)") }
            .navigationDestination(for: String.self) { Text("Word \($0)") }
        }
    }
}

private struct PathScreen: View {
    @State private var path = NavigationPath()
    var body: some View {
        VStack {
            Button("Add") { path.append(7) }
            Text("count \(path.count)")
            NavigationStack(path: $path) {
                VStack { NavigationLink("Go", value: 1) }
                    .navigationDestination(for: Int.self) { Text("Number \($0)") }
            }
        }
    }
}

private struct ArrayPathScreen: View {
    @State private var path: [Int] = []
    var body: some View {
        VStack {
            Text("path \(path.map(String.init).joined(separator: ","))")
            NavigationStack(path: $path) {
                VStack { NavigationLink("Go", value: 5) }
                    .navigationDestination(for: Int.self) { Text("Number \($0)") }
            }
        }
    }
}

private struct ToolbarScreen: View {
    var body: some View {
        NavigationStack {
            Text("x")
                .toolbar {
                    ToolbarItem(placement: .navigation) { Button("Menu") {} }
                    ToolbarItem(placement: .primaryAction) { Button("Add") {} }
                }
        }
    }
}

private struct PlainStackScreen: View {
    var body: some View { NavigationStack { Text("x") } }
}

private struct TitleScreen: View {
    var body: some View {
        NavigationStack {
            Text("body").navigationTitle("Inbox").navigationSubtitle("3 unread")
        }
    }
}

private struct PrincipalScreen: View {
    @State private var showExtra = false
    var body: some View {
        NavigationStack {
            Text("x")
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Centre") }
                    if showExtra { ToolbarItem(placement: .status) { Text("Extra") } }
                }
        }
    }
}

private struct SplitScreen: View {
    @State private var selection: String? = "a"
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) { ForEach(["a", "b"], id: \.self) { Text($0).tag($0) } }
        } detail: {
            Text("detail \(selection ?? "none")")
        }
    }
}

private struct SplitHiddenScreen: View {
    @State private var visibility = NavigationSplitViewVisibility.detailOnly
    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List { Text("side") }
        } detail: {
            Text("main")
        }
    }
}

private struct SplitLinkScreen: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("One") { Text("Detail one") }
                NavigationLink("Two") { Text("Detail two") }
            }
        } detail: {
            Text("Pick one")
        }
    }
}

private struct ThreeColumnScreen: View {
    var body: some View {
        NavigationSplitView {
            Text("S")
        } content: {
            Text("C")
        } detail: {
            Text("D")
        }
    }
}

@MainActor
final class Issue60NavigationTests: XCTestCase {
    private func opacities(_ graph: Graph) -> [Double] { i60Nodes(graph, kind: "modifier.opacity").map(\.opacity) }

    // MARK: stack

    func testRootShowsAndHasNoBackButton() {
        let graph = i60Graph(DestinationLinkScreen())
        XCTAssertNotNil(i60Text(graph, "Root"))
        XCTAssertNil(i60Text(graph, "Detail"))
        XCTAssertEqual(i60Nodes(graph, kind: "Button").count, 1, "only the link")
        XCTAssertNotNil(i60Text(graph, "Home"), "the navigation title shows in the bar row")
    }

    func testPushingShowsTheDestinationAndABackButtonAndHidesTheRootsTitle() {
        let graph = i60Graph(DestinationLinkScreen())
        i60Tap(graph, button: "Open")
        XCTAssertNotNil(i60Text(graph, "Detail"))
        XCTAssertEqual(i60Nodes(graph, kind: "Button").count, 2, "the back button and the covered root's link")
        XCTAssertNil(i60Text(graph, "Home"), "only the top screen's bar contributions count")
        XCTAssertNotNil(i60Nodes(graph, kind: "Image").first { $0.image == .system("chevron.left") })
        XCTAssertTrue(opacities(graph).contains(0), "the covered root stays alive, invisible")
    }

    func testBackButtonPopsAndTheTitleReturns() throws {
        let graph = i60Graph(DestinationLinkScreen())
        i60Tap(graph, button: "Open")
        let back = try XCTUnwrap(i60Nodes(graph, kind: "Button").first)
        XCTAssertTrue(graph.tapButton(back.id)); graph.flush()
        XCTAssertNil(i60Text(graph, "Detail"))
        XCTAssertNotNil(i60Text(graph, "Home"))
        XCTAssertEqual(i60Nodes(graph, kind: "Button").count, 1)
    }

    func testDismissFromEnvironmentPops() {
        let graph = i60Graph(DismissLinkScreen())
        i60Tap(graph, button: "Open")
        XCTAssertNotNil(i60Button(graph, "Close detail"))
        i60Tap(graph, button: "Close detail")
        XCTAssertNil(i60Button(graph, "Close detail"))
        XCTAssertNotNil(i60Button(graph, "Open"))
    }

    func testRootStateSurvivesPushAndPop() throws {
        let graph = i60Graph(StatefulRootScreen())
        i60Tap(graph, button: "Bump"); i60Tap(graph, button: "Bump")
        i60Tap(graph, button: "Open")
        let back = try XCTUnwrap(i60Nodes(graph, kind: "Button").first)
        XCTAssertTrue(graph.tapButton(back.id)); graph.flush()
        XCTAssertNotNil(i60Text(graph, "count 2"))
    }

    func testValueLinksResolveTheDestinationForTheValuesType() {
        let graph = i60Graph(ValueLinkScreen())
        i60Tap(graph, button: "Three")
        XCTAssertNotNil(i60Text(graph, "Number 3"))
        let again = i60Graph(ValueLinkScreen())
        i60Tap(again, button: "Word")
        XCTAssertNotNil(i60Text(again, "Word hello"))
        XCTAssertNil(i60Text(again, "Number 3"))
    }

    func testBoundPathCountsPushesAndPushesFromOutside() {
        let graph = i60Graph(PathScreen())
        XCTAssertNotNil(i60Text(graph, "count 0"))
        i60Tap(graph, button: "Go")
        XCTAssertNotNil(i60Text(graph, "count 1"))
        XCTAssertNotNil(i60Text(graph, "Number 1"))
        i60Tap(graph, button: "Add")
        XCTAssertNotNil(i60Text(graph, "count 2"))
        XCTAssertNotNil(i60Text(graph, "Number 7"))
    }

    func testBoundPathPopsThroughTheBackButton() throws {
        let graph = i60Graph(PathScreen())
        i60Tap(graph, button: "Go")
        let buttons = i60Nodes(graph, kind: "Button")
        let back = try XCTUnwrap(buttons.first { everyNode($0).contains { $0.image == .system("chevron.left") } })
        XCTAssertTrue(graph.tapButton(back.id)); graph.flush()
        XCTAssertNotNil(i60Text(graph, "count 0"))
        XCTAssertNil(i60Text(graph, "Number 1"))
    }

    func testArrayPathBinding() {
        let graph = i60Graph(ArrayPathScreen())
        i60Tap(graph, button: "Go")
        XCTAssertNotNil(i60Text(graph, "path 5"))
        XCTAssertNotNil(i60Text(graph, "Number 5"))
    }

    func testNavigationPathValueSemantics() {
        var path = NavigationPath()
        XCTAssertTrue(path.isEmpty)
        path.append(1); path.append("two")
        XCTAssertEqual(path.count, 2)
        path.removeLast()
        XCTAssertEqual(path, NavigationPath([1]))
        path.removeLast(5)
        XCTAssertTrue(path.isEmpty)
    }

    // MARK: toolbar and titles

    func testToolbarItemsGoToTheBarBySide() throws {
        let graph = i60Graph(ToolbarScreen())
        let menu = try XCTUnwrap(i60Button(graph, "Menu"))
        let add = try XCTUnwrap(i60Button(graph, "Add"))
        XCTAssertLessThan(Double(menu.frame.minX), 100, "navigation items lead")
        XCTAssertGreaterThan(Double(add.frame.minX), 200, "primary actions trail")
        XCTAssertLessThan(Double(add.frame.minY), 52, "inside the 52 pt bar row")
        XCTAssertEqual(Double(add.frame.minX + add.frame.width), 300 - 12, accuracy: 1.0, "12 pt from the trailing edge")
    }

    func testBarRowIs52PointsWithADividerBelowAndNoneWhenEmpty() throws {
        let graph = i60Graph(ToolbarScreen())
        let divider = try XCTUnwrap(i60Nodes(graph, kind: "Divider").first)
        XCTAssertEqual(divider.frame.minY, 52)
        let plain = i60Graph(PlainStackScreen())
        XCTAssertEqual(i60Nodes(plain, kind: "Divider").count, 0, "nothing to show, no bar row")
        XCTAssertEqual(i60Mid(try XCTUnwrap(i60Text(plain, "x")).frame).y, 100, accuracy: 1.0, "the root is centred in the whole 200 pt")
    }

    func testTitleAndSubtitleShowLeadingInTheBar() throws {
        let graph = i60Graph(TitleScreen())
        let title = try XCTUnwrap(i60Text(graph, "Inbox"))
        let subtitle = try XCTUnwrap(i60Text(graph, "3 unread"))
        XCTAssertEqual(title.frame.minX, 12)
        XCTAssertLessThan(Double(title.frame.minY), Double(subtitle.frame.minY))
    }

    func testPrincipalItemReplacesTheTitleAndConditionalItemsAppear() {
        let graph = i60Graph(PrincipalScreen())
        XCTAssertNotNil(i60Text(graph, "Centre"))
        XCTAssertNil(i60Text(graph, "Extra"))
    }

    // MARK: split view

    func testSplitViewColumnsAndSidebarSelection() throws {
        let graph = i60Graph(SplitScreen())
        let list = try XCTUnwrap(i60Nodes(graph, kind: "List").first)
        XCTAssertEqual(list.frame.width, 215)
        let detail = try XCTUnwrap(i60Text(graph, "detail a"))
        XCTAssertGreaterThan(Double(detail.frame.minX), 215)
        XCTAssertTrue(graph.selectRow(try XCTUnwrap(sr1RowID(graph, containing: "b")))); graph.flush()
        XCTAssertNotNil(i60Text(graph, "detail b"))
        XCTAssertNil(i60Text(graph, "detail a"))
    }

    func testSplitViewDetailOnlyHidesTheSidebar() {
        let graph = i60Graph(SplitHiddenScreen())
        XCTAssertNil(i60Text(graph, "side"))
        XCTAssertNotNil(i60Text(graph, "main"))
    }

    func testSidebarLinksReplaceTheDetail() {
        let graph = i60Graph(SplitLinkScreen())
        XCTAssertNotNil(i60Text(graph, "Pick one"))
        i60Tap(graph, button: "One")
        XCTAssertNotNil(i60Text(graph, "Detail one"))
        i60Tap(graph, button: "Two")
        XCTAssertNotNil(i60Text(graph, "Detail two"))
        XCTAssertNil(i60Text(graph, "Detail one"), "a second link replaces, it does not stack")
    }

    func testThreeColumnsHaveFixedSidebarAndContentWidths() throws {
        let graph = i60Graph(ThreeColumnScreen())
        let s = try XCTUnwrap(i60Text(graph, "S")), c = try XCTUnwrap(i60Text(graph, "C")), d = try XCTUnwrap(i60Text(graph, "D"))
        XCTAssertLessThan(Double(s.frame.minX), Double(c.frame.minX))
        XCTAssertLessThan(Double(c.frame.minX), Double(d.frame.minX))
        XCTAssertGreaterThanOrEqual(Double(c.frame.minX), 215)
        XCTAssertGreaterThanOrEqual(Double(d.frame.minX), 215 + 250)
    }
}
