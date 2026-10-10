import XCTest
@testable import SwiftRightBridge

/// The gate that keeps a UIA Invoke from moving the focus (F8, SR0 cross-compare) while a screen reader's own focus
/// request on a button still lands. Pure value logic: no renderer, no window.
final class ButtonFocusGateTests: XCTestCase {
    private let ms: UInt64 = 1_000_000
    private let t0: UInt64 = 5_000_000_000

    /// The recorded pair: focus request, then invoke of the same node 0.6 to 3.8 ms later. Nothing is applied.
    func testInvokeRightAfterFocusCancelsTheRequest() {
        var gate = ButtonFocusGate()
        XCTAssertNil(gate.request(7, at: t0))
        XCTAssertEqual(gate.pending, 7)
        XCTAssertTrue(gate.cancelForInvoke(of: 7, at: t0 + 1 * ms))
        XCTAssertNil(gate.pending)
        XCTAssertNil(gate.expired(at: t0 + 500 * ms), "a cancelled request never comes back")
        XCTAssertNil(gate.confirm())
    }

    /// Narrator moving to a button: a lone focus request lands once the window has passed.
    func testLoneFocusRequestIsAppliedAfterTheWindow() {
        var gate = ButtonFocusGate()
        XCTAssertNil(gate.request(261, at: t0))
        XCTAssertNil(gate.expired(at: t0 + ButtonFocusGate.settleNS), "still inside the window at the boundary")
        XCTAssertEqual(gate.expired(at: t0 + ButtonFocusGate.settleNS + 1), 261)
        XCTAssertNil(gate.pending)
        XCTAssertNil(gate.expired(at: t0 + 1_000 * ms), "taken once")
    }

    /// Narrator's activation after navigation: the focus already stands, so an invoke has nothing to cancel.
    func testInvokeAfterTheFocusWasAppliedKeepsIt() {
        var gate = ButtonFocusGate()
        _ = gate.request(261, at: t0)
        XCTAssertEqual(gate.expired(at: t0 + 100 * ms), 261)
        XCTAssertFalse(gate.cancelForInvoke(of: 261, at: t0 + 2_000 * ms))
    }

    /// An invoke that arrives after the window but before a tick took the request does not cancel it either.
    func testInvokeAfterTheWindowDoesNotCancelAnUntakenRequest() {
        var gate = ButtonFocusGate()
        _ = gate.request(9, at: t0)
        XCTAssertFalse(gate.cancelForInvoke(of: 9, at: t0 + 200 * ms))
        XCTAssertEqual(gate.confirm(), 9)
    }

    func testInvokeOfAnotherNodeLeavesTheRequestHeld() {
        var gate = ButtonFocusGate()
        _ = gate.request(9, at: t0)
        XCTAssertFalse(gate.cancelForInvoke(of: 10, at: t0 + 1 * ms))
        XCTAssertEqual(gate.pending, 9)
        XCTAssertEqual(gate.confirm(), 9, "the caller confirms it before running the other invoke")
    }

    func testInvokeWithNothingHeldCancelsNothing() {
        var gate = ButtonFocusGate()
        XCTAssertFalse(gate.cancelForInvoke(of: 7, at: t0))
        XCTAssertNil(gate.confirm())
        XCTAssertNil(gate.expired(at: t0 + 1_000 * ms))
    }

    func testNewRequestForAnotherNodeConfirmsTheEarlierOne() {
        var gate = ButtonFocusGate()
        XCTAssertNil(gate.request(1, at: t0))
        XCTAssertEqual(gate.request(2, at: t0 + 10 * ms), 1)
        XCTAssertEqual(gate.pending, 2)
        XCTAssertEqual(gate.age(at: t0 + 30 * ms), 20 * ms, "the window restarts with the new request")
    }

    func testRepeatedRequestForTheSameNodeRestartsTheWindow() {
        var gate = ButtonFocusGate()
        XCTAssertNil(gate.request(1, at: t0))
        XCTAssertNil(gate.request(1, at: t0 + 50 * ms))
        XCTAssertNil(gate.expired(at: t0 + 100 * ms), "50 ms since the restart")
        XCTAssertEqual(gate.expired(at: t0 + 120 * ms), 1)
    }

    func testConfirmTakesAHeldRequestOfAnyAge() {
        var gate = ButtonFocusGate()
        _ = gate.request(4, at: t0)
        XCTAssertEqual(gate.confirm(), 4)
        XCTAssertNil(gate.pending)
        XCTAssertNil(gate.age(at: t0))
    }

    /// The recorded gaps (0.59 to 3.84 ms over 46 invokes) are far inside the window.
    func testRecordedGapsAreInsideTheWindow() {
        XCTAssertGreaterThan(ButtonFocusGate.settleNS, 10 * 3_837_000)
        XCTAssertLessThan(ButtonFocusGate.settleNS, 4 * 16_700_000)
    }
}
