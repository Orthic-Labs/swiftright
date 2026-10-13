import Observation
import SwiftRightRuntime
import XCTest

@Observable
@MainActor
private final class LabelsModel {
    var enabled = false
}

private struct HiddenToggleScreen: View {
    @Bindable var model: LabelsModel

    var body: some View {
        Toggle("Wi-Fi", isOn: $model.enabled).labelsHidden()
    }
}

private struct VisibleToggleScreen: View {
    @Bindable var model: LabelsModel

    var body: some View {
        Toggle("Wi-Fi", isOn: $model.enabled)
    }
}

private struct RootEnvironmentToggleScreen: View {
    @Bindable var model: LabelsModel

    var body: some View {
        Toggle("Wi-Fi", isOn: $model.enabled)
    }
}

@MainActor
final class LabelsHiddenTests: XCTestCase {
    func testHiddenToggleCarriesOptionalVisibilityAndKeepsAccessibilityTitle() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(HiddenToggleScreen(model: LabelsModel()), measurer: measurer)
        graph.flush()

        let toggle = graph.snapshot()?.children.first?.children.first
        XCTAssertEqual(toggle?.labelsHidden, true)
        XCTAssertEqual(toggle?.accessibility.label, "Wi-Fi")
        XCTAssertEqual(toggle?.children, [])
        // the platform default style is a 16 x 16 pt checkbox: with its label hidden the Toggle is the control alone (ToggleMetrics)
        XCTAssertEqual(toggle?.frame.size, LayoutSize(width: 16, height: 16))
        XCTAssertEqual(measurer.callCount(for: "Wi-Fi"), 0)
    }

    func testLegacyToggleKeepsOptionalVisibilityNil() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(VisibleToggleScreen(model: LabelsModel()), measurer: measurer)
        graph.flush()

        let toggle = graph.snapshot()?.children.first
        XCTAssertNil(toggle?.labelsHidden)
        XCTAssertEqual(toggle?.children.first?.text, "Wi-Fi")
        XCTAssertEqual(measurer.callCount(for: "Wi-Fi"), 1)
    }

    func testRootEnvironmentVisibilityChangeInvalidatesToggleAndAncestorSizes() {
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(RootEnvironmentToggleScreen(model: LabelsModel()), measurer: measurer)
        graph.flush()
        let initial = graph.snapshot()?.children.first
        // label (5 characters at 8 pt) + 4.8 pt + the 16 pt checkbox = 60.8 pt, snapped to the pixel grid at scale 1
        XCTAssertEqual(initial?.frame.width, 61)
        XCTAssertEqual(initial?.frame.height, 16)

        graph.setRootEnvironment { $0.labelsHidden = true }
        graph.flush()
        let hidden = graph.snapshot()?.children.first
        XCTAssertEqual(hidden?.labelsHidden, true)
        XCTAssertEqual(hidden?.children, [])
        XCTAssertEqual(hidden?.frame.size, LayoutSize(width: 16, height: 16))
        XCTAssertEqual(hidden?.instance, initial?.instance)

        graph.setRootEnvironment { $0.labelsHidden = false }
        graph.flush()
        let visible = graph.snapshot()?.children.first
        XCTAssertNil(visible?.labelsHidden)
        XCTAssertEqual(visible?.children.first?.text, "Wi-Fi")
        XCTAssertEqual(visible?.frame.width, 61)
        XCTAssertEqual(visible?.frame.height, 16)
        XCTAssertEqual(visible?.instance, initial?.instance)
        XCTAssertEqual(measurer.callCount(for: "Wi-Fi"), 1, "cached text metrics remain reusable across visibility changes")
    }
}
