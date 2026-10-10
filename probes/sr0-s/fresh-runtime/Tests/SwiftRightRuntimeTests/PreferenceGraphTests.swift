import Observation
import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

private enum OrderedKey: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

private enum NumberKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

@Observable
@MainActor
private final class PreferenceModel {
    var value = 1
}

private struct PreferenceLeaf: View {
    @Bindable var model: PreferenceModel
    var body: some View { Text("leaf").preference(key: NumberKey.self, value: model.value) }
}

private struct NestedPreferenceScreen: View {
    let model: PreferenceModel
    var body: some View { PreferenceLeaf(model: model) }
}

@MainActor
final class PreferenceGraphTests: XCTestCase {
    func testPreferenceReductionFollowsChildOrder() {
        let graph = Graph(VStack {
            Text("a").preference(key: OrderedKey.self, value: ["a"])
            Text("b").preference(key: OrderedKey.self, value: ["b"])
        })
        XCTAssertEqual(graph.root?.preferences.value(for: OrderedKey.self), ["a", "b"])
    }

    func testDescendantPreferenceChangeBubblesWithoutParentBodyEvaluation() {
        let model = PreferenceModel()
        let graph = Graph(NestedPreferenceScreen(model: model))
        XCTAssertEqual(graph.root?.preferences.value(for: NumberKey.self), 1)
        model.value = 7
        graph.flush()
        XCTAssertEqual(graph.root?.preferences.value(for: NumberKey.self), 7)
    }
}
