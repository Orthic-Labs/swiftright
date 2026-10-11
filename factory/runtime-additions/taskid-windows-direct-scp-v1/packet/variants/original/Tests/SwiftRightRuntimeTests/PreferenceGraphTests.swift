import Observation
import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

private enum SumKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

private enum OrderedKey: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

@Observable
@MainActor
private final class PreferenceModel {
    var first = 1
    var second = 2
}

@MainActor
private final class PreferenceLog {
    var values: [Int] = []
}

private struct PreferenceScreen: View {
    @Bindable var model: PreferenceModel
    let log: PreferenceLog

    var body: some View {
        VStack {
            Text("first").preference(key: SumKey.self, value: model.first)
            Text("second").preference(key: SumKey.self, value: model.second)
        }
        .onPreferenceChange(SumKey.self) { log.values.append($0) }
    }
}

private struct PreferenceLeaf: View {
    @Bindable var model: PreferenceModel

    var body: some View {
        Text("leaf").preference(key: SumKey.self, value: model.first)
    }
}

private struct NestedPreferenceScreen: View {
    let model: PreferenceModel
    let log: PreferenceLog

    var body: some View {
        PreferenceLeaf(model: model)
            .onPreferenceChange(SumKey.self) { log.values.append($0) }
    }
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

    func testObserverRunsAfterSettledGraphAndOnlyForChangedValue() {
        let model = PreferenceModel()
        let log = PreferenceLog()
        let graph = Graph(PreferenceScreen(model: model, log: log))

        graph.flush()
        XCTAssertEqual(log.values, [3])
        model.first = 2
        model.second = 1
        graph.flush()
        XCTAssertEqual(log.values, [3])
        model.second = 4
        graph.flush()
        XCTAssertEqual(log.values, [3, 6])
    }

    func testDescendantPreferenceChangeBubblesWithoutParentBodyEvaluation() {
        let model = PreferenceModel()
        let log = PreferenceLog()
        let graph = Graph(NestedPreferenceScreen(model: model, log: log))

        graph.flush()
        XCTAssertEqual(log.values, [1])
        model.first = 7
        graph.flush()
        XCTAssertEqual(log.values, [1, 7])
    }
}
