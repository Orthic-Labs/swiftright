import XCTest
import SwiftRightHost
import SwiftRightRuntime
import SwiftRightBridge

/// The legacy vertical scroller's geometry and paint (`ScrollerPainter`), at scale 2.5. Frame 300 x 250 px (120 x 100 pt); a 100 pt viewport over
/// 120 pt of content gives a 93.8 pt track (3.0 pt top inset, 3.2 pt bottom; measured M1, #31) and a 78.17 pt thumb (93.8 * 100 / 120), 15.63 pt of travel.
final class ScrollerPainterTests: XCTestCase {
    private let frame = Rect(x: 0, y: 0, w: 300, h: 250)

    private func state(offset: Double = 0, content: Double = 120, viewport: Double = 100, shows: Bool = true) -> ScrollState {
        ScrollState(offsetY: offset, contentHeight: content, viewportHeight: viewport, showsScroller: shows)
    }

    private func layout(_ scroll: ScrollState) throws -> ScrollerLayout {
        try XCTUnwrap(ScrollerPainter.layout(frame: frame, scale: 2.5, scroll: scroll))
    }

    func testStripIsTheMeasuredWidthAtTheTrailingEdge() throws {
        let l = try layout(state())
        XCTAssertEqual(l.strip.x, 253, accuracy: 1)            // 300 px less 19 pt * 2.5 = 47.5 px, snapped
        XCTAssertEqual(l.strip.x + l.strip.w, 300, accuracy: 0.001)
        XCTAssertEqual(l.strip.y, 0); XCTAssertEqual(l.strip.h, 250)
    }

    func testThumbIsAtTheTopInsetAndTheTrailingInsideTheStripAtValueZero() throws {
        let l = try layout(state(offset: 0))
        XCTAssertEqual(l.thumb.y, 7.5, accuracy: 1)            // 3.0 pt top inset
        XCTAssertEqual(l.thumb.h, 195.4, accuracy: 1)          // 78.17 pt thumb
        XCTAssertEqual(l.thumb.x, 263, accuracy: 1)            // strip + 4 pt leading inset
        XCTAssertEqual(l.thumb.w, 27, accuracy: 1)             // 10.8 pt
    }

    func testThumbIsHalfwayThroughItsTravelAtValueHalf() throws {
        let l = try layout(state(offset: 10))                   // maxOffset 20: value 0.5
        XCTAssertEqual(l.thumb.y, 27.0, accuracy: 1)            // 3.0 + 7.82 pt
        XCTAssertEqual(l.thumb.h, 195.4, accuracy: 1)
    }

    func testThumbEndsAtTheBottomInsetAtValueOne() throws {
        let l = try layout(state(offset: 20))                   // value 1
        XCTAssertEqual(l.thumb.y, 46.6, accuracy: 1)            // 3.0 + 15.63 pt
        XCTAssertEqual(l.thumb.y + l.thumb.h, 242, accuracy: 1)     // 250 px less the 3.2 pt bottom inset (8 px)
    }

    func testThumbNeverShorterThanTheMinimumLength() throws {
        // 100 pt over 1000 pt: the proportion is 9.4 pt, the minimum 20 pt (measured M1).
        let l = try XCTUnwrap(ScrollerPainter.layout(frame: frame, scale: 2.5, scroll: state(offset: 0, content: 1000)))
        XCTAssertEqual(l.thumb.h, 50, accuracy: 0.5)            // 20 pt * 2.5
        let end = try XCTUnwrap(ScrollerPainter.layout(frame: frame, scale: 2.5, scroll: state(offset: 900, content: 1000)))
        XCTAssertEqual(end.thumb.y + end.thumb.h, 242, accuracy: 1)
    }

    func testNoScrollerWhenTheContentDoesNotOverflowOrTheHostHidesIt() {
        XCTAssertNil(ScrollerPainter.layout(frame: frame, scale: 2.5, scroll: state(shows: false)))
        XCTAssertNil(ScrollerPainter.layout(frame: frame, scale: 2.5, scroll: state(content: 100, viewport: 100)))
        XCTAssertNil(ScrollerPainter.thumbPoints(for: state(shows: false)))
    }

    func testPaintIsTrackBorderThenRoundedThumb() throws {
        let l = try layout(state())
        let primitives = ScrollerPainter.primitives(for: l, scale: 2.5)
        XCTAssertEqual(primitives.count, 3)
        guard case .rect(_, let track, _, _, _) = primitives[0], case .rect(_, let border, _, _, _) = primitives[1],
              case .rect(let thumb, let colour, let radius, _, _) = primitives[2] else { return XCTFail("scroller is not three rects") }
        XCTAssertEqual(track, ScrollerColors.track << 8 | 0xff)
        XCTAssertEqual(border, ScrollerColors.trackBorder << 8 | 0xff)
        XCTAssertEqual(colour, ScrollerColors.thumb << 8 | 0xff)
        XCTAssertEqual(radius, thumb.w / 2, accuracy: 0.001)     // rounded: radius is half the thumb's width
    }
}
