import SwiftRightRuntime
import XCTest

@MainActor
final class TruncationModeTests: XCTestCase {
    private func shown(_ mode: Text.TruncationMode, _ s: String, width: CGFloat) -> String? {
        let graph = Graph(Text(s).lineLimit(1).truncationMode(mode).frame(width: width, alignment: .leading), scale: 1)
        graph.flush()
        return everyNode(graph.snapshot()).first { $0.kind == "Text" }?.text
    }

    func testFitsUnchanged() {
        for m in [Text.TruncationMode.head, .middle, .tail] { XCTAssertEqual(shown(m, "short", width: 400), "short") }
    }

    func testHeadKeepsTheEnd() throws {
        let s = try XCTUnwrap(shown(.head, "The quick brown fox jumps over the lazy dog", width: 120))
        print("HEAD:", s)
        XCTAssertTrue(s.hasPrefix("\u{2026}") && s.hasSuffix("lazy dog") && s.count < 43)
    }

    func testMiddleKeepsBothEnds() throws {
        let s = try XCTUnwrap(shown(.middle, "The quick brown fox jumps over the lazy dog", width: 120))
        print("MIDDLE:", s)
        XCTAssertTrue(s.hasPrefix("The ") && s.hasSuffix("dog") && s.contains("\u{2026}"))
    }

    func testTailIsLeftToTheRenderer() {
        XCTAssertEqual(shown(.tail, "The quick brown fox jumps over the lazy dog", width: 120), "The quick brown fox jumps over the lazy dog")
    }
}
