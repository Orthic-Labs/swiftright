import SwiftRightRuntime
import XCTest

// SR1 round 4, block swiftui.font-custom: `.textCase(_:)` changes the displayed string, its measurement and its accessibility label (macOS 27: the AX value of the Text is the cased string).

private struct Cased: View {
    var body: some View {
        VStack {
            Text("Pulse hub").textCase(.uppercase)
            Text("PULSE Hub").textCase(.lowercase)
            Text("As Written")
            VStack { Text("inherited").textCase(.uppercase) }.textCase(nil)
        }
    }
}

@MainActor
final class TextCaseBlockTests: XCTestCase {
    func testCaseAppliesToTheDisplayedTextAndItsLabel() {
        let graph = Graph(Cased(), measurer: FixedAdvanceTextMeasurer(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        graph.flush()
        let texts = everyNode(graph.snapshot()).filter { $0.kind == "Text" }
        XCTAssertEqual(texts.compactMap(\.text), ["PULSE HUB", "pulse hub", "As Written", "INHERITED"])
        XCTAssertEqual(texts.compactMap(\.accessibility.label), ["PULSE HUB", "pulse hub", "As Written", "INHERITED"])
    }

    func testCaseKeepsTheLengthOfTheTextItMeasures() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(Text("ab").textCase(.uppercase), measurer: measurer, scale: 1)
        graph.flush()
        XCTAssertEqual(measurer.requests.last?.text, "AB")
    }
}
