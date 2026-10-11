import SwiftRightRuntime
import XCTest

final class AlignmentTests: XCTestCase {
    func testNineStandardAlignmentsMapToHorizontalAndVerticalAxes() {
        XCTAssertEqual(Alignment.topLeading, Alignment(horizontal: .leading, vertical: .top))
        XCTAssertEqual(Alignment.top, Alignment(horizontal: .center, vertical: .top))
        XCTAssertEqual(Alignment.topTrailing, Alignment(horizontal: .trailing, vertical: .top))
        XCTAssertEqual(Alignment.leading, Alignment(horizontal: .leading, vertical: .center))
        XCTAssertEqual(Alignment.center, Alignment(horizontal: .center, vertical: .center))
        XCTAssertEqual(Alignment.trailing, Alignment(horizontal: .trailing, vertical: .center))
        XCTAssertEqual(Alignment.bottomLeading, Alignment(horizontal: .leading, vertical: .bottom))
        XCTAssertEqual(Alignment.bottom, Alignment(horizontal: .center, vertical: .bottom))
        XCTAssertEqual(Alignment.bottomTrailing, Alignment(horizontal: .trailing, vertical: .bottom))
    }
}
