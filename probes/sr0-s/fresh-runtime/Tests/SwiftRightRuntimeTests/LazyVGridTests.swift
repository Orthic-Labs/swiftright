import SwiftRightRuntime
import XCTest

/// Frames measured from SwiftUI LazyVGrid on macOS 27 (22 Oct 2026), cells Color.red.frame(height: 10), container width 300.
@MainActor
final class LazyVGridTests: XCTestCase {
    private func xs(_ columns: [GridItem], count: Int = 4, width: CGFloat = 300, cellWidth: CGFloat? = nil) -> [(CGFloat, CGFloat)] {
        let graph = Graph(LazyVGrid(columns: columns) {
            ForEach(0..<count, id: \.self) { _ in Color.red.frame(width: cellWidth, height: 10) }
        }.frame(width: width), scale: 1)
        graph.flush()
        return everyNode(graph.snapshot()).filter { $0.kind == "Color" }.map { ($0.frame.minX, $0.frame.width) }
    }

    func testFixedColumnsCentred() {
        let f = xs([.init(.fixed(60)), .init(.fixed(80))], count: 2)
        XCTAssertEqual(f[0].0, 76); XCTAssertEqual(f[1].0, 144)
    }

    func testAdaptiveColumns() {
        let f = xs([.init(.adaptive(minimum: 60))], count: 4)
        XCTAssertEqual(f.map(\.0), [0, 77, 154, 231])
        XCTAssertEqual(f[0].1, 69)
    }

    func testFlexibleLimited() {
        let f = xs([.init(.flexible(minimum: 50, maximum: 80)), .init(.flexible(minimum: 50, maximum: 80)), .init(.flexible(minimum: 50, maximum: 80))], count: 3)
        XCTAssertEqual(f.map(\.0), [22, 110, 198])
        XCTAssertEqual(f[0].1, 80)
    }
}

@MainActor
final class ContentShapeHelpTests: XCTestCase {
    func testContentShapeAndHelpKeepLayout() {
        let graph = Graph(Color.red.frame(width: 30, height: 10).contentShape(Rectangle()).contentShape(.interaction, Circle()).help("tip").help(Text("tip")), scale: 1)
        graph.flush()
        let c = everyNode(graph.snapshot()).first { $0.kind == "Color" }
        XCTAssertEqual(c?.frame.width, 30)
    }
}
