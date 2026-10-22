import Foundation
import SwiftRightRuntime
import XCTest
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@MainActor
final class DragDropTests: XCTestCase {
    func testDropRunsTheDeepestHandlerAndDrivesIsTargeted() {
        var targeted = false, dropped = 0, outerDropped = 0
        let g = Graph(Color.red.frame(width: 100, height: 100)
            .onDrop(of: [.fileURL], isTargeted: Binding(get: { targeted }, set: { targeted = $0 })) { _ in dropped += 1; return true }
            .onDrop(of: [.plainText], isTargeted: nil) { _ in outerDropped += 1; return true }, scale: 1)
        g.flush()
        g.dropTargetChanged(atX: 50, y: 50)
        XCTAssertTrue(targeted)
        g.dropTargetChanged(atX: 500, y: 50)
        XCTAssertFalse(targeted)
        XCTAssertTrue(g.performDrop(atX: 50, y: 50, providers: [NSItemProvider()]))
        XCTAssertEqual(dropped + outerDropped, 1, "one handler takes the drop")
        XCTAssertFalse(g.performDrop(atX: 500, y: 500, providers: []))
    }

    func testOnDragIsAccepted() {
        let g = Graph(Color.red.frame(width: 10, height: 10).onDrag { NSItemProvider() }, scale: 1)
        g.flush()
        XCTAssertNotNil(g.snapshot())
    }
}
