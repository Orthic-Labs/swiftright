import XCTest
@testable import SwiftRightBridge

/// Pure-geometry tests for selectionRects (no renderer, no window): these run headlessly on macOS.
final class SelectionRectsTests: XCTestCase {
    private let origin: (x: Float, y: Float) = (x: 10, y: 20)
    private let lh: Float = 24

    /// "ab\ncd": cells a,b,'\n' on line 0 (8 px each, break zero width), c,d on line 1.
    private let cells: [CharCell] = [
        CharCell(utf8Offset: 0, utf8Len: 1, line: 0, wordStart: true, lineBreak: false, x0: 0, x1: 8),
        CharCell(utf8Offset: 1, utf8Len: 1, line: 0, wordStart: false, lineBreak: false, x0: 8, x1: 16),
        CharCell(utf8Offset: 2, utf8Len: 1, line: 0, wordStart: false, lineBreak: true, x0: 16, x1: 16),
        CharCell(utf8Offset: 3, utf8Len: 1, line: 1, wordStart: true, lineBreak: false, x0: 0, x1: 8),
        CharCell(utf8Offset: 4, utf8Len: 1, line: 1, wordStart: false, lineBreak: false, x0: 8, x1: 16),
    ]
    private let lines = [
        LineInfo(utf8Start: 0, utf8Len: 3, width: 16, top: 0, baseline: 16),
        LineInfo(utf8Start: 3, utf8Len: 2, width: 16, top: 24, baseline: 40),
    ]

    private func rects(_ s: Int, _ e: Int) -> [Rect] {
        selectionRects(cells: cells, lines: lines, start: s, end: e, origin: origin, lineHeightPx: lh, lineBreakWidth: 4)
    }

    func testCollapsedSelectionHasNoRects() {
        XCTAssertEqual(rects(2, 2), [])
    }

    func testSingleLineRange() {
        XCTAssertEqual(rects(0, 2), [Rect(x: 10, y: 20, w: 16, h: 24)])
        XCTAssertEqual(rects(1, 2), [Rect(x: 18, y: 20, w: 8, h: 24)])
    }

    func testSelectedLineBreakAddsNub() {
        XCTAssertEqual(rects(1, 3), [Rect(x: 18, y: 20, w: 12, h: 24)])
    }

    func testMultiLineRangeGivesOneRectPerLine() {
        XCTAssertEqual(rects(1, 5), [Rect(x: 18, y: 20, w: 12, h: 24), Rect(x: 10, y: 44, w: 16, h: 24)])
        XCTAssertEqual(rects(0, 4), [Rect(x: 10, y: 20, w: 20, h: 24), Rect(x: 10, y: 44, w: 8, h: 24)])
    }

    func testReversedAndOutOfRangeBoundsAreClamped() {
        XCTAssertEqual(rects(2, 0), rects(0, 2))
        XCTAssertEqual(rects(3, 99), [Rect(x: 10, y: 44, w: 16, h: 24)])
        XCTAssertEqual(rects(9, 12), [])
    }

    func testEmptyCellsYieldNothing() {
        XCTAssertEqual(selectionRects(cells: [], lines: [], start: 0, end: 5, origin: origin,
                                      lineHeightPx: lh, lineBreakWidth: 4), [])
    }
}
