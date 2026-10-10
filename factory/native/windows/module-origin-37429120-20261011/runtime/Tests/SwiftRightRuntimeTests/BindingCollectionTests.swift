import Foundation
import Observation
import SwiftRightRuntime
import XCTest

struct KeyedScreen: View {
    @Bindable var store: Store

    var body: some View {
        VStack {
            ForEach($store.rows, id: \.id) { row in
                Text(row.wrappedValue.text)
            }
        }
    }
}

@MainActor
final class BindingCollectionTests: XCTestCase {

    // Binding is a RandomAccessCollection of element bindings, as in SwiftUI.
    func testBindingIsRandomAccessCollection() {
        var rows = [Row(id: UUID(), text: "a"), Row(id: UUID(), text: "b")]
        let items = Binding<[Row]>(get: { rows }, set: { rows = $0 })
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].wrappedValue.text, "a")
        items[1].wrappedValue = Row(id: rows[1].id, text: "c")
        XCTAssertEqual(rows[1].text, "c", "element binding writes back through the collection")
    }

    // $store.rows.count and $store.rows[0] through the Bindable dynamic member.
    func testBindableProjectedRowsSupportCountAndSubscript() {
        let store = makeStore(3)
        let items = Bindable(wrappedValue: store).rows
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].wrappedValue.text, "r0")
        XCTAssertEqual(items.last?.wrappedValue.text, "r2")
    }

    // ForEach($items, id: \.id) keeps a row's node identity when a row is inserted above it.
    func testForEachKeyPathIdentityKeepsRowNodeAcrossInsertAbove() {
        let store = makeStore(4)
        let graph = Graph(KeyedScreen(store: store))
        graph.flush()

        let key = "[\(store.rows[2].id)]"
        let before = graph.ids(ofKind: "Text").first(where: { $0.contains(key) })
        XCTAssertNotNil(before)
        let instance = before.flatMap { graph.nodeInstance($0) }

        store.rows.insert(Row(id: UUID(), text: "new"), at: 0)
        graph.flush()

        let after = graph.ids(ofKind: "Text").first(where: { $0.contains(key) })
        XCTAssertEqual(after, before, "row id path unchanged")
        XCTAssertEqual(after.flatMap { graph.nodeInstance($0) }, instance, "same node instance survives")
    }
}
