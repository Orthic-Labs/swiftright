import Foundation
import Observation
import SwiftRightRuntime
import XCTest

@MainActor
final class SnapshotStorageTests: XCTestCase {
    func testEqualShapesIgnoreIndependentStorageBoxes() {
        let firstGraph = Graph(Rectangle())
        let secondGraph = Graph(Rectangle())
        firstGraph.flush()
        secondGraph.flush()

        XCTAssertEqual(firstGraph.snapshot(), secondGraph.snapshot())
        XCTAssertEqual(firstGraph.snapshot()?.shape, secondGraph.snapshot()?.shape)
    }

    func testDifferentGeometryOrPaintMakesSnapshotsUnequal() {
        let rectangle = Graph(Rectangle())
        let circle = Graph(Circle())
        let red = Graph(Rectangle().fill(Color.red))
        let blue = Graph(Rectangle().fill(Color.blue))
        rectangle.flush()
        circle.flush()
        red.flush()
        blue.flush()

        XCTAssertNotEqual(rectangle.snapshot(), circle.snapshot())
        XCTAssertNotEqual(red.snapshot(), blue.snapshot())
        XCTAssertNotEqual(red.snapshot()?.shape, blue.snapshot()?.shape)
    }

    func testLegacySnapshotHasNoShapeMetadata() {
        let graph = Graph(Text("legacy"))
        graph.flush()

        XCTAssertNil(graph.snapshot()?.shape)
    }

    func testRetainedSnapshotKeepsShapeValueAfterGraphChanges() {
        let store = SnapshotShapeStore()
        let graph = Graph(SnapshotShapeView(store: store))
        graph.flush()
        let retained = graph.snapshot()

        store.showCircle = true
        graph.flush()

        XCTAssertEqual(firstShape(in: retained)?.geometry, .rectangle)
        XCTAssertEqual(firstShape(in: graph.snapshot())?.geometry, .circle)
    }
}

@MainActor
private func firstShape(in node: ResolvedNode?) -> ResolvedShape? {
    guard let node else { return nil }
    if let shape = node.shape { return shape }
    for child in node.children {
        if let shape = firstShape(in: child) { return shape }
    }
    return nil
}

@Observable
@MainActor
private final class SnapshotShapeStore {
    var showCircle = false
}

private struct SnapshotShapeView: View {
    let store: SnapshotShapeStore

    var body: some View {
        if store.showCircle {
            Circle()
        } else {
            Rectangle()
        }
    }
}
