import SwiftRightRuntime
import XCTest

// SR1 block 12 (swiftui.binding). Expected values are measured on macOS 27 SwiftUI (factory/pipeline/blocks-6-10/swiftui.binding/FACTS.md).

private final class Tape { var calls: [String] = [] }

private struct DerivedToggle: View {
    @State var count = 3
    let tape: Tape
    var body: some View {
        let derived = Binding<Bool>(get: { count > 0 }, set: { count = $0 ? 1 : 0; tape.calls.append("count=\(count)") })
        Toggle("Enabled", isOn: derived).labelsHidden().toggleStyle(.switch)
    }
}

private struct ConstantToggle: View {
    var body: some View { Toggle("Enabled", isOn: .constant(true)).labelsHidden().toggleStyle(.switch) }
}

@MainActor
final class BindingTransactionTests: XCTestCase {
    private func toggleValue(_ graph: Graph) -> (id: String, value: String?) {
        let id = graph.ids(ofKind: "Toggle")[0]
        return (id, everyNode(graph.snapshot()).first { $0.id == id }?.accessibility.value)
    }

    func testDerivedBindingDrivesToggle() {
        let tape = Tape()
        let graph = Graph(DerivedToggle(tape: tape))
        graph.flush()
        var (id, value) = toggleValue(graph)
        XCTAssertEqual(value, "1")
        XCTAssertTrue(graph.activateToggle(id)); graph.flush()
        XCTAssertEqual(toggleValue(graph).value, "0")
        XCTAssertTrue(graph.activateToggle(id)); graph.flush()
        (id, value) = toggleValue(graph)
        XCTAssertEqual(value, "1")
        XCTAssertEqual(tape.calls, ["count=0", "count=1"])
    }

    func testConstantBindingBlocksChange() {
        let graph = Graph(ConstantToggle())
        graph.flush()
        let (id, value) = toggleValue(graph)
        XCTAssertEqual(value, "1")
        _ = graph.activateToggle(id); graph.flush()
        XCTAssertEqual(toggleValue(graph).value, "1")
        let c = Binding.constant(5)
        c.wrappedValue = 9
        XCTAssertEqual(c.wrappedValue, 5)
    }

    func testSetterReceivesBindingTransaction() {
        var seen: [Transaction] = []
        let b = Binding<Int>(get: { 0 }, set: { _, t in seen.append(t) })
        b.wrappedValue = 1
        // withAnimation does not reach the setter: the binding carries its own transaction (oracle).
        withAnimation(.easeIn(duration: 0.2)) { b.wrappedValue = 2 }
        var t = Transaction(animation: .linear(duration: 0.1)); t.disablesAnimations = true
        b.transaction(t).wrappedValue = 3
        b.animation(.easeIn(duration: 0.2)).wrappedValue = 4
        b.animation().wrappedValue = 5
        // transaction(_:) replaces the carried transaction; it does not merge.
        b.transaction(Transaction(animation: .linear(duration: 0.1))).transaction(Transaction()).wrappedValue = 6
        XCTAssertEqual(seen.map { $0.animation == nil }, [true, true, false, false, false, true])
        XCTAssertEqual(seen.map(\.disablesAnimations), [false, false, true, false, false, false])
        XCTAssertEqual(seen[4].animation, .default)
    }

    func testOneArgumentSetterIgnoresTransaction() {
        var last = 0
        let b = Binding<Int>(get: { last }, set: { last = $0 })
        b.animation().wrappedValue = 7
        XCTAssertEqual(last, 7)
    }

    func testStateProjectedValueWritesState() {
        struct V: View { @State var n = 1; var body: some View { let b = $n; Text("n=\(n)").onAppear { b.wrappedValue = 5 } } }
        let graph = Graph(V())
        graph.flush()
        let texts = everyNode(graph.snapshot()).compactMap(\.text)
        XCTAssertEqual(texts, ["n=5"])
    }

    func testDynamicMemberBindingKeepsTransaction() {
        struct P { var x = 0 }
        var seen: [Bool] = []
        var model = P()
        let b = Binding<P>(get: { model }, set: { v, t in model = v; seen.append(t.animation != nil) })
        b.animation().x.wrappedValue = 3
        XCTAssertEqual(model.x, 3)
        XCTAssertEqual(seen, [true])
    }
}
