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

@Observable
@MainActor
final class ChainModel {
    var trigger = 0
    var follower = 0
    var third = 0
    /// What the onChange of `trigger` does with the new value.
    var react: (ChainModel, Int) -> Void = { model, new in model.follower = new }
    /// What the onChange of `follower` does (nothing by default).
    var reactFollower: (ChainModel, Int) -> Void = { _, _ in }
}

/// Two boxes: the white one follows `trigger`, the black one follows `follower`, which an onChange of `trigger` writes.
struct ChainScreen: View {
    let model: ChainModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.white.frame(width: CGFloat(model.trigger + 10), height: 10)
            Color.black.frame(width: CGFloat(model.follower + 10), height: 10)
            Color.gray.frame(width: CGFloat(model.third + 10), height: 10)
        }
        .onChange(of: model.trigger) { _, new in model.react(model, new) }
        .onChange(of: model.follower) { _, new in model.reactFollower(model, new) }
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

    // MARK: Each change commits under the transaction it was made in

    private func chain(_ model: ChainModel) -> (Graph, Records) {
        let graph = Graph(ChainScreen(model: model))
        graph.rootProposal = ProposedViewSize(width: 240, height: 200)
        let records = Records()
        graph.commitSink = { records.items.append($0) }
        graph.flush()
        return (graph, records)
    }

    private func widths(_ graph: Graph) -> [Double] {
        var nodes: [ResolvedNode] = []
        collect(graph.snapshot(), into: &nodes) { $0.kind == "Color" }
        return nodes.map { Double($0.frame.width) }
    }

    func testPlainTriggerWithAnimatedOnChangeWriteSnapsTheTriggerAndAnimatesTheWrite() {
        let model = ChainModel()
        model.react = { model, new in withAnimation(.linear(duration: 1.0)) { model.follower = new } }
        let (graph, records) = chain(model)
        let base = records.items.count
        model.trigger = 40
        graph.flush()
        XCTAssertEqual(records.items.count - base, 2, "the trigger's pass, then the onChange pass under its own transaction")
        XCTAssertNil(records.items[base].animation, "the trigger was made with no transaction")
        XCTAssertEqual(records.items.last?.animation, "linear")
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[0], 50, accuracy: 1e-9, "the trigger snapped")
        XCTAssertEqual(mid[1], 30, accuracy: 1e-9, "the onChange write animates, halfway")
    }

    func testAnimatedTriggerWithNilAnimationOnChangeWriteAnimatesTheTriggerAndSnapsTheWrite() {
        let model = ChainModel()
        model.react = { model, new in withAnimation(nil) { model.follower = new } }
        let (graph, records) = chain(model)
        let base = records.items.count
        withAnimation(.linear(duration: 1.0)) { model.trigger = 40 }
        graph.flush()
        XCTAssertEqual(records.items.count - base, 2)
        XCTAssertEqual(records.items[base].animation, "linear", "the trigger keeps its own transaction")
        XCTAssertNil(records.items.last?.animation)
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[0], 30, accuracy: 1e-9, "the trigger animates")
        XCTAssertEqual(mid[1], 50, accuracy: 1e-9, "the nil-animation write snaps")
    }

    func testAnimatedTriggerWithDifferentAnimationOnChangeWriteKeepsBoth() {
        let model = ChainModel()
        model.react = { model, new in withAnimation(.linear(duration: 2.0)) { model.follower = new } }
        let (graph, records) = chain(model)
        let base = records.items.count
        withAnimation(.linear(duration: 1.0)) { model.trigger = 40 }
        graph.flush()
        XCTAssertEqual(records.items.count - base, 2)
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[0], 30, accuracy: 1e-9, "the trigger runs its own 1 s animation")
        XCTAssertEqual(mid[1], 20, accuracy: 1e-9, "the write runs its own 2 s animation (quarter of the way)")
    }

    func testPlainOnChangeWriteAfterAPlainTriggerCommitsOnce() {
        let model = ChainModel()
        let (graph, records) = chain(model)
        let base = records.items.count
        model.trigger = 40
        graph.flush()
        XCTAssertEqual(records.items.count - base, 1)
        XCTAssertEqual(Array(widths(graph).prefix(2)), [50, 50])
    }

    // A withAnimation nested in the one an onChange action opened: each write commits under the innermost transaction open when it is made (measured on
    // macOS 27, block 41 onchange-animation-v1: the Mac animates the inner write with the inner animation, the outer one with the outer).
    func testNestedWithAnimationInOnChangeInnerWriteTakesTheInnerAnimation() {
        let model = ChainModel()
        model.react = { model, new in
            withAnimation(.linear(duration: 2.0)) {
                model.follower = new
                withAnimation(.linear(duration: 1.0)) { model.third = new }
            }
        }
        let (graph, records) = chain(model)
        let base = records.items.count
        model.trigger = 40
        graph.flush()
        XCTAssertEqual(records.items.dropFirst(base).map { $0.animation }, [nil, "linear", "linear", nil],
                       "the trigger's pass; the outer write under the outer animation; the inner write under the inner one; the flush's closing commit")
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[0], 50, accuracy: 1e-9, "the trigger snapped")
        XCTAssertEqual(mid[1], 20, accuracy: 1e-9, "the outer write runs the outer 2 s animation (a quarter of the way)")
        XCTAssertEqual(mid[2], 30, accuracy: 1e-9, "the inner write runs the inner 1 s animation (halfway)")
    }

    // Outside onChange: x written under the outer transaction, y under the inner one nested in it, z under the outer again.
    func testNestedWithAnimationWritesTakeTheInnermostOpenTransaction() {
        let model = ChainModel()
        let (graph, records) = chain(model)
        let base = records.items.count
        withAnimation(.linear(duration: 2.0)) {
            model.trigger = 40
            withAnimation(.linear(duration: 1.0)) { model.third = 40 }
        }
        graph.flush()
        _ = records.items.dropFirst(base)
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[0], 20, accuracy: 1e-9, "the outer write: 2 s, a quarter of the way")
        XCTAssertEqual(mid[2], 30, accuracy: 1e-9, "the inner write: 1 s, halfway")
    }

    // T -> onChange: withAnimation(a) { follower } -> onChange of follower: withAnimation(nil) { third }
    func testOnChangeChainEachPassCommitsUnderItsOwnTransaction() {
        let model = ChainModel()
        model.react = { model, new in withAnimation(.linear(duration: 1.0)) { model.follower = new } }
        model.reactFollower = { model, new in withAnimation(nil) { model.third = new } }
        let (graph, records) = chain(model)
        let base = records.items.count
        model.trigger = 40
        graph.flush()
        XCTAssertEqual(records.items.dropFirst(base).map { $0.animation }, [nil, "linear", nil],
                       "trigger plain; the follower's pass under the animation; the nil write's pass snaps")
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[0], 50, accuracy: 1e-9)
        XCTAssertEqual(mid[1], 30, accuracy: 1e-9, "the follower animates")
        XCTAssertEqual(mid[2], 50, accuracy: 1e-9, "the third snaps")
    }

    // Two transactions one after the other in one action: the first pass commits under the first, the second under the second.
    func testSequentialTransactionsInOneOnChangeActionCommitSeparately() {
        let model = ChainModel()
        model.react = { model, new in
            withAnimation(.linear(duration: 1.0)) { model.follower = new }
            withAnimation(.linear(duration: 2.0)) { model.third = new }
        }
        let (graph, records) = chain(model)
        let base = records.items.count
        model.trigger = 40
        graph.flush()
        XCTAssertEqual(records.items.dropFirst(base).map { $0.animation }, [nil, "linear", "linear"])
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[1], 30, accuracy: 1e-9, "the first write runs its own 1 s animation")
        XCTAssertEqual(mid[2], 20, accuracy: 1e-9, "the second runs its own 2 s animation")
    }

    // A transaction belongs to the graph whose state its body wrote: another window's commit must not consume it.
    func testQueuedTransactionIsNotConsumedByAnotherWindow() {
        let modelA = MirrorModel(), modelB = MirrorModel()
        let (graphA, recordsA) = make(modelA)
        let (graphB, recordsB) = make(modelB)
        let baseA = recordsA.items.count, baseB = recordsB.items.count
        modelA.source = 40  // plain, in window A
        withAnimation(.linear(duration: 1.0)) { modelB.source = 40 }  // animated, in window B
        graphA.flush()  // A commits first
        XCTAssertNil(recordsA.items.last?.animation, "A's commit does not take B's transaction")
        XCTAssertEqual(box(graphA)?.frame.width ?? -1, 50, accuracy: 1e-9, "A snapped")
        graphB.flush()
        XCTAssertEqual(recordsB.items.count - baseB, 1)
        XCTAssertEqual(recordsB.items.last?.animation, "linear")
        graphB.tick(now: 0)
        graphB.tick(now: 0.5)
        XCTAssertEqual(box(graphB)?.frame.width ?? -1, 30, accuracy: 1e-9, "B animates")
        XCTAssertEqual(recordsA.items.count - baseA, 1)
    }
}
