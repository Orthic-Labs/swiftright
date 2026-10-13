import SwiftRightRuntime
import XCTest

/// A Button is its label inside the bordered push button macOS draws by default: 12 pt of padding each side, 4 pt above and below
/// (measured from SwiftUI on macOS: `Button("Run")` 48 x 24 pt for a 24 x 16 pt label; a 30 x 10 pt view label gives 54 x 18).
@MainActor
final class ButtonLayoutTests: XCTestCase {
    private func button(_ view: some View, scale: CGFloat = 1) -> ResolvedNode? {
        let graph = Graph(view, scale: scale)
        graph.flush()
        return everyNode(graph.snapshot()).first { $0.kind == "Button" }
    }

    func testButtonIsItsLabelPlusPadding() throws {
        let node = try XCTUnwrap(button(Button(action: {}) { Color.red.frame(width: 30, height: 10) }))
        XCTAssertEqual(node.frame.width, 54)
        XCTAssertEqual(node.frame.height, 18)
        let label = try XCTUnwrap(everyNode(node).first { $0.kind == "Color" })
        XCTAssertEqual(label.frame.minX, node.frame.minX + 12)
        XCTAssertEqual(label.frame.minY, node.frame.minY + 4)
    }

    func testTextButtonWidthAndHeightFollowItsLabel() throws {
        let node = try XCTUnwrap(button(Button("Run") {}))
        let label = try XCTUnwrap(everyNode(node).first { $0.kind == "Text" })
        XCTAssertEqual(node.frame.width, label.frame.width + 24, accuracy: 1e-9)
        XCTAssertEqual(node.frame.height, label.frame.height + 8, accuracy: 1e-9)
    }

    func testButtonKeepsItsSizeInsideALargerFrame() throws {
        let node = try XCTUnwrap(button(Button(action: {}) { Color.red.frame(width: 30, height: 10) }.frame(width: 100, height: 40)))
        XCTAssertEqual(node.frame.width, 54)
        XCTAssertEqual(node.frame.minX, 23)
    }
}
