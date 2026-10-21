import XCTest
@testable import SwiftRightHost
import SwiftRightBridge
import SwiftRightRuntime

/// A measurer and run source with fixed metrics (8 px per character, 16 px lines, 12 px baseline at scale 1) that records what the painter asks for.
@MainActor
final class StyledFake: TextMeasurer, TextRunSource {
    struct Fragment { var text: String; var fontID: String?; var style: TextRunStyle?; var color: UInt32? }
    var fragments: [Fragment] = []
    var plain: [Fragment] = []
    private var next: UInt64 = 100
    /// #69: when set, every run's outline is a 10 x 10 px square at (2, 3) in run px, shaped in opaque black.
    var squareOutlines = false
    func outline(of run: TextRunHandle) -> (outline: TextOutline, color: UInt32)? {
        guard squareOutlines else { return nil }
        return (TextOutline(commands: [0, 1, 1, 1, 4], points: [2, 3, 12, 3, 12, 13, 2, 13]), 0x0000_00ff)
    }

    func measure(_ request: TextMeasureRequest) -> SwiftRightRuntime.TextMeasurement {
        SwiftRightRuntime.TextMeasurement(size: LayoutSize(width: CGFloat(request.text.count) * 8, height: 16), baseline: 12, lineCount: 1)
    }
    func run(text: String, font: Font?, bounds: Rect) throws -> TextRunHandle { TextRunHandle(raw: 77) }
    func run(text: String, font: Font?, style: TextRunStyle?, bounds: Rect, color: UInt32?) throws -> TextRunHandle {
        plain.append(Fragment(text: text, fontID: font?.id, style: style, color: color))
        return TextRunHandle(raw: 78)
    }
    func fragmentRun(text: String, font: Font?, style: TextRunStyle?, color: UInt32?) throws -> NaturalTextRun? {
        fragments.append(Fragment(text: text, fontID: font?.id, style: style, color: color))
        next += 1
        return NaturalTextRun(run: TextRunHandle(raw: next), width: Float(text.count) * 8, height: 16, baseline: 12)
    }
}

// Issue #68: the painter lays the runs of a styled Text out with the runtime's flow and emits one shaped fragment per line stretch of a run.
@MainActor
final class StyledTextPainterTests: XCTestCase {
    private func paint<V: View>(_ view: V, source: TextRunSource, measurer: TextMeasurer, width: CGFloat? = 400) throws -> [(node: ResolvedNode, emission: NodeEmission)] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 1, text: source, log: { _ in })
        let graph = Graph(view, measurer: measurer, scale: 1)
        graph.rootProposal = ProposedViewSize(width: width, height: 200)
        graph.flush()
        painter.beginCommit()
        var out: [(ResolvedNode, NodeEmission)] = []
        for n in flatten(try XCTUnwrap(graph.snapshot())) where n.kind == "Text" {
            let bounds = Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height))
            out.append((n, try painter.emit(n, id: UInt64(n.instance + 1), bounds: bounds)))
        }
        painter.endCommit(committed: true)
        return out
    }

    private func texts(_ emission: NodeEmission) -> [(x: Float, y: Float)] {
        emission.primitives.compactMap { if case .text(_, let x, let y) = $0 { return (x, y) } else { return nil } }
    }

    private func rects(_ emission: NodeEmission) -> [(rect: Rect, color: UInt32)] {
        emission.primitives.compactMap { if case .rect(let r, let color, _, _, _) = $0 { return (r, color) } else { return nil } }
    }

    func testThreeRunsPaintAsThreeFragmentsOnOneBaseline() throws {
        let fake = StyledFake()
        let text: Text = Text("plain ") + Text("bold").bold() + Text(" link").foregroundColor(Color.blue)
        let painted = try paint(text, source: fake, measurer: fake)
        let emission = try XCTUnwrap(painted.first).emission
        XCTAssertEqual(fake.fragments.map(\.text), ["plain ", "bold", " link"])
        let at = texts(emission)
        XCTAssertEqual(at.map { $0.x - at[0].x }, [0, 48, 80])
        XCTAssertEqual(Set(at.map(\.y)).count, 1, "one line, one baseline")
        XCTAssertNil(fake.fragments[0].color)
        XCTAssertNil(fake.fragments[1].color)
        XCTAssertEqual(fake.fragments[2].color, try HostPaint.rgba(Color.blue.resolvedColor, opacity: 1))
        XCTAssertEqual(fake.fragments[1].fontID, Font.body.bold().id)
        XCTAssertEqual(emission.semantic?.label, "plain bold link")
        XCTAssertEqual(emission.semantic?.role, .staticText)
    }

    func testWrappedRunsPaintOneFragmentPerLineStretch() throws {
        let fake = StyledFake()
        let painted = try paint(Text("aaa bbb ") + Text("ccc").bold(), source: fake, measurer: fake, width: 56)
        let emission = try XCTUnwrap(painted.first).emission
        XCTAssertEqual(fake.fragments.map(\.text), ["aaa bbb", "ccc"], "the space at the break is dropped")
        let at = texts(emission)
        XCTAssertEqual(at[1].x, at[0].x)
        XCTAssertEqual(at[1].y - at[0].y, 16)
    }

    func testBackgroundUnderlineAndStrikethroughAreRects() throws {
        var highlighted = AttributedString("cd")
        highlighted.backgroundColor = Color.yellow
        highlighted.underlineStyle = Text.LineStyle.single
        highlighted.strikethroughStyle = Text.LineStyle(pattern: .solid, color: Color.red)
        let fake = StyledFake()
        let painted = try paint(Text("ab ") + Text(highlighted), source: fake, measurer: fake)
        let emission = try XCTUnwrap(painted.first).emission
        let boxes = rects(emission)
        XCTAssertEqual(boxes.count, 3)
        let origin = try XCTUnwrap(texts(emission).first)
        // the background spans the fragment's 16 px width and the line's 16 px height, behind its text
        XCTAssertEqual(boxes[0].rect, Rect(x: origin.x + 24, y: origin.y, w: 16, h: 16))
        XCTAssertEqual(boxes[0].color, try HostPaint.rgba(Color.yellow.resolvedColor, opacity: 1))
        // the Mac multiplies glyphs over a background run with it: the "cd" glyph colour is the label colour times the opaque yellow, "ab " keeps the measurer's colour
        let label = try HostPaint.rgba(.semantic("label"), opacity: 1), yellow = try HostPaint.rgba(Color.yellow.resolvedColor, opacity: 1)
        func product(_ shift: UInt32) -> UInt32 { UInt32((Double((label >> shift) & 255) * Double((yellow >> shift) & 255) / 255).rounded()) << shift }
        XCTAssertNil(fake.fragments[0].color)
        XCTAssertEqual(fake.fragments[1].color, product(24) | product(16) | product(8) | (label & 255))
        let order = emission.primitives.map { p -> String in
            switch p { case .rect: return "rect"; case .text: return "text"; default: return "other" }
        }
        XCTAssertEqual(order, ["text", "rect", "text", "rect", "rect"], "background, then the run's text, then its lines")
        // underline: below the baseline (12 px) in the text colour (the label colour: the run set none), strikethrough: above it in its own red
        XCTAssertGreaterThan(boxes[1].rect.y - origin.y, 12)
        XCTAssertEqual(boxes[1].rect.w, 16)
        XCTAssertLessThan(boxes[2].rect.y - origin.y, 12)
        XCTAssertEqual(boxes[2].color, try HostPaint.rgba(Color.red.resolvedColor, opacity: 1))
    }

    func testOneUndecoratedRunIsAPlainRequestWithItsStyle() throws {
        let fake = StyledFake()
        let painted = try paint(Text("hello").italic().kerning(2), source: fake, measurer: fake)
        let emission = try XCTUnwrap(painted.first).emission
        XCTAssertTrue(fake.fragments.isEmpty)
        XCTAssertEqual(fake.plain.map(\.text), ["hello"])
        XCTAssertEqual(fake.plain.first?.style, TextRunStyle(italic: true, kern: 2, tracking: 0))
        XCTAssertEqual(texts(emission).count, 1)
    }

    func testAPlainTextIsUntouched() throws {
        let fake = StyledFake()
        let painted = try paint(Text("plain"), source: fake, measurer: fake)
        XCTAssertNil(try XCTUnwrap(painted.first).node.styledText)
        XCTAssertTrue(fake.plain.isEmpty, "the plain path does not go through the styled run API")
    }

    func testRunsNeedAMeasurerToBeFlowed() throws {
        let runs = FakeRuns()
        XCTAssertThrowsError(try paint(Text("a ") + Text("b").bold(), source: runs, measurer: StyledFake())) {
            XCTAssertTrue(String(describing: $0).contains("Text runs"), "\($0)")
        }
    }

    // Issue #74: the colour of a linked run in Text(AttributedString): NSColor.linkColor, (0,104,218) in the Mac capture (markdown-basic-v1).
    func testTheLinkColourIsTheMacLinkBlue() throws {
        XCTAssertEqual(try HostPaint.rgba(.semantic("link"), opacity: 1), 0x0068daff)
        XCTAssertNotEqual(try HostPaint.rgba(.semantic("link"), opacity: 1, scheme: .dark), 0x0068daff)
    }
}
