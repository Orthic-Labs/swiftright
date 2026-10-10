import SwiftRightRuntime
import XCTest

private struct LayoutDirectionProbe: View {
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        Text(direction == .leftToRight ? "ltr" : "rtl")
    }
}

@MainActor
final class LayoutDirectionTests: XCTestCase {
    func testLayoutDirectionRoundTripAndEnvironmentReader() {
        var values = EnvironmentValues()
        XCTAssertEqual(values.layoutDirection, .leftToRight)

        values.layoutDirection = .rightToLeft
        XCTAssertEqual(values.layoutDirection, .rightToLeft)

        let graph = Graph(LayoutDirectionProbe().environment(\.layoutDirection, .rightToLeft))
        graph.flush()
        XCTAssertEqual(allTexts(graph, kind: "Text"), ["rtl"])
    }
}
