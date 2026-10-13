import SwiftRightRuntime
import XCTest

/// Button styles, measured from SwiftUI on macOS 27 (`NSHostingView.fittingSize`, factory/tools/switch-artwork/button-styles): `.bordered`, `.borderedProminent`
/// and the automatic style pad the label (48 x 24 pt for `Button("Run")`, 54 x 18 for a 30 x 10 view label); `.borderless` and `.plain` are the label alone
/// (24 x 16 and 30 x 10). A Button under `.keyboardShortcut(.defaultAction)` is the default button, which macOS draws as the prominent push button.
@MainActor
final class ButtonStyleTests: XCTestCase {
    private func button(_ view: some View) -> ResolvedNode? {
        let graph = Graph(view, scale: 1)
        graph.flush()
        return everyNode(graph.snapshot()).first { $0.kind == "Button" }
    }

    private func size(_ view: some View) throws -> (Double, Double) {
        let node = try XCTUnwrap(button(view))
        return (Double(node.frame.width), Double(node.frame.height))
    }

    private var viewLabel: some View { Color.red.frame(width: 30, height: 10) }

    func testPaddedStylesAddTwelveAndFour() throws {
        for (w, h) in [try size(Button(action: {}) { viewLabel }.buttonStyle(.bordered)),
                       try size(Button(action: {}) { viewLabel }.buttonStyle(.borderedProminent)),
                       try size(Button(action: {}) { viewLabel }.buttonStyle(.automatic))] {
            XCTAssertEqual(w, 54); XCTAssertEqual(h, 18)
        }
    }

    func testBorderlessAndPlainAreTheLabelAlone() throws {
        for (w, h) in [try size(Button(action: {}) { viewLabel }.buttonStyle(.borderless)), try size(Button(action: {}) { viewLabel }.buttonStyle(.plain))] {
            XCTAssertEqual(w, 30); XCTAssertEqual(h, 10)
        }
    }

    func testTextButtonStyleChangesTheFrameByThePadding() throws {
        let padded = try size(Button("Run") {}), plain = try size(Button("Run") {}.buttonStyle(.plain))
        XCTAssertEqual(padded.0 - plain.0, 24, accuracy: 1e-9)
        XCTAssertEqual(padded.1 - plain.1, 8, accuracy: 1e-9)
    }

    func testStyleReachesButtonsInsideAContainerAndTheNearestOneWins() throws {
        let graph = Graph(VStack { Button("A") {}; Button("B") {}.buttonStyle(.plain) }.buttonStyle(.borderless), scale: 1)
        graph.flush()
        let buttons = everyNode(graph.snapshot()).filter { $0.kind == "Button" }
        XCTAssertEqual(buttons.map(\.buttonStyle), ["BorderlessButtonStyle", "PlainButtonStyle"])
    }

    func testButtonStyleMetadataIsNilWhenNoneApplies() throws {
        XCTAssertNil(try XCTUnwrap(button(Button("Run") {})).buttonStyle)
    }

    func testDefaultActionMarksTheButton() throws {
        XCTAssertTrue(try XCTUnwrap(button(Button("Run") {}.keyboardShortcut(.defaultAction))).isDefaultButton)
        XCTAssertTrue(try XCTUnwrap(button(Button("Run") {}.keyboardShortcut(.return, modifiers: []))).isDefaultButton)
        XCTAssertFalse(try XCTUnwrap(button(Button("Run") {}.keyboardShortcut("r"))).isDefaultButton)
        XCTAssertFalse(try XCTUnwrap(button(Button("Run") {}.keyboardShortcut(.cancelAction))).isDefaultButton)
        XCTAssertFalse(try XCTUnwrap(button(Button("Run") {})).isDefaultButton)
    }

    func testDefaultActionOnlyMarksButtonsInsideItsView() throws {
        let graph = Graph(HStack { Button("A") {}; Button("B") {}.keyboardShortcut(.defaultAction) }, scale: 1)
        graph.flush()
        XCTAssertEqual(everyNode(graph.snapshot()).filter { $0.kind == "Button" }.map(\.isDefaultButton), [false, true])
    }

    func testDefaultActionRunsTheButtonOnReturn() throws {
        var runs = 0
        let graph = Graph(Button("Run") { runs += 1 }.keyboardShortcut(.defaultAction), scale: 1)
        graph.flush()
        XCTAssertTrue(graph.performKeyboardShortcut(.return, modifiers: []))
        XCTAssertEqual(runs, 1)
    }

    func testRoleDoesNotChangeTheLayoutOrTheStyle() throws {
        let a = try size(Button("Run", role: .destructive) {}), b = try size(Button("Run") {})
        XCTAssertEqual(a.0, b.0); XCTAssertEqual(a.1, b.1)
        XCTAssertNil(try XCTUnwrap(button(Button("Run", role: .destructive) {})).buttonStyle)
    }

    func testChangingTheStyleRelaysOutTheButton() throws {
        struct Switching: View {
            @State var plain = false
            var body: some View {
                VStack { if plain { Button("Run") {}.buttonStyle(.plain) } else { Button("Run") {}.buttonStyle(.bordered) }; Button("Flip") { plain.toggle() } }
            }
        }
        let graph = Graph(Switching(), scale: 1)
        graph.flush()
        let before = everyNode(graph.snapshot()).filter { $0.kind == "Button" }
        XCTAssertEqual(before[0].frame.height, before[1].frame.height)
        XCTAssertTrue(graph.tapButton(before[1].id))
        graph.flush()
        let after = everyNode(graph.snapshot()).filter { $0.kind == "Button" }
        XCTAssertEqual(Double(before[0].frame.height - after[0].frame.height), 8, accuracy: 1e-9)
    }

    func testLookResolution() {
        XCTAssertEqual(ButtonLook(style: nil), .bordered)
        XCTAssertEqual(ButtonLook(style: "DefaultButtonStyle"), .bordered)
        XCTAssertEqual(ButtonLook(style: nil, isDefaultAction: true), .prominent)
        XCTAssertEqual(ButtonLook(style: "PlainButtonStyle", isDefaultAction: true), .plain)
        XCTAssertEqual(ButtonLook(style: "BorderedProminentButtonStyle"), .prominent)
        XCTAssertEqual(ButtonLook(style: "BorderlessButtonStyle"), .borderless)
    }
}
