import Foundation
import Observation
import SwiftRightRuntime
import XCTest

struct ScrollFrameMaximumWitness: View {
    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Text("Row \(index)").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 120, height: 48)
    }
}

@Observable
@MainActor
final class FlexibleFrameModel {
    var maxWidth: CGFloat = 20
}

@MainActor
final class FrameMaximumTests: XCTestCase {
    private func nodes(_ graph: Graph, matching predicate: (ResolvedNode) -> Bool) -> [ResolvedNode] {
        var found: [ResolvedNode] = []
        collect(graph.snapshot(), into: &found, where: predicate)
        return found
    }

    func testLegacyFixedAndDefaultFrameCallsRemainAvailable() {
        struct LegacyCalls: View {
            var body: some View {
                Text("legacy").frame().frame(alignment: .leading).frame(width: 42, height: 27)
            }
        }
        let graph = Graph(LegacyCalls())
        graph.flush()
        XCTAssertEqual(graph.snapshot()?.frame.width, 42)
        XCTAssertEqual(graph.snapshot()?.frame.height, 27)
    }

    func testFiniteMaximumClampsFiniteParentProposal() {
        struct MaxWidthFill: View {
            var body: some View { Color.red.frame(maxWidth: 60) }
        }
        let bounded = Graph(MaxWidthFill())
        bounded.rootProposal = ProposedViewSize(width: 120, height: 30)
        bounded.flush()
        XCTAssertEqual(bounded.snapshot()?.frame.width, 60)

        let offered = Graph(MaxWidthFill())
        offered.rootProposal = ProposedViewSize(width: 40, height: 30)
        offered.flush()
        XCTAssertEqual(offered.snapshot()?.frame.width, 40)
    }

    func testMinimumAndMaximumClampChildProposalAndReportedFrame() {
        struct BoundedFill: View {
            var body: some View { Color.red.frame(minWidth: 80, maxWidth: 100) }
        }
        let graph = Graph(BoundedFill())
        graph.rootProposal = ProposedViewSize(width: 40, height: 20)
        graph.flush()
        XCTAssertEqual(graph.snapshot()?.frame.width, 80)
        XCTAssertEqual(nodes(graph) { $0.kind == "Color" }.first?.frame.width, 80)
    }

    func testChangedMaximumInvalidatesSameIdentityContentMeasurement() throws {
        struct UpdatingFrame: View {
            @Bindable var model: FlexibleFrameModel
            var body: some View {
                Text(String(repeating: "word ", count: 20)).frame(maxWidth: model.maxWidth)
            }
        }
        let model = FlexibleFrameModel()
        let graph = Graph(UpdatingFrame(model: model))
        graph.rootProposal = ProposedViewSize(width: 120, height: nil)
        graph.flush()
        let nodeID = try XCTUnwrap(nodes(graph) { $0.kind == "modifier.frame" }.first?.id)
        let instance = try XCTUnwrap(graph.nodeInstance(nodeID))
        let narrowHeight = try XCTUnwrap(nodes(graph) { $0.kind == "modifier.frame" }.first?.frame.height)

        model.maxWidth = 80
        graph.flush()

        let updated = try XCTUnwrap(nodes(graph) { $0.kind == "modifier.frame" }.first)
        XCTAssertEqual(graph.nodeInstance(nodeID), instance)
        XCTAssertEqual(updated.frame.width, 80)
        XCTAssertLessThan(updated.frame.height, narrowHeight)
    }

    func testInfiniteMaximumAcceptsFiniteProposalAndUnspecifiedWidthStaysIntrinsic() throws {
        struct FlexibleText: View {
            var body: some View { Text("intrinsic width").frame(maxWidth: .infinity, alignment: .leading) }
        }
        let offered = Graph(FlexibleText())
        offered.rootProposal = ProposedViewSize(width: 120, height: 30)
        offered.flush()
        XCTAssertEqual(offered.snapshot()?.frame.width, 120)

        let intrinsic = Graph(FlexibleText())
        intrinsic.flush()
        let width = try XCTUnwrap(intrinsic.snapshot()?.frame.width)
        XCTAssertGreaterThan(width, 0)
        XCTAssertTrue(width.isFinite)
        XCTAssertEqual(width, nodes(intrinsic) { $0.kind == "Text" }.first?.frame.width)
    }

    func testFlexibleFrameAlignmentPositionsChildInsideExpandedFrame() throws {
        struct TrailingText: View {
            var body: some View { Text("x").frame(maxWidth: .infinity, alignment: .trailing) }
        }
        let graph = Graph(TrailingText())
        graph.rootProposal = ProposedViewSize(width: 40, height: nil)
        graph.flush()
        let frame = try XCTUnwrap(graph.snapshot())
        let text = try XCTUnwrap(nodes(graph) { $0.kind == "Text" }.first)
        XCTAssertEqual(frame.frame.width, 40)
        XCTAssertEqual(text.frame.minX, frame.frame.width - text.frame.width, accuracy: 0.001)
    }

    func testMaximumHeightClampsAndExpandsByHeightProposal() {
        struct MaxHeightFill: View {
            var body: some View { Color.red.frame(maxHeight: 24) }
        }
        let bounded = Graph(MaxHeightFill())
        bounded.rootProposal = ProposedViewSize(width: 30, height: 60)
        bounded.flush()
        XCTAssertEqual(bounded.snapshot()?.frame.height, 24)

        let offered = Graph(MaxHeightFill())
        offered.rootProposal = ProposedViewSize(width: 30, height: 18)
        offered.flush()
        XCTAssertEqual(offered.snapshot()?.frame.height, 18)

        struct InfiniteMaxHeight: View {
            var body: some View { Color.red.frame(maxHeight: .infinity) }
        }
        let flexible = Graph(InfiniteMaxHeight())
        flexible.rootProposal = ProposedViewSize(width: 30, height: 48)
        flexible.flush()
        XCTAssertEqual(flexible.snapshot()?.frame.height, 48)
    }

    func testFiniteMaximumConstrainsWrappedSpacerInStack() throws {
        struct BoundedSpacer: View {
            var body: some View { HStack(spacing: 0) { Spacer(minLength: 0).frame(maxWidth: 20) } }
        }
        let graph = Graph(BoundedSpacer())
        graph.rootProposal = ProposedViewSize(width: 100, height: 24)
        graph.flush()
        let frame = try XCTUnwrap(nodes(graph) { $0.kind == "modifier.frame" }.first)
        XCTAssertEqual(frame.frame.width, 20)
        XCTAssertLessThanOrEqual(frame.frame.width, 20)
    }

    func testMinimumBoundSurvivesStackShareSmallerThanMinimum() throws {
        struct MinimumSpacer: View {
            var body: some View {
                HStack(spacing: 0) {
                    Text("x")
                    Spacer(minLength: 0).frame(minWidth: 80, maxWidth: .infinity)
                }
            }
        }
        let graph = Graph(MinimumSpacer())
        graph.rootProposal = ProposedViewSize(width: 30, height: 24)
        graph.flush()
        let frame = try XCTUnwrap(nodes(graph) { $0.kind == "modifier.frame" }.first)
        XCTAssertEqual(frame.frame.width, 80)
    }

    func testBoundedAndBareSpacersKeepIndependentStackFlexibility() throws {
        struct FlexibleSpacerRow: View {
            var body: some View {
                HStack(spacing: 0) {
                    Spacer(minLength: 0).frame(maxWidth: 20)
                    Spacer(minLength: 0)
                }
            }
        }
        let graph = Graph(FlexibleSpacerRow())
        graph.rootProposal = ProposedViewSize(width: 120, height: 24)
        graph.flush()
        let flexibleFrame = try XCTUnwrap(nodes(graph) { $0.kind == "modifier.frame" }.first)
        let spacerWidths = nodes(graph) { $0.kind == "Spacer" }.map(\.frame.width)
        XCTAssertEqual(flexibleFrame.frame.width, 20)
        XCTAssertEqual(spacerWidths.count, 2)
        let bareSpacerWidth = try XCTUnwrap(spacerWidths.max())
        XCTAssertGreaterThan(bareSpacerWidth, flexibleFrame.frame.width)
        XCTAssertTrue(flexibleFrame.frame.width.isFinite)
        XCTAssertTrue(bareSpacerWidth.isFinite)
    }

    func testCrossAxisFlexibleBoundPreservesSpacerMainAxisFlexibility() throws {
        struct CrossBoundSpacer: View {
            var body: some View {
                HStack(spacing: 0) { Spacer(minLength: 0).frame(maxHeight: 10) }
            }
        }
        let graph = Graph(CrossBoundSpacer())
        graph.rootProposal = ProposedViewSize(width: 90, height: 24)
        graph.flush()
        let frame = try XCTUnwrap(nodes(graph) { $0.kind == "modifier.frame" }.first)
        XCTAssertEqual(frame.frame.width, 90)
        XCTAssertEqual(frame.frame.height, 10)
    }

    func testBareSpacerStillTakesRemainingStackShare() throws {
        struct BareSpacerRow: View {
            var body: some View {
                HStack(spacing: 0) {
                    Text("A")
                    Spacer(minLength: 0)
                    Text("B")
                }
            }
        }
        let graph = Graph(BareSpacerRow())
        graph.rootProposal = ProposedViewSize(width: 100, height: 24)
        graph.flush()
        let spacer = try XCTUnwrap(nodes(graph) { $0.kind == "Spacer" }.first)
        XCTAssertGreaterThan(spacer.frame.width, 0)
        XCTAssertTrue(spacer.frame.width.isFinite)
    }

    func testMalformedFlexibleBoundsNormalizeToFiniteGeometry() throws {
        struct MalformedBounds: View {
            var body: some View {
                Color.red.frame(minWidth: 30, maxWidth: 10)
                    .frame(minHeight: .nan, maxHeight: -.infinity)
            }
        }
        let graph = Graph(MalformedBounds())
        graph.rootProposal = ProposedViewSize(width: 100, height: 40)
        graph.flush()
        let frame = try XCTUnwrap(graph.snapshot()?.frame)
        XCTAssertEqual(frame.width, 30)
        XCTAssertTrue(frame.width.isFinite && frame.height.isFinite)
    }

    func testHorizontalScrollPilotWitnessHasFiniteFrames() {
        let graph = Graph(ScrollFrameMaximumWitness())
        graph.flush()
        XCTAssertEqual(graph.snapshot()?.frame.width, 120)
        XCTAssertEqual(graph.snapshot()?.frame.height, 48)
        let rows = nodes(graph) { $0.kind == "Text" && $0.text?.hasPrefix("Row ") == true }
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.allSatisfy { $0.frame.width.isFinite && $0.frame.height.isFinite })
    }
}
