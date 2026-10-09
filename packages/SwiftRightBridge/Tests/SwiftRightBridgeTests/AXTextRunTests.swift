import XCTest
@testable import SwiftRightBridge

/// Marshalling-level tests for AX text runs (no renderer, no window): these run on macOS.
final class AXTextRunTests: XCTestCase {
    private let origin: (x: Float, y: Float) = (x: 10, y: 20)
    private let lh: Float = 24

    private func measurement(lines: [(start: UInt32, len: UInt32, top: Float)]) -> TextMeasurement {
        TextMeasurement(
            run: TextRunHandle(raw: 1), width: 0, height: 0, firstBaseline: 0, lastBaseline: 0,
            lines: lines.map { LineInfo(utf8Start: $0.start, utf8Len: $0.len, width: 16, top: $0.top, baseline: 0) },
            charCount: 0, cacheHit: false, cacheKey: 0)
    }

    /// One visible glyph cell per UTF-8 byte of `text` (ASCII only), line index from the line table.
    private func cells(for text: String, lines: [(start: UInt32, len: UInt32, top: Float)]) -> [CharCell] {
        var out: [CharCell] = []
        for (k, line) in lines.enumerated() {
            for off in line.start..<(line.start + line.len) {
                let isBreak = off < UInt32(text.utf8.count) && text.utf8[text.utf8.index(text.utf8.startIndex, offsetBy: Int(off))] == 0x0A
                let x0 = Float(out.filter { Int($0.line) == k }.count * 8)
                out.append(CharCell(utf8Offset: off, utf8Len: 1, line: UInt32(k), wordStart: false,
                                    lineBreak: isBreak, x0: x0, x1: isBreak ? x0 : x0 + 8))
            }
        }
        return out
    }

    func testEmptyTextPublishesOneZeroLengthRunAtFirstID() throws {
        let runs = try makeAXTextRunsChecked(text: "", measurement: nil, cells: [], origin: origin,
                                             lineHeightPx: lh, firstRunID: 500)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].id, 500)
        XCTAssertEqual(runs[0].text, "")
        XCTAssertEqual(runs[0].charLengths, [])
        XCTAssertEqual(runs[0].bounds, Rect(x: 10, y: 20, w: 0, h: 24))
    }

    func testMeasuredButEmptyCellsStillOneRun() throws {
        let m = measurement(lines: [])
        let runs = try makeAXTextRunsChecked(text: "", measurement: m, cells: [], origin: origin,
                                             lineHeightPx: lh, firstRunID: 7)
        XCTAssertEqual(runs.map(\.id), [7])
    }

    func testUnCheckedWrapperHasTheSameEmptyBehaviour() {
        let runs = makeAXTextRuns(text: "", measurement: nil, cells: [], origin: origin,
                                  lineHeightPx: lh, firstRunID: 9)
        XCTAssertEqual(runs.map(\.id), [9])
    }

    func testMultiLineRunIdsAreContiguousFromTheBlockBase() throws {
        // "ab\ncd": line 0 is "ab\n" (bytes 0..<3), line 1 is "cd" (bytes 3..<5).
        let table: [(start: UInt32, len: UInt32, top: Float)] = [(0, 3, 0), (3, 2, 24)]
        let text = "ab\ncd"
        let runs = try makeAXTextRunsChecked(text: text, measurement: measurement(lines: table),
                                             cells: cells(for: text, lines: table), origin: origin,
                                             lineHeightPx: lh, firstRunID: 1000)
        XCTAssertEqual(runs.map(\.id), [1000, 1001])
        XCTAssertEqual(runs.map(\.text), ["ab\n", "cd"])
        XCTAssertEqual(runs.map(\.bounds.y), [20, 44])
    }

    /// Regression for the fixed 32-id block: a 40-line editor used to publish ids 32..39 into the
    /// next node's block. Now every id stays inside its own block and the ids are distinct.
    func testFortyLineEditorStaysInsideItsBlock() throws {
        let lines = (0..<40).map { (start: UInt32($0), len: UInt32(1), top: Float($0) * lh) }
        let text = String(repeating: "x", count: 40)
        let runs = try makeAXTextRunsChecked(text: text, measurement: measurement(lines: lines),
                                             cells: cells(for: text, lines: lines), origin: origin,
                                             lineHeightPx: lh, firstRunID: 4096)
        let ids = runs.map(\.id)
        XCTAssertEqual(ids.count, 40)
        XCTAssertEqual(Set(ids).count, 40)
        XCTAssertEqual(ids.first, 4096)
        XCTAssertEqual(ids.last, 4096 + 39)
        XCTAssertLessThan(ids.last!, 4096 + axTextRunBlockSize)
    }

    func testBlockSizeIsTwoToTheSixteenth() {
        XCTAssertEqual(axTextRunBlockSize, 1 << 16)
    }

    func testExactlyOneBlockOfLinesIsAccepted() throws {
        let count = Int(axTextRunBlockSize)
        let lines = (0..<count).map { (start: UInt32(0), len: UInt32(0), top: Float($0) * lh) }
        let cell = [CharCell(utf8Offset: 0, utf8Len: 0, line: 0, wordStart: false, lineBreak: false, x0: 0, x1: 0)]
        let runs = try makeAXTextRunsChecked(text: "", measurement: measurement(lines: lines), cells: cell,
                                             origin: origin, lineHeightPx: lh, firstRunID: 1 << 20)
        XCTAssertEqual(runs.count, count)
        XCTAssertEqual(runs.last?.id, (1 << 20) + UInt64(count - 1))
    }

    func testOneLineOverTheBlockThrowsTypedError() {
        let count = Int(axTextRunBlockSize) + 1
        let lines = (0..<count).map { (start: UInt32(0), len: UInt32(0), top: Float($0) * lh) }
        let cell = [CharCell(utf8Offset: 0, utf8Len: 0, line: 0, wordStart: false, lineBreak: false, x0: 0, x1: 0)]
        XCTAssertThrowsError(try makeAXTextRunsChecked(text: "", measurement: measurement(lines: lines), cells: cell,
                                                       origin: origin, lineHeightPx: lh, firstRunID: 1)) { error in
            XCTAssertEqual(error as? AXTextRunError, .blockExceeded(lines: count, blockSize: axTextRunBlockSize))
        }
    }
}
