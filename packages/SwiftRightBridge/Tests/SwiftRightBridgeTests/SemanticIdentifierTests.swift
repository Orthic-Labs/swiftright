import XCTest
@testable import SwiftRightBridge

final class SemanticIdentifierTests: XCTestCase {
    func testShortIdentifiersAreUnchanged() {
        XCTAssertEqual(SemanticIdentifier.fit("root/#0/Text"), "root/#0/Text")
        let edge = String(repeating: "a", count: 256)
        XCTAssertEqual(SemanticIdentifier.fit(edge), edge)
    }

    func testLongIdentifiersFitAndStayUnique() {
        let a = String(repeating: "view/#0/", count: 50) + "x"
        let b = String(repeating: "view/#0/", count: 50) + "y"
        XCTAssertGreaterThan(a.utf8.count, 256)
        let fa = SemanticIdentifier.fit(a), fb = SemanticIdentifier.fit(b)
        XCTAssertLessThanOrEqual(fa.utf8.count, SemanticIdentifier.maxBytes)
        XCTAssertNotEqual(fa, fb, "paths that differ only at the end stay distinct")
        XCTAssertEqual(fa, SemanticIdentifier.fit(a), "stable")
        XCTAssertTrue(fa.hasPrefix(String(a.prefix(180))))
    }

    func testTheCutNeverSplitsACharacter() {
        let multibyte = String(repeating: "\u{4F60}", count: 120)   // 3 bytes each: 360 bytes
        let fitted = SemanticIdentifier.fit(multibyte)
        XCTAssertLessThanOrEqual(fitted.utf8.count, 256)
        XCTAssertNotNil(String(validatingUTF8: fitted.cString(using: .utf8)!))
    }
}
