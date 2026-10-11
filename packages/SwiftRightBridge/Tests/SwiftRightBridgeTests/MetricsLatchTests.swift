import XCTest
@testable import SwiftRightBridge

/// `metrics()` must equal the last window-metrics event's size and scale (SR0 findings section 12). No renderer, no window.
final class MetricsLatchTests: XCTestCase {
    private func event(kind: BridgeEvent.Kind, w: Int32, h: Int32, scale: Float) -> BridgeEvent {
        BridgeEvent(kindRaw: kind.rawValue, action: 0, window: 4_294_967_297, node: 0, snapshot: 0, seq: 1, arg: 0,
                    x: scale, y: 0, i0: w, i1: h, modifiers: 0, text: "", typed: "")
    }

    /// The recorded case: the getter still says 800x1396 after the event carried 800x600 at scale 2.5.
    func testEventPayloadOverridesStaleGetter() {
        var latch = MetricsLatch()
        let stale = (width: UInt32(800), height: UInt32(1396), scale: Float(2.5), active: true)
        XCTAssertEqual(latch.resolve(getter: stale).height, 1396, "before any event the getter answers")
        XCTAssertTrue(latch.apply(event(kind: .windowMetrics, w: 800, h: 600, scale: 2.5)))
        let m = latch.resolve(getter: stale)
        XCTAssertEqual(m.width, 800)
        XCTAssertEqual(m.height, 600)
        XCTAssertEqual(m.scale, 2.5)
        XCTAssertTrue(m.active, "active comes from the getter")
    }

    func testLaterEventReplacesEarlierOne() {
        var latch = MetricsLatch()
        latch.apply(event(kind: .windowMetrics, w: 800, h: 600, scale: 2.5))
        latch.apply(event(kind: .windowMetrics, w: 1000, h: 700, scale: 1.25))
        let m = latch.resolve(getter: (width: 1, height: 1, scale: 1, active: false))
        XCTAssertEqual([m.width, m.height], [1000, 700])
        XCTAssertEqual(m.scale, 1.25)
        XCTAssertFalse(m.active)
    }

    func testOtherEventsAreIgnored() {
        var latch = MetricsLatch()
        XCTAssertFalse(latch.apply(event(kind: .key, w: 5, h: 5, scale: 9)))
        XCTAssertEqual(latch, MetricsLatch())
    }

    func testBadPayloadValuesAreClamped() {
        var latch = MetricsLatch()
        latch.apply(event(kind: .windowMetrics, w: 800, h: 600, scale: 2.5))
        latch.apply(event(kind: .windowMetrics, w: -4, h: -1, scale: 0))
        let m = latch.resolve(getter: (width: 9, height: 9, scale: 1, active: true))
        XCTAssertEqual([m.width, m.height], [0, 0])
        XCTAssertEqual(m.scale, 2.5, "a non-positive scale keeps the previous one")
    }
}
