import XCTest
@testable import SwiftRightRuntime

/// Round 5 block 29: a non-resizable Image is sized by the environment font through `imageFontIntrinsicSize`.
@MainActor final class ImageFontIntrinsicTests: XCTestCase {
    private func size(_ view: some View) -> LayoutSize? {
        let graph = Graph(view)
        graph.imageIntrinsicSize = { _ in LayoutSize(width: 17, height: 16) }
        graph.imageFontIntrinsicSize = { _, font in
            // a stand-in for the host: nil font -> 13 pt, system(size:) -> its size; width = size + 3, height = size
            let pt = font == nil ? 13 : Double(font?.metadata?.pointSize ?? 0)
            return pt > 0 ? LayoutSize(width: CGFloat(pt + 3), height: CGFloat(pt)) : nil
        }
        graph.rootProposal = ProposedViewSize(width: 200, height: 200)
        graph.flush()
        return graph.snapshot().map { LayoutSize(width: $0.frame.width, height: $0.frame.height) }
    }

    func testNonResizableImageTakesTheFontSizeFromTheHost() {
        XCTAssertEqual(size(Image(systemName: "gearshape")), LayoutSize(width: 16, height: 13))
        XCTAssertEqual(size(Image(systemName: "gearshape").font(Font.system(size: 28, weight: .regular))), LayoutSize(width: 31, height: 28))
    }

    func testTheFontComesFromAnAncestorToo() {
        XCTAssertEqual(size(VStack { Image(systemName: "gearshape") }.font(Font.system(size: 20, weight: .regular)))?.height, 20)
    }

    func testHostThatDoesNotKnowTheFontKeepsTheNaturalSize() {
        let graph = Graph(Image(systemName: "gearshape").font(Font.custom("X", size: 9)))
        graph.imageIntrinsicSize = { _ in LayoutSize(width: 17, height: 16) }
        graph.imageFontIntrinsicSize = { _, _ in nil }
        graph.flush()
        XCTAssertEqual(graph.snapshot()?.frame.width, 17)
    }

    func testResizableImageIgnoresTheFontHook() {
        let graph = Graph(Image(systemName: "gearshape").resizable().scaledToFit())
        graph.imageIntrinsicSize = { _ in LayoutSize(width: 17, height: 16) }
        graph.imageFontIntrinsicSize = { _, _ in LayoutSize(width: 99, height: 99) }
        graph.rootProposal = ProposedViewSize(width: 34, height: 34)
        graph.flush()
        XCTAssertEqual(graph.snapshot()?.frame.width, 34)
    }
}
