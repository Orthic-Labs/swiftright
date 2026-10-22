import SwiftRightRuntime
import XCTest

@MainActor
final class TimelineViewTests: XCTestCase {
    private func texts(_ g: Graph) -> [String] { everyNode(g.snapshot()).compactMap { $0.kind == "Text" ? $0.text : nil } }

    func testPeriodicScheduleQuantizesTheHostClock() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let v = TimelineView(.periodic(from: start, by: 2)) { c in Text("\(Int(c.date.timeIntervalSinceReferenceDate))") }
        let g = Graph(v, scale: 1)
        g.flush()
        XCTAssertEqual(texts(g), ["0"])
        g.tick(now: 5.5); g.flush()
        XCTAssertEqual(texts(g), ["4"])
        g.tick(now: 6.0); g.flush()
        XCTAssertEqual(texts(g), ["6"])
    }

    func testAnimationScheduleFollowsEveryTick() {
        let v = TimelineView(.animation) { c in Text("\(Int(c.date.timeIntervalSinceReferenceDate * 10))") }
        let g = Graph(v, scale: 1)
        g.flush()
        g.tick(now: 1.25); g.flush()
        XCTAssertEqual(texts(g), ["12"])
        g.tick(now: 1.5); g.flush()
        XCTAssertEqual(texts(g), ["15"])
    }
}
