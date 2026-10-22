import XCTest
import SwiftRightHost
@testable import SwiftRightBridge

// Issue #60 pass 3 host tests: Button pressed and focused artwork, the wrapped (vertical-axis) TextField paint, the stroked pill, bundled-face weights.

/// A run source that records the runs asked for and answers `cells(of:)` with a fixed list.
private final class WrappedRuns: TextRunSource {
    var asked: [(text: String, bounds: Rect, color: UInt32?)] = []
    var cells: [CharCell] = []
    func run(text: String, font: Font?, bounds: Rect) throws -> TextRunHandle { asked.append((text, bounds, nil)); return TextRunHandle(raw: 5) }
    func run(text: String, font: Font?, bounds: Rect, color: UInt32) throws -> TextRunHandle { asked.append((text, bounds, color)); return TextRunHandle(raw: 6) }
    func cells(of run: TextRunHandle) -> [CharCell] { cells }
}

private struct WitnessButton: View { var body: some View { Button("Run") {} } }
private struct WitnessProminent: View { var body: some View { Button("Run") {}.buttonStyle(.borderedProminent) } }
private struct WitnessPlain: View { var body: some View { Button("Run") {}.buttonStyle(.plain) } }
private struct WitnessDisabled: View { var body: some View { Button("Run") {}.disabled(true) } }
private struct WitnessNotes: View {
    @State var text = "aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll"
    var body: some View { TextField("Notes", text: $text, axis: .vertical).lineLimit(2).frame(width: 120) }
}
private struct WitnessExtras: View {
    var body: some View {
        VStack {
            Text("Heading").accessibilityAddTraits(.isHeader)
            Text("Site").accessibilityAddTraits(.isLink)
            Text("Memory").accessibilityValue("1.2 GB").accessibilityHint("Memory in use")
            Button("Run") {}.accessibilityHint("Starts the scan")
            Text("Plain")
        }
    }
}
private struct WitnessCapsules: View {
    var body: some View {
        VStack {
            Capsule(style: .circular).stroke(Color.red, lineWidth: 4).frame(width: 80, height: 32)
            Capsule().stroke(Color.red, lineWidth: 4).frame(width: 80, height: 32)
        }
    }
}

@MainActor
final class Issue60Controls3HostTests: XCTestCase {
    private func pixel(_ image: ContinuousRGBAImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let o = (y * image.width + x) * 4
        return (Int(image.rgba[o]), Int(image.rgba[o + 1]), Int(image.rgba[o + 2]), Int(image.rgba[o + 3]))
    }

    private func buttonNode<V: View>(_ view: V, pressed: Bool = false, focused: Bool = false) throws -> ResolvedNode {
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let id = try XCTUnwrap(graph.ids(ofKind: "Button").first)
        if pressed { XCTAssertTrue(graph.setPressedButton(id)) }
        if focused { XCTAssertTrue(graph.setFocusedButton(id)) }
        return try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "Button" })
    }

    private func bounds(_ n: ResolvedNode) -> Rect { Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height)) }

    // MARK: Button pressed

    func testPressedColoursMoveTheFillAFixedFractionTowardBlackOrWhite() {
        // measured on macOS 27 (CI 39694640337): bordered body 235 -> 212, prominent (0,123,255) -> (0,111,230); the dark bordered body is not measured
        XCTAssertEqual(ButtonArtwork.pressedColor(0xebebeb, prominent: false, dark: false), 0xd4d4d4)
        XCTAssertEqual(ButtonArtwork.pressedColor(0x303030, prominent: false, dark: true), 0x444444, "the dark bordered body lightens")
        XCTAssertEqual(ButtonArtwork.pressedColor(0x007bff, prominent: true, dark: false), 0x006fe6)
        XCTAssertEqual(ButtonArtwork.pressedColor(0x007bff, prominent: true, dark: true), 0x1988ff, "a prominent body lightens in dark mode (measured (25,136,255))")
    }

    func testAPressedBodyIsFilledWithThePressedColour() {
        let normal = ButtonArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5, isEnabled: true)
        let pressed = ButtonArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5, isEnabled: true, pressed: true)
        XCTAssertEqual(pixel(normal, 150, 30).r, 0xeb)
        XCTAssertEqual(pixel(pressed, 150, 30).r, 0xd4); XCTAssertEqual(pixel(pressed, 150, 30).a, 255)
        XCTAssertEqual(pressed.width, 300); XCTAssertEqual(pressed.height, 60, "a press changes colour, not size")
        let prominent = ButtonArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5, isEnabled: true, prominent: true, pressed: true)
        XCTAssertEqual(pixel(prominent, 150, 30).g, 0x6f)
        // a tint colours the prominent body first, then the press darkens it
        let tinted = ButtonArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5, isEnabled: true, prominent: true, tint: 0xff383c, pressed: true)
        XCTAssertEqual(pixel(tinted, 150, 30).r, Int((255.0 * (1 - ButtonArtwork.pressedProminentMix)).rounded()))
    }

    func testADisabledBodyIgnoresPressAndFocus() {
        let plain = ButtonArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5, isEnabled: false)
        let both = ButtonArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5, isEnabled: false, pressed: true, focused: true)
        XCTAssertEqual(plain, both)
    }

    func testTheButtonPointerHighlightsWhileHeldInsideAndReleasesOnlyInside() throws {
        let graph = Graph(WitnessButton(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let node = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "Button" })
        let centre = (x: Float(node.pixelFrame.x) + Float(node.pixelFrame.width) / 2, y: Float(node.pixelFrame.y) + Float(node.pixelFrame.height) / 2)
        let pointer = HostButtonPointer()
        XCTAssertNil(pointer.press(x: -20, y: -20, scale: 2.5, graph: graph), "nothing under the pointer")
        XCTAssertEqual(pointer.press(x: centre.x, y: centre.y, scale: 2.5, graph: graph), node.id)
        XCTAssertTrue(try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "Button" }).buttonIsPressed)
        XCTAssertTrue(pointer.move(x: -20, y: -20, scale: 2.5, graph: graph), "leaving the button un-highlights it")
        XCTAssertFalse(try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "Button" }).buttonIsPressed)
        XCTAssertTrue(pointer.move(x: centre.x, y: centre.y, scale: 2.5, graph: graph), "coming back highlights it again")
        XCTAssertFalse(pointer.move(x: centre.x, y: centre.y, scale: 2.5, graph: graph), "no change, no repaint")
        XCTAssertEqual(pointer.release(x: centre.x, y: centre.y, scale: 2.5, graph: graph), node.id, "released inside: tap it")
        XCTAssertNil(graph.pressedButton); XCTAssertNil(pointer.held)
        _ = pointer.press(x: centre.x, y: centre.y, scale: 2.5, graph: graph)
        XCTAssertNil(pointer.release(x: -20, y: -20, scale: 2.5, graph: graph), "released outside: no tap")
        XCTAssertNil(graph.pressedButton)
    }

    // MARK: Button focus ring

    func testAFocusedBodyHasARingMarginAroundIt() {
        let m = ButtonArtwork.focusRingPixels(scale: 2.5)
        XCTAssertEqual(m, 8, "3 pt at scale 2.5 is 7.5 px, 8 px")
        let focused = ButtonArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5, isEnabled: true, focused: true)
        XCTAssertEqual(focused.width, 300 + 2 * m); XCTAssertEqual(focused.height, 60 + 2 * m)
        // the body keeps its fill, offset by the margin
        XCTAssertEqual(pixel(focused, m + 150, m + 30).r, 0xeb); XCTAssertEqual(pixel(focused, m + 150, m + 30).a, 255)
        // the ring: (0,103,245) at half opacity (measured on macOS 27: solid ring pixels over white are (128,179,250)), in the margin beside the body's straight edge
        let ring = pixel(focused, 3, m + 30)
        XCTAssertEqual(ring.a, Int(ButtonArtwork.focusRingAlpha)); XCTAssertEqual(ring.r, 0); XCTAssertEqual(ring.g, 0x67); XCTAssertEqual(ring.b, 0xf5)
        // outside the outer outline (the very corner of the image) nothing is drawn
        XCTAssertEqual(pixel(focused, 0, 0).a, 0)
        // the ring does not cover the body: just inside the body's top edge is body, not ring
        XCTAssertEqual(pixel(focused, m + 150, m + 2).a, 255)
    }

    // Issue #79: a focused .plain or .borderless Button gets a ring alone, 3 pt outside the label's frame (measured: the same colour and outset as the bodied styles).
    func testALabelOnlyFocusRingSurroundsTheFrameAndLeavesItsInsideClear() {
        let m = ButtonArtwork.focusRingPixels(scale: 2.5)
        let ring = ButtonArtwork.labelFocusRing(widthPX: 73, heightPX: 40, scale: 2.5)
        XCTAssertEqual(ring.width, 73 + 2 * m); XCTAssertEqual(ring.height, 40 + 2 * m)
        let edge = pixel(ring, 3, m + 20)   // inside the 8 px band, beside the frame's left edge
        XCTAssertEqual(edge.a, Int(ButtonArtwork.focusRingAlpha)); XCTAssertEqual(edge.r, 0); XCTAssertEqual(edge.g, 0x67); XCTAssertEqual(edge.b, 0xf5)
        XCTAssertEqual(pixel(ring, m + 36, m + 20).a, 0, "the label's own area is clear")
        XCTAssertLessThan(pixel(ring, 0, 0).a, Int(ButtonArtwork.focusRingAlpha), "the corners are only slightly rounded (about 1.5 pt) but the very corner is not solid")
    }

    func testAFocusedPlainButtonPlansARingAndAnUnfocusedOneDoesNot() throws {
        struct W: View { var body: some View { Button("Plain") {}.buttonStyle(.plain) } }
        let plain = try buttonNode(W())
        XCTAssertNil(try ButtonPainter.plan(plain, bounds: bounds(plain), scale: 2.5).image)
        let focused = try buttonNode(W(), focused: true)
        let plan = try ButtonPainter.plan(focused, bounds: bounds(focused), scale: 2.5)
        XCTAssertNotNil(plan.image); XCTAssertTrue(plan.isFocused)
        XCTAssertEqual(plan.placement.w, bounds(focused).w + 2 * Float(ButtonArtwork.focusRingPixels(scale: 2.5)), accuracy: 0.1)
    }

    func testAFocusRingFollowsTheTint() {
        let tinted = ButtonArtwork.render(widthPX: 300, heightPX: 60, scale: 2.5, isEnabled: true, prominent: true, tint: 0xff383c, focused: true)
        let ring = pixel(tinted, 3, ButtonArtwork.focusRingPixels(scale: 2.5) + 30)
        XCTAssertEqual(ring.r, 0xff); XCTAssertEqual(ring.g, 0x38); XCTAssertEqual(ring.b, 0x3c)
    }

    func testTheButtonPlanCarriesPressedAndFocusedAndPlacesTheRingImage() throws {
        let plain = try ButtonPainter.plan(try buttonNode(WitnessButton()), bounds: Rect(x: 100, y: 100, w: 150, h: 60), scale: 2.5)
        XCTAssertFalse(plain.isPressed); XCTAssertFalse(plain.isFocused)
        let pressed = try ButtonPainter.plan(try buttonNode(WitnessButton(), pressed: true), bounds: Rect(x: 100, y: 100, w: 150, h: 60), scale: 2.5)
        XCTAssertTrue(pressed.isPressed); XCTAssertFalse(pressed.isFocused)
        XCTAssertEqual(pressed.placement, plain.placement, "a press keeps the placement")
        XCTAssertNotEqual(pressed.image?.rgba, plain.image?.rgba)
        let focused = try ButtonPainter.plan(try buttonNode(WitnessButton(), focused: true), bounds: Rect(x: 100, y: 100, w: 150, h: 60), scale: 2.5)
        XCTAssertTrue(focused.isFocused)
        XCTAssertEqual(focused.placement.x, plain.placement.x - 8); XCTAssertEqual(focused.placement.y, plain.placement.y - 8)
        XCTAssertEqual(focused.placement.w, plain.placement.w + 16); XCTAssertEqual(focused.placement.h, plain.placement.h + 16)
        let disabled = try ButtonPainter.plan(try buttonNode(WitnessDisabled()), bounds: Rect(x: 100, y: 100, w: 150, h: 60), scale: 2.5)
        XCTAssertFalse(disabled.isPressed)
    }

    func testAPressedButtonPaintsThroughTheNodePainter() throws {
        let node = try buttonNode(WitnessProminent(), pressed: true)
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: FakeRuns(), log: { _ in })
        painter.beginCommit()
        let emission = try painter.emit(node, id: UInt64(node.instance + 1), bounds: bounds(node))
        painter.endCommit(committed: true)
        guard case .image(let handle, _, _) = try XCTUnwrap(emission.primitives.first) else { return XCTFail("a bodied Button is an image") }
        let entry = try XCTUnwrap(images.registered[handle.raw])
        let o = (Int(entry.height) / 2 * Int(entry.width) + Int(entry.width) / 2) * 4
        XCTAssertEqual(Int(entry.rgba[o + 1]), 0x6f, "the prominent fill, darkened")
    }

    func testAPressedPlainButtonDimsItsLabel() throws {
        XCTAssertNil(try ButtonPainter.labelColor(of: try buttonNode(WitnessPlain())), "a plain label keeps its own colour")
        let pressed = try XCTUnwrap(try ButtonPainter.labelColor(of: try buttonNode(WitnessPlain(), pressed: true)))
        XCTAssertEqual(Double(pressed & 255), (216 * ButtonPainter.pressedBodilessLabelAlpha).rounded(), "label alpha 0xd8 dimmed")
        XCTAssertEqual(try ButtonPainter.labelColor(of: try buttonNode(WitnessButton(), pressed: true)), 0x242424ff, "a bodied label is not dimmed: its body darkens")
    }

    // MARK: wrapped TextField

    func testWrappedFieldPositionsGiveTheLineAndXOfEveryBoundary() {
        func cell(_ off: UInt32, line: UInt32, x0: Float, x1: Float, br: Bool = false) -> CharCell {
            CharCell(utf8Offset: off, utf8Len: 1, line: line, wordStart: false, lineBreak: br, x0: x0, x1: x1)
        }
        let cells = [cell(0, line: 0, x0: 0, x1: 6), cell(1, line: 0, x0: 6, x1: 12), cell(2, line: 0, x0: 12, x1: 12, br: true),
                     cell(3, line: 1, x0: 0, x1: 6), cell(4, line: 1, x0: 6, x1: 12)]
        let p = TextFieldGeometry.positions(text: "ab\ncd", cells: cells, runWidth: 12)
        XCTAssertEqual(p.map { $0.line }, [0, 0, 0, 1, 1, 1])
        XCTAssertEqual(p.map { $0.x }, [0, 6, 12, 0, 6, 12])
        XCTAssertEqual(TextFieldGeometry.lineWidths(cells: cells), [0: 12, 1: 12])
    }

    func testAVerticalFieldPaintsItsWrappedTextClippedToTheLinesItShows() throws {
        let graph = Graph(WitnessNotes(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let node = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "TextField" })
        let info = try XCTUnwrap(node.verticalField)
        XCTAssertEqual(info.visibleLines, 2)
        let runs = WrappedRuns()
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: runs, log: { _ in })
        painter.beginCommit()
        let b = bounds(node)
        let emission = try painter.emit(node, id: UInt64(node.instance + 1), bounds: b)
        painter.endCommit(committed: true)
        XCTAssertEqual(b.h, 100, "two lines: 8 pt + 2 x 16 pt = 40 pt")
        let asked = try XCTUnwrap(runs.asked.first)
        XCTAssertEqual(asked.text, "aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll")
        XCTAssertEqual(asked.bounds.w, Float(info.textWidth) * 2.5, accuracy: 0.01)
        XCTAssertEqual(asked.bounds.h, 160, "the run is all four lines (64 pt); the field shows two")
        XCTAssertEqual(asked.bounds.x, b.x + 15, "the text starts 6 pt in"); XCTAssertEqual(asked.bounds.y, b.y + 10, "below the bezel's 4 pt inset")
        XCTAssertEqual(asked.color, TextFieldColors.text, "typed text, not the placeholder")
        guard case .clipPush(let clip) = emission.primitives[1] else { return XCTFail("clip after the bezel") }
        XCTAssertEqual(clip.y, b.y + 10); XCTAssertEqual(clip.h, 80, "the visible lines: 100 px less the 2 x 10 px inset")
        XCTAssertEqual(clip.x, b.x + 10); XCTAssertEqual(clip.w, 280)
        guard case .text(_, let x, let y) = emission.primitives[2] else { return XCTFail("the wrapped run") }
        XCTAssertEqual(x, b.x + 15); XCTAssertEqual(y, b.y + 10)
        XCTAssertEqual(emission.semantic?.role, .textField)
    }

    // MARK: accessibility the ABI cannot carry yet (F10)

    func testHintHeaderLinkAndAStaticTextValueAreRecordedForTheCommit() throws {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(WitnessExtras(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let root = try XCTUnwrap(graph.snapshot())
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: root, version: 1, previousLive: [], submit: { upserts = $0.upserts })
        func extras(ofText text: String) throws -> ResolvedNodePainter.AccessibilityExtras? {
            let node = try XCTUnwrap(flatten(root).first { $0.kind == "Text" && $0.text == text })
            return painter.accessibilityExtras[UInt64(node.instance + 1)]
        }
        XCTAssertEqual(try extras(ofText: "Heading")?.isHeader, true)
        XCTAssertEqual(try extras(ofText: "Site")?.isLink, true)
        let memory = try XCTUnwrap(try extras(ofText: "Memory"))
        XCTAssertEqual(memory.staticTextValue, "1.2 GB"); XCTAssertEqual(memory.hint, "Memory in use")
        XCTAssertNil(try extras(ofText: "Plain"))
        let button = try XCTUnwrap(flatten(root).first { $0.kind == "Button" })
        XCTAssertEqual(painter.accessibilityExtras[UInt64(button.instance + 1)]?.hint, "Starts the scan")
        // nothing the ABI cannot carry leaks into the published element
        let published = try XCTUnwrap(upserts.first { $0.id == UInt64(button.instance + 1) }?.semantic)
        XCTAssertEqual(published.role, .button); XCTAssertEqual(published.label, "Run")
    }

    // MARK: stroked pill (F4)

    func testAStrokedCircularPillIsARectWithARoundedBorderGrownByHalfTheWidth() throws {
        let graph = Graph(WitnessCapsules(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let capsules = flatten(try XCTUnwrap(graph.snapshot())).filter { $0.kind == "Capsule" }
        XCTAssertEqual(capsules.count, 2)
        let frame = Rect(x: 100, y: 100, w: 200, h: 80)
        // circular: an ABI rect with a border; the stroke is centred on the path, so the rect grows by half the 10 px width and the radius with it (a pill stays a pill)
        guard case .primitive(.rect(let rect, _, let radius, let borderColor, let borderWidth)) = try ShapePainter.plan(capsules[0], bounds: frame, scale: 2.5) else { return XCTFail("circular pill stroke is a rect") }
        XCTAssertEqual(rect, Rect(x: 95, y: 95, w: 210, h: 90))
        XCTAssertEqual(radius, 45); XCTAssertEqual(borderWidth, 10); XCTAssertEqual(borderColor, 0xff383cff)
        XCTAssertEqual(radius, min(rect.w, rect.h) / 2)
        // continuous (the default): the continuous raster, which strokes the pill's outline at the same width
        guard case .continuous(let request) = try ShapePainter.plan(capsules[1], bounds: frame, scale: 2.5) else { return XCTFail("continuous pill stroke is the continuous raster") }
        XCTAssertEqual(request.cornerRadiusPX, 40); XCTAssertEqual(request.strokeWidthPX, 10); XCTAssertEqual(request.strokeRGBA, 0xff383cff); XCTAssertNil(request.fillRGBA)
        let result = try ContinuousShapeRaster.render(request)
        let image = result.image
        XCTAssertEqual(image.width, 210); XCTAssertEqual(image.height, 90)
        XCTAssertEqual(pixel(image, 5, 45).a, 255, "the stroke's leftmost pole is solid")
        // Apple's stroker draws a short tick across the path at each pole of a pill (F4); this one is a clean outline: the interior beside the pole is empty
        XCTAssertEqual(pixel(image, 20, 45).a, 0)
        XCTAssertEqual(pixel(image, 105, 45).a, 0)
        XCTAssertEqual(pixel(image, 105, 5).a, 255, "the straight top edge is stroked")
    }

    // MARK: bundled face weights (E14b)

    func testAFaceNameSuffixNamesItsWeight() {
        XCTAssertEqual(BundledFontLibrary.weightClass(inFaceName: "Tinos-Bold"), 700)
        XCTAssertEqual(BundledFontLibrary.weightClass(inFaceName: "Tinos-SemiBold"), 600)
        XCTAssertEqual(BundledFontLibrary.weightClass(inFaceName: "Tinos-Semi_Bold"), 600)
        XCTAssertEqual(BundledFontLibrary.weightClass(inFaceName: "Tinos-Regular"), 400)
        XCTAssertEqual(BundledFontLibrary.weightClass(inFaceName: "Tinos-Black"), 900)
        XCTAssertNil(BundledFontLibrary.weightClass(inFaceName: "Tinos"))
        XCTAssertNil(BundledFontLibrary.weightClass(inFaceName: "Tinos-Italic"))
    }

    private final class BoldFaces: CustomFontResolving {
        func providerFamily(forCustomName name: String) -> String? { name.lowercased().hasPrefix("tinos") ? "Tinos" : nil }
        func metrics(forCustomName name: String) -> FontFileMetrics? { providerFamily(forCustomName: name) == nil ? nil : FontFileMetrics.parse(tinosLikeSfnt()) }
        func weight(forCustomName name: String) -> UInt32? { name.lowercased() == "tinos-bold" ? 700 : nil }
    }

    func testACustomFaceNameSelectsItsWeightAndAnExplicitWeightStillWins() throws {
        let body = BodyFontProfile(family: "Segoe UI", weight: 400, fontSizeDIP: 12, lineHeightDIP: 16)
        func request(_ font: Font) -> TextMeasureRequest { TextMeasureRequest(text: "x", fontID: font.id, proposedWidth: nil, scale: 1, fontMetadata: font.metadata, lineLimit: nil) }
        let byName = try TextRequestAdapter.shapingRequest(for: request(Font.custom("Tinos-Bold", size: 18)), body: body, fonts: BoldFaces(), scale: 1, textColor: 0)
        XCTAssertEqual(byName.weight, 700); XCTAssertEqual(byName.fontFamily, "Tinos")
        let family = try TextRequestAdapter.shapingRequest(for: request(Font.custom("Tinos", size: 18)), body: body, fonts: BoldFaces(), scale: 1, textColor: 0)
        XCTAssertEqual(family.weight, 400)
        let light = try TextRequestAdapter.shapingRequest(for: request(Font.custom("Tinos-Bold", size: 18).weight(.light)), body: body, fonts: BoldFaces(), scale: 1, textColor: 0)
        XCTAssertEqual(light.weight, 300, "`.weight(_:)` on the Font is the caller's explicit choice")
        let bold = try TextRequestAdapter.shapingRequest(for: request(Font.custom("Tinos", size: 18).weight(.bold)), body: body, fonts: BoldFaces(), scale: 1, textColor: 0)
        XCTAssertEqual(bold.weight, 700, "the renderer picks the registered bold face of the family for this weight")
    }
}
