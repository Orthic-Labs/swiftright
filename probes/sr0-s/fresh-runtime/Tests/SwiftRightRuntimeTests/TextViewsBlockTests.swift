import SwiftRightRuntime
import XCTest

// Round 5, block swiftui.text-views (Pulse hub gaps G01, G07-G11, G16, G18): Text(verbatim:), AnyView, Color.clear and Color.opacity returning a Color,
// State(initialValue:), a single-child ViewBuilder returning that child, View.id, ViewModifier.

@MainActor enum TVLog { static var appears = 0; static var inits = 0 }

private struct TVStateful: View {
    @State var n: Int
    init() { _n = State(initialValue: 5) }
    var body: some View {
        Button("n=\(n)") { n += 1 }
    }
}

private struct TVHolder<Trailing: View>: View {
    let trailing: Trailing
    init(@ViewBuilder trailing: () -> Trailing) { self.trailing = trailing() }
    var body: some View { HStack { Text("t"); trailing } }
}
private struct TVNone: View { var body: some View { Color.clear.frame(width: 1, height: 1) } }
extension TVHolder where Trailing == TVNone {
    init() { self.init { TVNone() } }
}

private struct TVPad: ViewModifier {
    let by: CGFloat
    func body(content: Content) -> some View { content.padding(by) }
}
private struct TVConditional: ViewModifier {
    let on: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if on { content.opacity(0.5) } else { content }
    }
}

private struct TVIdBox: View {
    @State var tick = 0
    let key: Int
    var body: some View {
        Button("k=\(key) t=\(tick)") { tick += 1 }.onAppear { TVLog.appears += 1 }
    }
}
private struct TVAnyChoice: View {
    let first: Bool
    var body: some View {
        let v: AnyView = first ? AnyView(Text("first")) : AnyView(Button("second") {})
        return VStack { v }
    }
}

@MainActor
final class TextViewsBlockTests: XCTestCase {
    func testTextVerbatimIsTheWrittenString() {
        let g = Graph(Text(verbatim: "100% {name} \\(x)"), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        g.flush()
        XCTAssertEqual(everyNode(g.snapshot()).filter { $0.kind == "Text" }.compactMap(\.text), ["100% {name} \\(x)"])
    }

    func testStateInitialValue() {
        let g = Graph(TVStateful(), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        g.flush()
        XCTAssertEqual(everyNode(g.snapshot()).filter { $0.kind == "Text" }.compactMap(\.text), ["n=5"])
        let id = g.ids(ofKind: "Button")[0]
        XCTAssertTrue(g.tapButton(id)); g.flush()
        XCTAssertEqual(everyNode(g.snapshot()).filter { $0.kind == "Text" }.compactMap(\.text), ["n=6"])
    }

    func testSingleChildBuilderReturnsItsChild() {
        // `Trailing == TVNone` only type-checks when `{ TVNone() }` builds a TVNone, not a TupleView<TVNone>
        let g = Graph(TVHolder(), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        g.flush()
        XCTAssertEqual(everyNode(g.snapshot()).filter { $0.kind == "Text" }.count, 1)
        let built = ViewBuilder.buildBlock(TVNone())
        XCTAssertTrue(type(of: built) == TVNone.self)
    }

    func testColorClearAndColorOpacityReturnAColor() {
        let c: Color = Color.red.opacity(0.5)
        XCTAssertEqual(c.resolvedColor, .semanticAlpha("system.red", 0.5))
        XCTAssertEqual(Color.black.opacity(0.5).opacity(0.5).resolvedColor, .semanticAlpha("black", 0.25))
        XCTAssertEqual(Color(red: 1, green: 0, blue: 0, opacity: 0.5).opacity(0.5).resolvedColor, .rgba(1, 0, 0, 0.25))
        XCTAssertEqual(Color.clear.resolvedColor, .semantic("clear"))
        let s: Color = .clear   // a fill position: `.fill(.clear)`
        XCTAssertEqual(s, Color.clear)
        let g = Graph(Rectangle().fill(Color.black.opacity(0.1)).frame(width: 10, height: 10), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        g.flush()
        XCTAssertNotNil(g.snapshot())
    }

    func testViewModifierWrapsContent() {
        let g = Graph(Text("m").modifier(TVPad(by: 7)), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        g.rootProposal = ProposedViewSize(width: 100, height: 100)
        g.flush()
        let text = everyNode(g.snapshot()).first { $0.kind == "Text" }
        XCTAssertEqual(text?.frame.origin.x, 7)
        XCTAssertEqual(text?.frame.origin.y, 7)
    }

    func testViewModifierWithABranch() {
        let off = Graph(Text("m").modifier(TVConditional(on: false)), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        off.flush()
        let on = Graph(Text("m").modifier(TVConditional(on: true)), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        on.flush()
        XCTAssertEqual(everyNode(off.snapshot()).first { $0.kind == "Text" }?.opacity, 1)
        XCTAssertEqual(everyNode(on.snapshot()).first { $0.kind == "Text" }?.opacity, 0.5)
    }

    func testIDChangeRestartsStateAndAppear() {
        TVLog.appears = 0
        struct Host: View {
            @State var key = 1
            var body: some View { VStack { Button("flip") { key += 1 }; TVIdBox(key: key).id(key) } }
        }
        let g = Graph(Host(), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        g.flush()
        XCTAssertEqual(TVLog.appears, 1)
        let box = g.ids(ofKind: "Button")[1]
        XCTAssertTrue(g.tapButton(box)); g.flush()
        XCTAssertTrue(everyNode(g.snapshot()).contains { $0.text == "k=1 t=1" }, "state kept while the id is the same")
        // the id is the key owned by the parent: change it
        XCTAssertTrue(g.tapButton(g.ids(ofKind: "Button")[0])); g.flush()
        XCTAssertTrue(everyNode(g.snapshot()).contains { $0.text == "k=2 t=0" }, "a new id is a new view: state restarts")
        XCTAssertEqual(TVLog.appears, 2)
    }

    func testAnyViewIsTransparentAndATypeChangeIsANewView() {
        let g = Graph(TVAnyChoice(first: true), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        g.flush()
        XCTAssertEqual(everyNode(g.snapshot()).filter { $0.kind == "Text" }.compactMap(\.text), ["first"])
        XCTAssertEqual(g.ids(ofKind: "Button").count, 0)
        let h = Graph(TVAnyChoice(first: false), measurer: FixedAdvanceTextMeasurer(), scale: 1)
        h.flush()
        XCTAssertEqual(h.ids(ofKind: "Button").count, 1)
        // the layout does not see the erasure: a VStack of one AnyView sizes like its child
        let plain = Graph(VStack { Text("first") }, measurer: FixedAdvanceTextMeasurer(), scale: 1); plain.flush()
        let a = everyNode(g.snapshot()).first { $0.kind == "Text" }?.frame
        let b = everyNode(plain.snapshot()).first { $0.kind == "Text" }?.frame
        XCTAssertEqual(a?.size.width, b?.size.width)
    }
}
