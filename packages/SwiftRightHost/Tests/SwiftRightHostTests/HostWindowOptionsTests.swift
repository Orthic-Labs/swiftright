import XCTest
@testable import SwiftRightHost

final class HostWindowOptionsTests: XCTestCase {
    func testNoRenderScaleIsTheOldCall() throws {
        var seen: (String, UInt32, UInt32, Bool, Float?, Bool)?
        let o = HostWindowOptions(title: "w", width: 320, height: 240, pointerMoves: true)
        XCTAssertNil(o.renderScale)
        _ = try HostWindowOptions.forward(o) { seen = ($0, $1, $2, $3, $4, $5); return 0 }
        XCTAssertEqual(seen?.0, "w")
        XCTAssertEqual(seen?.1, 320)
        XCTAssertEqual(seen?.2, 240)
        XCTAssertEqual(seen?.3, true)
        XCTAssertNil(seen?.4)
        XCTAssertEqual(seen?.5, false, "pointer wheel is off unless asked")
    }

    func testRenderScaleIsPassedThroughUnchanged() throws {
        var scale: Float?
        let o = HostWindowOptions(title: "w", width: 320, height: 240, renderScale: 2.5)
        let rc = try HostWindowOptions.forward(o) { _, w, h, _, s, _ in scale = s; XCTAssertEqual(w, 320); XCTAssertEqual(h, 240); return 7 }
        XCTAssertEqual(scale, 2.5)
        XCTAssertEqual(rc, 7)
    }

    func testPointerWheelDefaultsOffAndIsPassedThrough() throws {
        XCTAssertFalse(HostWindowOptions(title: "w", width: 1, height: 1).pointerWheel)
        var wheel: Bool?
        let o = HostWindowOptions(title: "w", width: 320, height: 240, pointerWheel: true)
        _ = try HostWindowOptions.forward(o) { _, _, _, _, _, w in wheel = w; return 0 }
        XCTAssertEqual(wheel, true)
    }
}
