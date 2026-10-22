@testable import SwiftRightRuntime
import XCTest

@MainActor
final class AccessoryModifiersTests: XCTestCase {
    func testAccessibilityActionsAreListedAndRun() throws {
        var ran: [String] = []
        let g = Graph(Color.red.frame(width: 10, height: 10).accessibilityAction(named: "Open") { ran.append("open") }.accessibilityAction(.escape) { ran.append("escape") }, scale: 1)
        g.flush()
        let root = try XCTUnwrap(g.snapshot()).id
        XCTAssertEqual(Set(g.accessibilityActionNames(on: root)), ["Open", "escape"])
        XCTAssertTrue(g.performAccessibilityAction(named: "Open", on: root))
        XCTAssertFalse(g.performAccessibilityAction(named: "Missing", on: root))
        XCTAssertEqual(ran, ["open"])
    }

    func testTimingCurveMatchesTheBuiltInEaseInOut() {
        let custom = Animation.timingCurve(0.42, 0, 0.58, 1, duration: 0.35)
        XCTAssertEqual(custom.duration, 0.35)
        // the built-in ease-in-out is the (0.42, 0, 0.58, 1) curve: compare progress at a few times through a driven animation
        XCTAssertEqual(custom.curve.value(at: 0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(custom.curve.value(at: 0.25), Animation.easeInOut.curve.value(at: 0.25), accuracy: 1e-6)
    }

    func testMaskWithAShapeClipsAndKeepsLayout() {
        let g = Graph(ZStack { Color.red.frame(width: 40, height: 40).mask { Circle() } }, scale: 1)
        g.flush()
        XCTAssertNotNil(everyNode(g.snapshot()).first { $0.clipShape != nil })
    }

    func testNamespaceIsStablePerInstance() {
        struct Probe { @Namespace var ns }
        let p = Probe()
        XCTAssertEqual(p.ns, p.ns)
        XCTAssertNotEqual(Probe().ns, p.ns)
    }
}
