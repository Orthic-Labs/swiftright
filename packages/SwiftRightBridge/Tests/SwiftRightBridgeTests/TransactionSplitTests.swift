import XCTest
@testable import SwiftRightBridge

final class TransactionSplitTests: XCTestCase {
    private func nodes(_ n: Int, primitives: Int = 1) -> [NodeUpsert] {
        (0..<n).map { NodeUpsert(id: UInt64($0 + 1), parent: $0 == 0 ? 0 : UInt64($0), order: 0, flags: [], bounds: Rect(x: 0, y: 0, w: 1, h: 1),
                                 primitives: Array(repeating: .rect(Rect(x: 0, y: 0, w: 1, h: 1), color: 0), count: primitives), semantic: nil) }
    }
    func testASmallTransactionIsOneTransactionAtItsOwnVersion() {
        let parts = BridgeWindow.split(Transaction(version: 5, focus: 3, upserts: nodes(10)), lastVersion: 4)
        XCTAssertEqual(parts.count, 1); XCTAssertEqual(parts[0].version, 5); XCTAssertEqual(parts[0].focus, 3)
    }
    func testALargeTreeIsSplitInTreeOrderWithIncreasingVersionsAndTheFocusLast() {
        let parts = BridgeWindow.split(Transaction(version: 7, focus: 9, upserts: nodes(4718)), lastVersion: 6)
        XCTAssertEqual(parts.map { $0.upserts.count }, [4096, 622])
        XCTAssertEqual(parts.map { $0.version }, [7, 8])
        XCTAssertEqual(parts.map { $0.focus }, [0, 9])
        XCTAssertEqual(parts.flatMap { $0.upserts.map(\.id) }, (1...4718).map { UInt64($0) }, "tree order is kept: a parent is always sent before its children")
    }
    func testPrimitiveLimitAndRemovesAreSplitToo() {
        let parts = BridgeWindow.split(Transaction(version: 1, upserts: nodes(100, primitives: 1000), removes: (1...5000).map { UInt64($0) }), lastVersion: 0)
        XCTAssertTrue(parts.allSatisfy { $0.upserts.count <= 4096 && $0.removes.count <= 4096 && $0.upserts.reduce(0) { $0 + $1.primitives.count } <= 65536 })
        XCTAssertEqual(parts.flatMap(\.removes).count, 5000)
        XCTAssertEqual(parts.reduce(0) { $0 + $1.upserts.count }, 100)
        XCTAssertEqual(parts.map(\.version), Array(1...UInt64(parts.count)))
    }
    func testTheNextHostVersionIsRaisedPastASplit() {
        let parts = BridgeWindow.split(Transaction(version: 8, upserts: nodes(10)), lastVersion: 9)
        XCTAssertEqual(parts[0].version, 10, "the host asked for 8, the renderer has seen 9")
    }
}
