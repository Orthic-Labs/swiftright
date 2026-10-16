import XCTest
@testable import SwiftRightHost

final class HostWindowOptionsTests: XCTestCase {
    func testNoRenderScaleIsTheOldCall() throws {
        var seen: (String, UInt32, UInt32, Bool, Float?)?
        let o = HostWindowOptions(title: "w", width: 320, height: 240, pointerMoves: true)
        XCTAssertNil(o.renderScale)
        _ = try HostWindowOptions.forward(o) { seen = ($0, $1, $2, $3, $4); return 0 }
        XCTAssertEqual(seen?.0, "w")
        XCTAssertEqual(seen?.1, 320)
        XCTAssertEqual(seen?.2, 240)
        XCTAssertEqual(seen?.3, true)
        XCTAssertNil(seen?.4)
    }

    func testRenderScaleIsPassedThroughUnchanged() throws {
        var scale: Float?
        let o = HostWindowOptions(title: "w", width: 320, height: 240, renderScale: 2.5)
        let rc = try HostWindowOptions.forward(o) { _, w, h, _, s in scale = s; XCTAssertEqual(w, 320); XCTAssertEqual(h, 240); return 7 }
        XCTAssertEqual(scale, 2.5)
        XCTAssertEqual(rc, 7)
    }
}
