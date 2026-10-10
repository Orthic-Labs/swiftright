import Foundation
import Observation
import SwiftRightRuntime
import XCTest

@Observable
@MainActor
final class MutableFontModel {
    var design: Font.Design = .serif
}

struct MutableDesignFontProbe: View {
    let model: MutableFontModel
    var body: some View { Text("descriptor").font(.system(size: 16, design: model.design)) }
}

@Observable
@MainActor
final class MutableLineLimitModel {
    var limit = 1
}

struct MutableLineLimitProbe: View {
    let model: MutableLineLimitModel
    var body: some View { Text("three lines").lineLimit(model.limit) }
}

@MainActor
final class DescriptorTextMeasurer: TextMeasurer {
    var requests: [TextMeasureRequest] = []

    func measure(_ request: TextMeasureRequest) -> TextMeasurement {
        requests.append(request)
        let lineHeight: CGFloat = request.fontMetadata?.design == .rounded ? 13 : 10
        let lines = min(3, request.lineLimit ?? 1)
        let height = CGFloat(lines) * lineHeight
        return TextMeasurement(size: LayoutSize(width: 80, height: height), baseline: lineHeight * 0.75, lineCount: lines)
    }
}

@MainActor
final class FontAdditionTests: XCTestCase {
    func testIndependentlyConstructedMetadataFontsCompareAndHashByValue() {
        let first = Font.system(size: 17, weight: .medium, design: .serif)
        let second = Font.system(size: 17, weight: .medium, design: .serif)

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 1)
    }

    func testMetadataFontEqualityIncludesMetadataValue() {
        let serif = Font.system(size: 17, design: .serif)
        let rounded = Font.system(size: 17, design: .rounded)

        XCTAssertNotEqual(serif, rounded)
        XCTAssertEqual(Set([serif, rounded]).count, 2)
    }

    func testLegacyFontAndExplicitMetadataFontWithSameIDRemainDistinct() {
        let legacy = Font.system(size: 17)
        let explicit = Font.system(size: 17, design: .default)

        XCTAssertEqual(legacy.id, explicit.id)
        XCTAssertNil(legacy.metadata)
        XCTAssertNotNil(explicit.metadata)
        XCTAssertNotEqual(legacy, explicit)
    }

    func testRetainedSnapshotKeepsFontMetadataAfterDesignChanges() {
        let model = MutableFontModel()
        let graph = Graph(MutableDesignFontProbe(model: model))
        graph.flush()
        let retained = graph.snapshot()

        model.design = .rounded
        graph.flush()

        XCTAssertEqual(firstFont(in: retained)?.metadata?.design, .serif)
        XCTAssertEqual(firstFont(in: graph.snapshot())?.metadata?.design, .rounded)
    }

    func testSystemDesignIsPassedAsMetadataWithoutChangingLegacyID() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(Text("design").font(.system(size: 17, weight: .medium, design: .serif)), measurer: measurer)
        graph.flush()

        let font = Font.system(size: 17, weight: .medium, design: .serif)
        let request = measurer.requests.first
        XCTAssertEqual(font.id, Font.system(size: 17, weight: .medium).id)
        XCTAssertEqual(request?.fontID, font.id)
        XCTAssertEqual(request?.fontMetadata?.pointSize, 17)
        XCTAssertEqual(request?.fontMetadata?.weight, .medium)
        XCTAssertEqual(request?.fontMetadata?.design, .serif)
        XCTAssertNil(request?.fontMetadata?.familyName)
    }

    func testSameTextNodeInvalidatesWhenDesignChangesWithoutChangingID() {
        let model = MutableFontModel()
        let measurer = DescriptorTextMeasurer()
        let graph = Graph(MutableDesignFontProbe(model: model), measurer: measurer)
        graph.flush()
        let textID = graph.ids(ofKind: "Text").first
        XCTAssertEqual(sr1Kind(graph, "Text").first?.frame.height, 10)

        model.design = .rounded
        graph.flush()
        XCTAssertEqual(graph.ids(ofKind: "Text").first, textID)
        XCTAssertEqual(sr1Kind(graph, "Text").first?.frame.height, 13)
        XCTAssertEqual(measurer.requests.map { $0.fontMetadata?.design }, [.serif, .rounded])
    }

    func testCustomFamilyMetadataSurvivesWeightModifier() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(Text("custom").font(.custom("Example Display", size: 19).weight(.bold)), measurer: measurer)
        graph.flush()

        let metadata = measurer.requests.first?.fontMetadata
        XCTAssertEqual(metadata?.familyName, "Example Display")
        XCTAssertEqual(metadata?.pointSize, 19)
        XCTAssertEqual(metadata?.weight, .bold)
        XCTAssertTrue(metadata?.isCustom == true)
        XCTAssertNil(metadata?.design)
    }

    func testSameTextNodeInvalidatesWhenLineLimitChanges() {
        let model = MutableLineLimitModel()
        let measurer = DescriptorTextMeasurer()
        let graph = Graph(MutableLineLimitProbe(model: model), measurer: measurer)
        graph.flush()
        let textID = graph.ids(ofKind: "Text").first
        XCTAssertEqual(sr1Kind(graph, "Text").first?.frame.height, 10)

        model.limit = 2
        graph.flush()
        XCTAssertEqual(graph.ids(ofKind: "Text").first, textID)
        XCTAssertEqual(sr1Kind(graph, "Text").first?.frame.height, 20)
        XCTAssertEqual(measurer.requests.map(\.lineLimit), [1, 2])
    }

    func testLineLimitReachesMeasurerAndCapsTextHeight() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(Text("aa bb cc dd ee").lineLimit(2), measurer: measurer)
        graph.rootProposal = ProposedViewSize(width: 40, height: nil)
        graph.flush()

        XCTAssertEqual(measurer.requests.first?.lineLimit, 2)
        XCTAssertEqual(sr1Kind(graph, "Text").first?.frame.height, 32)
    }

    func testLegacySystemFontLeavesMetadataUnset() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(Text("legacy").font(.system(size: 17, weight: .medium)), measurer: measurer)
        graph.flush()
        graph.flush()

        XCTAssertEqual(measurer.requests.first?.fontID, "system(17.0,medium)")
        XCTAssertEqual(measurer.requests.count, 1)
        XCTAssertNil(measurer.requests.first?.fontMetadata)
        XCTAssertNil(Font.system(size: 17, weight: .medium).metadata)
    }
}

@MainActor
private func firstFont(in node: ResolvedNode?) -> Font? {
    guard let node else { return nil }
    if let font = node.style.font { return font }
    for child in node.children {
        if let font = firstFont(in: child) { return font }
    }
    return nil
}
