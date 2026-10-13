import XCTest
@testable import SwiftRightRuntime

private enum FirstWins: PreferenceKey {
    typealias Value = CGFloat?                      // no defaultValue: nil through ExpressibleByNilLiteral
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = value ?? nextValue() }
}

private struct Reader: View {
    @State private var width: CGFloat = -1
    let contributes: Bool
    var body: some View {
        VStack(spacing: 0) {
            if contributes {
                Rectangle().fill(Color.red).frame(width: 30, height: 10).preference(key: FirstWins.self, value: 30)
                Rectangle().fill(Color.blue).frame(width: 70, height: 10).preference(key: FirstWins.self, value: 70)
            }
            Rectangle().fill(Color.green).frame(width: width, height: 6)
        }.onPreferenceChange(FirstWins.self) { width = $0 ?? 5 }
    }
}

@MainActor
final class PreferenceNilDefaultTests: XCTestCase {
    func testOptionalValuedKeyDefaultsToNil() {
        XCTAssertNil(FirstWins.defaultValue)
    }

    private func barWidth(contributes: Bool) -> CGFloat? {
        let graph = Graph(Reader(contributes: contributes), scale: 2)
        graph.rootProposal = ProposedViewSize(width: 200, height: 200)
        graph.flush()
        var nodes: [ResolvedNode] = []
        func walk(_ n: ResolvedNode) { nodes.append(n); n.children.forEach(walk) }
        walk(graph.snapshot()!)
        return nodes.last { $0.kind == "Rectangle" }?.frame.width
    }

    func testFirstContributionWinsAndIsRenderedByTheObservingParent() {
        XCTAssertEqual(barWidth(contributes: true), 30)
    }

    func testWithoutContributorsTheParentSeesTheNilDefault() {
        XCTAssertEqual(barWidth(contributes: false), 5)
    }

    func testObserverReportsTheDefaultOnceWhenNothingContributes() {
        final class Log { var calls: [CGFloat?] = [] }
        let log = Log()
        let graph = Graph(Text("x").onPreferenceChange(FirstWins.self) { log.calls.append($0) }, scale: 2)
        graph.rootProposal = ProposedViewSize(width: 100, height: 100)
        graph.flush(); graph.flush()
        XCTAssertEqual(log.calls.count, 1)                 // measured on SwiftUI (macOS 27): called once with defaultValue
        XCTAssertNil(log.calls[0] ?? nil)
    }
}
