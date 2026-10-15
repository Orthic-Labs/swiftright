import SwiftRightRuntime
import XCTest

// Round 6 block 38: .onHover and .onTapGesture, and the SwiftCrossUI #789 family (docs/prior-art.md section 2, case swiftui.gestures/body-ends-in-modifier-v1):
// a body that ends in .onHover / .onTapGesture versus the same body wrapped in a VStack, an explicit-return body, and a nested composite.

private final class Log { var events: [String] = []; var taps = 0; var other = 0 }

private struct EndsInTap: View {
    let log: Log
    @State private var count = 0
    var body: some View {
        Rectangle().fill(Color.red).frame(width: 40, height: 20).onTapGesture { count += 1; log.taps = count }
    }
}

private struct EndsInHover: View {
    let log: Log
    @State private var hovered = false
    var body: some View {
        Rectangle().fill(hovered ? Color.green : Color.red).frame(width: 40, height: 20).onHover { hovered = $0; log.events.append("A:\($0)") }
    }
}

private struct ExplicitReturn: View {
    let log: Log
    @State private var count = 0
    var body: some View {
        return Rectangle().fill(Color.red).frame(width: 40, height: 20).onTapGesture { count += 1; log.taps = count }
    }
}

private struct Nested: View {
    let log: Log
    var body: some View { EndsInTap(log: log) }
}

private struct Wrapped: View {
    let log: Log
    @State private var count = 0
    var body: some View {
        VStack { Rectangle().fill(Color.red).frame(width: 40, height: 20).onTapGesture { count += 1; log.taps = count } }
    }
}

private struct Adjacent: View {
    let log: Log
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.red).frame(width: 40, height: 20).onHover { log.events.append("A:\($0)") }
            Rectangle().fill(Color.blue).frame(width: 40, height: 20).onHover { log.events.append("B:\($0)") }
        }
    }
}

private struct WithUnrelated: View {
    let log: Log
    @State private var count = 0
    @State private var other = 0
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.red).frame(width: 40, height: 20).onTapGesture { count += 1; log.taps = count }
            Rectangle().fill(Color.blue).frame(width: 40, height: 20).onTapGesture { other += 1; log.other = other }
        }
    }
}

private extension LayoutRect {
    var midX: CGFloat { minX + width / 2 }
    var midY: CGFloat { minY + height / 2 }
}

@MainActor
final class GestureBlockTests: XCTestCase {
    private func make(_ view: some View) -> Graph { let g = Graph(view, scale: 2.5); g.flush(); return g }
    private func rects(_ g: Graph) -> [ResolvedNode] { everyNode(g.snapshot()).filter { $0.kind == "Rectangle" } }

    func testFirstCommitCompletesAndBoundsMatchTheWrappedLeaf() throws {
        let a = make(EndsInTap(log: Log())), b = make(Wrapped(log: Log())), c = make(ExplicitReturn(log: Log())), d = make(Nested(log: Log()))
        for g in [a, b, c, d] { XCTAssertNotNil(g.snapshot(), "the first commit completes") }
        let leaf = try XCTUnwrap(rects(b).first)
        for g in [a, c, d] {
            let r = try XCTUnwrap(rects(g).first)
            XCTAssertEqual(rects(g).count, 1)
            XCTAssertEqual(r.frame.width, leaf.frame.width); XCTAssertEqual(r.frame.height, leaf.frame.height)
            XCTAssertEqual(r.kind, leaf.kind)
            // same nodes as the wrapped leaf apart from the stack that wraps it
            XCTAssertEqual(everyNode(g.snapshot()).filter { $0.kind == "modifier.onTapGesture" }.count, 1)
        }
        XCTAssertEqual(everyNode(b.snapshot()).count, everyNode(a.snapshot()).count + 1 + 1 - 1, "the VStack is the one extra node (the wrapped leaf has the same subtree)")
    }

    private func checkCentreAndOutside(_ name: String, _ g: Graph, _ log: Log) throws {
        let r = try XCTUnwrap(rects(g).first)
        let cx = r.frame.midX, cy = r.frame.midY
        XCTAssertFalse(g.tapGesture(atX: r.frame.maxX + 1, y: cy), "\(name): outside (right)")
        XCTAssertFalse(g.tapGesture(atX: cx, y: r.frame.maxY + 1), "\(name): outside (below)")
        XCTAssertFalse(g.tapGesture(atX: r.frame.minX - 1, y: cy), "\(name): outside (left)")
        XCTAssertEqual(log.taps, 0)
        XCTAssertTrue(g.tapGesture(atX: cx, y: cy), name)
        XCTAssertEqual(log.taps, 1)
        XCTAssertTrue(g.tapGesture(atX: cx, y: cy)); XCTAssertEqual(log.taps, 2, "\(name): the state survives between taps")
    }

    func testACentreClickAddsOneAndAnOutsideClickAddsNone() throws {
        var log = Log(); try checkCentreAndOutside("ends-in-tap", make(EndsInTap(log: log)), log)
        log = Log(); try checkCentreAndOutside("wrapped", make(Wrapped(log: log)), log)
        log = Log(); try checkCentreAndOutside("explicit-return", make(ExplicitReturn(log: log)), log)
        log = Log(); try checkCentreAndOutside("nested", make(Nested(log: log)), log)
    }

    func testStateSurvivesAnUnrelatedWrite() throws {
        let log = Log(); let g = make(WithUnrelated(log: log))
        let rs = rects(g)
        XCTAssertEqual(rs.count, 2)
        g.tapGesture(atX: rs[0].frame.midX, y: rs[0].frame.midY); g.tapGesture(atX: rs[0].frame.midX, y: rs[0].frame.midY)
        XCTAssertEqual(log.taps, 2)
        g.tapGesture(atX: rs[1].frame.midX, y: rs[1].frame.midY)            // an unrelated write
        XCTAssertEqual(log.other, 1)
        g.tapGesture(atX: rs[0].frame.midX, y: rs[0].frame.midY)
        XCTAssertEqual(log.taps, 3, "the first leaf kept its count across the other leaf's write")
    }

    func testHoverCallbacksInOrderAndTheStateFollows() throws {
        let log = Log(); let g = make(EndsInHover(log: log))
        let r = try XCTUnwrap(rects(g).first)
        g.pointerMoved(toX: r.frame.midX, y: r.frame.midY)
        g.pointerMoved(toX: r.frame.midX + 1, y: r.frame.midY)              // still inside: no callback
        XCTAssertEqual(log.events, ["A:true"])
        g.pointerMoved(toX: r.frame.maxX + 5, y: r.frame.midY)
        XCTAssertEqual(log.events, ["A:true", "A:false"])
        g.pointerMoved(toX: r.frame.midX, y: r.frame.midY)
        g.pointerMoved(toX: nil, y: nil)                                     // the pointer left the window
        XCTAssertEqual(log.events, ["A:true", "A:false", "A:true", "A:false"])
        g.pointerMoved(toX: nil, y: nil)
        XCTAssertEqual(log.events.count, 4, "nothing more once everything is left")
    }

    func testBetweenAdjacentViewsTheExitComesBeforeTheEntry() throws {
        let log = Log(); let g = make(Adjacent(log: log))
        let rs = rects(g)
        XCTAssertEqual(rs.count, 2)
        g.pointerMoved(toX: rs[0].frame.midX, y: rs[0].frame.midY)
        g.pointerMoved(toX: rs[1].frame.midX, y: rs[1].frame.midY)
        g.pointerMoved(toX: rs[0].frame.midX, y: rs[0].frame.midY)
        XCTAssertEqual(log.events, ["A:true", "A:false", "B:true", "B:false", "A:true"])
    }

    func testTheFrameEdgesAreHalfOpen() throws {
        let log = Log(); let g = make(EndsInTap(log: log))
        let r = try XCTUnwrap(rects(g).first)
        XCTAssertTrue(g.tapGesture(atX: r.frame.minX, y: r.frame.minY), "the top-left corner is inside")
        XCTAssertFalse(g.tapGesture(atX: r.frame.maxX, y: r.frame.midY), "the right edge is outside")
    }

    func testOnlyASingleTapIsDelivered() throws {
        let box = Log()
        let g = make(Rectangle().fill(Color.red).frame(width: 40, height: 20).onTapGesture(count: 2) { box.taps += 1 })
        let r = try XCTUnwrap(rects(g).first)
        XCTAssertFalse(g.tapGesture(atX: r.frame.midX, y: r.frame.midY))
        XCTAssertEqual(box.taps, 0)
    }

    func testTheDeepestTapGestureWins() throws {
        let log = Log()
        let g = make(VStack { Rectangle().fill(Color.red).frame(width: 40, height: 20).onTapGesture { log.taps += 100 } }.onTapGesture { log.taps += 1 })
        let r = try XCTUnwrap(rects(g).first)
        XCTAssertTrue(g.tapGesture(atX: r.frame.midX, y: r.frame.midY)); XCTAssertEqual(log.taps, 100)
    }
}
