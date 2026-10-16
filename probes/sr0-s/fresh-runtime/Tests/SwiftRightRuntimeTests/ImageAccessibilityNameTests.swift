import Foundation
import SwiftRightRuntime
import XCTest

/// Block 41 controls-b: an unlabelled `Image(systemName: "star.fill")` is named "Favorite" on macOS 27 (its SF Symbol description), not "star.fill";
/// `.accessibilityLabel` and the Image's own label still win.
@MainActor
final class ImageAccessibilityNameTests: XCTestCase {
    private func images(_ node: ResolvedNode?) -> [ResolvedNode] {
        guard let node else { return [] }
        var out: [ResolvedNode] = node.accessibility.role == "image" ? [node] : []
        for child in node.children { out += images(child) }
        return out
    }

    private func names<V: View>(_ view: V) -> [String?] {
        let graph = Graph(view)
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        graph.flush()
        return images(graph.snapshot()).map { $0.accessibility.label }
    }

    func testAnUnlabelledStarFillIsNamedByItsSymbolDescriptionNotItsSymbolName() {
        struct Witness: View { var body: some View { Image(systemName: "star.fill").frame(width: 16, height: 16) } }
        XCTAssertEqual(names(Witness()), ["Favorite"])
    }

    func testAnUnmeasuredSymbolFallsBackToItsName() {
        struct Witness: View { var body: some View { Image(systemName: "gear").frame(width: 16, height: 16) } }
        XCTAssertEqual(names(Witness()), ["gear"])
    }

    func testAnAccessibilityLabelIsCarriedByItsModifierNodeAboveTheImage() {
        // The override is a modifier node the host applies to the element beneath (ResolvedNodePainter): the image keeps its own description.
        struct Witness: View {
            var body: some View { Image(systemName: "star.fill").frame(width: 16, height: 16).accessibilityLabel("Settings") }
        }
        let graph = Graph(Witness())
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        graph.flush()
        func all(_ n: ResolvedNode?) -> [ResolvedNode] { guard let n else { return [] }; return [n] + n.children.flatMap { all($0) } }
        let labels = all(graph.snapshot()).compactMap { $0.accessibility.label }
        XCTAssertTrue(labels.contains("Settings"))
        XCTAssertEqual(names(Witness()), ["Favorite"])
    }
}
