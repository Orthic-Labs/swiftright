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

@Observable
@MainActor
final class SettlesModel {
    var x = 0
    var y = 0
    var shown = true
}

/// A removable blue bar (opacity transition) above a red bar that follows `x` and a green bar that follows `y`.
struct SettlesScreen: View {
    let model: SettlesModel
    var body: some View {
        VStack(spacing: 0) {
            if model.shown { Color.blue.frame(width: 50, height: 10).transition(.opacity) }
            Color.red.frame(width: CGFloat(model.x) * 20 + 10, height: 10)
            Color.green.frame(width: CGFloat(model.y) * 20 + 10, height: 10)
        }
        .frame(width: 200, height: 80, alignment: .top)
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

    // Outside onChange: `trigger` written under the outer transaction, `third` under the inner one nested in it (#59: the comment named a
    // third write under the outer transaction that the test never made; `follower`, written by trigger's onChange, is not asserted here).
    func testNestedWithAnimationWritesTakeTheInnermostOpenTransaction() {
        let model = ChainModel()
        let (graph, _) = chain(model)
        withAnimation(.linear(duration: 2.0)) {
            model.trigger = 40
            withAnimation(.linear(duration: 1.0)) { model.third = 40 }
        }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[0], 20, accuracy: 1e-9, "the outer write: 2 s, a quarter of the way")
        XCTAssertEqual(mid[2], 30, accuracy: 1e-9, "the inner write: 1 s, halfway")
    }

    // A chain of onChange passes: writing the trigger runs its onChange, which writes `follower` under withAnimation(linear 1 s); that pass's onChange of
    // `follower` writes `third` under withAnimation(nil). Each pass commits under its own transaction: the records read [plain, linear, plain], the
    // follower animates (halfway at 0.5 s) and the third snaps.
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

    // Issue #2 (A): a completion that settles inside a nested block runs after every transaction frame has closed, so its writes do not take the open
    // outer animation. The outer body writes `follower` (2 s); the nested withAnimation(nil) writes `trigger` and its completion writes `third`.
    func testNestedCompletionWritesDoNotInheritTheOuterAnimation() {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, _) = chain(model)
        var completed = false
        withAnimation(.linear(duration: 2.0)) {
            model.follower = 40
            withAnimation(nil) { model.trigger = 40 } completion: {
                completed = true
                model.third = 40
            }
            XCTAssertFalse(completed, "the completion waits for the outer frame to close")
        }
        XCTAssertTrue(completed, "it runs when the outermost frame ends")
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[0], 50, accuracy: 1e-9, "the nested nil write snaps")
        XCTAssertEqual(mid[1], 20, accuracy: 1e-9, "the outer write runs the outer 2 s animation")
        XCTAssertEqual(mid[2], 50, accuracy: 1e-9, "the completion's write is plain: it does not take the outer animation")
    }

    // Issue #2 (B): an outer completion fires only after its own writes have committed and its animation has settled, even when a nested block animates
    // and a segment commit changes no layout. The outer body first writes `follower` to 5 and back to 0 (it notifies, the layout is unchanged), so the
    // segment commit the nested block forces applies the outer transaction to no changed node: before the fix that settled it and ran its completion inside
    // the body, before the outer write that follows the nested block.
    func testOuterCompletionFiresAfterTheOuterWriteCommitsAndSettles() {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, _) = chain(model)
        var fired = false
        withAnimation(.linear(duration: 1.0)) {
            model.follower = 5
            model.follower = 0
            withAnimation(.linear(duration: 1.0)) { model.third = 40 }
            XCTAssertFalse(fired, "the outer completion has not run after the nested block")
            model.trigger = 40  // the outer write that follows the nested block
        } completion: {
            fired = true
        }
        XCTAssertFalse(fired, "not before the outer write has committed")
        graph.flush()
        graph.tick(now: 0)
        XCTAssertFalse(fired)
        graph.tick(now: 0.5)
        XCTAssertFalse(fired, "the outer write is still animating")
        XCTAssertEqual(widths(graph)[0], 30, accuracy: 1e-9)
        graph.tick(now: 1.0)
        XCTAssertTrue(fired, "after the outer animation settles")
        XCTAssertEqual(widths(graph)[0], 50, accuracy: 1e-9)
    }

    // A completion with no enclosing transaction behaves as before: it runs at the tick that ends the animation, and its own write is plain.
    func testCompletionOutsideAnyTransactionRunsAtTheTickAndItsWriteIsPlain() {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, _) = chain(model)
        var fired = false
        withAnimation(.linear(duration: 1.0)) { model.trigger = 40 } completion: {
            fired = true
            model.third = 40
        }
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertFalse(fired)
        graph.tick(now: 1.0)
        XCTAssertTrue(fired)
        graph.flush()
        graph.tick(now: 1.5)
        let w = widths(graph)
        XCTAssertEqual(w[0], 50, accuracy: 1e-9)
        XCTAssertEqual(w[2], 50, accuracy: 1e-9, "the completion's write snaps")
    }

    // A completion that settled inside a nested block while the outer transaction is still queued on its graph (the outer body wrote after the nested
    // block) does not run at a tick, however early: its write would coalesce into the commit that applies the queued outer animation.
    func testTickWhileOuterTransactionIsQueuedDoesNotRunTheNestedCompletion() {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, _) = chain(model)
        var completed = false
        withAnimation(.linear(duration: 2.0)) {
            withAnimation(nil) { model.trigger = 40 } completion: {
                completed = true
                model.third = 40
            }
            model.follower = 40  // outer write after the nested block: the outer transaction is queued at the end of the body
        }
        XCTAssertFalse(completed, "waits: the outer transaction is still queued")
        graph.tick(now: 0)
        XCTAssertFalse(completed, "a tick does not run it")
        graph.flush()
        XCTAssertTrue(completed, "it runs at the commit that applies the outer transaction")
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[1], 20, accuracy: 1e-9, "the outer write runs the outer 2 s animation")
        XCTAssertEqual(mid[2], 50, accuracy: 1e-9, "the completion's write is plain")
    }

    // The same, with another window committing in between: its commit drains completions but does not run this graph's gated one.
    func testAnotherWindowsCommitDoesNotRunACompletionGatedOnAQueuedTransaction() {
        let modelA = ChainModel(), modelB = ChainModel()
        modelA.react = { _, _ in }
        modelB.react = { _, _ in }
        let (graphA, _) = chain(modelA)
        let (graphB, _) = chain(modelB)
        var completed = false
        withAnimation(.linear(duration: 2.0)) {
            withAnimation(nil) { modelA.trigger = 40 } completion: {
                completed = true
                modelA.third = 40
            }
            modelA.follower = 40
        }
        modelB.trigger = 40  // a plain change in window B
        graphB.flush()
        XCTAssertFalse(completed, "B's commit does not run A's gated completion")
        graphA.flush()
        XCTAssertTrue(completed, "A's commit takes the queued outer transaction, then runs it")
        graphA.flush()
        graphA.tick(now: 0)
        graphA.tick(now: 0.5)
        XCTAssertEqual(widths(graphA)[1], 20, accuracy: 1e-9)
        XCTAssertEqual(widths(graphA)[2], 50, accuracy: 1e-9, "plain")
        XCTAssertEqual(widths(graphB)[0], 50, accuracy: 1e-9, "B's own plain change snapped")
    }

    // Two windows: a completion that settles in window A while a transaction is open (the outer body writes window B's state, after A's nested block) waits
    // until B's commit takes that transaction; neither a tick nor A's own commit runs it earlier, and its write is then plain.
    func testCompletionInOneWindowNeverRunsUnderTheOtherWindowsOpenTransaction() {
        let modelA = ChainModel(), modelB = ChainModel()
        modelA.react = { _, _ in }
        modelB.react = { _, _ in }
        let (graphA, _) = chain(modelA)
        let (graphB, _) = chain(modelB)
        var ran = false
        withAnimation(.linear(duration: 2.0)) {
            withAnimation(nil) { modelA.trigger = 40 } completion: {
                ran = true
                modelA.third = 40
            }
            XCTAssertFalse(ran, "A's completion does not run while the outer transaction is open")
            modelB.follower = 40  // window B's write, after the nested block: the transaction is queued on B
        }
        XCTAssertFalse(ran, "B still queues the transaction")
        graphA.tick(now: 0)
        graphA.flush()
        XCTAssertFalse(ran, "neither a tick nor A's commit runs it")
        graphB.flush()
        XCTAssertTrue(ran, "B's commit takes the transaction, then runs the completion")
        graphA.flush()
        graphA.tick(now: 0)
        graphB.tick(now: 0)
        graphA.tick(now: 0.5)
        graphB.tick(now: 0.5)
        XCTAssertEqual(widths(graphA)[2], 50, accuracy: 1e-9, "A's completion write is plain, not B's 2 s animation")
        XCTAssertEqual(widths(graphB)[1], 20, accuracy: 1e-9, "B's own write animates under its transaction")
    }

    // Issue #29 (1): a completion that settles at a tick with no block open, while an unrelated transaction is queued on its graph, does not run until that
    // transaction's commit has taken the queue; its write is then plain, and the unrelated write animates.
    func testTickSettledCompletionDoesNotTakeAnUnrelatedQueuedTransaction() {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, _) = chain(model)
        var completed = false
        withAnimation(.linear(duration: 1.0)) { model.trigger = 40 } completion: {
            completed = true
            model.third = 40
        }
        graph.flush()
        graph.tick(now: 0)
        withAnimation(.linear(duration: 2.0)) { model.follower = 40 }  // unrelated, queued on the graph, not yet committed
        graph.tick(now: 1.0)  // the first animation ends here and its completion settles
        XCTAssertFalse(completed, "the completion waits for the queued transaction's commit")
        graph.flush()
        XCTAssertTrue(completed, "it runs after the commit that took the queue")
        graph.flush()  // commits the completion's write, plain
        graph.tick(now: 1.0)
        graph.tick(now: 1.5)
        let mid = widths(graph)
        XCTAssertEqual(mid[1], 20, accuracy: 1e-9, "the unrelated write runs its own 2 s animation")
        XCTAssertEqual(mid[2], 50, accuracy: 1e-9, "the completion's write snaps")
    }

    // Issue #29 (2a): an outer withAnimation whose only writes are in nested blocks only settles its completion: a later unrelated write is plain, and the
    // commit record names no animation (issue #29 item 4).
    func testSettlesOnlyOuterBlockDoesNotAnimateALaterUnrelatedWrite() {
        let model = SettlesModel()
        let graph = Graph(SettlesScreen(model: model))
        let records = Records()
        graph.commitSink = { records.items.append($0) }
        graph.flush()
        withAnimation(.linear(duration: 2.0)) { withAnimation(nil) { model.x = 1 } }
        let base = records.items.count
        model.y = 1  // plain, later, unrelated
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        var nodes: [ResolvedNode] = []
        collect(graph.snapshot(), into: &nodes) { $0.kind == "Color" }
        XCTAssertEqual(Double(nodes[2].frame.width), 30, accuracy: 1e-9, "the later write snaps: the outer 2 s animation governs nothing")
        XCTAssertTrue(records.items.dropFirst(base).allSatisfy { $0.animation == nil }, "no commit after the block names an animation")
    }

    // Issue #29 (2b): the same outer block governs no later removal (Transition.swift removalTransaction): no ghost is kept.
    func testSettlesOnlyOuterBlockDoesNotAnimateALaterRemoval() {
        let model = SettlesModel()
        let graph = Graph(SettlesScreen(model: model))
        graph.flush()
        XCTAssertEqual(colourCount(graph), 3)
        withAnimation(.linear(duration: 2.0)) { withAnimation(nil) { model.x = 1 } }
        model.shown = false  // plain removal
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(colourCount(graph), 2, "the removed bar is gone at once: no fade-out ghost")
    }

    // Issue #29 hardening: a graph torn down inside a withAnimation body after a write takes no queued transaction (it never commits again), so the block's
    // completion still runs and no completion in the process is held back.
    func testTearDownInsideABodyDoesNotStrandTheCompletion() {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, _) = chain(model)
        var fired = false
        withAnimation(.linear(duration: 1.0)) {
            model.trigger = 40
            graph.tearDown()
        } completion: {
            fired = true
        }
        XCTAssertTrue(fired, "the completion runs: the closed graph holds no queued transaction")
        // an unrelated completion elsewhere is not held back either
        let other = ChainModel()
        other.react = { _, _ in }
        let (otherGraph, _) = chain(other)
        var otherFired = false
        withAnimation(.linear(duration: 1.0)) { other.trigger = 40 } completion: { otherFired = true }
        otherGraph.flush()
        otherGraph.tick(now: 0)
        otherGraph.tick(now: 1.0)
        XCTAssertTrue(otherFired)
    }

    // Issue #29 hardening: flush() called synchronously inside a body commits before the body ends; the transaction is queued at the end of the body with
    // nothing dirty. The scheduled flush still commits a non-empty queue, so the completion runs.
    func testSynchronousFlushInsideABodyDoesNotStrandTheQueuedTransaction() async throws {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, _) = chain(model)
        var fired = false
        withAnimation(.linear(duration: 1.0)) {
            model.trigger = 40
            graph.flush()
        } completion: {
            fired = true
        }
        try await settle(until: { fired })
        XCTAssertTrue(fired, "the scheduled flush took the queued transaction and settled it")
    }

    // Issue #30 (measured on macOS 27): a withAnimation / withTransaction whose body wrote nothing governs no later write. (a) empty withAnimation.
    func testEmptyWithAnimationDoesNotAnimateALaterPlainWrite() {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, records) = chain(model)
        withAnimation(.linear(duration: 2.0)) {}
        let base = records.items.count
        model.follower = 40
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(widths(graph)[1], 50, accuracy: 1e-9, "the later write snaps")
        XCTAssertTrue(records.items.dropFirst(base).allSatisfy { $0.animation == nil })
    }

    // (b) an empty block's completion still fires, once, and the later write snaps.
    func testEmptyWithAnimationCompletionFiresOnceAndALaterWriteSnaps() {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, _) = chain(model)
        var fired = 0
        withAnimation(.linear(duration: 2.0)) {} completion: { fired += 1 }
        XCTAssertEqual(fired, 1, "the completion runs: nothing waits on it")
        model.follower = 40
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(widths(graph)[1], 50, accuracy: 1e-9, "the later write snaps")
        XCTAssertEqual(fired, 1, "once")
    }

    // (c) an empty withTransaction likewise.
    func testEmptyWithTransactionDoesNotAnimateALaterPlainWrite() {
        let model = ChainModel()
        model.react = { _, _ in }
        let (graph, _) = chain(model)
        withTransaction(Transaction(animation: .linear(duration: 2.0))) {}
        model.follower = 40
        graph.flush()
        graph.tick(now: 0)
        graph.tick(now: 0.5)
        XCTAssertEqual(widths(graph)[1], 50, accuracy: 1e-9, "the later write snaps")
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
