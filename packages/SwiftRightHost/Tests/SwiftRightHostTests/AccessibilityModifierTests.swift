import XCTest
import SwiftRightHost
import SwiftRightBridge

private struct AXValueWitness: View {
    var body: some View {
        VStack {
            Text("Volume").accessibilityValue("50 percent")
            Text("Plain")
            Rectangle().fill(Color.red).frame(width: 40, height: 10).accessibilityLabel("Level").accessibilityValue("high")
            Button("Go") {}.accessibilityValue("ready")
        }
    }
}
private struct AXHiddenWitness: View {
    var body: some View {
        VStack {
            Text("Visible one")
            Text("Hidden text").accessibilityHidden(true)
            Button("Hidden button") {}.accessibilityHidden(true)
            VStack { Text("inner a"); Text("inner b") }.accessibilityHidden(true)
            Text("Shown again").accessibilityHidden(false)
        }
    }
}
private struct AXElementWitness: View {
    var body: some View {
        VStack {
            HStack { Text("Memory"); Text("1.2 GB") }.accessibilityElement(children: .combine)
            HStack { Text("Swap"); Text("0 MB") }.accessibilityElement(children: .ignore).accessibilityLabel("Swap usage")
            HStack { Text("Disk"); Text("40 GB") }.accessibilityElement(children: .contain)
            HStack { Text("Net"); Text("3 Mb/s") }.accessibilityElement(children: .combine).accessibilityValue("fast")
        }
    }
}
private struct AXTraitsWitness: View {
    var body: some View {
        VStack {
            Rectangle().fill(Color.blue).frame(width: 40, height: 10).accessibilityLabel("Chart").accessibilityAddTraits(.isImage)
            Button("Selected") {}.accessibilityAddTraits(.isSelected)
            Text("Heading").accessibilityAddTraits(.isHeader)
            Button("Run") {}.accessibilityHint("Starts the scan")
        }
    }
}

@MainActor
final class AccessibilityModifierTests: XCTestCase {
    /// the semantics each node published, in tree order: (runtime kind, role, label, value)
    private func semantics<V: View>(_ view: V) throws -> [(kind: String, node: SemanticNode?)] {
        let painter = ResolvedNodePainter(images: FakeImages(), scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let root = try XCTUnwrap(graph.snapshot())
        var upserts: [NodeUpsert] = []
        let committed = try painter.commit(root: root, version: 1, previousLive: [], submit: { upserts = $0.upserts })
        var kinds: [UInt64: String] = [:]
        func walk(_ n: ResolvedNode) { kinds[UInt64(n.instance + 1)] = n.kind; n.children.forEach(walk) }
        walk(root)
        _ = committed
        return upserts.map { (kinds[$0.id] ?? "?", $0.semantic) }
    }
    private func published<V: View>(_ view: V) throws -> [SemanticNode] { try semantics(view).compactMap { $0.node }.filter { $0.role != .window } }

    func testValueIsPublishedOnTheElementBeneath() throws {
        let s = try published(AXValueWitness())
        let volume = try XCTUnwrap(s.first { $0.label == "Volume" })
        XCTAssertEqual(volume.role, .staticText); XCTAssertEqual(volume.value, "50 percent")
        XCTAssertEqual(try XCTUnwrap(s.first { $0.label == "Plain" }).value, "")
        let go = try XCTUnwrap(s.first { $0.label == "Go" })
        XCTAssertEqual(go.role, .button); XCTAssertEqual(go.value, "ready")
        XCTAssertNil(s.first { $0.label == "Level" }, "a Rectangle with a label and no trait publishes no element (macOS: AXUnknown)")
    }

    func testHiddenRemovesTheWholeSubtree() throws {
        let labels = try published(AXHiddenWitness()).map(\.label)
        XCTAssertEqual(labels, ["Visible one", "Shown again"])
    }

    func testElementChildren() throws {
        let s = try published(AXElementWitness())
        XCTAssertEqual(s.first { $0.label == "Memory, 1.2 GB" }?.role, .staticText, "combine: one element reading both texts")
        XCTAssertNil(s.first { $0.label == "Memory" })
        XCTAssertEqual(s.first { $0.label == "Swap usage" }?.role, .group, "ignore: the node is one element with its own label")
        XCTAssertNil(s.first { $0.label == "Swap" })
        XCTAssertNotNil(s.first { $0.label == "Disk" }); XCTAssertNotNil(s.first { $0.label == "40 GB" }, "contain keeps the children")
        let net = try XCTUnwrap(s.first { $0.label == "Net, 3 Mb/s" })
        XCTAssertEqual(net.value, "fast")
    }

    func testTraits() throws {
        let s = try published(AXTraitsWitness())
        let chart = try XCTUnwrap(s.first { $0.label == "Chart" })
        XCTAssertEqual(chart.role, .image)
        XCTAssertEqual(s.first { $0.label == "Selected" }?.selected, true)
        XCTAssertEqual(s.first { $0.label == "Heading" }?.role, .staticText, "isHeader has no renderer role: carried, not exposed")
        XCTAssertEqual(s.first { $0.label == "Run" }?.role, .button, "a hint changes nothing the ABI carries")
    }

    func testTheModifiersAreOnTheResolvedTree() throws {
        let graph = Graph(AXTraitsWitness(), scale: 2.5); graph.flush()
        var all: [ResolvedNode] = []
        func walk(_ n: ResolvedNode) { all.append(n); n.children.forEach(walk) }
        walk(try XCTUnwrap(graph.snapshot()))
        XCTAssertEqual(all.first { $0.kind == "modifier.accessibilityHint" }?.accessibility.hint, "Starts the scan")
        XCTAssertEqual(all.first { $0.kind == "modifier.accessibilityTraits" && $0.accessibility.addedTraits.contains("isHeader") }?.accessibility.addedTraits, ["isHeader"])
    }
}
