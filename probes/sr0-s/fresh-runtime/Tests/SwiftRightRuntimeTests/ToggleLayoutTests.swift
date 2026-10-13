import SwiftRightRuntime
import XCTest

private struct HiddenSwitch: View {
    @State private var on = true
    var body: some View { Toggle("Enabled", isOn: $on).labelsHidden().toggleStyle(.switch) }
}

private struct LabelledSwitch: View {
    @State private var on = false
    var body: some View { Toggle("Enabled", isOn: $on).toggleStyle(.switch) }
}

private struct DisabledSwitch: View {
    @State private var on = true
    var body: some View { Toggle("Enabled", isOn: $on).labelsHidden().toggleStyle(.switch).disabled(true) }
}

private struct SwitchInRow: View {
    @State private var on = true
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().frame(width: 10, height: 10)
            Toggle("Enabled", isOn: $on).labelsHidden().toggleStyle(.switch)
        }
    }
}

private struct BareToggle: View {
    @State private var on = true
    var body: some View { Toggle("Enabled", isOn: $on).labelsHidden() }
}

/// A Toggle with switch artwork takes the size SwiftUI gives it on macOS (54 x 24 pt control, 8 pt to its label).
@MainActor
final class ToggleLayoutTests: XCTestCase {
    private func toggle(_ view: some View, scale: CGFloat = 1) -> ResolvedNode? {
        let graph = Graph(view, scale: scale)
        graph.flush()
        return everyNode(graph.snapshot()).first { $0.kind == "Toggle" }
    }

    func testSwitchWithoutLabelIsTheControlAlone() throws {
        let node = try XCTUnwrap(toggle(HiddenSwitch()))
        XCTAssertEqual(node.frame.width, 54)
        XCTAssertEqual(node.frame.height, 24)
        XCTAssertTrue(node.children.isEmpty)
    }

    func testSwitchControlSizeIsPixelAlignedAtScale2_5() throws {
        let node = try XCTUnwrap(toggle(HiddenSwitch(), scale: 2.5))
        XCTAssertEqual(node.pixelFrame.width, 135)
        XCTAssertEqual(node.pixelFrame.height, 60)
    }

    func testLabelLeadsAndControlTrailsWithEightPointsBetween() throws {
        let node = try XCTUnwrap(toggle(LabelledSwitch()))
        let label = try XCTUnwrap(everyNode(node).first { $0.kind == "Text" })
        XCTAssertEqual(label.frame.minX, node.frame.minX)
        XCTAssertEqual(node.frame.width, label.frame.width + 8 + 54, accuracy: 1e-9)
        XCTAssertEqual(node.frame.height, max(label.frame.height, 24))
        // centred vertically
        XCTAssertEqual(label.frame.minY + label.frame.height / 2, node.frame.minY + node.frame.height / 2, accuracy: 1e-9)
        XCTAssertEqual(node.accessibility.value, "0")
    }

    func testRightToLeftPutsTheLabelAtTheTrailingEdge() throws {
        let node = try XCTUnwrap(toggle(LabelledSwitch().environment(\.layoutDirection, .rightToLeft)))
        let label = try XCTUnwrap(everyNode(node).first { $0.kind == "Text" })
        XCTAssertEqual(label.frame.maxX, node.frame.maxX, accuracy: 1e-9)
    }

    func testSwitchIsAnIntrinsicSizedChildInAStack() throws {
        let graph = Graph(SwitchInRow())
        graph.flush()
        let toggle = try XCTUnwrap(everyNode(graph.snapshot()).first { $0.kind == "Toggle" })
        XCTAssertEqual(toggle.frame.minX, 10)
        XCTAssertEqual(toggle.frame.width, 54)
    }

    func testDisabledSwitchKeepsItsSizeAndReportsDisabled() throws {
        let node = try XCTUnwrap(toggle(DisabledSwitch()))
        XCTAssertEqual(node.frame.width, 54)
        XCTAssertFalse(node.accessibility.isEnabled)
    }

    func testToggleWithoutStyleKeepsItsPreviousLayout() throws {
        let node = try XCTUnwrap(toggle(BareToggle()))
        XCTAssertEqual(node.frame.width, 0)
        XCTAssertEqual(node.frame.height, 0)
    }

    func testMetricsResolveOnlyTheSwitchStyle() {
        XCTAssertEqual(ToggleMetrics.artwork(forStyle: "SwitchToggleStyle"), .switchControl)
        XCTAssertNil(ToggleMetrics.artwork(forStyle: nil))
        XCTAssertEqual(ToggleArtwork.switchControl.controlSize, LayoutSize(width: 54, height: 24))
        XCTAssertEqual(ToggleArtwork.switchControl.labelSpacing, 8)
    }
}
