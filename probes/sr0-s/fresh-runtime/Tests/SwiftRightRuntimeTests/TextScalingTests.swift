import Foundation
@testable import SwiftRightRuntime
import XCTest

// SR2 block R5 (#40): `minimumScaleFactor` and the View-level `monospacedDigit()`.

/// Each character is half the point size wide; lines are the point size tall.
@MainActor
final class ProportionalMeasurer: TextMeasurer {
    func measure(_ r: TextMeasureRequest) -> TextMeasurement {
        let pt = r.fontMetadata?.pointSize ?? 13
        let w = CGFloat(r.text.count) * pt / 2
        return TextMeasurement(size: LayoutSize(width: w, height: pt), baseline: pt * 0.8, lineCount: 1)
    }
}

@MainActor
final class TextScalingTests: XCTestCase {
    private func text<V: View>(_ view: V, width: CGFloat) throws -> ResolvedNode {
        let g = Graph(view, measurer: ProportionalMeasurer())
        g.rootProposal = ProposedViewSize(width: width, height: 100)
        g.flush()
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return try XCTUnwrap(walk(try XCTUnwrap(g.snapshot())).first { $0.kind == "Text" })
    }

    func testAOneLineTextShrinksInHalfPointsUntilItFits() throws {
        // "123456" at 20 pt is 60 pt wide; offered 40 it shrinks to 13 pt (40 / 60 x 20 = 13.33, floored to a half point): 39 pt wide.
        let t = try text(Text("123456").font(.system(size: 20)).lineLimit(1).minimumScaleFactor(0.5).frame(width: 40), width: 200)
        XCTAssertEqual(t.style.font?.metadata?.pointSize, 13)
        XCTAssertEqual(t.frame.width, 39)
        XCTAssertEqual(t.frame.height, 13)
    }

    func testShrinkingStopsAtTheFactor() throws {
        let t = try text(Text("123456").font(.system(size: 20)).lineLimit(1).minimumScaleFactor(0.5).frame(width: 20), width: 200)
        XCTAssertEqual(t.style.font?.metadata?.pointSize, 10, "never below 0.5 x 20")
        XCTAssertEqual(t.frame.width, 20, "still too wide at the floor: it takes the offered width (truncated)")
    }

    func testATextThatFitsKeepsItsFontAndNoFactorMeansNoShrinking() throws {
        XCTAssertEqual(try text(Text("12").font(.system(size: 20)).lineLimit(1).minimumScaleFactor(0.5).frame(width: 40), width: 200).style.font?.metadata?.pointSize, 20)
        XCTAssertEqual(try text(Text("123456").font(.system(size: 20)).lineLimit(1).frame(width: 40), width: 200).style.font?.metadata?.pointSize, 20)
    }

    func testViewMonospacedDigitGivesTabularFigures() throws {
        let t = try text(Text("12:30").font(.system(size: 14, weight: .semibold)).monospacedDigit(), width: 200)
        XCTAssertEqual(t.style.font?.metadata?.monospacedDigit, true)
        XCTAssertEqual(t.style.font?.metadata?.pointSize, 14)
        XCTAssertEqual(t.style.font?.metadata?.weight, .semibold)
        XCTAssertEqual(try text(Text("12").monospacedDigit(), width: 200).style.font?.metadata?.monospacedDigit, true, "no font set: the body font, tabular")
    }
}
