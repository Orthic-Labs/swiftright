import Foundation
import SwiftRightRuntime
import XCTest

// SR1 round 4, block swiftui.observation. The witnesses (factory/pipeline/blocks-21-23/swiftui.observation) read a plain global stamp inside view bodies: a body that
// re-ran after a model change shows the new stamp, one that did not shows the old. Measured on macOS 27 SwiftUI, and pinned here against the runtime. This file imports
// SwiftRightRuntime only: `@Observable` must be reachable through it (a Windows witness has no other import), as it is through SwiftUI on the Mac.

@MainActor
enum ObsStamp { static var value = 0 }

@Observable final class ObsPairModel { var a = 0; var b = 0 }

private struct ObsReaderA: View {
    let m: ObsPairModel
    var body: some View { Text("A a=\(m.a) s=\(ObsStamp.value)") }
}

private struct ObsReaderB: View {
    let m: ObsPairModel
    var body: some View { Text("B b=\(m.b) s=\(ObsStamp.value)") }
}

private struct ObsPair: View {
    let m: ObsPairModel
    var body: some View { VStack { ObsReaderA(m: m); ObsReaderB(m: m) } }
}

@Observable final class ObsInner { var v = 0; init(_ v: Int = 0) { self.v = v } }
@Observable final class ObsOuter { var inner = ObsInner(); var other = 0 }

private struct ObsInnerReader: View {
    let o: ObsOuter
    var body: some View { Text("inner=\(o.inner.v) s=\(ObsStamp.value)") }
}

@Observable final class ObsItem { let id: Int; var done = false; init(_ id: Int) { self.id = id } }
@Observable final class ObsStore { var items: [ObsItem] = [ObsItem(0), ObsItem(1), ObsItem(2)] }

private struct ObsItemRow: View {
    let item: ObsItem
    var body: some View { Text("item \(item.id) done=\(item.done ? 1 : 0) s=\(ObsStamp.value)") }
}

private struct ObsItemList: View {
    let store: ObsStore
    var body: some View { VStack(spacing: 0) { ForEach(store.items, id: \.id) { item in ObsItemRow(item: item) } } }
}

@Observable final class ObsSum { var a = 0; var b = 0; var total: Int { a + b } }

private struct ObsTotalReader: View {
    let m: ObsSum
    var body: some View { Text("total=\(m.total) s=\(ObsStamp.value)") }
}

private struct ObsAReader: View {
    let m: ObsSum
    var body: some View { Text("a=\(m.a) s=\(ObsStamp.value)") }
}

@Observable final class ObsSettings { var on = false; var count = 0 }

private struct ObsEditor: View {
    @Bindable var s: ObsSettings
    var body: some View {
        let on = $s.on
        Button("Flip") { ObsStamp.value += 1; on.wrappedValue.toggle() }
    }
}

private struct ObsOnReader: View {
    let s: ObsSettings
    var body: some View { Text("on=\(s.on ? 1 : 0) s=\(ObsStamp.value)") }
}

private struct ObsCountReader: View {
    let s: ObsSettings
    var body: some View { Text("count=\(s.count) s=\(ObsStamp.value)") }
}

private struct ObsBindableHost: View {
    let s: ObsSettings
    var body: some View { VStack { ObsEditor(s: s); ObsOnReader(s: s); ObsCountReader(s: s) } }
}

@MainActor
private func texts(_ graph: Graph) -> [String] {
    everyNode(graph.snapshot()).filter { $0.kind == "Text" }.compactMap(\.text)
}

@MainActor
private func make<V: View>(_ view: V) -> Graph {
    ObsStamp.value = 0
    let graph = Graph(view, scale: 2.5)
    graph.rootProposal = ProposedViewSize(width: 240, height: 200)
    graph.flush()
    return graph
}

@MainActor
final class ObservationBlockTests: XCTestCase {
    func testAChangeReRunsOnlyTheReaderOfThatProperty() {
        let m = ObsPairModel()
        let graph = make(ObsPair(m: m))
        XCTAssertEqual(texts(graph), ["A a=0 s=0", "B b=0 s=0"])
        ObsStamp.value = 1; m.b += 1; graph.flush()
        XCTAssertEqual(texts(graph), ["A a=0 s=0", "B b=1 s=1"], "the reader of a keeps its old body")
        ObsStamp.value = 2; m.a += 1; graph.flush()
        XCTAssertEqual(texts(graph), ["A a=1 s=2", "B b=1 s=1"])
    }

    func testNestedModelsFollowTheSwappedInnerAndIgnoreTheRetiredOne() {
        let o = ObsOuter()
        let graph = make(ObsInnerReader(o: o))
        ObsStamp.value = 1; o.inner.v += 1; graph.flush()
        XCTAssertEqual(texts(graph), ["inner=1 s=1"])
        ObsStamp.value = 2; o.other += 1; graph.flush()
        XCTAssertEqual(texts(graph), ["inner=1 s=1"], "an outer property nobody reads re-runs nothing")
        let retired = o.inner
        ObsStamp.value = 3; o.inner = ObsInner(100); graph.flush()
        XCTAssertEqual(texts(graph), ["inner=100 s=3"])
        ObsStamp.value = 4; retired.v += 1; graph.flush()
        XCTAssertEqual(texts(graph), ["inner=100 s=3"], "the retired inner model is no longer observed")
        ObsStamp.value = 5; o.inner.v += 1; graph.flush()
        XCTAssertEqual(texts(graph), ["inner=101 s=5"])
    }

    func testCollectionRowsReRunOnlyForTheirOwnItemAndAppendingKeepsTheRowsItAlreadyShows() {
        let store = ObsStore()
        let graph = make(ObsItemList(store: store))
        XCTAssertEqual(texts(graph), ["item 0 done=0 s=0", "item 1 done=0 s=0", "item 2 done=0 s=0"])
        ObsStamp.value = 1; store.items[1].done.toggle(); graph.flush()
        XCTAssertEqual(texts(graph), ["item 0 done=0 s=0", "item 1 done=1 s=1", "item 2 done=0 s=0"])
        ObsStamp.value = 2; store.items.append(ObsItem(3)); graph.flush()
        XCTAssertEqual(texts(graph), ["item 0 done=0 s=0", "item 1 done=1 s=1", "item 2 done=0 s=0", "item 3 done=0 s=2"], "rows already shown are not re-run by an append")
        ObsStamp.value = 3; store.items[3].done.toggle(); graph.flush()
        XCTAssertEqual(texts(graph), ["item 0 done=0 s=0", "item 1 done=1 s=1", "item 2 done=0 s=0", "item 3 done=1 s=3"])
        ObsStamp.value = 4; store.items[1].done.toggle(); graph.flush()
        XCTAssertEqual(texts(graph), ["item 0 done=0 s=0", "item 1 done=0 s=4", "item 2 done=0 s=0", "item 3 done=1 s=3"])
    }

    func testComputedPropertyDependsOnItsStoredProperties() {
        let m = ObsSum()
        let graph = make(VStack { ObsTotalReader(m: m); ObsAReader(m: m) })
        ObsStamp.value = 1; m.b += 1; graph.flush()
        XCTAssertEqual(texts(graph), ["total=1 s=1", "a=0 s=0"])
        ObsStamp.value = 2; m.a += 1; graph.flush()
        XCTAssertEqual(texts(graph), ["total=2 s=2", "a=1 s=2"])
    }

    func testBindableBindingWritesTheModelAndOnlyItsReadersFollow() {
        let s = ObsSettings()
        let graph = make(ObsBindableHost(s: s))
        XCTAssertEqual(texts(graph), ["Flip", "on=0 s=0", "count=0 s=0"])
        let flip = everyNode(graph.snapshot()).first { $0.kind == "Button" }
        XCTAssertNotNil(flip)
        _ = graph.tapButton(flip?.id ?? "")
        graph.flush()
        XCTAssertTrue(s.on)
        XCTAssertEqual(texts(graph), ["Flip", "on=1 s=1", "count=0 s=0"], "the count reader keeps its old body")
        ObsStamp.value = 2; s.count += 1; graph.flush()
        XCTAssertEqual(texts(graph), ["Flip", "on=1 s=1", "count=1 s=2"])
    }
}
