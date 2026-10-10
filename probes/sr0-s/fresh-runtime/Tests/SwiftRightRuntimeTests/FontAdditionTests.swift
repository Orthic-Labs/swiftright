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

@MainActor
final class DescriptorTextMeasurer: TextMeasurer {
    var requests: [TextMeasureRequest] = []

    func measure(_ request: TextMeasureRequest) -> TextMeasurement {
        requests.append(request)
        let height: CGFloat = request.fontMetadata?.design == .rounded ? 13 : 10
        return TextMeasurement(size: LayoutSize(width: 80, height: height), baseline: height * 0.75, lineCount: 1)
    }
}

@MainActor
final class FontAdditionTests: XCTestCase {
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

    func testLegacySystemFontLeavesMetadataUnset() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(Text("legacy").font(.system(size: 17, weight: .medium)), measurer: measurer)
        graph.flush()

        XCTAssertEqual(measurer.requests.first?.fontID, "system(17.0,medium)")
        XCTAssertNil(measurer.requests.first?.fontMetadata)
        XCTAssertNil(Font.system(size: 17, weight: .medium).metadata)
    }
}
