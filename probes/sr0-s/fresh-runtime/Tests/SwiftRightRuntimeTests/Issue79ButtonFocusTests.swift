import XCTest
@testable import SwiftRightRuntime

// Issue #79: Tab walks the Buttons that carry a `.focused` binding (Mac with full keyboard access on), and each Button in turn reports `buttonIsFocused`.
@MainActor
final class Issue79ButtonFocusTests: XCTestCase {
    struct Screen: View {
        @FocusState private var focus: Int?
        var body: some View {
            VStack(spacing: 14) {
                Button { } label: { Text("Bordered").frame(width: 84) }.buttonStyle(.bordered).focused($focus, equals: 0)
                Button { } label: { Text("Prominent").frame(width: 84) }.buttonStyle(.borderedProminent).focused($focus, equals: 1)
                Button { } label: { Text("Plain").frame(width: 84) }.buttonStyle(.plain).focused($focus, equals: 2)
                Button { } label: { Text("Borderless").frame(width: 84) }.buttonStyle(.borderless).focused($focus, equals: 3)
                TextField("Field", text: .constant("")).frame(width: 120).focused($focus, equals: 4)
            }
            .padding(20).frame(width: 200, height: 260)
            .onAppear { focus = 0 }
        }
    }

    private func focusedButtons(_ graph: Graph) -> [Bool] {
        var out: [Bool] = []
        func walk(_ n: ResolvedNode) { if n.kind == "Button" { out.append(n.buttonIsFocused) }; n.children.forEach(walk) }
        walk(graph.snapshot()!)
        return out
    }

    func testTabWalksTheFocusedButtonsInOrder() throws {
        let graph = Graph(Screen(), scale: 1)
        graph.tabFocusesAllControls = true   // full keyboard access on (macOS default off: Tab then skips Buttons)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        XCTAssertEqual(focusedButtons(graph), [true, false, false, false], "initial focus on the first Button")
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(focusedButtons(graph), [false, true, false, false])
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(focusedButtons(graph), [false, false, true, false])
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(focusedButtons(graph), [false, false, false, true])
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(focusedButtons(graph), [false, false, false, false], "the TextField holds the focus")
    }

    func testWithTheMacDefaultTabSkipsTheButtons() throws {
        let graph = Graph(Screen(), scale: 1)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        XCTAssertTrue(graph.moveFocus(forward: true))
        XCTAssertEqual(focusedButtons(graph), [false, false, false, false], "Tab goes to the TextField, not to a Button")
    }
}
