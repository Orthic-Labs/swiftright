import XCTest
import SwiftRightHost
import SwiftRightRuntime
import SwiftRightBridge

/// The legacy vertical scroller's geometry and paint (`ScrollerPainter`), at scale 2.5. Frame 300 x 250 px (120 x 100 pt); a 100 pt viewport over
/// 120 pt of content gives a 90 pt track (3.8 pt top inset, 6.2 pt bottom) and a 75 pt thumb (90 * 100 / 120), 15 pt of travel.
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
        XCTAssertEqual(l.thumb.y, 9.5, accuracy: 1)            // 3.8 pt top inset
        XCTAssertEqual(l.thumb.h, 187.5, accuracy: 1)          // 75 pt thumb
        XCTAssertEqual(l.thumb.x, 263, accuracy: 1)            // strip + 4 pt leading inset
        XCTAssertEqual(l.thumb.w, 27, accuracy: 1)             // 10.8 pt
    }

    func testThumbIsHalfwayThroughItsTravelAtValueHalf() throws {
        let l = try layout(state(offset: 10))                   // maxOffset 20: value 0.5
        XCTAssertEqual(l.thumb.y, 28.25, accuracy: 1)           // 3.8 + 7.5 pt
        XCTAssertEqual(l.thumb.h, 187.5, accuracy: 1)
    }

    func testThumbEndsAtTheBottomInsetAtValueOne() throws {
        let l = try layout(state(offset: 20))                   // value 1
        XCTAssertEqual(l.thumb.y, 47, accuracy: 1)              // 3.8 + 15 pt
        XCTAssertEqual(l.thumb.y + l.thumb.h, 234.5, accuracy: 1)   // 250 px less the 6.2 pt bottom inset (15.5 px)
    }

    func testThumbNeverShorterThanTheMinimumLength() throws {
        // 100 pt over 1000 pt: the proportion is 9 pt, the minimum 18 pt.
        let l = try XCTUnwrap(ScrollerPainter.layout(frame: frame, scale: 2.5, scroll: state(offset: 0, content: 1000)))
        XCTAssertEqual(l.thumb.h, 45, accuracy: 0.5)            // 18 pt * 2.5
        let end = try XCTUnwrap(ScrollerPainter.layout(frame: frame, scale: 2.5, scroll: state(offset: 900, content: 1000)))
        XCTAssertEqual(end.thumb.y + end.thumb.h, 234.5, accuracy: 1)
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
