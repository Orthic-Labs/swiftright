import Foundation
import SwiftRightRuntime
import Observation
import XCTest

/// Block 41 compat state-nested-update: a state change made before a `withAnimation` block is its own transaction. On macOS 27 (real SwiftUI) the
/// witness `onAppear { value = 1; value = 2; withAnimation { value = 3; value = 4 } }` evaluates the body with 0, 2, 4, 4 (never 1): the
/// non-animated pair settles before the animated block begins.
@Observable
@MainActor
final class TransactionProbe {
    var values: [Int] = []
    var changes: [[Int]] = []
}

/// The case's shape (block 41 state-nested-update): the body reads the probe's values and changes, and `onChange` appends to `changes`. That
/// observed append is a second change after the animated one, so the body is evaluated again with the same value 4 (the Mac's 4th evaluation).
struct TransactionBoundaryWitness: View {
    @State private var value = 0
    let probe: TransactionProbe
    var body: some View {
        let _ = probe.values.append(value)
        return VStack(alignment: .leading, spacing: 8) {
            Color.white.frame(width: 20, height: 10)
                .onAppear {
                    value = 1
                    value = 2
                    withAnimation { value = 3; value = 4 }
                }
                .onChange(of: value) { old, new in probe.changes.append([old, new]) }
            Text("\(probe.changes.count)")
        }
    }
}

@MainActor
final class StateTransactionBoundaryTests: XCTestCase {
    func testStateChangesBeforeAWithAnimationBlockEvaluateAsTheirOwnTransaction() {
        let probe = TransactionProbe()
        let graph = Graph(TransactionBoundaryWitness(probe: probe))
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        graph.flush()
        // onChange actions run after the update commits; the writes they make are the next pass (one coalesced evaluation): 0, 2, 4, 4 as on the Mac.
        XCTAssertEqual(probe.values, [0, 2, 4, 4], "Mac: 0, 2, 4, 4")
        XCTAssertEqual(probe.changes, [[0, 2], [2, 4]], "the two onChange actions, in order")
    }

    func testTheBoundaryAloneEvaluatesThePlainWritesBeforeTheAnimatedBlock() {
        struct Animated: View {
            @State var value = 0
            let probe: TransactionProbe
            var body: some View {
                let _ = probe.values.append(value)
                return Color.white.frame(width: 20, height: 10).onAppear {
                    value = 1
                    value = 2
                    withAnimation { value = 3; value = 4 }
                }
            }
        }
        let probe = TransactionProbe()
        let graph = Graph(Animated(probe: probe))
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        graph.flush()
        XCTAssertEqual(probe.values, [0, 2, 4], "the non-animated pair settles before the animated block; 1 is never seen")
    }

    func testWithoutAnimatedBlockTheCoalescedChangesEvaluateOnce() {
        struct Plain: View {
            @State var value = 0
            let probe: TransactionProbe
            var body: some View {
                let _ = probe.values.append(value)
                return Color.white.frame(width: 20, height: 10).onAppear { value = 1; value = 2 }
            }
        }
        let probe = TransactionProbe()
        let graph = Graph(Plain(probe: probe))
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        graph.flush()
        XCTAssertEqual(probe.values, [0, 2], "two plain writes in one action are one transaction")
    }
}
