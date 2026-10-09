import Foundation
import Observation
import TestSinkBackend
import XCTest

@testable @_spi(Backends) import SwiftCrossUI

@MainActor
final class BindingCollectionTests: XCTestCase {

    // Binding is a RandomAccessCollection of element bindings, as in SwiftUI.
    func testBindingIsRandomAccessCollection() {
        #if SCUI_STOCK_FOREACHBINDING
        XCTFail("BLOCKED: stock SCUI Binding is not a Collection")
        #else
        var rows = [Row(id: UUID(), text: "a"), Row(id: UUID(), text: "b")]
        let items = Binding<[Row]>(get: { rows }, set: { rows = $0 })
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].wrappedValue.text, "a")
        items[1].wrappedValue = Row(id: rows[1].id, text: "c")
        XCTAssertEqual(rows[1].text, "c", "element binding writes back through the collection")
        #endif
    }

    // $store.rows.count and $store.rows[0] through the Bindable dynamic member.
    func testBindableProjectedRowsSupportCountAndSubscript() {
        #if SCUI_STOCK_FOREACHBINDING
        XCTFail("BLOCKED: stock SCUI Binding is not a Collection")
        #else
        let store = makeStore(3)
        let items = Bindable(wrappedValue: store).rows
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].wrappedValue.text, "r0")
        XCTAssertEqual(items.last?.wrappedValue.text, "r2")
        #endif
    }

    // ForEach($items, id: \.id) keeps a row's node identity when a row is inserted above it.
    func testForEachKeyPathIdentityKeepsRowNodeAcrossInsertAbove() async throws {
        let store = makeStore(4)
        let h = Harness { KeyedScreen(store: store) }
        await h.flush()

        let before = h.tree.find(kind: "Text").first { $0.text == "r2" }
        XCTAssertNotNil(before)

        store.rows.insert(Row(id: UUID(), text: "new"), at: 0)
        await h.flush()

        let after = h.tree.find(kind: "Text").first { $0.text == "r2" }
        XCTAssertTrue(after?.widget === before?.widget, "same node instance survives")
    }
}
