import XCTest
@testable import SwiftRightHost
import SwiftRightBridge

// Issue #60 pass 2: gradients are rasterised by the host (GradientRaster), in gamma-encoded sRGB with straight alpha, and masked by `.clipShape` when filling a shape.

@MainActor
final class GradientRasterTests: XCTestCase {
    private let black: UInt32 = 0x000000ff, white: UInt32 = 0xffffffff

    private func px(_ image: ContinuousRGBAImage, _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * image.width + x) * 4
        return Array(image.rgba[i..<i + 4])
    }

    private func linear(_ start: UnitPoint, _ end: UnitPoint, _ stops: [GradientRaster.Stop], w: Int, h: Int) throws -> ContinuousRGBAImage {
        try XCTUnwrap(GradientRaster.render(geometry: .linear(start: start, end: end), stops: stops, widthPX: w, heightPX: h, scale: 1))
    }

    func testTwoStopEndpointsAreExactBeyondTheStopsAndTheMidpointIsTheMean() throws {
        // stops at 0.25 and 0.75 over 100 px: pixels left of x = 25 and right of x = 75 are the stop colours exactly (the gradient is clamped)
        let image = try linear(.leading, .trailing, [.init(location: 0.25, rgba: black), .init(location: 0.75, rgba: white)], w: 100, h: 2)
        XCTAssertEqual(px(image, 0, 0), [0, 0, 0, 255])
        XCTAssertEqual(px(image, 24, 1), [0, 0, 0, 255])
        XCTAssertEqual(px(image, 75, 0), [255, 255, 255, 255])
        XCTAssertEqual(px(image, 99, 1), [255, 255, 255, 255])
        // pixel 50 has centre 50.5: t = (50.5 - 25) / 50 = 0.51 -> 130.05
        XCTAssertEqual(px(image, 50, 0), [130, 130, 130, 255])
        // an odd width puts a pixel centre on the exact midpoint: 127.5 rounds to 128
        let odd = try linear(.leading, .trailing, [.init(location: 0, rgba: black), .init(location: 1, rgba: white)], w: 101, h: 1)
        XCTAssertEqual(px(odd, 50, 0), [128, 128, 128, 255])
        XCTAssertEqual(px(odd, 0, 0)[0], 1, "the first pixel centre is 0.5 px in: 1.27 of 255")
        XCTAssertEqual(px(odd, 100, 0)[0], 254)
    }

    func testChannelsInterpolateInGammaEncodedSRGB() throws {
        // red 0xff0000 to blue 0x0000ff at the exact midpoint: both channels 127.5 -> 128 (a linear-light mix would give 188)
        let image = try linear(.leading, .trailing, [.init(location: 0, rgba: 0xff0000ff), .init(location: 1, rgba: 0x0000ffff)], w: 101, h: 1)
        XCTAssertEqual(px(image, 50, 0), [128, 0, 128, 255])
    }

    func testThreeStopsPassThroughTheMiddleColour() throws {
        let image = try linear(.leading, .trailing, [.init(location: 0, rgba: 0xff0000ff), .init(location: 0.5, rgba: 0x00ff00ff), .init(location: 1, rgba: 0x0000ffff)], w: 101, h: 1)
        XCTAssertEqual(px(image, 50, 0), [0, 255, 0, 255])
        XCTAssertEqual(px(image, 25, 0), [126, 129, 0, 255], "t = 0.2525: just over half way from red to green")
    }

    func testAlphaInterpolatesStraightAndAClearStopKeepsTheOtherHue() throws {
        let image = try linear(.leading, .trailing, [.init(location: 0, rgba: 0x0000ffff), .init(location: 1, rgba: 0x00000000)], w: 101, h: 1)
        XCTAssertEqual(px(image, 50, 0), [0, 0, 255, 128], "blue to clear fades alpha only; the hue stays blue")
        let reversed = try linear(.leading, .trailing, [.init(location: 0, rgba: 0x00000000), .init(location: 1, rgba: 0x0000ffff)], w: 101, h: 1)
        XCTAssertEqual(px(reversed, 50, 0), [0, 0, 255, 128])
    }

    func testDiagonalGradientHasConstantColourAlongTheAntiDiagonal() throws {
        let image = try linear(.topLeading, .bottomTrailing, [.init(location: 0, rgba: black), .init(location: 1, rgba: white)], w: 100, h: 100)
        // t = (x + y + 1) / 200
        XCTAssertEqual(px(image, 50, 0), px(image, 0, 50))
        XCTAssertEqual(px(image, 25, 25), px(image, 50, 0))
        XCTAssertEqual(px(image, 10, 60), px(image, 60, 10))
        XCTAssertNotEqual(px(image, 51, 0), px(image, 50, 0))
        XCTAssertEqual(px(image, 0, 0)[0], 1)
        XCTAssertEqual(px(image, 99, 99)[0], 254)
        // and it is not the dominant-axis approximation: a pure vertical gradient would give equal colours along a row
        XCTAssertNotEqual(px(image, 0, 50), px(image, 99, 50))
    }

    func testAGradientAtOtherAnglesRunsAlongItsOwnLine() throws {
        // bottom -> top: reversed vertical
        let up = try linear(.bottom, .top, [.init(location: 0, rgba: black), .init(location: 1, rgba: white)], w: 4, h: 100)
        XCTAssertEqual(px(up, 0, 99)[0], 1)
        XCTAssertEqual(px(up, 3, 0)[0], 254)
        XCTAssertEqual(px(up, 0, 40), px(up, 3, 40), "constant along a row")
        // 2:1 frame, corner to corner: the isolines are perpendicular to the (200, 100) vector in pixels, so (x, y) and (x + 100, y - 200 * 100 / ... ) are not equal along the rows
        let wide = try linear(.topLeading, .bottomTrailing, [.init(location: 0, rgba: black), .init(location: 1, rgba: white)], w: 200, h: 100)
        // t = ((x + .5) * 200 + (y + .5) * 100) / 50000: (100, 0) and (0, 200) would match, but along the row t grows 0.004 per px and down a column 0.002
        let a = Double(px(wide, 100, 0)[0]), b = Double(px(wide, 100, 50)[0])
        XCTAssertEqual(b - a, 255 * 50 * 100 / 50000, accuracy: 1.5)
    }

    func testRadialRingsAreSymmetricAndClampOutsideTheRadii() throws {
        let stops: [GradientRaster.Stop] = [.init(location: 0, rgba: black), .init(location: 1, rgba: white)]
        let image = try XCTUnwrap(GradientRaster.render(geometry: .radial(center: .center, startRadius: 10, endRadius: 40), stops: stops, widthPX: 100, heightPX: 100, scale: 1))
        XCTAssertEqual(px(image, 49, 49), [0, 0, 0, 255], "inside the start radius")
        XCTAssertEqual(px(image, 0, 0), [255, 255, 255, 255], "beyond the end radius")
        XCTAssertEqual(px(image, 49, 49), px(image, 50, 50))
        XCTAssertEqual(px(image, 49, 70), px(image, 70, 49))
        XCTAssertEqual(px(image, 49, 70), px(image, 49, 29))
        // r = 25 at (74.5 - 50): t = (24.5 - 10) / 30 for pixel (74, 49.5)...: centre distance along x of pixel 74 from 50 is 24.5 and 0.5 in y
        let r = (24.5 * 24.5 + 0.5 * 0.5).squareRoot()
        XCTAssertEqual(Double(px(image, 74, 49)[0]), 255 * (r - 10) / 30, accuracy: 0.51)
        // radii are in points: the same gradient at scale 2 reaches twice as far
        let double = try XCTUnwrap(GradientRaster.render(geometry: .radial(center: .center, startRadius: 10, endRadius: 40), stops: stops, widthPX: 200, heightPX: 200, scale: 2))
        XCTAssertEqual(px(double, 99, 99), [0, 0, 0, 255])
        XCTAssertEqual(px(double, 0, 0), [255, 255, 255, 255])
        XCTAssertEqual(Double(px(double, 99 + 40, 99)[0]), Double(px(image, 49 + 20, 49)[0]), accuracy: 3, "the same ring, to within the pixel-centre offset")
    }

    func testDegenerateAndOversizedRequests() throws {
        XCTAssertNil(GradientRaster.render(geometry: .linear(start: .top, end: .bottom), stops: [], widthPX: 4, heightPX: 4, scale: 1))
        XCTAssertNil(GradientRaster.render(geometry: .linear(start: .top, end: .bottom), stops: [.init(location: 0, rgba: black)], widthPX: 0, heightPX: 4, scale: 1))
        XCTAssertNil(GradientRaster.render(geometry: .linear(start: .top, end: .bottom), stops: [.init(location: 0, rgba: black)], widthPX: 5000, heightPX: 5000, scale: 1))
        let flat = try linear(.center, .center, [.init(location: 0, rgba: 0x336699ff), .init(location: 1, rgba: white)], w: 3, h: 3)
        XCTAssertEqual(px(flat, 1, 1), [0x33, 0x66, 0x99, 255], "start == end draws the first colour")
        let single = try linear(.top, .bottom, [.init(location: 0.5, rgba: 0x336699ff)], w: 2, h: 8)
        XCTAssertEqual(px(single, 1, 7), [0x33, 0x66, 0x99, 255])
    }

    func testRepeatedRenderIsServedFromTheCacheWithIdenticalPixels() throws {
        let stops: [GradientRaster.Stop] = [.init(location: 0, rgba: 0x112233ff), .init(location: 1, rgba: 0xddeeffff)]
        let a = try linear(.top, .bottom, stops, w: 16, h: 16)
        let b = try linear(.top, .bottom, stops, w: 16, h: 16)
        XCTAssertEqual(a, b)
    }
}

@MainActor
final class GradientPainterTests: XCTestCase {
    private func commit<V: View>(_ view: V) throws -> (images: FakeImages, upserts: [NodeUpsert]) {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        var upserts: [NodeUpsert] = []
        _ = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { upserts = $0.upserts })
        return (images, upserts)
    }

    private func pixel(_ e: FakeImages.Entry, _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * Int(e.width) + x) * 4
        return Array(e.rgba[i..<i + 4])
    }

    private let black = Color(red: 0, green: 0, blue: 0), white = Color(red: 1, green: 1, blue: 1)

    func testAGradientViewIsOneBitmapOfItsPixelFrame() throws {
        let (images, upserts) = try commit(LinearGradient(colors: [black, white], startPoint: .top, endPoint: .bottom).frame(width: 40, height: 40))
        XCTAssertEqual(images.registered.count, 1)
        let entry = try XCTUnwrap(images.registered.values.first)
        XCTAssertEqual(entry.width, 100); XCTAssertEqual(entry.height, 100)
        XCTAssertEqual(pixel(entry, 0, 0), [1, 1, 1, 255], "row 0 centre is 0.5 px in: 1.27 of 255")
        XCTAssertEqual(pixel(entry, 60, 49), [126, 126, 126, 255])
        XCTAssertEqual(pixel(entry, 3, 50), [129, 129, 129, 255])
        let placements = upserts.flatMap(\.primitives).compactMap { p -> Rect? in if case .image(_, let r, _) = p { return r } else { return nil } }
        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(Int(placements[0].w.rounded()), 100)
    }

    func testAShapeFilledWithAGradientIsMaskedByTheShapesCoverage() throws {
        let (images, _) = try commit(RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [black, white], startPoint: .leading, endPoint: .trailing)).frame(width: 40, height: 40))
        let entry = try XCTUnwrap(images.registered.values.first)
        let w = Int(entry.width), h = Int(entry.height)
        XCTAssertEqual(pixel(entry, 0, 0)[3], 0, "the corner is outside the rounded rectangle")
        XCTAssertEqual(pixel(entry, w / 2, h / 2)[3], 255)
        // the colour is the gradient's, not the mask's: a pixel on the vertical centre line at x = 25 is 25.5 / 100 of the way
        XCTAssertEqual(pixel(entry, 25, h / 2)[0], 65)
        // the edge is anti-aliased: some pixel along the arc is neither 0 nor 255
        var partial = 0
        for y in 0..<h { for x in 0..<w { let a = pixel(entry, x, y)[3]; if a != 0, a != 255 { partial += 1 } } }
        XCTAssertGreaterThan(partial, 0)
        // a plain Rectangle fill needs no mask: every pixel opaque
        let (rect, _) = try commit(Rectangle().fill(LinearGradient(colors: [black, white], startPoint: .leading, endPoint: .trailing)).frame(width: 40, height: 40))
        let flat = try XCTUnwrap(rect.registered.values.first)
        XCTAssertTrue(stride(from: 3, to: flat.rgba.count, by: 4).allSatisfy { flat.rgba[$0] == 255 })
    }

    func testOpacityScalesTheStopsAlpha() throws {
        let (images, _) = try commit(LinearGradient(colors: [black, white], startPoint: .top, endPoint: .bottom).frame(width: 8, height: 8).opacity(0.5))
        let entry = try XCTUnwrap(images.registered.values.first)
        XCTAssertEqual(pixel(entry, 5, 5)[3], 128)
    }

    func testBrightnessAddsToTheStops() throws {
        let (images, _) = try commit(LinearGradient(colors: [black, black], startPoint: .top, endPoint: .bottom).frame(width: 8, height: 8).brightness(0.2))
        let entry = try XCTUnwrap(images.registered.values.first)
        XCTAssertEqual(pixel(entry, 1, 1), [51, 51, 51, 255])
    }

    func testTheBitmapIsReleasedWhenTheGradientGoes() throws {
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: FakeRuns(), log: { _ in })
        let graph = Graph(LinearGradient(colors: [black, white], startPoint: .top, endPoint: .bottom).frame(width: 20, height: 20), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let first = try painter.commit(root: try XCTUnwrap(graph.snapshot()), version: 1, previousLive: [], submit: { _ in })
        XCTAssertEqual(images.live.count, 1)
        let empty = Graph(Text("x"), scale: 2.5)
        empty.rootProposal = ProposedViewSize(width: 320, height: 240)
        empty.flush()
        _ = try painter.commit(root: try XCTUnwrap(empty.snapshot()), version: 2, previousLive: first.live, submit: { _ in })
        XCTAssertEqual(images.live.count, 0)
    }
}
