import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

// Issue #60: Gradient / LinearGradient / RadialGradient. A gradient view is one "Gradient" node carrying a ResolvedGradient; the host rasterises it
// (GradientRaster tests in SwiftRightHostTests).

@MainActor
final class Issue60GradientTests: XCTestCase {
    private let black = Color(red: 0, green: 0, blue: 0)
    private let white = Color(red: 1, green: 1, blue: 1)

    func testColorsGetEvenlySpacedStops() {
        let gradient = Gradient(colors: [Color.red, Color.green, Color.blue])
        XCTAssertEqual(gradient.stops.map(\.location), [0, 0.5, 1])
        XCTAssertEqual(Gradient(colors: [Color.red]).stops.map(\.location), [0])
    }

    func testMidpointBlendOfTwoRGBAColours() {
        let gradient = Gradient(colors: [black, white])
        XCTAssertEqual(gradient.resolvedColor(at: 0.25), .rgba(0.25, 0.25, 0.25, 1))
        XCTAssertEqual(gradient.resolvedColor(at: 0.75), .rgba(0.75, 0.75, 0.75, 1))
    }

    func testColourToClearFadesTheSemanticColoursAlpha() {
        let gradient = Gradient(colors: [Color.blue, Color.clear])
        XCTAssertEqual(gradient.resolvedColor(at: 0.25), .semanticAlpha("system.blue", 0.75))
        XCTAssertEqual(gradient.resolvedColor(at: 0.75), .semanticAlpha("system.blue", 0.25))
    }

    func testStopsAreOrderedAndClamped() {
        let style = LinearGradient(stops: [Gradient.Stop(color: white, location: 1.5), Gradient.Stop(color: black, location: -0.5), Gradient.Stop(color: Color.red, location: 0.5)],
                                   startPoint: .top, endPoint: .bottom)
        XCTAssertEqual(style.resolved.stops.map(\.location), [0, 0.5, 1])
        XCTAssertEqual(style.resolved.stops.map(\.color), [.rgba(0, 0, 0, 1), .semantic("system.red"), .rgba(1, 1, 1, 1)])
        let equal = LinearGradient(stops: [Gradient.Stop(color: black, location: 0.5), Gradient.Stop(color: white, location: 0.5)], startPoint: .top, endPoint: .bottom)
        XCTAssertEqual(equal.resolved.stops.map(\.color), [.rgba(0, 0, 0, 1), .rgba(1, 1, 1, 1)], "equal locations keep their order (a hard edge)")
    }

    func testAsAShapeStyleItResolvesToItsMidpointColour() {
        let gradient = LinearGradient(colors: [Color.blue, Color.clear], startPoint: .top, endPoint: .bottom)
        XCTAssertEqual(gradient.resolvedColor, .semanticAlpha("system.blue", 0.5))
        let graph = i60Graph(Rectangle().fill(AnyShapeStyle(gradient)).frame(width: 20, height: 20))
        XCTAssertEqual(i60Nodes(graph, kind: "Rectangle").first?.shape?.paint?.color, .semanticAlpha("system.blue", 0.5))
    }

    func testALinearGradientViewIsOneNodeThatFillsTheFrame() throws {
        let style = LinearGradient(colors: [black, white], startPoint: .topLeading, endPoint: .bottomTrailing)
        let graph = i60Graph(style.frame(width: 40, height: 64))
        let nodes = i60Nodes(graph, kind: "Gradient")
        XCTAssertEqual(nodes.count, 1)
        let node = try XCTUnwrap(nodes.first)
        XCTAssertEqual(node.frame.width, 40); XCTAssertEqual(node.frame.height, 64)
        XCTAssertEqual(node.gradient?.geometry, .linear(start: .topLeading, end: .bottomTrailing))
        XCTAssertEqual(node.gradient?.stops, [ResolvedGradient.Stop(location: 0, color: .rgba(0, 0, 0, 1)), ResolvedGradient.Stop(location: 1, color: .rgba(1, 1, 1, 1))])
        XCTAssertEqual(i60Nodes(graph, kind: "Color").count, 0, "no stacked bands any more")
    }

    func testAGradientWithNothingProposedIsAShapesTenPointSquare() throws {
        let graph = i60Graph(LinearGradient(colors: [black, white], startPoint: .top, endPoint: .bottom), width: nil, height: nil)
        let node = try XCTUnwrap(i60Nodes(graph, kind: "Gradient").first)
        XCTAssertEqual(node.frame.width, 10); XCTAssertEqual(node.frame.height, 10)
    }

    func testRadialGradientCarriesCentreAndRadii() throws {
        let style = RadialGradient(colors: [Color.red, Color.blue], center: .topLeading, startRadius: 4, endRadius: 30)
        let graph = i60Graph(style.frame(width: 60, height: 60))
        let node = try XCTUnwrap(i60Nodes(graph, kind: "Gradient").first)
        XCTAssertEqual(node.gradient?.geometry, .radial(center: .topLeading, startRadius: 4, endRadius: 30))
        XCTAssertEqual(node.gradient?.stops.count, 2)
    }

    func testShapeFillWithAGradientIsTheGradientClippedToTheShape() throws {
        let style = LinearGradient(colors: [Color.blue, Color.clear], startPoint: .top, endPoint: .bottom)
        let graph = i60Graph(RoundedRectangle(cornerRadius: 8).fill(style).frame(width: 80, height: 40))
        XCTAssertEqual(i60Nodes(graph, kind: "Gradient").count, 1)
        let clip = try XCTUnwrap(i60Nodes(graph, kind: "modifier.clipShape").first)
        XCTAssertEqual(clip.frame.width, 80)
        XCTAssertEqual(clip.frame.height, 40)
        XCTAssertEqual(clip.clipShape?.geometry, .roundedRectangle(cornerRadius: 8, style: .continuous))
        let radial = i60Graph(Circle().fill(RadialGradient(colors: [Color.red, Color.blue], center: .center, startRadius: 0, endRadius: 20)).frame(width: 40, height: 40))
        XCTAssertEqual(i60Nodes(radial, kind: "Gradient").count, 1)
        XCTAssertEqual(i60Nodes(radial, kind: "modifier.clipShape").first?.clipShape?.geometry, .circle)
    }

    func testBackgroundGradientIsBehindTheViewAndKeepsItsSize() throws {
        let style = LinearGradient(colors: [black, white], startPoint: .top, endPoint: .bottom)
        let graph = i60Graph(Text("hello").padding(10).background(style), width: nil, height: nil)
        let node = try XCTUnwrap(i60Nodes(graph, kind: "Gradient").first)
        let text = try XCTUnwrap(i60Text(graph, "hello"))
        XCTAssertEqual(Double(node.frame.width), Double(text.frame.width) + 20, accuracy: 0.5)
        XCTAssertEqual(Double(node.frame.height), Double(text.frame.height) + 20, accuracy: 0.5)
    }
}
