import XCTest
@testable import SwiftRightRuntime

/// Round 5 block 35: `Image(decorative: RGBAImage, scale:)` carries decoded pixels; layout comes from the pixel size.
@MainActor final class ImageDataTests: XCTestCase {
    private func pixels(_ w: Int, _ h: Int, fill: UInt8 = 7) -> RGBAImage {
        RGBAImage(width: w, height: h, rgba: [UInt8](repeating: fill, count: w * h * 4))!
    }

    private func root(_ view: some View, proposal: ProposedViewSize = ProposedViewSize(width: 400, height: 400)) -> ResolvedNode? {
        let graph = Graph(view)
        graph.rootProposal = proposal
        graph.flush()
        return graph.snapshot()
    }

    func testRejectsMismatchedBuffers() {
        XCTAssertNil(RGBAImage(width: 2, height: 2, rgba: [UInt8](repeating: 0, count: 15)))
        XCTAssertNil(RGBAImage(width: 0, height: 2, rgba: []))
        XCTAssertNil(RGBAImage(width: -1, height: 2, rgba: [UInt8](repeating: 0, count: 8)))
    }

    func testContentIDIsStableAndSensitiveToPixelsAndShape() {
        XCTAssertEqual(pixels(4, 2).contentID, pixels(4, 2).contentID)
        XCTAssertEqual(pixels(4, 2), pixels(4, 2))
        XCTAssertNotEqual(pixels(4, 2).contentID, pixels(4, 2, fill: 8).contentID)
        XCTAssertNotEqual(pixels(4, 2).contentID, pixels(2, 4).contentID)
        XCTAssertNotEqual(pixels(4, 2), pixels(2, 4))
        XCTAssertEqual(Set([pixels(4, 2), pixels(4, 2), pixels(3, 3)]).count, 2)
    }

    func testIntrinsicSizeIsPixelsOverScale() {
        XCTAssertEqual(root(Image(decorative: pixels(40, 20)))?.frame.width, 40)
        XCTAssertEqual(root(Image(decorative: pixels(40, 20)))?.frame.height, 20)
        let scaled = root(Image(decorative: pixels(100, 50), scale: 2.5))
        XCTAssertEqual(scaled?.frame.width, 40)
        XCTAssertEqual(scaled?.frame.height, 20)
        let retina = root(Image(decorative: pixels(64, 64), scale: 2))
        XCTAssertEqual(retina?.frame.width, 32)
    }

    func testNonResizableIgnoresTheProposalAndHostHooks() {
        let graph = Graph(Image(decorative: pixels(40, 20)))
        graph.imageIntrinsicSize = { _ in LayoutSize(width: 99, height: 99) }
        graph.imageFontIntrinsicSize = { _, _ in LayoutSize(width: 77, height: 77) }
        graph.rootProposal = ProposedViewSize(width: 10, height: 10)
        graph.flush()
        XCTAssertEqual(graph.snapshot()?.frame.width, 40)
        XCTAssertEqual(graph.snapshot()?.frame.height, 20)
    }

    func testNonPositiveScaleFallsBackToOne() {
        XCTAssertEqual(root(Image(decorative: pixels(8, 8), scale: 0))?.frame.width, 8)
    }

    func testResizableScaledToFitKeepsTheAspectRatio() {
        let fit = root(Image(decorative: pixels(40, 20)).resizable().scaledToFit(), proposal: ProposedViewSize(width: 100, height: 100))
        XCTAssertEqual(fit?.frame.width, 100)
        XCTAssertEqual(fit?.frame.height, 50)
        let framed = root(Image(decorative: pixels(40, 20)).resizable().scaledToFit().frame(width: 16, height: 16))
        let image = framed?.children.first
        XCTAssertEqual(image?.frame.width, 16)
        XCTAssertEqual(image?.frame.height, 8)
    }

    func testResizableWithoutFitFillsTheProposal() {
        let node = root(Image(decorative: pixels(40, 20)).resizable().frame(width: 30, height: 30))
        XCTAssertEqual(node?.children.first?.frame.width, 30)
        XCTAssertEqual(node?.children.first?.frame.height, 30)
    }

    func testResolvedNodeCarriesThePixels() {
        let image = pixels(3, 2)
        let node = root(Image(decorative: image, scale: 2))
        guard case .pixels(let carried, let scale)? = node?.image else { return XCTFail("no pixel reference") }
        XCTAssertEqual(carried.rgba, image.rgba)
        XCTAssertEqual(scale, 2)
        XCTAssertNil(node?.imageSizing)
        XCTAssertEqual(node?.accessibility.role, "image")
    }

    func testDifferentPixelsAreADifferentImageNode() {
        let graph = Graph(Image(decorative: pixels(4, 4)))
        graph.flush()
        let before = graph.snapshot()?.image
        let graph2 = Graph(Image(decorative: pixels(4, 4, fill: 9)))
        graph2.flush()
        XCTAssertNotEqual(before, graph2.snapshot()?.image)
        XCTAssertEqual(before, ImageReference.pixels(pixels(4, 4), scale: 1))
    }
}
