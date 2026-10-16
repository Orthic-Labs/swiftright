import Foundation
import Observation
import SwiftRightRuntime
import XCTest

@Observable
@MainActor
final class MirrorModel {
    var source = 0
    var mirrored = 0
    var bodies: [Int] = []
}

/// `onChange(of: source)` writes `mirrored`; the box width follows `mirrored`.
struct MirrorScreen: View {
    let model: MirrorModel
    var body: some View {
        let _ = model.bodies.append(model.source)
        return Color.white
            .frame(width: CGFloat(model.mirrored + 10), height: 10)
            .onChange(of: model.source) { _, new in model.mirrored = new }
    }
}

@MainActor
final class TransactionBoundaryScopeTests: XCTestCase {
    final class Records { var items: [CommitRecord] = [] }

    private func box(_ graph: Graph) -> ResolvedNode? {
        var nodes: [ResolvedNode] = []
        collect(graph.snapshot(), into: &nodes) { $0.kind == "Color" }
        return nodes.first
    }

    private func make(_ model: MirrorModel) -> (Graph, Records) {
        let graph = Graph(MirrorScreen(model: model))
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        let records = Records()
        graph.commitSink = { records.items.append($0) }
        graph.flush()
        return (graph, records)
    }

    // Finding 2: an onChange write that follows an animated change inherits the animated transaction, in the one commit the flush makes.
    func testOnChangeWriteInheritsTheAnimatedTransactionWithoutAnExtraCommit() {
        let model = MirrorModel()
        let (graph, records) = make(model)
        let base = records.items.count
        withAnimation(.linear(duration: 1.0)) { model.source = 40 }
        graph.flush()
        XCTAssertEqual(model.mirrored, 40, "the onChange action ran")
        XCTAssertEqual(records.items.count - base, 1, "one commit for the animated change and the onChange write it triggered")
        XCTAssertEqual(records.items.last?.animation, "linear")
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(box(graph)?.frame.width ?? -1, 30, accuracy: 1e-9, "10 to 50, halfway: the onChange write animates")
        graph.tick(now: 1.0)
        XCTAssertEqual(box(graph)?.frame.width ?? -1, 50, accuracy: 1e-9)
    }

    func testPlainChangeIntoOnChangeIsNotAnimatedAndCommitsOnce() {
        let model = MirrorModel()
        let (graph, records) = make(model)
        let base = records.items.count
        model.source = 40
        graph.flush()
        XCTAssertEqual(records.items.count - base, 1)
        XCTAssertNil(records.items.last?.animation)
        XCTAssertEqual(box(graph)?.frame.width ?? -1, 50, accuracy: 1e-9, "snaps")
    }

    // Finding 1: the boundary settles the graph that owns the pending change, whichever graph flushed last.
    func testBoundarySettlesTheGraphThatOwnsTheState() {
        let modelA = MirrorModel(), modelB = MirrorModel()
        let (graphB, _) = make(modelB)
        let (graphA, _) = make(modelA)  // A flushed last: the old single static boundary pointed at A
        XCTAssertEqual(modelB.bodies, [0])
        modelB.source = 1  // pending in B, plain
        withAnimation { modelB.source = 2 }
        XCTAssertEqual(modelB.bodies, [0, 1], "B's plain write settled at the boundary, as its own transaction")
        graphB.flush()
        XCTAssertEqual(Array(modelB.bodies.prefix(3)), [0, 1, 2])
        XCTAssertEqual(modelA.bodies, [0], "the other window is untouched")
        XCTAssertEqual(graphA.counts().dirty, 0)
    }

    func testAnimatedWriteInOneWindowSettlesAnotherWindowsPriorChangeWithoutCommitting() {
        let modelA = MirrorModel(), modelB = MirrorModel()
        let (graphA, recordsA) = make(modelA)
        let (graphB, _) = make(modelB)
        let base = recordsA.items.count
        modelA.source = 7  // pending in A
        withAnimation { modelB.source = 3 }
        XCTAssertEqual(modelA.bodies, [0, 7], "A's change was made before the new transaction, so it settles at the boundary")
        XCTAssertEqual(recordsA.items.count, base, "settling commits nothing")
        graphA.flush()
        graphB.flush()
        XCTAssertEqual(modelA.mirrored, 7)
        XCTAssertEqual(modelB.mirrored, 3)
    }

    // Finding 3: an async caller whose body dirties nothing still gets its flush.
    func testAsyncWithAnimationThatDirtiesNothingStillSchedulesTheFlush() async {
        let model = MirrorModel()
        let (graph, records) = make(model)
        let base = records.items.count
        await Task { @MainActor in
            model.source = 5  // dirties the body
            withAnimation { }  // settles that change; the body dirties nothing
        }.value
        for _ in 0..<100 where records.items.count == base { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(records.items.count - base, 1, "the settled state is committed without a later unrelated flush")
        XCTAssertEqual(graph.counts().dirty, 0)
    }

    // The settle evaluates the body outside a flush, which queues the onChange action; only the flush the settle schedules can run it.
    func testSettleQueuedOnChangeActionRunsInTheFlushTheSettleSchedules() async {
        let model = MirrorModel()
        let (graph, records) = make(model)
        let base = records.items.count
        await Task { @MainActor in
            model.source = 9
            withAnimation(.linear(duration: 1.0)) { }
            XCTAssertEqual(model.bodies.last, 9, "the settle evaluated the body")
            XCTAssertEqual(model.mirrored, 0, "the onChange action is queued, not yet run")
            XCTAssertEqual(graph.counts().dirty, 0, "nothing dirty: the old `!dirty.isEmpty` guard would skip the flush")
        }.value
        for _ in 0..<100 where model.mirrored != 9 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.mirrored, 9, "the queued action ran")
        XCTAssertEqual(records.items.count - base, 1, "one commit")
    }

    // The existing 0,2,4,4 sequence still holds, in two commits (first render, then the flush's final commit).
    func testNestedUpdateSequenceAndCommitCount() {
        let probe = TransactionProbe()
        let graph = Graph(TransactionBoundaryWitness(probe: probe))
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        var commits = 0
        graph.commitSink = { _ in commits += 1 }
        graph.flush()
        XCTAssertEqual(probe.values, [0, 2, 4, 4])
        XCTAssertEqual(probe.changes, [[0, 2], [2, 4]])
        XCTAssertEqual(commits, 2, "the state before onAppear, and the final state; no commit between the onChange pass")
    }
}
