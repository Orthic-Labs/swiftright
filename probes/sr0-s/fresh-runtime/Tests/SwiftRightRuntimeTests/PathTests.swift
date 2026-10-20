import Foundation
@testable import SwiftRightRuntime
import XCTest

/// F-path P1: the `Path` builders, transforms, trimming and the shape API that carries paths to the host.
@MainActor
final class PathTests: XCTestCase {
    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private func endPoint(_ e: Path.Element) -> CGPoint? {
        switch e {
        case .move(let p), .line(let p): return p
        case .quadCurve(let p, _), .curve(let p, _, _): return p
        case .closeSubpath: return nil
        }
    }

    private func assertPoint(_ p: CGPoint?, _ x: Double, _ y: Double, accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
        guard let p else { return XCTFail("no point", file: file, line: line) }
        XCTAssertEqual(Double(p.x), x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(Double(p.y), y, accuracy: accuracy, file: file, line: line)
    }

    // MARK: Builders

    func testLineQuadAndCubicElements() {
        var p = Path()
        p.move(to: pt(1, 2))
        p.addLine(to: pt(3, 4))
        p.addQuadCurve(to: pt(5, 6), control: pt(4, 7))
        p.addCurve(to: pt(7, 8), control1: pt(6, 9), control2: pt(8, 9))
        p.closeSubpath()
        XCTAssertEqual(p.elements, [.move(to: pt(1, 2)), .line(to: pt(3, 4)), .quadCurve(to: pt(5, 6), control: pt(4, 7)),
                                    .curve(to: pt(7, 8), control1: pt(6, 9), control2: pt(8, 9)), .closeSubpath])
        var seen = 0
        p.forEach { _ in seen += 1 }
        XCTAssertEqual(seen, 5)
    }

    func testAddLineWithoutACurrentPointStartsASubpath() {
        var p = Path()
        p.addLine(to: pt(2, 3))
        XCTAssertEqual(p.elements, [.move(to: pt(2, 3))])
    }

    func testDrawingAfterCloseStartsANewSubpathAtTheClosedStart() {
        var p = Path()
        p.move(to: pt(1, 1)); p.addLine(to: pt(5, 1)); p.closeSubpath()
        p.addLine(to: pt(9, 9))
        XCTAssertEqual(p.elements, [.move(to: pt(1, 1)), .line(to: pt(5, 1)), .closeSubpath, .move(to: pt(1, 1)), .line(to: pt(9, 9))])
    }

    func testRectElementsRunClockwiseFromTheOrigin() {
        XCTAssertEqual(Path(CGRect(x: 1, y: 2, width: 10, height: 20)).elements,
                       [.move(to: pt(1, 2)), .line(to: pt(11, 2)), .line(to: pt(11, 22)), .line(to: pt(1, 22)), .closeSubpath])
    }

    func testEllipseStartsAtThreeOClockAndRunsVisuallyClockwiseInFourCubics() {
        let p = Path(ellipseIn: CGRect(x: 10, y: 20, width: 100, height: 60))
        XCTAssertEqual(p.elements.count, 6)
        assertPoint(endPoint(p.elements[0]), 110, 50)
        // 3 o'clock -> 6 o'clock (y down) -> 9 -> 12 -> 3
        assertPoint(endPoint(p.elements[1]), 60, 80)
        assertPoint(endPoint(p.elements[2]), 10, 50)
        assertPoint(endPoint(p.elements[3]), 60, 20)
        assertPoint(endPoint(p.elements[4]), 110, 50)
        XCTAssertEqual(p.elements[5], .closeSubpath)
        for e in p.elements[1...4] { guard case .curve = e else { return XCTFail("cubic expected") } }
    }

    func testAddArcSweepsInIncreasingAngleWhenClockwiseIsFalse() {
        // y-down space: angle 0 is 3 o'clock, 90 degrees is 6 o'clock; clockwise false = increasing angle = visually clockwise.
        var p = Path()
        p.addArc(center: pt(0, 0), radius: 10, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        XCTAssertEqual(p.elements.count, 2)
        assertPoint(endPoint(p.elements[0]), 10, 0)
        assertPoint(endPoint(p.elements[1]), 0, 10)
    }

    func testAddArcWithClockwiseTrueSweepsTheLongWayRoundVisuallyCounterClockwise() {
        var p = Path()
        p.addArc(center: pt(0, 0), radius: 10, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: true)
        // 0 -> -90 -> -180 -> -270: three quadrant cubics; the first ends at 12 o'clock (0, -10), the last at 6 o'clock (0, 10)
        XCTAssertEqual(p.elements.count, 4)
        assertPoint(endPoint(p.elements[1]), 0, -10)
        assertPoint(endPoint(p.elements[2]), -10, 0)
        assertPoint(endPoint(p.elements[3]), 0, 10)
    }

    func testAddArcQuadrantSplitsAndControlPointsLieOnTheTangents() {
        func curves(_ degrees: Double, clockwise: Bool = false) -> Int {
            var p = Path()
            p.addArc(center: pt(0, 0), radius: 10, startAngle: .degrees(0), endAngle: .degrees(degrees), clockwise: clockwise)
            return p.elements.count - 1
        }
        XCTAssertEqual(curves(90), 1)
        XCTAssertEqual(curves(100), 2)
        XCTAssertEqual(curves(180), 2)
        XCTAssertEqual(curves(270), 3)
        XCTAssertEqual(curves(360), 4)
        XCTAssertEqual(curves(720), 4, "a sweep of two pi or more is one full circle")
        XCTAssertEqual(curves(0), 0, "equal angles draw nothing past the start point")
        var p = Path()
        p.addArc(center: pt(0, 0), radius: 10, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        guard case .curve(_, let c1, let c2) = p.elements[1] else { return XCTFail() }
        let k = 4.0 / 3.0 * tan(Double.pi / 8) * 10
        assertPoint(c1, 10, k)
        assertPoint(c2, k, 10)
    }

    func testAddArcJoinsTheCurrentPointWithALine() {
        var p = Path()
        p.move(to: pt(0, 0))
        p.addArc(center: pt(10, 0), radius: 10, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        XCTAssertEqual(p.elements[1], .line(to: pt(20, 0)))
    }

    func testRoundedRectElementsAreFourLinesFourCurvesAndClose() {
        let p = Path(roundedRect: CGRect(x: 0, y: 0, width: 40, height: 20), cornerRadius: 5)
        XCTAssertEqual(p.elements.count, 10)
        assertPoint(endPoint(p.elements[0]), 5, 0)
        assertPoint(endPoint(p.elements[1]), 35, 0)
        assertPoint(endPoint(p.elements[2]), 40, 5)
        // a radius past half the short side clamps to it: a pill has no straight short edges
        let pill = Path(roundedRect: CGRect(x: 0, y: 0, width: 40, height: 20), cornerRadius: 99)
        XCTAssertEqual(pill.boundingRect.height, 20, accuracy: 1e-9)
        // a zero radius is a rect
        XCTAssertEqual(Path(roundedRect: CGRect(x: 0, y: 0, width: 4, height: 4), cornerRadius: 0), Path(CGRect(x: 0, y: 0, width: 4, height: 4)))
    }

    func testClosureInitAndAddPath() {
        let p = Path { $0.move(to: CGPoint(x: 0, y: 0)); $0.addLine(to: CGPoint(x: 1, y: 1)) }
        var q = Path(CGRect(x: 0, y: 0, width: 2, height: 2))
        q.addPath(p)
        XCTAssertEqual(q.elements.count, 5 + 2)
    }

    // MARK: Transforms and bounds

    func testApplyingAndOffsetBy() {
        let p = Path(CGRect(x: 0, y: 0, width: 10, height: 20))
        let scaled = p.applying(CGAffineTransform(scaleX: 2, y: 3))
        XCTAssertEqual(scaled.elements[2], .line(to: pt(20, 60)))
        let moved = p.offsetBy(dx: 5, dy: -1)
        XCTAssertEqual(moved.elements[0], .move(to: pt(5, -1)))
        XCTAssertEqual(moved.elements[2], .line(to: pt(15, 19)))
        // a rotation by 90 degrees (a, b, c, d = 0, 1, -1, 0): (x, y) -> (-y, x)
        let rotated = p.applying(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0))
        XCTAssertEqual(rotated.elements[1], .line(to: pt(0, 10)))
        XCTAssertEqual(rotated.elements[2], .line(to: pt(-20, 10)))
    }

    func testBoundingRectIsTightAroundCurves() {
        let circle = Path(ellipseIn: CGRect(x: 10, y: 20, width: 100, height: 60)).boundingRect
        XCTAssertEqual(Double(circle.minX), 10, accuracy: 1e-9); XCTAssertEqual(Double(circle.maxX), 110, accuracy: 1e-9)
        XCTAssertEqual(Double(circle.minY), 20, accuracy: 1e-9); XCTAssertEqual(Double(circle.maxY), 80, accuracy: 1e-9)
        var arch = Path()
        arch.move(to: pt(0, 0)); arch.addQuadCurve(to: pt(10, 0), control: pt(5, 10))
        XCTAssertEqual(Double(arch.boundingRect.maxY), 5, accuracy: 1e-9, "the quad peaks at half the control height, not at the control point")
        XCTAssertEqual(Path().boundingRect, .zero)
    }

    // MARK: Trimming

    func testCircleTrimLengthIsTheFractionOfTheArcLength() {
        let r = 50.0
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r))
        // The Bezier circle is within 3e-4 of a true circle in radius: lengths agree to better than 1e-3 relative.
        XCTAssertEqual(Double(circle.arcLength), 2 * Double.pi * r, accuracy: 2 * Double.pi * r * 1e-3)
        let trimmed = circle.trimmedPath(from: 0, to: 0.62)
        let expected = 0.62 * 2 * Double.pi * r
        XCTAssertEqual(Double(trimmed.arcLength), expected, accuracy: expected * 1e-3)
        XCTAssertEqual(Double(trimmed.arcLength), 0.62 * Double(circle.arcLength), accuracy: 1e-6, "exactly the fraction of the measured length")
        // starts at 3 o'clock
        assertPoint(endPoint(trimmed.elements[0]), 100, 50)
    }

    func testQuarterTrimEndsAtSixOClockAndIsASingleOpenSubpath() {
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100))
        let quarter = circle.trimmedPath(from: 0, to: 0.25)
        assertPoint(endPoint(quarter.elements.last!), 50, 100, accuracy: 1e-6)
        XCTAssertEqual(quarter.elements.filter { if case .move = $0 { return true }; return false }.count, 1)
        XCTAssertFalse(quarter.elements.contains(.closeSubpath))
    }

    func testTrimOfARectIsExactAndWrapsAcrossCorners() {
        let rect = Path(CGRect(x: 0, y: 0, width: 10, height: 10))      // length 40 with the closing edge
        XCTAssertEqual(Double(rect.arcLength), 40, accuracy: 1e-9)
        let piece = rect.trimmedPath(from: 0.125, to: 0.375)            // arc length 5 ... 15
        XCTAssertEqual(piece.elements, [.move(to: pt(5, 0)), .line(to: pt(10, 0)), .line(to: pt(10, 5))])
        XCTAssertEqual(Double(piece.arcLength), 10, accuracy: 1e-9)
        let closing = rect.trimmedPath(from: 0.9, to: 1)                // inside the closing edge (x = 0, y from 10 up to 0)
        XCTAssertEqual(closing.elements.count, 2)
        assertPoint(endPoint(closing.elements[0]), 0, 4)
        assertPoint(endPoint(closing.elements[1]), 0, 0)
    }

    func testDegenerateTrims() {
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertTrue(circle.trimmedPath(from: 0, to: 0).isEmpty)
        XCTAssertTrue(circle.trimmedPath(from: 0.5, to: 0.2).isEmpty)
        XCTAssertEqual(circle.trimmedPath(from: -1, to: 2), circle, "0...1 after clamping is the path itself")
        XCTAssertEqual(Double(circle.trimmedPath(from: 0, to: 0.02).arcLength), 0.02 * Double(circle.arcLength), accuracy: 1e-6)
        XCTAssertTrue(Path().trimmedPath(from: 0, to: 0.5).isEmpty)
    }

    func testTrimSpansSubpathsInOrder() {
        var p = Path()
        p.move(to: pt(0, 0)); p.addLine(to: pt(10, 0))
        p.move(to: pt(0, 5)); p.addLine(to: pt(10, 5))
        let t = p.trimmedPath(from: 0.25, to: 0.75)                    // 5 ... 15 of 20
        XCTAssertEqual(t.elements, [.move(to: pt(5, 0)), .line(to: pt(10, 0)), .move(to: pt(0, 5)), .line(to: pt(5, 5))])
    }

    // MARK: Shape API

    func testShapeGeometryResolvesLikeTheSwiftUIShapes() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        XCTAssertEqual(Circle().path(in: rect).boundingRect.width, 40, accuracy: 1e-9)
        XCTAssertEqual(Rectangle().path(in: rect), Path(rect))
        XCTAssertEqual(RoundedRectangle(cornerRadius: 4, style: .circular).path(in: rect), Path(roundedRect: rect, cornerRadius: 4))
        let capsule = Capsule(style: .circular).path(in: rect)
        XCTAssertEqual(Double(capsule.boundingRect.height), 40, accuracy: 1e-9)
        XCTAssertEqual(Capsule().shapeGeometry, .capsule(style: .continuous))
        let continuous = RoundedRectangle(cornerRadius: 8).path(in: rect)
        XCTAssertEqual(continuous.elements.count, 18, "three cubics per corner (existing continuous-corner geometry)")
    }

    func testInsetShrinksTheRectAndTheRadiusAndSumsNestedInsets() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let inset = Circle().inset(by: 5)
        XCTAssertEqual(inset.shapeGeometry, .inset(.circle, by: 5))
        let b = inset.path(in: rect).boundingRect
        XCTAssertEqual(Double(b.minX), 5, accuracy: 1e-9); XCTAssertEqual(Double(b.width), 90, accuracy: 1e-9)
        XCTAssertEqual(inset.inset(by: 2).shapeGeometry, .inset(.circle, by: 7))
        let rr = RoundedRectangle(cornerRadius: 10, style: .circular).inset(by: 4).path(in: rect)
        XCTAssertEqual(rr, Path(roundedRect: CGRect(x: 4, y: 4, width: 92, height: 92), cornerRadius: 6))
        XCTAssertTrue(Rectangle().inset(by: 60).path(in: rect).isEmpty, "an inset past the centre leaves nothing")
        XCTAssertEqual(Capsule(style: .circular).inset(by: 3).path(in: CGRect(x: 0, y: 0, width: 50, height: 20)).boundingRect.height, 14, accuracy: 1e-9)
    }

    func testTrimGeometryComposesWithInset() {
        let g = Circle().inset(by: 3).trim(from: 0, to: 0.5).shapeGeometry
        XCTAssertEqual(g, .trimmed(.inset(.circle, by: 3), from: 0, to: 0.5))
        XCTAssertEqual(g.kindName, "Circle")
        let half = g.makePath(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(Double(half.arcLength), 0.5 * Double.pi * 94, accuracy: 0.5 * Double.pi * 94 * 1e-3)
    }

    private struct Wedge: Shape {
        var size: CGFloat
        @MainActor var body: Never { fatalError() }
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX + size, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.closeSubpath()
            }
        }
    }

    func testACustomShapeOverridesPathInAndCarriesItInItsGeometry() {
        let w = Wedge(size: 7)
        guard case .custom(let custom) = w.shapeGeometry else { return XCTFail("custom geometry expected") }
        let p = custom.path(in: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(p.elements[1], .line(to: pt(7, 10)))
        XCTAssertEqual(w.shapeGeometry, Wedge(size: 7).shapeGeometry)
        XCTAssertNotEqual(w.shapeGeometry, Wedge(size: 8).shapeGeometry)
        XCTAssertEqual(w.shapeGeometry.kindName, "Path")
        XCTAssertEqual(Path().shapeGeometry, .path(Path()))
    }

    func testStrokeAndFillStylesAreRecordedOnTheNode() {
        let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .bevel, miterLimit: 3, dash: [4, 2], dashPhase: 1)
        let graph = Graph(Circle().inset(by: 2).trim(from: 0, to: 0.62).stroke(Color.blue, style: style))
        graph.rootProposal = ProposedViewSize(width: 40, height: 40)
        graph.flush()
        let node = graph.snapshot()
        XCTAssertEqual(node?.kind, "Circle")
        XCTAssertEqual(node?.shape?.geometry, .trimmed(.inset(.circle, by: 2), from: 0, to: 0.62))
        XCTAssertEqual(node?.shape?.paint?.kind, .stroke)
        XCTAssertEqual(node?.shape?.paint?.lineWidth, 4)
        XCTAssertEqual(node?.shape?.paint?.strokeStyle, style)

        let plain = Graph(Circle().stroke(Color.blue, lineWidth: 3))
        plain.rootProposal = ProposedViewSize(width: 40, height: 40)
        plain.flush()
        XCTAssertNil(plain.snapshot()?.shape?.paint?.strokeStyle, "a plain stroke records no style")
        XCTAssertNil(plain.snapshot()?.shape?.paint?.fillStyle)

        let eo = Graph(Path(CGRect(x: 0, y: 0, width: 4, height: 4)).fill(Color.red, style: FillStyle(eoFill: true)))
        eo.rootProposal = ProposedViewSize(width: 40, height: 40)
        eo.flush()
        XCTAssertEqual(eo.snapshot()?.kind, "Path")
        XCTAssertEqual(eo.snapshot()?.shape?.paint?.fillStyle, FillStyle(eoFill: true))
    }

    func testStrokeBorderInsetsByHalfTheLineWidth() {
        let graph = Graph(Circle().strokeBorder(Color.green, lineWidth: 6))
        graph.rootProposal = ProposedViewSize(width: 40, height: 40)
        graph.flush()
        XCTAssertEqual(graph.snapshot()?.shape?.geometry, .inset(.circle, by: 3))
        XCTAssertEqual(graph.snapshot()?.shape?.paint?.lineWidth, 6)
    }

    func testAngleConversions() {
        XCTAssertEqual(Angle.degrees(180).radians, Double.pi, accuracy: 1e-12)
        XCTAssertEqual(Angle(radians: Double.pi / 2).degrees, 90, accuracy: 1e-12)
        XCTAssertLessThan(Angle.degrees(10), Angle.degrees(20))
    }
}
