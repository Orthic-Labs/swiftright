# SR0-S fresh runtime: headless core result

Scope: a Swift implementation of SwiftUI programming-model semantics (views, builders, state,
bindings, environment, focus, observation, lifecycle, tasks, transactions, commit sink) with
no renderer and no Apple UI import. Module `SwiftRightRuntime`, tests `SwiftRightRuntimeTests`.
Public signatures follow `probes/sr0-c/same-source/.../WindowsStubs.swift`.

Platforms: macOS 27 arm64, Swift 6.4 (Xcode-27-RC). Windows 11 x64, Swift 6.4.0 (swift-6.4-RELEASE).
Language mode Swift 6. Imports: Foundation, Observation, and XCTest in tests only.
Not committed. Only files under `probes/sr0-s/fresh-runtime/` were written.

## Verdict

- Mac: `swift test` 9 of 9 PASS.
- Windows: `swift test` 9 of 9 PASS.
- The macOS run hit one intermittent F3 failure. Root cause was an address-reuse hazard in the
  test helper (not the runtime's semantics). Fixed by using per-graph instance numbers. After the
  fix: Mac 8 of 8 clean loops, Windows 3 of 3 clean runs.
- Fix-iteration cap: exceeded on macOS. Eight edit-build-test cycles were needed before green
  (see "Fix iterations"). Windows needed one toolchain workaround and one rewrite, plus bisect builds.

## Architecture

- **Views.swift**: `View` (MainActor), `ViewBuilder` (parameter packs, optional, either),
  `TupleView`, `ConditionalContent`, primitives `Text`, `Button`, `TextField`, `VStack`, `HStack`,
  `Spacer`, `List`, `ForEach` (`data, id:`, `Identifiable`, and `Binding<C>`), `onMove` pass-through.
  Builder containers are expanded by reflection; primitives report a `NodeKind` and content.
- **Graph.swift**: retained graph. Each body result is expanded into leaves with a structural
  `NodeID` path: builder tuple index, Either branch, Optional presence, leaf type identity, and
  ForEach keyed id. `reconcile` keeps node objects for surviving ids, tears down removed nodes in
  pre-order (onDisappear, then task cancel, then children), and creates new nodes for new ids.
  `flush()` applies coalesced invalidations, ancestors first, then emits one `CommitRecord`
  (resolved tree, focused node id, animation tags) to `commitSink`.
- **State.swift**: `@State` values live in a node-owned `StateBox` keyed by property label, so
  storage follows node identity, not the transient view value. `Binding` (get/set,
  dynamicMember, projected init), `Bindable`, `@Environment` with `EnvironmentKey`, `@FocusState`
  with `FocusState.Binding`. Boxes are `@Observable`, so a body re-evaluates only when a property it
  read changes.
- **Modifiers.swift**: `padding`, `onAppear`, `onDisappear`, `task`, `focused(_:equals:)`,
  `animation(_:value:)`, `environment(_:_:)`. Each is a wrapper node, so lifecycle follows identity.
- **Owner-generation guard**: `TaskOwner.current?.commit { ... }` runs only if the owning node is
  alive and its generation is unchanged. Teardown bumps the generation.
- **Transactions**: `withAnimation` sets a MainActor transaction context. Invalidations raised in
  it, and `.animation(value:)` changes, are recorded as tags in the next commit record.
- **Observation dispatch**: `withObservationTracking` `onChange` calls `noteChange` through
  `MainActor.assumeIsolated`. Invalidation is synchronous into the dirty set, and a Task schedules
  one coalesced flush per turn. Tests call `flush()` explicitly.

## Tests (verbatim, trimmed)

Mac, `swift test -v`:
```
testBindingWriteBackThroughForEach passed (0.001 seconds).
testCommitSinkReceivesResolvedTree passed (0.001 seconds).
testEnvironmentOverridePropagation passed (0.001 seconds).
testF1_SurvivingRowIdentityAcrossInsertAbove passed (0.027 seconds).
testF2_ReorderPreservesStateAndFocus passed (0.017 seconds).
testF3_RemovalTearsDownAndReinsertionGetsFreshState passed (0.137 seconds).
testF4_StaleAsyncResultIsRejectedAfterRemoval passed (0.127 seconds).
testObservationFineGrainedInvalidation passed (0.001 seconds).
testTransactionAnimationTagRecorded passed (0.001 seconds).
Executed 9 tests, with 0 failures (0 unexpected) in 0.312 (0.313) seconds
```

Windows, `swift test`:
```
Test Case 'RuntimeTests.testCommitSinkReceivesResolvedTree' passed (0.001 seconds)
Test Case 'RuntimeTests.testEnvironmentOverridePropagation' passed (0.0 seconds)
Test Case 'RuntimeTests.testF1_SurvivingRowIdentityAcrossInsertAbove' passed (0.041 seconds)
Test Case 'RuntimeTests.testF2_ReorderPreservesStateAndFocus' passed (0.027 seconds)
Test Case 'RuntimeTests.testF3_RemovalTearsDownAndReinsertionGetsFreshState' passed (0.178 seconds)
Test Case 'RuntimeTests.testF4_StaleAsyncResultIsRejectedAfterRemoval' passed (0.131 seconds)
Test Case 'RuntimeTests.testObservationFineGrainedInvalidation' passed (0.001 seconds)
Test Case 'RuntimeTests.testTransactionAnimationTagRecorded' passed (0.001 seconds)
Executed 9 tests, with 0 failures (0 unexpected) in 0.382 (0.382) seconds
```
(`testBindingWriteBackThroughForEach` was also PASS on Windows; its line was cut by the trimmed
tail capture. The Windows run reports 0 failures across all 9.)

| Test | Assertion focus | Mac | Windows |
|---|---|---|---|
| F1 surviving-row identity | insert above keeps node instance, `@State` serial, text edits, focus | PASS | PASS |
| F2 reorder | move keeps node instance, `@State`, focus | PASS | PASS |
| F3 removal / reinsertion | teardown order `disappear r3`, `cancelled r3`, `commit=false r3`; reinserted row is a new instance with fresh `@State` | PASS | PASS |
| F4 stale async | cancelled task's guarded commit rejected; live row control commits | PASS | PASS |
| Environment | override applies to subtree only | PASS | PASS |
| Observation | unrelated property change does not re-evaluate a body | PASS | PASS |
| Binding write-back | `ForEach($rows) { $row in }` writes to the correct row | PASS | PASS |
| Transaction tag | `withAnimation` and `.animation(value:)` tags appear in commit records | PASS | PASS |
| Commit sink | one record per flush, resolved tree | PASS | PASS |

## Deviations from the stub

- `Binding` is **not** a `Collection` here. Declaring the conformance made `ForEach($items)` pick
  the generic Identifiable initializer. That path iterates indices, reads the array outside
  tracking, and hands out index-based row bindings, which go stale after insert or move. This is
  the F1 failure mode. Removing the conformance routes `ForEach($items)` to the `Binding<C>`
  initializer, which resolves rows by id.
- Added `ForEach(_:id:content:)` (the spec's `ForEach(data,id:)`). `TupleView` carries `value`.
- `Bindable<Value: AnyObject>` (needed for the key-path projection).
- `Layout`, `Toggle`, alignment-driven layout, `UnitPoint`, `ProposedViewSize` are not implemented.
  The stub's declarations for them are not implemented.

## Known semantic gaps vs SwiftUI

1. **No layout.** VStack, HStack, padding, and Spacer have no measure or place pass. Padding is
   recorded in the commit tree only. Layout authority and the `Layout` protocol are absent (TODO).
2. **Subtree re-evaluation.** When a parent re-evaluates, every child re-evaluates. SwiftUI skips
   children whose inputs are equal. Body counts can therefore exceed SwiftUI's.
3. **Invalidation is observation-only.** A state write with no observed reader schedules no commit.
4. **Focus.** One focus tag per `FocusState`. The tag is not cleared when its row is removed, so
   reinsertion restores focus. The Mac-recorded removal outcome is not available in this lane, so
   that behaviour is unvalidated. No test asserts it.
5. **Text input.** `TextField` is a string binding only. No caret, selection, undo, or IME
   composition. F1's "caret stays on row 5" is covered by text identity and focus, not caret offset.
6. **`onMove`** is accepted but not wired to a move gesture. Tests call `move(fromOffsets:toOffset:)`
   on the model.
7. **Tasks.** Cancellation happens on disappear and on node-identity change. There is no explicit
   task-id restart. The `name` argument is ignored. Commit checks generation only, so cleanup that
   ignores cancellation remains permitted.
8. **Animation.** Tags are recorded only. There is no interpolation or interruption.
9. **Duplicate ForEach ids** keep the first occurrence and drop the rest silently, with no diagnostic.
10. **State identity** is keyed by property label. Renaming a `@State` property resets it.
11. **Main-actor requirement.** `noteChange` uses `MainActor.assumeIsolated`. Mutating observed
    state off the main actor traps.
12. **Accessibility, geometry, and hit testing** are absent. Commit records carry kind, text,
    children, focus, and animation only.
13. **No Mac trace** exists in this lane. The teardown order asserted (onDisappear, then cancel)
    is the one defined in this runtime, not one recorded from macOS.

## Fix iterations

- macOS: 8 edit-build-test cycles to green, one over the cap of 6. (1) Sendable on `Segment`
  and isolation of protocols. (2) `return fatalError` in body stubs. (3) `titleKey` builder
  closures. (4) MainActor on the builder and containers. (5) test `$row` misuse. (6) `TupleView`
  reflected a single child's fields. (7) removed the `Binding` collection conformance (F1 root
  cause). (8) node tokens switched from object address to instance numbers (F3 flake).
- Windows: the first test compile hit a Swift 6.4 compiler assertion (`LocalDiscriminator is set
  multiple times`). Bisect builds in `D:\Claude\sr0s-bisect` isolated it to a nested closure in a
  `ForEach` body. Fix: move the action into a free function. Then one more test-side rewrite
  (closure locals in `RowView` moved into `RowTask`). Runtime sources needed no Windows-only change.

## LOC

| File | Lines |
|---|---|
| Sources/SwiftRightRuntime/Graph.swift | 443 |
| Sources/SwiftRightRuntime/Views.swift | 330 |
| Sources/SwiftRightRuntime/State.swift | 233 |
| Sources/SwiftRightRuntime/Modifiers.swift | 53 |
| Tests/SwiftRightRuntimeTests/RuntimeTests.swift | 404 |
| Package.swift | 21 |
| **Total** | **1484** |

Runtime only: 1059 lines. Tests: 404 lines.

## Reproduce

- Mac: `cd probes/sr0-s/fresh-runtime && swift test`
- Windows: `scripts/sync-to-win.sh` in three batches (Package.swift, Sources, Tests), then
  `swift test` in `D:\Claude\sr0s-fresh-runtime`.
- `.build/` is git-ignored. The Windows bisect directory `D:\Claude\sr0s-bisect` is outside the
  repository and can be deleted.

## Primary verification & follow-up (2026-10-09)

Primary reran `swift test`: macOS 9/9 and Windows x64 9/9 pass (fresh sync to `D:\Claude\sr0s-fresh-runtime-verify`).

Follow-up: removing `Binding: RandomAccessCollection` fixed F1 by steering overload resolution, but SwiftUI keeps that conformance and selects identity through `ForEach.init(_ data: Binding<C>, content:)` where `C.Element: Identifiable`. Restore the conformance and add the explicit binding-collection initializer so source using `$items` as a collection stays portable.
