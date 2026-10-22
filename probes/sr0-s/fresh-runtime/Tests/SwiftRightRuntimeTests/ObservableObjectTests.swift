import Combine
import Foundation
import SwiftRightRuntime
import XCTest

final class PublishedCounter: ObservableObject {
    @Published var value = 0
    nonisolated(unsafe) static var made = 0
    init() { PublishedCounter.made += 1 }
}

@MainActor
final class ObservableObjectTests: XCTestCase {
    private func texts(_ g: Graph) -> [String] { everyNode(g.snapshot()).compactMap { $0.kind == "Text" ? $0.text : nil } }

    struct Owner: View {
        @StateObject var counter = PublishedCounter()
        let bump: Bool
        var body: some View { VStack { Text("owner \(counter.value)"); Child(counter: counter) }.onAppear { if bump { counter.value += 1 } } }
    }
    struct Child: View {
        @ObservedObject var counter: PublishedCounter
        var body: some View { Text("child \(counter.value)") }
    }

    func testPublishedChangeReRendersOwnerAndObserver() {
        PublishedCounter.made = 0
        let g = Graph(Owner(bump: true), scale: 1)
        g.flush(); g.flush()
        XCTAssertEqual(texts(g), ["owner 1", "child 1"])
        XCTAssertEqual(PublishedCounter.made, 1, "the StateObject is made once")
    }

    struct Reader: View {
        @EnvironmentObject var counter: PublishedCounter
        var body: some View { Text("env \(counter.value)") }
    }

    func testEnvironmentObjectReadsAndFollowsTheObject() {
        let c = PublishedCounter()
        let g = Graph(VStack { Reader() }.environmentObject(c), scale: 1)
        g.flush()
        XCTAssertEqual(texts(g), ["env 0"])
        c.value = 5
        g.flush()
        XCTAssertEqual(texts(g), ["env 5"])
    }

    struct BindingProbe: View {
        @ObservedObject var counter: PublishedCounter
        var body: some View { Text("b \(counter.value)").onAppear { $counter.value.wrappedValue = 9 } }
    }

    func testProjectedBindingWritesThroughTheObject() {
        let c = PublishedCounter()
        let g = Graph(BindingProbe(counter: c), scale: 1)
        g.flush(); g.flush()
        XCTAssertEqual(c.value, 9)
        XCTAssertEqual(texts(g), ["b 9"])
    }

    func testOnReceiveDeliversPublisherValues() {
        let subject = PassthroughSubject<Int, Never>()
        var got: [Int] = []
        let g = Graph(Text("x").onReceive(subject) { got.append($0) }, scale: 1)
        g.flush()
        subject.send(1); subject.send(2)
        g.flush()
        subject.send(3)
        XCTAssertEqual(got, [1, 2, 3], "one subscription across evaluations")
    }
}
