import XCTest
@testable import SwiftRightRuntime

/// Wave 1 block I2 (docs/foundations-images-fonts.md 1.3): `.interpolation(_:)`, `.antialiased(_:)`, `.scaledToFill()`, `.aspectRatio(_:contentMode:)` and `.clipped()` resolve for the host.
@MainActor
final class ImageLayoutI2Tests: XCTestCase {
    private func pixels(_ w: Int, _ h: Int) -> RGBAImage { RGBAImage(width: w, height: h, rgba: [UInt8](repeating: 128, count: w * h * 4))! }

    /// Frames are snapped to the 2.5 scale pixel grid, which can move an edge by 1 px (0.4 pt) at an exact half pixel: compare within that.
    private func resolve<V: View>(_ view: V, proposal: ProposedViewSize = ProposedViewSize(width: 200, height: 200), scale: CGFloat = 2.5) -> [ResolvedNode] {
        let graph = Graph(view, scale: scale)
        graph.rootProposal = proposal
        graph.flush()
        func flat(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(flat) }
        return graph.snapshot().map(flat) ?? []
    }

    func testInterpolationAndAntialiasedReachTheHost() {
        let levels: [Image.Interpolation] = [.none, .low, .medium, .high]
        for level in levels {
            let node = resolve(Image(decorative: pixels(8, 8)).resizable().interpolation(level).antialiased(false)).first { $0.image != nil }
            XCTAssertEqual(node?.imageSizing?.interpolation, level)
            XCTAssertEqual(node?.imageSizing?.antialiased, false)
        }
        // never set: nil (the host draws like .low), and a plain non-resizable image keeps imageSizing nil
        let plain = resolve(Image(decorative: pixels(8, 8))).first { $0.image != nil }
        XCTAssertNil(plain?.imageSizing)
        let resizable = resolve(Image(decorative: pixels(8, 8)).resizable()).first { $0.image != nil }
        XCTAssertNil(resizable?.imageSizing?.interpolation)
        // a non-resizable image that asks for a level still reaches the host (it may be drawn at another scale)
        let asked = resolve(Image(decorative: pixels(8, 8), scale: 1).interpolation(.none)).first { $0.image != nil }
        XCTAssertEqual(asked?.imageSizing?.interpolation, Image.Interpolation.none)
    }

    func testScaledToFillTakesTheLargerScaleAndOverflowsTheFrame() {
        // 40 x 20 pt image in a 20 x 20 pt frame: fit 20 x 10, fill 40 x 20 (the frame does not clip; `.clipped()` does)
        let fit = resolve(Image(decorative: pixels(100, 50), scale: 2.5).resizable().scaledToFit().frame(width: 20, height: 20)).first { $0.image != nil }
        XCTAssertEqual(fit?.frame.width ?? -999, 20, accuracy: 0.45); XCTAssertEqual(fit?.frame.height ?? -999, 10, accuracy: 0.45)
        let fill = resolve(Image(decorative: pixels(100, 50), scale: 2.5).resizable().scaledToFill().frame(width: 20, height: 20)).first { $0.image != nil }
        XCTAssertEqual(fill?.frame.width ?? -999, 40, accuracy: 0.45); XCTAssertEqual(fill?.frame.height ?? -999, 20, accuracy: 0.45)
        XCTAssertEqual(fill?.frame.origin.x ?? -999, -10, accuracy: 0.45)       // centred in the frame, overflowing on both sides
        let tallFill = resolve(Image(decorative: pixels(50, 100), scale: 2.5).resizable().scaledToFill().frame(width: 30, height: 10)).first { $0.image != nil }
        XCTAssertEqual(tallFill?.frame.width ?? -999, 30, accuracy: 0.45); XCTAssertEqual(tallFill?.frame.height ?? -999, 60, accuracy: 0.45)
    }

    func testAspectRatioOverridesTheImagesOwn() {
        let r = resolve(Image(decorative: pixels(100, 50), scale: 2.5).resizable().aspectRatio(1, contentMode: .fit).frame(width: 30, height: 20)).first { $0.image != nil }
        XCTAssertEqual(r?.frame.width ?? -999, 20, accuracy: 0.45); XCTAssertEqual(r?.frame.height ?? -999, 20, accuracy: 0.45)
        let f = resolve(Image(decorative: pixels(100, 50), scale: 2.5).resizable().aspectRatio(1, contentMode: .fill).frame(width: 30, height: 20)).first { $0.image != nil }
        XCTAssertEqual(f?.frame.width ?? -999, 30, accuracy: 0.45); XCTAssertEqual(f?.frame.height ?? -999, 30, accuracy: 0.45)
        let own = resolve(Image(decorative: pixels(100, 50), scale: 2.5).resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20)).first { $0.image != nil }
        XCTAssertEqual(own?.frame.width ?? -999, 20, accuracy: 0.45); XCTAssertEqual(own?.frame.height ?? -999, 10, accuracy: 0.45)
    }

    func testClippedIsAPassThroughModifierNode() {
        let nodes = resolve(Image(decorative: pixels(100, 50), scale: 2.5).resizable().scaledToFill().frame(width: 20, height: 20).clipped())
        let clip = nodes.first { $0.kind == "modifier.clipped" }
        XCTAssertNotNil(clip)
        XCTAssertEqual(clip?.frame.width ?? -999, 20, accuracy: 0.45); XCTAssertEqual(clip?.frame.height ?? -999, 20, accuracy: 0.45)    // layout is the frame's: clipped changes nothing
    }
}
