import Observation
import SwiftRightRuntime
import XCTest

@Observable
@MainActor
private final class ToggleStyleModel {
    var enabled = true
}

private struct AutomaticStyleScreen: View {
    @Bindable var model: ToggleStyleModel
    var body: some View { Toggle("Enabled", isOn: $model.enabled).labelsHidden().toggleStyle(.automatic) }
}

private struct SwitchStyleScreen: View {
    @Bindable var model: ToggleStyleModel
    var body: some View { Toggle("Enabled", isOn: $model.enabled).labelsHidden().toggleStyle(.switch) }
}

private struct LegacyStyleScreen: View {
    @Bindable var model: ToggleStyleModel
    var body: some View { Toggle("Enabled", isOn: $model.enabled).labelsHidden() }
}

@MainActor
final class ToggleStyleTests: XCTestCase {
    private func toggle(in node: ResolvedNode?) -> ResolvedNode? {
        guard let node else { return nil }
        if node.kind == "Toggle" { return node }
        for child in node.children {
            if let result = toggle(in: child) { return result }
        }
        return nil
    }

    func testAutomaticStyleMetadataLeavesLegacyToggleGeometryAndAccessibilityUnchanged() {
        let legacyGraph = Graph(LegacyStyleScreen(model: ToggleStyleModel()))
        let styledGraph = Graph(AutomaticStyleScreen(model: ToggleStyleModel()))
        legacyGraph.flush()
        styledGraph.flush()

        let legacyToggle = toggle(in: legacyGraph.snapshot())
        let styledToggle = toggle(in: styledGraph.snapshot())
        XCTAssertNil(legacyToggle?.toggleStyle)
        XCTAssertEqual(styledToggle?.toggleStyle, "DefaultToggleStyle")
        XCTAssertEqual(styledToggle?.frame, legacyToggle?.frame)
        XCTAssertEqual(styledToggle?.children, legacyToggle?.children)
        XCTAssertEqual(styledToggle?.labelsHidden, legacyToggle?.labelsHidden)
        XCTAssertEqual(styledToggle?.accessibility, legacyToggle?.accessibility)

        let id = styledGraph.ids(ofKind: "Toggle").first!
        XCTAssertTrue(styledGraph.activateToggle(id))
        styledGraph.flush()
        XCTAssertEqual(toggle(in: styledGraph.snapshot())?.accessibility.value, "0")
    }

    func testSwitchStyleMetadataIsRecordedWithoutChangingToggleKind() {
        let graph = Graph(SwitchStyleScreen(model: ToggleStyleModel()))
        graph.flush()

        let toggle = toggle(in: graph.snapshot())
        XCTAssertEqual(toggle?.kind, "Toggle")
        XCTAssertEqual(toggle?.toggleStyle, "SwitchToggleStyle")
        XCTAssertEqual(toggle?.accessibility.role, "checkbox")
        XCTAssertEqual(toggle?.accessibility.value, "1")
    }
}
