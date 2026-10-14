import Foundation
import SwiftRightRuntime
import XCTest

// SR1 round 4, block swiftui.spacer-divider: layout facts measured on macOS 27 SwiftUI (factory/pipeline/blocks-21-23/swiftui.spacer-divider, scale 2.5).

private struct DefaultSpacerRow: View {
    let width: CGFloat
    var body: some View {
        HStack { Color.red.frame(width: 40, height: 20); Spacer(); Color.blue.frame(width: 40, height: 20) }.frame(width: width, height: 20)
    }
}

private struct ZeroMinSpacerRow: View {
    var body: some View {
        HStack { Color.red.frame(width: 40, height: 20); Spacer(minLength: 0); Color.blue.frame(width: 40, height: 20) }.frame(width: 80, height: 20)
    }
}

private struct ExplicitSpacingSpacerRow: View {
    var body: some View {
        HStack(spacing: 20) { Color.red.frame(width: 40, height: 20); Spacer(); Color.blue.frame(width: 40, height: 20) }.frame(width: 80, height: 20)
    }
}

private struct DefaultSpacingMixedRow: View {
    var body: some View {
        HStack { Color.red.frame(width: 30, height: 20); Color.blue.frame(width: 30, height: 20); Spacer(minLength: 0); Color.green.frame(width: 30, height: 20) }.frame(width: 100, height: 20)
    }
}

private struct VerticalSpacerColumn: View {
    var body: some View {
        VStack { Color.red.frame(width: 20, height: 20); Spacer(); Color.blue.frame(width: 20, height: 20) }.frame(width: 20, height: 44)
    }
}

private struct HorizontalDividerColumn: View {
    var body: some View {
        VStack(spacing: 0) { Color.red.frame(width: 200, height: 40); Divider(); Color.blue.frame(width: 200, height: 40) }.frame(width: 200)
    }
}

private struct VerticalDividerRow: View {
    var body: some View {
        HStack(spacing: 0) { Color.red.frame(width: 60, height: 80); Divider(); Color.blue.frame(width: 60, height: 80) }.frame(height: 80)
    }
}

private struct VerticalDividerRowFramed: View {
    var body: some View {
        HStack(spacing: 0) { Color.red.frame(width: 60, height: 80); Divider().frame(width: 12); Color.blue.frame(width: 60, height: 80) }.frame(height: 80)
    }
}

private struct DividerWithOverlayInRow: View {
    var body: some View {
        HStack(spacing: 0) { Divider().overlay { Color.red } }.frame(height: 60)
    }
}

private struct FramedDivider: View {
    var body: some View { Divider().frame(width: 160, height: 12) }
}

private struct DividerInZStack: View {
    var body: some View { ZStack { Color.blue.frame(width: 100, height: 40); Divider() }.frame(width: 100, height: 40) }
}

@MainActor
final class SpacerDividerTests: XCTestCase {
    private func widths(_ view: some View, kind: String = "Spacer") throws -> (spacer: CGFloat, positions: [CGFloat], colours: [CGFloat]) {
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let all = everyNode(graph.snapshot())
        let spacer = try XCTUnwrap(all.first { $0.kind == kind })
        let colours = all.filter { $0.kind == "Color" }
        return (spacer.frame.width, colours.map(\.frame.minX), colours.map(\.frame.width))
    }

    private func gap(_ view: some View) throws -> CGFloat {
        let graph = Graph(view, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let colours = everyNode(graph.snapshot()).filter { $0.kind == "Color" }
        return colours[1].frame.minX - colours[0].frame.maxX
    }

    func testSpacerDefaultMinimumLengthIsEightPoints() throws {
        // measured: 100 pt frame -> 20 pt gap; 84 and 80 pt frames -> the Spacer keeps 8 pt and the row overflows (centred)
        XCTAssertEqual(try gap(DefaultSpacerRow(width: 100)), 20)
        XCTAssertEqual(try gap(DefaultSpacerRow(width: 84)), 8)
        XCTAssertEqual(try gap(DefaultSpacerRow(width: 80)), 8)
    }

    func testSpacerMinimumLengthZeroCollapses() throws {
        XCTAssertEqual(try gap(ZeroMinSpacerRow()), 0)
    }

    func testDefaultSpacingNextToSpacerIsZeroButExplicitSpacingApplies() throws {
        // measured: explicit spacing 20 around a Spacer in an 80 pt frame: 20 + 8 + 20 = 48 pt between the rectangles
        XCTAssertEqual(try gap(ExplicitSpacingSpacerRow()), 48)
        // default spacing: two rectangles are 8 pt apart, a Spacer(minLength: 0) between rectangles adds no spacing (100 - 90 - 8 = 2)
        let graph = Graph(DefaultSpacingMixedRow(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let c = everyNode(graph.snapshot()).filter { $0.kind == "Color" }
        XCTAssertEqual(c[1].frame.minX - c[0].frame.maxX, 8)
        XCTAssertEqual(c[2].frame.minX - c[1].frame.maxX, 2)
    }

    func testVerticalSpacerDefaultMinimumLength() throws {
        let graph = Graph(VerticalSpacerColumn(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let c = everyNode(graph.snapshot()).filter { $0.kind == "Color" }
        XCTAssertEqual(c[1].frame.minY - c[0].frame.maxY, 8, "44 pt for 2 x 20 pt leaves 4 pt: the Spacer keeps its 8 pt minimum and the column overflows")
    }

    func testHorizontalDividerIsOnePointThickAndFillsTheWidth() throws {
        let graph = Graph(HorizontalDividerColumn(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let divider = try XCTUnwrap(everyNode(graph.snapshot()).first { $0.kind == "Divider" })
        XCTAssertEqual(divider.frame.width, 200)
        XCTAssertEqual(divider.frame.height, 1, accuracy: 0.21, "1 pt snaps to 2 or 3 device pixels (0.8 or 1.2 pt at scale 2.5)")
    }

    func testDividerInAnHStackIsVerticalAndFillsTheRowHeight() throws {
        func check(_ graph: Graph) throws {
            graph.rootProposal = ProposedViewSize(width: 320, height: 240)
            graph.flush()
            let divider = try XCTUnwrap(everyNode(graph.snapshot()).first { $0.kind == "Divider" })
            XCTAssertEqual(divider.frame.width, 1, accuracy: 0.21)
            XCTAssertEqual(divider.frame.height, 80, "the Divider takes the height the row was given")
        }
        try check(Graph(VerticalDividerRow(), scale: 2.5))
        try check(Graph(VerticalDividerRowFramed(), scale: 2.5))
    }

    func testDividerKeepsItsAxisThroughAnOverlayModifier() throws {
        let graph = Graph(DividerWithOverlayInRow(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let divider = try XCTUnwrap(everyNode(graph.snapshot()).first { $0.kind == "Divider" })
        XCTAssertEqual(divider.frame.width, 1, accuracy: 0.21)
        XCTAssertEqual(divider.frame.height, 60)
    }

    func testStandaloneAndZStackDividersAreHorizontalRules() throws {
        let graph = Graph(FramedDivider(), scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 320, height: 240)
        graph.flush()
        let divider = try XCTUnwrap(everyNode(graph.snapshot()).first { $0.kind == "Divider" })
        XCTAssertEqual(divider.frame.width, 160)
        XCTAssertEqual(divider.frame.height, 1, accuracy: 0.21)
        XCTAssertEqual(divider.frame.minY + divider.frame.height / 2, 6, accuracy: 0.21, "centred in the 12 pt frame")
        let z = Graph(DividerInZStack(), scale: 2.5)
        z.rootProposal = ProposedViewSize(width: 320, height: 240)
        z.flush()
        let zd = try XCTUnwrap(everyNode(z.snapshot()).first { $0.kind == "Divider" })
        XCTAssertEqual(zd.frame.width, 100)
        XCTAssertEqual(zd.frame.height, 1, accuracy: 0.21)
    }
}
