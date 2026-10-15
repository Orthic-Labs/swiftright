import SwiftRightRuntime
import XCTest

// Layout rules, decisions L1-L8 (docs/sr1-decisions.md; the Mac measurements are probes/layout-rules/mac-text.jsonl and mac-stack.jsonl, macOS 27):
//  L1  a Text reports at most the width it was offered: offered 0 it reports 0 (the renderer reads a zero bound as "no bound": the runtime corrects that);
//  L2  a stack probes each child with 0 and with infinity; the difference is its flexibility, a Text's minimum width is 0;
//  L3  children are served by layout priority, highest first; each group keeps the minimum width of every lower group in reserve (a Text keeps none);
//  L4  inside a group the least flexible child goes first and is offered an equal share of what is left among the children still unsized;
//  L7  fixedSize proposes nothing on the fixed axes.
// The text is `FixedAdvanceTextMeasurer`: 8 pt per character, 16 pt lines, words wrap greedily and a word wider than the offer stays whole.
// `BridgeLike` reads a zero proposal as unbounded, as the Windows renderer does, so these tests fail on the product before the fix.

private let A = "Unused 90+ days"   // 15 characters: 120 pt on one line
private let B = "Demo Install"      // 12 characters: 96 pt
private let S = "Hi"                // 2 characters: 16 pt
private let L = "Settings and preferences for the application"   // 44 characters: 352 pt

@MainActor
private final class BridgeLike: TextMeasurer {
    let inner = FixedAdvanceTextMeasurer()
    func measure(_ request: TextMeasureRequest) -> TextMeasurement {
        let unbounded = request.proposedWidth == 0 ? nil : request.proposedWidth
        return inner.measure(TextMeasureRequest(text: request.text, fontID: request.fontID, proposedWidth: unbounded, scale: request.scale,
                                                fontMetadata: request.fontMetadata, lineLimit: request.lineLimit))
    }
}

/// A row's Text widths and the first text's x, laid out in `width` pt with the given spacing.
@MainActor
private func textWidths(_ view: some View, width: CGFloat, height: CGFloat = 100, measurer: TextMeasurer = BridgeLike()) -> [CGFloat] {
    let g = Graph(view, measurer: measurer, scale: 1)
    g.rootProposal = ProposedViewSize(width: width, height: height)
    g.flush()
    return everyNode(g.snapshot()).filter { $0.kind == "Text" }.map(\.frame.size.width)
}

private func row<C: View>(_ width: CGFloat, spacing: CGFloat = 8, @ViewBuilder _ content: () -> C) -> some View {
    HStack(spacing: spacing) { content() }.frame(width: width, height: 100, alignment: .leading)
}

@MainActor
final class TextStackDistributionTests: XCTestCase {
    // L1
    func testATextOfferedZeroReportsZeroAndNeverMoreThanItIsOffered() {
        // frame(width: 0): the Text is offered 0; it must not report its one-line width
        XCTAssertEqual(textWidths(Text(A).frame(width: 0), width: 300), [0])
        XCTAssertEqual(textWidths(Text(A).lineLimit(1).frame(width: 0), width: 300), [0])
        XCTAssertEqual(textWidths(Text(A).frame(width: 5), width: 300), [5], "no room for a glyph: the offer, not a wider laid-out word")
        XCTAssertEqual(textWidths(Text(A).frame(width: 90), width: 300), [80], "wrapped: the widest line ('Unused 90+'), below the offer")
        XCTAssertEqual(textWidths(Text(A).frame(width: 300), width: 300), [120], "room to spare: the one-line width")
        XCTAssertEqual(textWidths(Text(A).frame(width: 0), width: 300, measurer: FixedAdvanceTextMeasurer()), [0], "the same with a measurer that already reports a narrow word")
    }

    // (a) the priority inversion of the Windows hub: the lower group gives way first
    func testTheLowerPriorityTextGivesWayFirst() {
        // 150 wide, 8 between: 142 to share. B (priority 1) is served first and keeps its 96; A is offered the 46 that remain (its word 'Unused' is 48: clamped)
        XCTAssertEqual(textWidths(row(150) { Text(A).lineLimit(1); Text(B).lineLimit(1).layoutPriority(1) }, width: 150), [46, 96])
        // the other way round: A (priority 1) keeps its 120 and B gets the 22 left
        XCTAssertEqual(textWidths(row(150) { Text(A).lineLimit(1).layoutPriority(1); Text(B).lineLimit(1) }, width: 150), [120, 22])
        // too tight for both: the higher priority one is cut last (before the fix it was the one that was cut)
        XCTAssertEqual(textWidths(row(100) { Text(A).lineLimit(1); Text(B).lineLimit(1).layoutPriority(1) }, width: 100), [48, 32])
    }

    // (b) a long label beside a short one is not cut while the row has room
    func testALongLabelBesideAShortOneKeepsItsWidthWhenThereIsRoom() {
        XCTAssertEqual(textWidths(row(150) { Text(A).lineLimit(1); Text(S).lineLimit(1) }, width: 150), [120, 16], "before the fix: [48, 16], A cut to an equal share")
        XCTAssertEqual(textWidths(row(150) { Text(S).lineLimit(1); Text(A).lineLimit(1) }, width: 150), [16, 120])
        // the two longer labels share equally when neither fits: the less flexible (B) first
        XCTAssertEqual(textWidths(row(220) { Text(A).lineLimit(1); Text(B).lineLimit(1) }, width: 220), [80, 96])
        XCTAssertEqual(textWidths(row(220) { Text(B).lineLimit(1); Text(A).lineLimit(1) }, width: 220), [96, 80])
        XCTAssertEqual(textWidths(row(300) { Text(A).lineLimit(1); Text(B).lineLimit(1) }, width: 300), [120, 96], "both whole when the row has room")
    }

    // L4: the least flexible goes first and is offered an equal share; the most flexible takes what is left
    func testTheLeastFlexibleChildIsOfferedAnEqualShareFirst() {
        // 150 wide, 8 between: 142 to share. B (96, the less flexible) is offered 71 and wraps to 56; A is offered 86 and wraps to its widest line
        XCTAssertEqual(textWidths(row(150) { Text(A); Text(B) }, width: 150), [80, 56])
        XCTAssertEqual(textWidths(row(150) { Text(B); Text(A) }, width: 150), [56, 80])
    }

    func testEachGroupKeepsTheMinimumOfTheLowerGroups() {
        // priorities 2 / 1 / 0 in 220: the top one takes what it can, the middle one what is left
        XCTAssertEqual(textWidths(row(220) { Text(L).lineLimit(1).layoutPriority(2); Text(A).lineLimit(1).layoutPriority(1); Text(B).lineLimit(1) }, width: 220),
                       [192, 12, 0])
        XCTAssertEqual(textWidths(row(220) { Text(L).lineLimit(1); Text(A).lineLimit(1).layoutPriority(1); Text(B).lineLimit(1).layoutPriority(2) }, width: 220),
                       [28, 80, 96])
        // two above two: the upper pair is served whole, the lower pair shares what it leaves (the short one first)
        XCTAssertEqual(textWidths(row(300) { Text(A).lineLimit(1).layoutPriority(1); Text(B).lineLimit(1).layoutPriority(1); Text(L).lineLimit(1); Text(S).lineLimit(1) }, width: 300),
                       [120, 96, 44, 16])
    }

    func testASpacerKeepsItsMinimumAndTheTextsShareTheRest() {
        XCTAssertEqual(textWidths(row(300) { Text(A).lineLimit(1); Spacer(); Text(B).lineLimit(1) }, width: 300), [120, 96])
        // 200 wide, two gaps of 8, the spacer's 8: B is offered 88 and wraps to 'Demo', A is offered the rest and keeps its line
        XCTAssertEqual(textWidths(row(200) { Text(A).lineLimit(1); Spacer(); Text(B).lineLimit(1) }, width: 200), [120, 32])
        XCTAssertEqual(textWidths(row(200) { Text(A).lineLimit(1); Spacer(minLength: 30); Text(B).lineLimit(1) }, width: 200), [120, 32])
    }

    func testAFixedSizeTextKeepsItsLineAndIsServedFirst() {
        XCTAssertEqual(textWidths(row(100) { Text(A).lineLimit(1).fixedSize(); Text(B).lineLimit(1) }, width: 100), [120, 0], "A overflows; B gets nothing")
        XCTAssertEqual(textWidths(row(200) { Text(A).fixedSize(); Text(B) }, width: 200), [120, 56], "B wraps in the 72 that remain")
        // a vertical fixedSize follows the offered width and keeps every line
        XCTAssertEqual(textWidths(Text(L).fixedSize(horizontal: false, vertical: true).frame(width: 100), width: 300), [96])
    }
}
