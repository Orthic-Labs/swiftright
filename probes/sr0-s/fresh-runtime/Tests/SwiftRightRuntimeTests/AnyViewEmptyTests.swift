import Foundation
import SwiftRightRuntime
import XCTest

/// Block 41 compat any-view: `AnyView(EmptyView()).frame(width: 40, height: 10)` between two rows of a VStack (spacing 8) takes no space and no
/// stack spacing on macOS 27 (ImageRenderer, scale 2.5, the case's witness: the lower rows sit 18 pt higher than the Windows layout had them).
@MainActor
final class AnyViewEmptyTests: XCTestCase {
    private func root<V: View>(_ view: V) -> ResolvedNode? {
        let graph = Graph(view)
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        graph.flush()
        return graph.snapshot()
    }

    private func colors(_ node: ResolvedNode?) -> [ResolvedNode] {
        guard let node else { return [] }
        var out: [ResolvedNode] = node.kind == "Color" ? [node] : []
        for child in node.children { out += colors(child) }
        return out
    }

    func testAnEmptyErasedViewWithAFrameTakesNoSpaceAndNoSpacing() {
        struct Witness: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    Color.red.frame(width: 60, height: 12)
                    AnyView(EmptyView()).frame(width: 40, height: 10)
                    Color.gray.frame(width: 80, height: 6)
                }
            }
        }
        let node = root(Witness())
        let rows = colors(node)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.last?.frame.minY, 20, "12 pt row + 8 pt spacing; the empty erased view adds neither")
        XCTAssertEqual(node?.frame.height, 26, "12 + 8 + 6")
    }

    func testANonEmptyErasedViewStillTakesItsFrameAndSpacing() {
        struct Witness: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    Color.red.frame(width: 60, height: 12)
                    AnyView(Color.blue).frame(width: 40, height: 10)
                    Color.gray.frame(width: 80, height: 6)
                }
            }
        }
        let rows = colors(root(Witness()))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.last?.frame.minY, 38, "12 + 8 + 10 + 8: the non-empty erased frame keeps its space")
    }
}
