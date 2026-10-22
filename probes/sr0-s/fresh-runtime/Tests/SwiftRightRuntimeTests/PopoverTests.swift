import SwiftRightRuntime
import XCTest

@MainActor
final class PopoverTests: XCTestCase {
    private func panel(_ edge: Edge, shown: Bool = true) -> CGRect? {
        let g = Graph(ZStack { Color.red.frame(width: 40, height: 20).popover(isPresented: .constant(shown), arrowEdge: edge) { Color.blue.frame(width: 30, height: 10) } }.frame(width: 200, height: 200), scale: 1)
        g.flush()
        let anchor = everyNode(g.snapshot()).first { $0.kind == "Color" && $0.frame.width == 40 }!.frame
        guard let pop = everyNode(g.snapshot()).first(where: { $0.kind == "Color" && $0.frame.width == 30 })?.frame else { return nil }
        return CGRect(x: pop.minX - anchor.minX, y: pop.minY - anchor.minY, width: pop.width, height: pop.height)
    }

    func testTopArrowEdgePutsThePopoverBelowCentred() throws {
        let r = try XCTUnwrap(panel(.top))
        XCTAssertEqual(r.minY, 20, accuracy: 0.5)
        XCTAssertEqual(r.minX, 5, accuracy: 0.5)
    }

    func testOtherEdges() throws {
        XCTAssertEqual(try XCTUnwrap(panel(.bottom)).maxY, 0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(panel(.leading)).minX, 40, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(panel(.trailing)).maxX, 0, accuracy: 0.5)
    }

    func testNothingWhenNotPresented() { XCTAssertNil(panel(.top, shown: false)) }
}
