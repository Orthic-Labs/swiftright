import XCTest
@testable import SwiftRightHost
import SwiftRightBridge
import SwiftRightRuntime

// Issue #69: a bitmap under `.rotationEffect` is resampled through the rotation by the host and drawn 1:1 (the renderer transform is translation only).
@MainActor
final class Issue69RotatedImageTests: XCTestCase {
    /// A quarter turn of a 4 x 2 bitmap about its centre is an exact permutation of its pixels into a 2 x 4 bitmap.
    func testQuarterTurnPermutesPixels() throws {
        let w = 4, h = 2
        let rgba: [UInt8] = (0..<w * h).flatMap { i -> [UInt8] in [UInt8(i * 30), UInt8(255 - i * 30), 7, 255] }
        let placement = Rect(x: 10, y: 20, w: 4, h: 2)
        let turn = ShapeRotation(radians: .pi / 2, anchorX: 12, anchorY: 21).transform
        let out = try XCTUnwrap(RotatedRaster.rotate(rgba: rgba, width: w, height: h, placement: placement, transform: turn))
        XCTAssertEqual(out.placement, Rect(x: 11, y: 19, w: 2, h: 4))
        XCTAssertEqual(out.image.width, 2); XCTAssertEqual(out.image.height, 4)
        // y-down clockwise quarter turn: destination (x, y) shows source (y, h - 1 - x)
        for y in 0..<4 { for x in 0..<2 {
            let si = ((h - 1 - x) * w + y) * 4, di = (y * 2 + x) * 4
            XCTAssertEqual(Array(out.image.rgba[di..<di + 4]), Array(rgba[si..<si + 4]), "pixel \(x),\(y)")
        } }
    }

    /// A 30 degree turn keeps the coverage (area) and leaves anti-aliased edges.
    func testThirtyDegreesKeepsAreaAndAntialiasesEdges() throws {
        let rgba = [UInt8](repeating: 255, count: 20 * 10 * 4)
        let turn = ShapeRotation(radians: .pi / 6, anchorX: 10, anchorY: 5).transform
        let out = try XCTUnwrap(RotatedRaster.rotate(rgba: rgba, width: 20, height: 10, placement: Rect(x: 0, y: 0, w: 20, h: 10), transform: turn))
        let alphas = stride(from: 3, to: out.image.rgba.count, by: 4).map { Double(out.image.rgba[$0]) / 255 }
        // area coverage of the rectangle inset by 0.2 texels on each side: 19.6 x 9.6
        XCTAssertEqual(alphas.reduce(0, +), 19.6 * 9.6, accuracy: 2)
        XCTAssertGreaterThan(alphas.filter { $0 > 0.05 && $0 < 0.95 }.count, 20, "edges are partial coverage")
    }

    /// The painter draws a rotated pixel Image as one rotated bitmap and no longer reports it as a limitation.
    func testPainterRotatesAPixelImage() throws {
        let src = RGBAImage(width: 8, height: 4, rgba: [UInt8](repeating: 200, count: 8 * 4 * 4))!
        let graph = Graph(Image(decorative: src, scale: 1).resizable().frame(width: 8, height: 4).rotationEffect(.degrees(90)), scale: 1)
        graph.rootProposal = ProposedViewSize(width: 100, height: 100)
        graph.flush()
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 1, log: { _ in })
        let node = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.image != nil })
        let f = node.pixelFrame
        let bounds = Rect(x: Float(f.x), y: Float(f.y), w: Float(f.width), h: Float(f.height))
        let turn = ShapeRotation(radians: .pi / 2, anchorX: Double(bounds.x + bounds.w / 2), anchorY: Double(bounds.y + bounds.h / 2))
        painter.beginCommit()
        let out = try painter.emit(node, id: 1, bounds: bounds, rotations: [turn])
        painter.endCommit(committed: true)
        guard case .image(let handle, _, _)? = out.primitives.first else { return XCTFail("no image") }
        XCTAssertEqual(images.registered[handle.raw]?.width, 4)
        XCTAssertEqual(images.registered[handle.raw]?.height, 8)
        XCTAssertEqual(painter.rotationLimitationCount, 0)
    }
}

// Issue #69: Text under `.rotationEffect` is filled from the run's glyph outlines (renderer rev 0.14), rotated in window pixels.
@MainActor
final class Issue69RotatedTextTests: XCTestCase {
    private func emitRotated(_ fake: StyledFake) throws -> (NodeEmission, FakeImages, ResolvedNodePainter) {
        let graph = Graph(Text("Hi").rotationEffect(.degrees(45)), measurer: fake, scale: 1)
        graph.rootProposal = ProposedViewSize(width: 200, height: 200)
        graph.flush()
        let images = FakeImages()
        let painter = ResolvedNodePainter(images: images, scale: 1, text: fake, log: { _ in })
        let node = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "Text" })
        let f = node.pixelFrame
        let bounds = Rect(x: Float(f.x), y: Float(f.y), w: Float(f.width), h: Float(f.height))
        let turn = ShapeRotation(radians: .pi / 4, anchorX: Double(bounds.x + bounds.w / 2), anchorY: Double(bounds.y + bounds.h / 2))
        painter.beginCommit()
        let out = try painter.emit(node, id: 1, bounds: bounds, rotations: [turn])
        painter.endCommit(committed: true)
        return (out, images, painter)
    }

    func testRotatedTextIsFilledFromItsOutline() throws {
        let fake = StyledFake(); fake.squareOutlines = true
        let (out, images, painter) = try emitRotated(fake)
        XCTAssertEqual(out.primitives.count, 1)
        guard case .image(let handle, _, _)? = out.primitives.first, let entry = images.registered[handle.raw] else { return XCTFail("no bitmap") }
        let coverage = stride(from: 3, to: entry.rgba.count, by: 4).reduce(0.0) { $0 + Double(entry.rgba[$1]) / 255 }
        XCTAssertEqual(coverage, 100, accuracy: 3, "the 10 x 10 square keeps its area when turned")
        XCTAssertGreaterThan(entry.width, 12, "a square turned 45 degrees is wider than it was")
        XCTAssertEqual(painter.rotationLimitationCount, 0)
        XCTAssertEqual(out.semantic?.label, "Hi")
    }

    func testWithoutOutlinesTheRunStaysAndIsReported() throws {
        let (out, _, painter) = try emitRotated(StyledFake())
        guard case .text? = out.primitives.first else { return XCTFail("the run is kept") }
        XCTAssertEqual(painter.rotationLimitationCount, 1)
    }
}
