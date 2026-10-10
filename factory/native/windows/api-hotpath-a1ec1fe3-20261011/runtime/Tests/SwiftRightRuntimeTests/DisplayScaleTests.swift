import Foundation
import SwiftRightRuntime
import XCTest

private struct DisplayScaleProbe: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Text("scale-\(Int(displayScale))")
    }
}

@MainActor
final class DisplayScaleTests: XCTestCase {
    func testDisplayScaleDefaultsToUnitScaleAndAcceptsNativeScalar() {
        var values = EnvironmentValues()
        XCTAssertEqual(values.displayScale, CGFloat(1))

        values.displayScale = 2.0
        XCTAssertEqual(values.displayScale, CGFloat(2))
    }

    func testDisplayScaleEnvironmentModifierPropagatesToDescendant() {
        let graph = Graph(VStack {
            DisplayScaleProbe()
            DisplayScaleProbe().environment(\.displayScale, 3)
        })
        graph.flush()

        XCTAssertEqual(allTexts(graph, kind: "Text"), ["scale-1", "scale-3"])
    }

    func testDisplayScaleRootOverrideReevaluatesEnvironmentReader() {
        let graph = Graph(DisplayScaleProbe())
        graph.flush()
        XCTAssertEqual(allTexts(graph, kind: "Text"), ["scale-1"])

        graph.setRootEnvironment { $0.displayScale = 2 }
        graph.flush()
        XCTAssertEqual(allTexts(graph, kind: "Text"), ["scale-2"])
    }
}
