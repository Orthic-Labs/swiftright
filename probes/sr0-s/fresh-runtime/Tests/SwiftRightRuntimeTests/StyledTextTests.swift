import Foundation
import XCTest
@testable import SwiftRightRuntime

// Issue #68: styled Text runs (StyledText.swift). The fixed-advance measurer gives every character 8 pt, a line 16 pt and a first baseline 12 pt at scale 1, so the
// expected geometry is worked by hand.

@MainActor
private final class OpenLog { var opened: [URL] = [] }

@MainActor
final class StyledTextTests: XCTestCase {
    private func snapshot<V: View>(_ view: V, measurer: FixedAdvanceTextMeasurer = FixedAdvanceTextMeasurer(), width: CGFloat? = 400, height: CGFloat? = 200) throws -> (graph: Graph, root: ResolvedNode) {
        let graph = Graph(view, measurer: measurer, scale: 1)
        graph.rootProposal = ProposedViewSize(width: width, height: height)
        graph.flush()
        return (graph, try XCTUnwrap(graph.snapshot()))
    }

    private func texts(_ root: ResolvedNode) -> [ResolvedNode] {
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { (n.kind == "Text" ? [n] : []) + n.children.flatMap(walk) }
        return walk(root)
    }

    private func firstText<V: View>(_ view: V, width: CGFloat? = 400) throws -> ResolvedNode {
        try XCTUnwrap(texts(try snapshot(view, width: width).root).first)
    }

    // MARK: Building runs

    func testTwoPlainTextsStayOnePlainString() throws {
        let joined = Text("a") + Text("b")
        XCTAssertNil(joined.runs)
        XCTAssertEqual(joined.string, "ab")
        let node = try firstText(joined)
        XCTAssertNil(node.styledText)
        XCTAssertEqual(node.text, "ab")
    }

    func testAnAttributedStringWithoutAttributesIsPlain() throws {
        let text = Text(AttributedString("plain"))
        XCTAssertNil(text.runs)
        XCTAssertNil(try firstText(text).styledText)
    }

    func testTextModifiersReturnTextAndJoinRuns() throws {
        let text: Text = Text("plain ") + Text("bold").bold() + Text(" link").foregroundColor(Color.blue)
        XCTAssertEqual(text.string, "plain bold link")
        let node = try firstText(text)
        let runs = try XCTUnwrap(node.styledText).runs
        XCTAssertEqual(runs.map(\.text), ["plain ", "bold", " link"])
        XCTAssertNil(runs[0].font)
        XCTAssertNil(runs[0].foreground)
        XCTAssertEqual(runs[1].font?.metadata?.isEmphasized, true, "bold() on the default body font is the body's emphasized weight")
        XCTAssertEqual(runs[2].foreground, Color.blue.resolvedColor)
        XCTAssertNil(runs[2].font)
        XCTAssertEqual(node.text, "plain bold link")
    }

    func testBoldKeepsWorkingUnderALaterFont() throws {
        let text: Text = Text("x").bold().font(Font.system(size: 20))
        let run = try XCTUnwrap(try XCTUnwrap(try firstText(text).styledText).runs.first)
        XCTAssertEqual(run.font?.metadata?.pointSize, 20)
        XCTAssertEqual(run.font?.metadata?.weight, .bold)
    }

    func testRunsWithTheirOwnAttributesWinOverTextModifiers() throws {
        var attributed = AttributedString("own")
        attributed.font = Font.headline
        attributed.foregroundColor = Color.red
        var other = AttributedString(" inherited")
        other[SwiftRightTextAttributes.Kerning.self] = 2  // explicit key: on the Mac, XCTest pulls in AppKit's kern too
        attributed += other
        let text: Text = Text(attributed).font(Font.title).foregroundColor(Color.green).underline()
        let runs = try XCTUnwrap(try firstText(text).styledText).runs
        XCTAssertEqual(runs.map(\.text), ["own", " inherited"])
        XCTAssertEqual(runs[0].font, Font.headline, "the run's own font wins")
        XCTAssertEqual(runs[1].font, Font.title, "a run without a font takes the modifier's")
        XCTAssertEqual(runs[0].foreground, Color.red.resolvedColor)
        XCTAssertEqual(runs[1].foreground, Color.green.resolvedColor)
        XCTAssertNotNil(runs[0].underline)
        XCTAssertNotNil(runs[1].underline)
        XCTAssertEqual(runs[1].style?.kern, 2)
        XCTAssertNil(runs[0].style)
    }

    func testAttributedStringAttributesMapToRuns() throws {
        var lead = AttributedString("see ")
        lead.backgroundColor = Color.yellow
        var link = AttributedString("docs")
        link.link = URL(string: "https://example.test/docs")
        link.underlineStyle = Text.LineStyle.single
        link.strikethroughStyle = Text.LineStyle(pattern: .dash, color: Color.red)
        link[SwiftRightTextAttributes.Tracking.self] = 0.5
        link[SwiftRightTextAttributes.BaselineOffset.self] = 3
        lead += link
        let runs = try XCTUnwrap(try firstText(Text(lead)).styledText).runs
        XCTAssertEqual(runs.map(\.text), ["see ", "docs"])
        XCTAssertEqual(runs[0].background, Color.yellow.resolvedColor)
        XCTAssertNil(runs[0].link)
        XCTAssertEqual(runs[1].link, URL(string: "https://example.test/docs"))
        XCTAssertEqual(runs[1].underline, ResolvedTextLine(pattern: "solid", color: nil))
        XCTAssertEqual(runs[1].strikethrough, ResolvedTextLine(pattern: "dash", color: Color.red.resolvedColor))
        XCTAssertEqual(runs[1].style?.tracking, 0.5)
        XCTAssertEqual(runs[1].baselineOffset, 3)
    }

    // Issue #74: SwiftUI draws a linked run in the system link colour unless the run has its own foreground colour.
    func testALinkedRunWithoutAColourTakesTheLinkColour() throws {
        var text = AttributedString("see ")
        var link = AttributedString("docs")
        link.link = URL(string: "https://example.test/docs")
        var coloured = AttributedString(" more")
        coloured.link = URL(string: "https://example.test/more")
        coloured.foregroundColor = Color.red
        text += link
        text += coloured
        let runs = try XCTUnwrap(try firstText(Text(text)).styledText).runs
        XCTAssertEqual(runs.map(\.text), ["see ", "docs", " more"])
        XCTAssertNil(runs[0].foreground, "unlinked text keeps the environment's colour")
        XCTAssertEqual(runs[1].foreground, .semantic("link"))
        XCTAssertEqual(runs[2].foreground, Color.red.resolvedColor, "a run's own colour wins")
    }

    func testAdjacentRunsWithEqualAttributesMerge() {
        let text = Text("a").bold() + Text("b").bold() + Text("c")
        XCTAssertEqual(text.plainRuns.map(\.text), ["ab", "c"])
    }

    func testTextCaseAppliesToEveryRun() throws {
        let node = try firstText((Text("ab ") + Text("cd").bold()).textCase(.uppercase))
        XCTAssertEqual(node.text, "AB CD")
        XCTAssertEqual(try XCTUnwrap(node.styledText).runs.map(\.text), ["AB ", "CD"])
    }

    func testAViewModifierOnTextKeepsTheModifierNode() throws {
        // `.font` on a Text used as a view is still the environment modifier (the node tree of a plain Text is unchanged).
        let root = try snapshot(Text("x").font(Font.title)).root
        XCTAssertNotEqual(root.kind, "Text")
        XCTAssertNil(texts(root).first?.styledText)
    }

    func testResolvedNodeCarriesLineLimitAndEnvironmentFont() throws {
        let view = (Text("a") + Text("b").italic()).font(Font.system(size: 15)).lineLimit(2)
        let styled = try XCTUnwrap(try firstText(view).styledText)
        XCTAssertEqual(styled.lineLimit, 2)
        XCTAssertEqual(styled.runs[0].font?.metadata?.pointSize, 15, "a run without a font draws with the environment's")
        XCTAssertEqual(styled.runs[1].style?.italic, true)
        XCTAssertEqual(styled.runs[1].font?.metadata?.pointSize, 15)
    }

    // MARK: Layout

    func testRunsAreMeasuredWordByWordAndShareALine() throws {
        let text: Text = Text("plain ") + Text("bold").bold() + Text(" link").foregroundColor(Color.blue)
        let node = try firstText(text, width: nil)
        XCTAssertEqual(node.frame.width, 15 * 8, accuracy: 1e-9)
        XCTAssertEqual(node.frame.height, 16, accuracy: 1e-9)
    }

    func testWrappingBreaksAtSpacesAcrossRuns() throws {
        // "aaa bbb" is 56 pt and fits; "ccc" does not.
        let node = try firstText(Text("aaa bbb ") + Text("ccc").bold(), width: 56)
        XCTAssertEqual(node.frame.width, 56, accuracy: 1e-9)
        XCTAssertEqual(node.frame.height, 32, accuracy: 1e-9)
    }

    func testASingleUndecoratedRunIsOneNativeRequest() throws {
        let measurer = FixedAdvanceTextMeasurer()
        _ = try snapshot(Text("hello world").italic().kerning(1.5), measurer: measurer, width: 400)
        let style = TextRunStyle(italic: true, kern: 1.5, tracking: 0)
        XCTAssertFalse(measurer.requests.isEmpty)
        XCTAssertTrue(measurer.requests.allSatisfy { $0.text == "hello world" && $0.runStyle == style }, "one request per proposal, never word by word")
    }

    func testADecoratedSingleRunIsFlowed() throws {
        let measurer = FixedAdvanceTextMeasurer()
        _ = try snapshot(Text("ab cd").underline(), measurer: measurer, width: 400)
        XCTAssertEqual(Set(measurer.requests.map(\.text)), ["ab", " ", "cd"])
    }

    // MARK: Flow

    private func flow(_ runs: [ResolvedTextRun], width: CGFloat?, limit: Int? = nil, metrics: @escaping (Int) -> TextFlowMetrics = { _ in TextFlowMetrics(width: 8, height: 16, baseline: 12) }) -> TextFlowLayout {
        TextRunFlow.layout(runs: runs, maxWidth: width, lineLimit: limit) { text, run in
            let m = metrics(run)
            return TextFlowMetrics(width: m.width * CGFloat(text.count), height: m.height, baseline: m.baseline)
        }
    }

    func testFlowKeepsAWordWholeAcrossRuns() {
        let runs = [ResolvedTextRun(text: "one bol"), ResolvedTextRun(text: "dly two")]
        // "one " is 32 pt and "boldly" (48) would end at 80: it wraps; "boldly two" (80) does not fit 56 either, so "two" wraps too.
        let layout = flow(runs, width: 56)
        XCTAssertEqual(layout.lines.count, 3)
        XCTAssertEqual(layout.fragments.filter { $0.line == 1 }.map(\.text).joined(), "boldly")
        XCTAssertEqual(layout.fragments.filter { $0.line == 1 }.map(\.run), [0, 1], "the word is one stretch per run")
    }

    func testFlowDropsSpacesAtTheBreak() {
        let layout = flow([ResolvedTextRun(text: "aa   bb")], width: 16)
        XCTAssertEqual(layout.lines.count, 2)
        XCTAssertEqual(layout.fragments.map(\.text), ["aa", "bb"])
        XCTAssertEqual(layout.fragments[1].x, 0)
        XCTAssertEqual(layout.lines[0].width, 16)
    }

    func testFlowAWordWiderThanTheLineStaysWhole() {
        let layout = flow([ResolvedTextRun(text: "abcdefgh ij")], width: 24)
        XCTAssertEqual(layout.fragments.map(\.text), ["abcdefgh", "ij"])
        XCTAssertEqual(layout.lines.count, 2)
    }

    func testFlowNewlinesAndEmptyLines() {
        let layout = flow([ResolvedTextRun(text: "a\n\nb\n")], width: nil)
        XCTAssertEqual(layout.lines.count, 4, "a, an empty line, b, and the empty line a trailing newline leaves")
        XCTAssertEqual(layout.height, 64)
        XCTAssertEqual(layout.lines[1].fragments.count, 0)
        XCTAssertEqual(layout.lines[1].height, 16)
        XCTAssertEqual(layout.firstBaseline, 12)
        XCTAssertEqual(layout.lastBaseline, 3 * 16 + 12)
    }

    func testFlowAlignsRunsOnTheLineBaseline() {
        // run 1 is taller (24 high, baseline 18): the line is 24 high with its baseline at 18; run 0 hangs 6 down so its baseline (12) is on it.
        let runs = [ResolvedTextRun(text: "ab "), ResolvedTextRun(text: "CD")]
        let layout = flow(runs, width: nil) { $0 == 0 ? TextFlowMetrics(width: 8, height: 16, baseline: 12) : TextFlowMetrics(width: 10, height: 24, baseline: 18) }
        XCTAssertEqual(layout.lines.count, 1)
        XCTAssertEqual(layout.lines[0].height, 24)
        XCTAssertEqual(layout.firstBaseline, 18)
        XCTAssertEqual(layout.fragments.map(\.y), [6, 0])
        XCTAssertEqual(layout.fragments.map(\.x), [0, 24])
        XCTAssertEqual(layout.fragments[0].text, "ab ")
        XCTAssertEqual(layout.width, 44)
    }

    func testFlowBaselineOffsetRaisesAFragment() {
        var raised = ResolvedTextRun(text: "up")
        raised.baselineOffset = 4
        let layout = flow([ResolvedTextRun(text: "a "), raised], width: nil)
        XCTAssertEqual(layout.fragments.map(\.y), [0, -4])
    }

    func testFlowLineLimitEndsInAnEllipsis() {
        let layout = flow([ResolvedTextRun(text: "aa bb cc dd")], width: 16, limit: 2)
        XCTAssertEqual(layout.lines.count, 2)
        XCTAssertTrue(layout.truncated)
        XCTAssertEqual(layout.fragments.last?.text, "bb\u{2026}")
        XCTAssertEqual(layout.height, 32)
    }

    func testFlowOfNothingIsEmpty() {
        let layout = flow([ResolvedTextRun(text: "")], width: 100)
        XCTAssertTrue(layout.lines.isEmpty)
        XCTAssertEqual(layout.height, 0)
    }

    // MARK: Links

    private func tap(_ graph: Graph, _ node: ResolvedNode, dx: CGFloat, dy: CGFloat) -> Bool {
        graph.tapGesture(atX: node.frame.minX + dx, y: node.frame.minY + dy)
    }

    func testTappingALinkRunOpensItsURLThroughOpenURL() throws {
        let log = OpenLog()
        var attributed = AttributedString("see ")
        var link = AttributedString("docs")
        link.link = URL(string: "https://example.test/docs")
        attributed += link
        let view = Text(attributed).environment(\.openURL, OpenURLAction { url in log.opened.append(url); return .handled })
        let (graph, root) = try snapshot(view, width: nil)
        let node = try XCTUnwrap(texts(root).first)
        XCTAssertEqual(node.frame.width, 64, accuracy: 1e-9)
        XCTAssertFalse(tap(graph, node, dx: 10, dy: 8), "the plain run is not a link")
        XCTAssertTrue(log.opened.isEmpty)
        XCTAssertTrue(tap(graph, node, dx: 40, dy: 8))
        XCTAssertEqual(log.opened, [URL(string: "https://example.test/docs")!])
        XCTAssertFalse(tap(graph, node, dx: 70, dy: 8), "past the end of the text")
        XCTAssertFalse(tap(graph, node, dx: 40, dy: 20), "below the text")
    }

    func testALinkOnTheSecondLineIsFoundThere() throws {
        let log = OpenLog()
        var attributed = AttributedString("aaaa bbbb ")
        var link = AttributedString("cc")
        link.link = URL(string: "https://example.test/c")
        attributed += link
        // 72 pt: "aaaa bbbb" is 72 and fits, "cc" wraps to the second line (y 16..32).
        let view = Text(attributed).environment(\.openURL, OpenURLAction { url in log.opened.append(url); return .discarded })
        let (graph, root) = try snapshot(view, width: 72)
        let node = try XCTUnwrap(texts(root).first)
        XCTAssertEqual(node.frame.height, 32, accuracy: 1e-9)
        XCTAssertFalse(tap(graph, node, dx: 4, dy: 8))
        XCTAssertTrue(tap(graph, node, dx: 4, dy: 24))
        XCTAssertEqual(log.opened.count, 1)
    }

    func testASingleLinkRunIsLinkedOverItsWholeFrame() throws {
        let log = OpenLog()
        var link = AttributedString("a link")
        link.link = URL(string: "https://example.test/")
        let view = Text(link).environment(\.openURL, OpenURLAction { url in log.opened.append(url); return .handled })
        let (graph, root) = try snapshot(view, width: nil)
        let node = try XCTUnwrap(texts(root).first)
        XCTAssertTrue(tap(graph, node, dx: 2, dy: 2))
        XCTAssertEqual(log.opened.count, 1)
    }
}
