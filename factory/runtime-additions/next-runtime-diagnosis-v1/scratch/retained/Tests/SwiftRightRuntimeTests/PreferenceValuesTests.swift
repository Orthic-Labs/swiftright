import SwiftRightRuntime
import XCTest
@testable import SwiftRightRuntime

private enum StringListKey: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

final class PreferenceValuesTests: XCTestCase {
    func testDefaultAndSharedReduction() {
        var values = PreferenceValues()
        XCTAssertEqual(values.value(for: StringListKey.self), [])

        values.reduce(["first"], for: StringListKey.self)
        var child = PreferenceValues()
        child.set(["second"], for: StringListKey.self)
        values.merge(child)

        XCTAssertEqual(values.value(for: StringListKey.self), ["first", "second"])
    }
}
