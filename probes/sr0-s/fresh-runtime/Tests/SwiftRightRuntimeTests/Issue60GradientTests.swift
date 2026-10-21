import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: Gradient / LinearGradient (composed from solid bands; the host has no gradient fill).

@MainActor
final class Issue60GradientTests: XCTestCase {
    private let black = Color(red: 0, green: 0, blue: 0)
    private let white = Color(red: 1, green: 1, blue: 1)

    func testColorsGetEvenlySpacedStops() {
        let gradient = Gradient(colors: [Color.red, Color.green, Color.blue])
        XCTAssertEqual(gradient.stops.map(\.location), [0, 0.5, 1])
        XCTAssertEqual(Gradient(colors: [Color.red]).stops.map(\.location), [0])
    }

    func testRGBAColoursBlendLinearlyAtBandCentres() {
        let gradient = LinearGradient(colors: [black, white], startPoint: .top, endPoint: .bottom)
        XCTAssertEqual(gradient.bandColor(0, of: 2), .rgba(0.25, 0.25, 0.25, 1))
        XCTAssertEqual(gradient.bandColor(1, of: 2), .rgba(0.75, 0.75, 0.75, 1))
    }

    func testColourToClearFadesTheSemanticColoursAlpha() {
        let gradient = LinearGradient(colors: [Color.blue, Color.clear], startPoint: .top, endPoint: .bottom)
        XCTAssertEqual(gradient.bandColor(0, of: 2), .semanticAlpha("system.blue", 0.75))
        XCTAssertEqual(gradient.bandColor(1, of: 2), .semanticAlpha("system.blue", 0.25))
    }

    func testTwoDifferentSemanticColoursStepAtTheMidpoint() {
        let gradient = LinearGradient(colors: [Color.red, Color.blue], startPoint: .top, endPoint: .bottom)
        XCTAssertEqual(gradient.bandColor(0, of: 4), .semantic("system.red"))
        XCTAssertEqual(gradient.bandColor(3, of: 4), .semantic("system.blue"))
    }

    func testStopsOutsideTheirRangeClampAndUnsortedStopsAreOrdered() {
        let gradient = LinearGradient(stops: [Gradient.Stop(color: white, location: 0.8), Gradient.Stop(color: black, location: 0.2)],
                                      startPoint: .top, endPoint: .bottom)
        XCTAssertEqual(gradient.gradient.resolvedColor(at: 0), .rgba(0, 0, 0, 1))
        XCTAssertEqual(gradient.gradient.resolvedColor(at: 1), .rgba(1, 1, 1, 1))
        guard case .rgba(let r, let g, let b, let a) = gradient.gradient.resolvedColor(at: 0.5) else { return XCTFail("not an rgba colour") }
        XCTAssertEqual(r, 0.5, accuracy: 1e-9); XCTAssertEqual(g, 0.5, accuracy: 1e-9); XCTAssertEqual(b, 0.5, accuracy: 1e-9); XCTAssertEqual(a, 1)
    }

    func testAxisIsTheDominantDirectionAndReversedWhenEndPrecedesStart() {
        XCTAssertTrue(LinearGradient(colors: [black, white], startPoint: .top, endPoint: .bottom).isVertical)
        XCTAssertFalse(LinearGradient(colors: [black, white], startPoint: .leading, endPoint: .trailing).isVertical)
        let reversed = LinearGradient(colors: [black, white], startPoint: .bottom, endPoint: .top)
        XCTAssertEqual(reversed.bandColor(0, of: 2), .rgba(0.75, 0.75, 0.75, 1))
    }

    func testDegenerateGradientIsItsFirstColour() {
        let gradient = LinearGradient(colors: [black, white], startPoint: .center, endPoint: .center)
        XCTAssertEqual(gradient.bandColor(5), .rgba(0, 0, 0, 1))
    }

    func testAsAShapeStyleItResolvesToItsMidpointColour() {
        let gradient = LinearGradient(colors: [Color.blue, Color.clear], startPoint: .top, endPoint: .bottom)
        XCTAssertEqual(gradient.resolvedColor, .semanticAlpha("system.blue", 0.5))
        let graph = i60Graph(Rectangle().fill(AnyShapeStyle(gradient)).frame(width: 20, height: 20))
        XCTAssertEqual(i60Nodes(graph, kind: "Rectangle").first?.shape?.paint?.color, .semanticAlpha("system.blue", 0.5))
    }

    func testAGradientViewIsStackedBandsThatFillTheFrame() {
        let gradient = LinearGradient(colors: [black, white], startPoint: .top, endPoint: .bottom)
        let graph = i60Graph(gradient.frame(width: 40, height: 64))
        let bands = i60Nodes(graph, kind: "Color")
        XCTAssertEqual(bands.count, LinearGradient.bandCount)
        XCTAssertTrue(bands.allSatisfy { $0.frame.width == 40 && $0.frame.height == 2 })
        XCTAssertEqual(bands.first?.color, gradient.bandColor(0))
        XCTAssertEqual(bands.last?.color, gradient.bandColor(LinearGradient.bandCount - 1))
        let ys = bands.map { Double($0.frame.minY) }
        XCTAssertEqual(ys, ys.sorted())
    }

    func testHorizontalGradientStacksBandsLeftToRight() {
        let gradient = LinearGradient(colors: [black, white], startPoint: .leading, endPoint: .trailing)
        let graph = i60Graph(gradient.frame(width: 64, height: 10))
        let bands = i60Nodes(graph, kind: "Color")
        XCTAssertEqual(bands.count, LinearGradient.bandCount)
        XCTAssertTrue(bands.allSatisfy { $0.frame.width == 2 && $0.frame.height == 10 })
        XCTAssertEqual(i60Nodes(graph, kind: "HStack").count, 1)
    }

    func testShapeFillWithAGradientClipsTheBandsToTheShape() {
        let gradient = LinearGradient(colors: [Color.blue, Color.clear], startPoint: .top, endPoint: .bottom)
        let graph = i60Graph(Rectangle().fill(gradient).frame(width: 80, height: 40))
        XCTAssertEqual(i60Nodes(graph, kind: "Color").count, LinearGradient.bandCount)
        let clip = i60Nodes(graph, kind: "modifier.clipShape").first
        XCTAssertEqual(clip?.frame.width, 80)
        XCTAssertEqual(clip?.frame.height, 40)
        XCTAssertEqual(clip?.clipShape?.geometry, .rectangle)
    }

    func testBackgroundGradientIsBehindTheViewAndKeepsItsSize() {
        let gradient = LinearGradient(colors: [black, white], startPoint: .top, endPoint: .bottom)
        let graph = i60Graph(Text("hello").padding(10).background(gradient), width: nil, height: nil)
        XCTAssertEqual(i60Nodes(graph, kind: "Color").count, LinearGradient.bandCount)
        let text = i60Text(graph, "hello")
        let bands = i60Nodes(graph, kind: "Color")
        let spanTop = bands.map { Double($0.frame.minY) }.min() ?? -1
        XCTAssertEqual(spanTop, Double(graph.snapshot()?.frame.minY ?? 0), accuracy: 0.5)
        XCTAssertEqual(Double(bands.first?.frame.width ?? 0), Double(text?.frame.width ?? 0) + 20, accuracy: 0.5)
    }
}
