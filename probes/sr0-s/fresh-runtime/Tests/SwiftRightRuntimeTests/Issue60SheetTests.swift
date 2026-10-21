import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: .sheet(isPresented:) and .sheet(item:) as an overlay layer, and @Environment(\.dismiss).

@MainActor
private final class SheetLog { var lines: [String] = [] }

private struct SheetScreen: View {
    @State private var show = false
    let log: SheetLog

    var body: some View {
        VStack {
            Button("Open") { show = true }
            Text("below")
        }
        .frame(width: 300, height: 200)
        .sheet(isPresented: $show, onDismiss: { log.lines.append("dismissed") }) {
            VStack {
                Text("Are you sure?")
                Button("OK") { show = false }
            }
        }
    }
}

private struct DismissingSheetContent: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("Done") { dismiss() }
    }
}

private struct DismissScreen: View {
    @State private var show = true
    var body: some View {
        Text("root").frame(width: 300, height: 200).sheet(isPresented: $show) { DismissingSheetContent() }
    }
}

private struct Thing: Identifiable {
    let id: Int
    let name: String
}

private struct ItemScreen: View {
    @State private var item: Thing? = nil
    let log: SheetLog

    var body: some View {
        VStack {
            Button("Pick") { item = Thing(id: 1, name: "alpha") }
        }
        .frame(width: 300, height: 200)
        .sheet(item: $item, onDismiss: { log.lines.append("item dismissed") }) { thing in
            VStack {
                Text("Item \(thing.name)")
                Button("Dismiss") { item = nil }
            }
        }
    }
}

@MainActor
final class Issue60SheetTests: XCTestCase {
    func testSheetContentAppearsOnlyWhilePresented() {
        let graph = i60Graph(SheetScreen(log: SheetLog()))
        XCTAssertNil(i60Text(graph, "Are you sure?"))
        i60Tap(graph, button: "Open")
        XCTAssertNotNil(i60Text(graph, "Are you sure?"))
        XCTAssertNotNil(i60Button(graph, "OK"))
        i60Tap(graph, button: "OK")
        XCTAssertNil(i60Text(graph, "Are you sure?"))
    }

    func testCoveredViewTakesNoPointerHitsWhileTheSheetIsUp() throws {
        let graph = i60Graph(SheetScreen(log: SheetLog()))
        XCTAssertEqual(try XCTUnwrap(i60Button(graph, "Open")).accessibility.allowsHitTesting, true)
        i60Tap(graph, button: "Open")
        XCTAssertEqual(try XCTUnwrap(i60Button(graph, "Open")).accessibility.allowsHitTesting, false)
        XCTAssertEqual(try XCTUnwrap(i60Button(graph, "OK")).accessibility.allowsHitTesting, true)
        i60Tap(graph, button: "OK")
        XCTAssertEqual(try XCTUnwrap(i60Button(graph, "Open")).accessibility.allowsHitTesting, true)
    }

    func testPanelIsCentredOnTheTopEdgeAtItsIdealSizeOverAScrim() throws {
        let graph = i60Graph(SheetScreen(log: SheetLog()))
        i60Tap(graph, button: "Open")
        let text = try XCTUnwrap(i60Text(graph, "Are you sure?"))
        let ok = try XCTUnwrap(i60Button(graph, "OK"))
        // the sheet's VStack is as wide as its widest child, not the 300 pt window
        let panelWidth = max(Double(text.frame.width), Double(ok.frame.width))
        XCTAssertLessThan(panelWidth, 200)
        XCTAssertEqual(i60Mid(text.frame).x, 150, accuracy: 1.0, "centred horizontally in the covered view")
        XCTAssertLessThan(Double(text.frame.minY), 60, "attached to the top edge")
        let scrim = i60Nodes(graph, kind: "Color").first { $0.color == .semanticAlpha("black", SheetMetrics.scrimOpacity) }
        XCTAssertEqual(scrim?.frame.width, 300)
        XCTAssertEqual(scrim?.frame.height, 200)
    }

    func testOnDismissRunsWhenThePresentationEnds() {
        let log = SheetLog()
        let graph = i60Graph(SheetScreen(log: log))
        i60Tap(graph, button: "Open")
        XCTAssertEqual(log.lines, [])
        i60Tap(graph, button: "OK")
        graph.flush()
        XCTAssertEqual(log.lines, ["dismissed"])
    }

    func testDismissFromTheEnvironmentClosesTheSheet() {
        let graph = i60Graph(DismissScreen())
        XCTAssertNotNil(i60Button(graph, "Done"))
        i60Tap(graph, button: "Done")
        XCTAssertNil(i60Button(graph, "Done"))
        XCTAssertNotNil(i60Text(graph, "root"))
    }

    func testItemSheetPresentsTheItemAndClearsIt() {
        let log = SheetLog()
        let graph = i60Graph(ItemScreen(log: log))
        XCTAssertNil(i60Text(graph, "Item alpha"))
        i60Tap(graph, button: "Pick")
        XCTAssertNotNil(i60Text(graph, "Item alpha"))
        i60Tap(graph, button: "Dismiss")
        graph.flush()
        XCTAssertNil(i60Text(graph, "Item alpha"))
        XCTAssertEqual(log.lines, ["item dismissed"])
    }

    func testDismissActionOutsideAnyPresentationDoesNothing() {
        let graph = i60Graph(DismissingSheetContent())
        XCTAssertNoThrow(graph.tapButton(i60Button(graph, "Done")!.id))
        XCTAssertNotNil(i60Button(graph, "Done"))
    }
}
