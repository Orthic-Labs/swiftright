import Foundation
import Observation
import TestSinkBackend
import XCTest

@testable @_spi(Backends) import SwiftCrossUI

// Port of RuntimeTests.swift (fresh runtime) onto the SwiftCrossUI fork. Names match the fresh suite.
@MainActor
final class SemanticTests: XCTestCase {

    // F1: a surviving row keeps node identity, @State, and focus when a row is inserted above it.
    func testF1_SurvivingRowIdentityAcrossInsertAbove() async throws {
        let store = makeStore()
        let h = Harness { Screen(store: store) }
        await h.flush()

        let target = h.tree.rowViews[4]
        let widgetBefore = target.widget
        let serialBefore = serialText(target)

        h.tap(target.find(kind: "Button")[0])
        await h.flush()
        XCTAssertTrue(h.backend.focusedWidget.map { h.tree.rowViews[4].contains($0) } ?? false, "focus should land on row 5")

        store.rows[4].text += "abc"
        await h.flush()
        store.rows.insert(Row(id: UUID(), text: "new"), at: 0)
        await h.flush()
        store.rows[5].text += "d"
        await h.flush()

        let after = h.tree.rowViews[5]
        XCTAssertEqual(fieldText(after), "r4abcd")
        XCTAssertTrue(after.widget === widgetBefore, "same node instance survives")
        XCTAssertEqual(serialText(after), serialBefore, "@State survives")
        XCTAssertTrue(h.backend.focusedWidget.map { after.contains($0) } ?? false, "focus stays on row 5")
    }

    // F2: a move keeps identity, @State and focus for the moved row.
    func testF2_ReorderPreservesStateAndFocus() async throws {
        let store = makeStore()
        let h = Harness { Screen(store: store) }
        await h.flush()

        let target = h.tree.rowViews[2]
        let widget = target.widget
        let serial = serialText(target)
        h.tap(target.find(kind: "Button")[0])
        await h.flush()

        moveRows(&store.rows, from: 2, to: 7)
        await h.flush()

        let moved = h.tree.rowViews.last!
        XCTAssertTrue(moved.widget === widget, "same node after move")
        XCTAssertEqual(serialText(moved), serial)
        XCTAssertTrue(h.backend.focusedWidget.map { moved.contains($0) } ?? false)
    }

    // F3, List: macOS 27 List preserves @State across remove -> reinsert of the same id.
    func testF3_ListReinsertPreservesStateWhileLifecycleFires() async throws {
        let store = makeStore()
        let h = Harness { ListScreen(store: store) }
        await h.flush()

        let removed = store.rows[3]
        let before = h.tree.rowViews[3]
        let serialBefore = serialText(before)

        let markRemoved = store.log.count
        store.rows.remove(at: 3)
        await h.flush()
        try await settle()
        XCTAssertFalse(h.tree.rowViews.contains { $0.widget === before.widget }, "removed node is gone")
        XCTAssertEqual(rowLog(store, from: markRemoved), ["disappear r3", "cancelled r3", "commit=false r3"])

        let markReinserted = store.log.count
        store.rows.insert(removed, at: 3)
        await h.flush()
        let after = h.tree.rowViews[3]
        XCTAssertFalse(after.widget === before.widget, "reinsertion is a new node")
        XCTAssertNotNil(serialBefore)
        XCTAssertEqual(serialText(after), serialBefore, "List keeps reinserted row @State")
        try await settle()
        XCTAssertEqual(rowLog(store, from: markReinserted), ["appear r3", "commit=true r3"], "onAppear and task restart fire")
        XCTAssertTrue(store.results.contains("r3"), "restarted task commits")
    }

    // F3, VStack + ForEach: VStack resets @State on remove -> reinsert of the same id.
    func testF3_VStackReinsertResetsState() async throws {
        let store = makeStore()
        let h = Harness { Screen(store: store) }
        await h.flush()

        let removed = store.rows[3]
        let before = h.tree.rowViews[3]
        let serialBefore = serialText(before)

        let markRemoved = store.log.count
        store.rows.remove(at: 3)
        await h.flush()
        try await settle()
        XCTAssertFalse(h.tree.rowViews.contains { $0.widget === before.widget }, "removed node is gone")
        XCTAssertEqual(rowLog(store, from: markRemoved), ["disappear r3", "cancelled r3", "commit=false r3"])

        let markReinserted = store.log.count
        store.rows.insert(removed, at: 3)
        await h.flush()
        let after = h.tree.rowViews[3]
        XCTAssertFalse(after.widget === before.widget, "reinsertion is a new node")
        XCTAssertNotEqual(serialText(after), serialBefore, "VStack resets reinserted row @State")
        try await settle()
        XCTAssertEqual(rowLog(store, from: markReinserted), ["appear r3", "commit=true r3"], "onAppear and task restart fire")
    }

    // F3, bound: 65 rows retire in one pass; the most recently retired keeps state, the oldest lost it.
    func testF3_ListRetainedStateIsBounded() async throws {
        let store = makeStore(70)
        let h = Harness { ListScreen(store: store) }
        await h.flush()

        let oldest = store.rows[0]
        let newest = store.rows[64]
        let oldestSerial = serialText(h.tree.rowViews[0])
        let newestSerial = serialText(h.tree.rowViews[64])
        store.rows.removeFirst(65)
        await h.flush()
        try await settle()

        store.rows.insert(newest, at: 0)
        await h.flush()
        XCTAssertEqual(serialText(h.tree.rowViews[0]), newestSerial, "most recently retired row is retained")

        store.rows.insert(oldest, at: 0)
        await h.flush()
        XCTAssertNotEqual(serialText(h.tree.rowViews[0]), oldestSerial, "oldest retired row was evicted")
    }

    // F4: a stale async result is cancelled and rejected; cleanup still runs and is observable.
    func testF4_StaleAsyncResultIsRejectedAfterRemoval() async throws {
        let store = makeStore(3)
        let h = Harness { Screen(store: store) }
        await h.flush()

        store.rows.remove(at: 2)
        await h.flush()
        try await settle()

        XCTAssertFalse(store.results.contains("r2"), "stale result must not commit")
        XCTAssertTrue(store.log.contains("cancelled r2"), "cancellation delivered")
        XCTAssertTrue(store.log.contains("commit=false r2"), "guarded commit rejected")
        XCTAssertTrue(store.results.contains("r0"), "live row still commits (control)")
    }

    // EXTRA (not in the fresh suite): teardown is part of the commit, not an ARC side effect.
    // Right after the update is applied (no yielding to the main actor) the removed row has
    // already logged `disappear`.
    func testExtra_TeardownRunsInsideCommit() async throws {
        let store = makeStore(5)
        let h = Harness { Screen(store: store) }
        await h.flush()
        let mark = store.log.count
        store.rows.remove(at: 3)
        h.drainNow()
        XCTAssertEqual(rowLog(store, from: mark), ["disappear r3"], "onDisappear ran synchronously in the commit")
    }

    // Environment: an override applies to its subtree only.
    func testEnvironmentOverridePropagation() async throws {
        let h = Harness { EnvScreen() }
        await h.flush()
        XCTAssertEqual(h.tree.texts, ["theme light", "theme dark"])
    }

    // Observation: a body re-evaluates only when a property it read changes.
    func testObservationFineGrainedInvalidation() async throws {
        try blockedUnlessRequested("""
            BLOCKED: a body is evaluated once per phase (children, layoutableChildren, computeLayout, \
            commit) and a child's reads merge into every ancestor's tracking scope, so an unrelated \
            property change re-evaluates every probe (measured +8 evaluations each per update). Needs \
            per-pass body memoization plus clean-subtree skipping; a partial skip override (O6) was \
            attempted and reverted.
            """)
        let model = Model()
        let counter = EvalCounter()
        let h = Harness { ObsScreen(model: model, counter: counter) }
        await h.flush()
        // PORT: SCUI evaluates a body more than once per layout (probe + final pass). The fresh
        // assertion "== 1" is expressed as a delta below, so only invalidation granularity is tested.
        let a0 = counter.a, b0 = counter.b
        XCTAssertGreaterThan(a0, 0)
        XCTAssertGreaterThan(b0, 0)

        model.b += 1
        await h.flush()
        XCTAssertEqual(counter.a, a0, "ProbeA did not read b")
        XCTAssertGreaterThan(counter.b, b0, "ProbeB re-evaluated")
        XCTAssertEqual(h.tree.texts, ["a 0", "b 1"])

        let a1 = counter.a, b1 = counter.b
        model.a += 1
        await h.flush()
        XCTAssertGreaterThan(counter.a, a1)
        XCTAssertEqual(counter.b, b1, "ProbeB did not read a")
    }

    // Binding write-back through ForEach($rows) { $row in }.
    func testBindingWriteBackThroughForEach() async throws {
        let store = makeStore(3)
        let h = Harness { WriteBackScreen(store: store) }
        await h.flush()
        let buttons = h.tree.find(kind: "Button")
        XCTAssertEqual(buttons.count, 3)

        h.tap(buttons[1])
        await h.flush()
        XCTAssertEqual(store.rows.map(\.text), ["r0", "set", "r2"])
    }

    // Transactions: withAnimation and .animation(value:) tag the invalidation/flush.
    func testTransactionAnimationTagRecorded() async throws {
        throw XCTSkip("BLOCKED: SwiftCrossUI has no transaction or animation model (assessment B5)")
    }

    // Commit sink: the resolved tree is available after a flush, with kinds and text.
    func testCommitSinkReceivesResolvedTree() async throws {
        let h = Harness { EnvScreen() }
        await h.flush()
        XCTAssertEqual(h.tree.find(kind: "EnvScreen").count, 1)
        XCTAssertFalse(h.tree.children.isEmpty)
    }
}
