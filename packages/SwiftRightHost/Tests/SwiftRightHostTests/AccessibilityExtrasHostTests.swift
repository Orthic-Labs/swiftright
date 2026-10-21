import XCTest
import SwiftRightBridge
@testable import SwiftRightHost
import SwiftRightRuntime

// Issue #60 item 6: the host passes the accessibility extras (hint, header and link traits, a static text's value) to the bridge when the renderer
// reports ABI 0.13 (`ResolvedNodePainter.publishesAccessibilityExtras`, set from `Bridge.supportsAccessibilityExtras`), and publishes the element
// exactly as before otherwise.

private struct ExtrasWitness: View {
    var body: some View {
        VStack {
            Text("Heading").accessibilityAddTraits(.isHeader)
            Text("Site").accessibilityAddTraits(.isLink)
            Text("Memory").accessibilityValue("1.2 GB").accessibilityHint("Memory in use")
            Button("Run") {}.accessibilityHint("Starts the scan")
            Text("Plain")
        }
    }
}

@MainActor
final class AccessibilityExtrasHostTests: XCTestCase {
    private func commit(publishing: Bool) throws -> (root: ResolvedNode, upserts: [NodeUpsert]) {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        painter.publishesAccessibilityExtras = publishing
        let graph = Graph(ExtrasWitness(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let root = try XCTUnwrap(graph.snapshot())
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: root, version: 1, previousLive: [], submit: { upserts = $0.upserts })
        return (root, upserts)
    }

    private func semantic(_ text: String, _ r: (root: ResolvedNode, upserts: [NodeUpsert]), kind: String = "Text") throws -> SemanticNode {
        let node = try XCTUnwrap(flatten(r.root).first { $0.kind == kind && (kind == "Button" || $0.text == text) })
        return try XCTUnwrap(r.upserts.first { $0.id == UInt64(node.instance + 1) }?.semantic)
    }

    func testExtrasAreOnTheElementsWhenTheRendererTakesThem() throws {
        let r = try commit(publishing: true)
        XCTAssertEqual(try semantic("Heading", r).extras, SemanticExtras(isHeader: true))
        XCTAssertEqual(try semantic("Site", r).extras, SemanticExtras(isLink: true))
        let memory = try semantic("Memory", r)
        XCTAssertEqual(memory.extras, SemanticExtras(hint: "Memory in use", value: "1.2 GB"))
        XCTAssertEqual(memory.role, .staticText)
        XCTAssertEqual(memory.label, "Memory")
        XCTAssertEqual(memory.value, "", "the value travels in the extras, so the static text keeps its own name")
        XCTAssertNil(try semantic("Plain", r).extras)
        let button = try semantic("", r, kind: "Button")
        XCTAssertEqual(button.extras, SemanticExtras(hint: "Starts the scan"))
        XCTAssertEqual(button.role, .button); XCTAssertEqual(button.label, "Run")
    }

    func testNothingIsSentToAnOlderRenderer() throws {
        let r = try commit(publishing: false)
        for text in ["Heading", "Site", "Memory", "Plain"] { XCTAssertNil(try semantic(text, r).extras, text) }
        XCTAssertNil(try semantic("", r, kind: "Button").extras)
        XCTAssertEqual(try semantic("Memory", r).value, "1.2 GB", "unchanged behaviour: the value is the published value")
    }
}
