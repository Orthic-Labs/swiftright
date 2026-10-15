import XCTest
import SwiftRightHost
import SwiftRightBridge

private struct Witness_ButtonView: View {
    var body: some View { Button("Run") {} }
}

private struct Witness_DisabledButtonView: View {
    var body: some View { Button("Run") {}.disabled(true) }
}

private struct Witness_ProminentButton: View { var body: some View { Button("Run") {}.buttonStyle(.borderedProminent) } }
private struct Witness_DefaultActionButton: View { var body: some View { Button("Run") {}.keyboardShortcut(.defaultAction) } }
private struct Witness_DisabledDefaultActionButton: View { var body: some View { Button("Run") {}.keyboardShortcut(.defaultAction).disabled(true) } }
private struct Witness_BorderlessButton: View { var body: some View { Button("Run") {}.buttonStyle(.borderless) } }
private struct Witness_DisabledBorderlessButton: View { var body: some View { Button("Run") {}.buttonStyle(.borderless).disabled(true) } }
private struct Witness_PlainButton: View { var body: some View { Button("Run") {}.buttonStyle(.plain) } }
private struct Witness_DisabledPlainButton: View { var body: some View { Button("Run") {}.buttonStyle(.plain).disabled(true) } }
private struct Witness_RedBorderlessButton: View { var body: some View { Button("Run") {}.buttonStyle(.borderless).foregroundStyle(Color.red) } }
private struct Witness_RedBorderedButton: View { var body: some View { Button("Run") {}.foregroundStyle(Color.red) } }
private struct Witness_DestructiveButton: View { var body: some View { Button("Run", role: .destructive) {} } }

/// A Button is one image primitive (the bordered push button artwork) plus button semantics; its label paints itself in the button's label colour.
@MainActor
final class ButtonPainterTests: XCTestCase {
    private func paint<V: View>(_ view: V, runs fakeRuns: FakeRuns? = nil) throws -> (nodes: [(ResolvedNode, NodeEmission)], images: FakeImages, runs: FakeRuns) {
        let runs = fakeRuns ?? FakeRuns()
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: runs, log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let root = try XCTUnwrap(graph.snapshot())
        var out: [(ResolvedNode, NodeEmission)] = []
        // walk through commit so the label colour is inherited exactly as in a window
        _ = try painter.commit(root: root, version: 1, previousLive: [], submit: { _ in })        // `runs` records what the commit asked for
        let emitImages = FakeImages()
        let emitPainter = ResolvedNodePainter(images: emitImages, scale: 2.5, text: FakeRuns(), log: { _ in })
        emitPainter.beginCommit()
        for n in flatten(root) {
            let b = Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
            out.append((n, try emitPainter.emit(n, id: UInt64(n.instance + 1), bounds: b)))
        }
        emitPainter.endCommit(committed: true)
        return (out, emitImages, runs)
    }

    func testButtonPaintsOneImageAndButtonSemantics() throws {
        let r = try paint(Witness_ButtonView())
        let button = try XCTUnwrap(r.nodes.first { $0.0.kind == "Button" })
        guard case .image(let handle, _, _) = try XCTUnwrap(button.1.primitives.first) else { return XCTFail("a button is an image primitive") }
        XCTAssertEqual(button.1.primitives.count, 1)
        let entry = try XCTUnwrap(r.images.registered[handle.raw])
        XCTAssertEqual(entry.width, UInt32(button.0.pixelFrame.width))
        XCTAssertEqual(Float(entry.height), 60, "a 24 pt body-text button is 60 px tall at scale 2.5")
        XCTAssertEqual(button.1.semantic?.role, .button)
        XCTAssertEqual(button.1.semantic?.actions, [.invoke])
        XCTAssertEqual(button.1.semantic?.disabled, false)
        XCTAssertEqual(button.1.flags, [.hitTarget])
    }

    func testTheLabelTakesTheButtonsLabelColour() throws {
        let enabled = try paint(Witness_ButtonView()), disabled = try paint(Witness_DisabledButtonView())
        XCTAssertEqual(enabled.runs.colours, [0x242424ff])
        XCTAssertEqual(disabled.runs.colours, [0xb6b6b6ff])
    }

    func testDisabledButtonIsFlaggedOffersNoActionAndHasADifferentFill() throws {
        let r = try paint(Witness_DisabledButtonView())
        let button = try XCTUnwrap(r.nodes.first { $0.0.kind == "Button" })
        XCTAssertEqual(button.1.semantic?.disabled, true)
        XCTAssertEqual(button.1.semantic?.actions, [])
        let enabled = try paint(Witness_ButtonView())
        XCTAssertNotEqual(try XCTUnwrap(r.images.registered.values.first).rgba, try XCTUnwrap(enabled.images.registered.values.first).rgba)
    }

    func testButtonFrameIsLabelPlusPadding() throws {
        let r = try paint(Witness_ButtonView())
        let button = try XCTUnwrap(r.nodes.first { $0.0.kind == "Button" }).0
        let label = try XCTUnwrap(flatten(button).first { $0.kind == "Text" })
        XCTAssertEqual(Double(button.pixelFrame.width - label.pixelFrame.width), 24 * 2.5, accuracy: 1.0)
        XCTAssertEqual(Double(button.pixelFrame.height - label.pixelFrame.height), 8 * 2.5, accuracy: 1.0)
        XCTAssertEqual(Double(label.pixelFrame.x - button.pixelFrame.x), 12 * 2.5, accuracy: 1.0)
    }

    // MARK: styles (decision 12)

    private func fill(_ r: (nodes: [(ResolvedNode, NodeEmission)], images: FakeImages, runs: FakeRuns)) throws -> [UInt8]? {
        r.images.registered.values.first.map { Array($0.rgba[((30 * Int($0.width)) + 60) * 4 ..< ((30 * Int($0.width)) + 60) * 4 + 3]) }
    }

    func testProminentAndDefaultActionPaintTheAccentFillAndAWhiteLabel() throws {
        for r in [try paint(Witness_ProminentButton()), try paint(Witness_DefaultActionButton())] {
            XCTAssertEqual(try fill(r), [0, 123, 255])
            XCTAssertEqual(r.runs.colours, [0xffffffff])
        }
    }

    func testDisabledDefaultActionIsAnOrdinaryDisabledButton() throws {
        let r = try paint(Witness_DisabledDefaultActionButton())
        XCTAssertEqual(try fill(r), [245, 245, 245])
        XCTAssertEqual(r.runs.colours, [0xb6b6b6ff])
    }

    func testBorderlessAndPlainHaveNoBodyButStayHitTargets() throws {
        for r in [try paint(Witness_BorderlessButton()), try paint(Witness_PlainButton())] {
            let button = try XCTUnwrap(r.nodes.first { $0.0.kind == "Button" })
            XCTAssertEqual(button.1.primitives.count, 0)
            XCTAssertTrue(r.images.registered.isEmpty)
            XCTAssertEqual(button.1.flags, [.hitTarget])
            XCTAssertEqual(button.1.semantic?.role, .button)
            XCTAssertEqual(button.1.semantic?.actions, [.invoke])
        }
    }

    func testBorderlessAndPlainLabelColours() throws {
        XCTAssertEqual(try paint(Witness_BorderlessButton()).runs.colours, [0x7f7f7fff])
        XCTAssertEqual(try paint(Witness_DisabledBorderlessButton()).runs.colours, [0xbfbfbfff])
        XCTAssertEqual(try paint(Witness_PlainButton()).runs.colours, [nil], "an enabled plain label keeps the default text colour")
        XCTAssertEqual(try paint(Witness_DisabledPlainButton()).runs.colours, [0x0000006c], "half of the label colour's opacity")
    }

    /// Known limit: a Text label inherits the Button's foreground through the environment and cannot tell it from its own, so it always wins; SwiftUI keeps a
    /// prominent label white and dims a disabled plain label to half opacity. Only the borderless and enabled plain cases are exact.
    func testForegroundStyleColoursABorderlessLabel() throws {
        let colours = try paint(Witness_RedBorderlessButton()).runs.colours
        XCTAssertEqual(colours.count, 1)
        XCTAssertNotEqual(colours, [0x7f7f7fff])
    }

    /// Round 5 block 31 (hub gap R11): a plain or borderless Button under `.opacity` draws only its label, faded; a bordered one still needs group opacity over its artwork.
    func testOpacityOnAPlainButtonFadesItsLabel() throws {
        struct Faded: View { var body: some View { Button("Run") {}.buttonStyle(.plain).opacity(0.5) } }
        struct FadedBorderless: View { var body: some View { Button("Run") {}.buttonStyle(.borderless).opacity(0.5) } }
        struct FadedBordered: View { var body: some View { Button("Run") {}.opacity(0.5) } }
        XCTAssertEqual(try paint(Faded()).runs.colours.compactMap { $0 }.map { $0 & 255 }, [108], "216 x 0.5")
        XCTAssertEqual(try paint(FadedBorderless()).runs.colours.count, 1)
        XCTAssertThrowsError(try paint(FadedBordered()))
    }

    func testAnEmptyFramedButtonPaintsNothingInsteadOfFailing() throws {
        struct Empty: View { var body: some View { Button("Run") {}.frame(width: 0, height: 0) } }
        struct EmptyPlain: View { var body: some View { Button("Run") {}.buttonStyle(.plain).frame(width: 0, height: 0) } }
        XCTAssertNoThrow(try paint(Empty()))
        XCTAssertNoThrow(try paint(EmptyPlain()))
    }

    func testForegroundOnABorderedButtonTintsItsFillAndIsNotModelled() {
        XCTAssertThrowsError(try paint(Witness_RedBorderedButton()))
    }

    func testRoleDoesNotChangeThePaint() throws {
        let plain = try paint(Witness_ButtonView()), destructive = try paint(Witness_DestructiveButton())
        XCTAssertEqual(plain.runs.colours, destructive.runs.colours)
        XCTAssertEqual(try fill(plain), try fill(destructive))
    }

    func testButtonLabelTextPublishesNoSemanticNodeOfItsOwn() throws {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(Witness_ButtonView(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var sent: SwiftRightBridge.Transaction?
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { sent = $0 })
        let roles = try XCTUnwrap(sent).upserts.compactMap { $0.semantic?.role }
        XCTAssertEqual(roles, [.button])
    }
}
