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

## SR0-S follow-up: binding collection and runtime layout engine (2026-10-09)

Scope: `probes/sr0-s/fresh-runtime/` only. Not committed, no branch, no push. Swift 6.4, Swift 6 mode,
Foundation and Observation only (XCTest in tests only).

### Verdict

- Mac (arm64, macOS 27, Xcode-27-RC Swift 6.4): `swift test` 19 of 19 PASS (two clean runs).
- Windows (x64, swift-6.4.0 RELEASE): `swift test` 19 of 19 PASS (one clean run).
- Fix iterations: Mac 3 of 6 (see below). Windows 0 (no Windows-only edits).

### Verbatim output (trimmed)

Mac, `swift test`:
```
Test Suite 'BindingCollectionTests' passed. Executed 3 tests, with 0 failures (0 unexpected)
Test Suite 'LayoutTests' passed. Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'RuntimeTests' passed. Executed 9 tests, with 0 failures (0 unexpected)
Executed 19 tests, with 0 failures (0 unexpected) in 0.338 (0.344) seconds
```

Windows, `swift test`:
```
Executed 3 tests, with 0 failures (0 unexpected) in 0.243 (0.243) seconds
Executed 7 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
Executed 9 tests, with 0 failures (0 unexpected) in 0.363 (0.363) seconds
Executed 19 tests, with 0 failures (0 unexpected) in 0.61 (0.61) seconds
```

### What changed

1. **Binding collection (supersedes the "Deviations" note above).** `Binding` now conforms to
   `Sequence`, `Collection`, `BidirectionalCollection`, `RandomAccessCollection` and `MutableCollection`
   when `Value` is a `MutableCollection & RandomAccessCollection`. Element bindings are addressed by index
   on access, as in SwiftUI. `ForEach($items) { $item in }` selects the `Identifiable` initializer
   `ForEach.init(_: Binding<C>, content:)` and `ForEach.init(_:, id: KeyPath, content:)`; identity comes
   from the element id. The generic index-based `ForEach` initializers are marked `@_disfavoredOverload`
   so they do not win overload resolution. F1 through F4 stay green. New tests: `$items.count`,
   `$items[0]`, element write-back, and keypath identity surviving an insert above.
2. **Layout engine (new).** Proposal/response layout with `ProposedViewSize` (nil, finite, infinite).
   `Text` wraps through `TextMeasurer`. `Spacer` takes remaining main-axis space. `HStack` and `VStack`
   support alignment and spacing, distributing least-flexible children first. `List` is a vertical stack
   with zero spacing that fills the cross axis. `padding` is a geometry node. The public `Layout` protocol
   (`sizeThatFits`, `placeSubviews`, `Subviews`, `ProposedViewSize`, per-container cache) is implemented.
   Measurement is memoized per node by text and wrap width.
3. **Text measurement.** `TextMeasurer` is a synchronous `@MainActor` protocol. `FixedAdvanceTextMeasurer`
   gives a fixed advance per character, greedy word wrap at the proposed width, and counts requests per text.
4. **Commit output.** `ResolvedNode` now carries `frame` (logical points, edges snapped to the physical pixel
   grid) and `pixelFrame` (integer device pixels). `Graph(_:measurer:scale:)` and `rootProposal` set the
   scale and the root size.

### Tests added

- Text wraps to two lines when the proposed width shrinks to 60 pt (56 x 32 pt).
- HStack with Spacer: widths [8, 268, 8] at width 300, minX [0, 16, 292].
- VStack alignment leading, center, trailing: short-line minX 0, 28, 56.
- Padding: child inset by 10 pt, container 36 x 36 pt.
- Custom `Layout`: side by side at width 300, stacked at 150, side by side again at 300 (threshold 200).
- Pixel alignment at scale 2.5: every edge lands on an integer pixel; a 25 pt offset becomes 25.2 pt (63 px).
- Relayout: changing one Text re-measures only that text (siblings hit the memo).

### Semantics knowingly diverging from SwiftUI

- `Layout` has no layout values, priorities or spacing APIs (per CONTRACT section 2 subset).
- Pixel rounding snaps each edge to the nearest device pixel. SwiftUI rounds per layout rules that are not
  reproduced here.
- Padding uses a fixed default of 16 pt when no length is given. SwiftUI uses platform-dependent defaults.
- Stack spacing defaults to 8 pt. SwiftUI's default is style- and context-dependent.
- Alignment is applied only on the cross axis. Spacer minimum length is respected, but spacer flexibility
  is a simple least-flexible-first split rather than SwiftUI's full priority system.
- The text measurer is fixed-advance. Real shaping, baselines and line breaking (Rust side, per architecture
  section 6) are not exercised.
- `ForEach` keypath and binding identity are by id; duplicate ids keep the first occurrence (unchanged).
- `.task`, animation, focus and environment semantics are unchanged from the prior section.
- `Layout` is `@MainActor`, and measurement runs synchronously during commit, so it cannot pump tasks.

### Fix iterations (Mac)

1. Foundation's `CGRect`/`CGSize` on this toolchain lacked `minX` and `zero` and `CGSize` was not
   `Equatable`. Replaced with portable `LayoutPoint`, `LayoutSize` and `LayoutRect`, which also keeps
   Windows and Mac identical.
2. Binding collection conformances needed their inherited protocols declared explicitly.
3. `ForEach($items)` regressed to index identity (F1 and F2 failed). Fixed with `@_disfavoredOverload`
   on the generic initializers.

### LOC

| File | Lines |
|---|---|
| Sources/SwiftRightRuntime/Geometry.swift | 147 |
| Sources/SwiftRightRuntime/Graph.swift | 477 |
| Sources/SwiftRightRuntime/Layout.swift | 92 |
| Sources/SwiftRightRuntime/LayoutEngine.swift | 234 |
| Sources/SwiftRightRuntime/Modifiers.swift | 54 |
| Sources/SwiftRightRuntime/State.swift | 256 |
| Sources/SwiftRightRuntime/TextMeasurement.swift | 89 |
| Sources/SwiftRightRuntime/Views.swift | 391 |
| Tests/SwiftRightRuntimeTests/BindingCollectionTests.swift | 58 |
| Tests/SwiftRightRuntimeTests/LayoutTests.swift | 216 |
| Tests/SwiftRightRuntimeTests/RuntimeTests.swift | 404 (unchanged) |
| Package.swift | 21 |
| **Total** | **2439** |

Runtime only: 1740 lines (was 1059). Tests: 678 lines (was 404).

### Reproduce

- Mac: `cd probes/sr0-s/fresh-runtime && swift test`
- Windows: `scripts/sync-to-win.sh probes/sr0-s/fresh-runtime 'D:\Claude\sr0s-fresh-runtime-2'`, then
  `swift test` in `D:\Claude\sr0s-fresh-runtime-2` with the Swift runtime bin directory on PATH.

## SR0-S F3 alignment: List retains removed-row state (2026-10-09)

Source of truth: `conformance/sr0-slice/CONTRACT.md` F3 row and `probes/sr0-o/fixtures/RESULT.md`
("F3 oracle table" and "Primary verification"). macOS 27.0.1 oracle: List preserves row `@State`
across remove → reinsert of the same id (gaps 0/1/3 s); VStack and LazyVStack reset it. Teardown
(onDisappear, task cancel) and reinsert (onAppear, task restart) fire in all containers.

### Result

| Platform | `swift test` | Fix iterations |
|---|---|---|
| macOS 27 arm64, Swift 6.4 | PASS 21 of 21 (3 further repeats: 21 of 21 each) | 0 (first run green) |
| Windows 11 x64, Swift 6.4.0 | PASS 21 of 21 (2 further repeats: 21 of 21 each) | 0 (first run green) |

Baseline before the change: Mac 19 of 19. The 19 original tests stay green. F3 became three tests
(List preserve, VStack reset, bound) so the total is 21.

### Change (runtime, `Sources/SwiftRightRuntime/`)

- `LayoutEngine.swift`: `StackSpec.retainsRemovedRowState` (default false).
- `Views.swift`: `List` sets it true. VStack and HStack leave it false.
- `Graph.swift`: `RowStateCache` on each node. When a keyed child (ForEach row) is removed from a
  retaining container, `teardown` runs as before (lifecycle first), then stores each removed node's
  `@State` storage under its full `NodeID`. When a node is created under a retaining ancestor, a
  cached entry for that `NodeID` is restored into the new node's storage before its first evaluate,
  so `@State` binds to the old box. Restored entries are consumed.

### Assumptions (PROVISIONAL, pending oracle traces)

- Cache lifetime: the List's own lifetime. The cache dies with the List node.
- Bound: 64 retired top-level rows, oldest evicted first. The value is not derived from the oracle.
- Scope: only keyed (ForEach) rows are retained. Unkeyed List children are not.
- Gaps: the oracle recorded 0/1/3 s gaps. Longer gaps and List destruction are not yet traced.
- Not covered: LazyVStack has no runtime node yet, so the "LazyVStack resets" half of F3 is not
  asserted here. The VStack case is asserted; the LazyVStack case waits for a LazyVStack primitive.

### Tests (`Tests/SwiftRightRuntimeTests/RuntimeTests.swift`)

- `testF3_ListReinsertPreservesStateWhileLifecycleFires`: removal logs disappear, cancelled,
  commit=false. Reinsert keeps the old serial text. Reinsert logs appear and commit=true after restart.
- `testF3_VStackReinsertResetsState`: same lifecycle assertions, fresh `@State` (serial changes).
- `testF3_ListRetainedStateIsBounded`: 65 rows retire in one pass. The newest keeps state, the
  oldest (evicted) does not.
- `RowView` gained `onAppear` logging (`appear rN`). `ListScreen` is the List variant of `Screen`.
- Not asserted: focus after reinsert (the oracle records focus, but the runtime test does not yet check it).

### Reproduce

- Mac: `cd probes/sr0-s/fresh-runtime && swift test`
- Windows: `scripts/sync-to-win.sh probes/sr0-s/fresh-runtime 'D:\Claude\sr0s-fresh-runtime-v4'`, then
  `swift test` in `D:\Claude\sr0s-fresh-runtime-v4` with the Swift runtime bin on PATH.
- Nothing committed, pushed, or branched. Writes limited to `probes/sr0-s/fresh-runtime/`.

## SR0-S closure of Windows-matrix gaps: focus, teardown, task(id:), containers, animation, IME (2026-10-09)

Scope: `probes/sr0-s/fresh-runtime/` only. Foundation and Observation only, Swift 6 mode. Headless: no windows opened on
Windows. Nothing committed, branched or pushed. Mac oracle: `probes/sr0-o/fixtures/RESULT.md` and its out/ traces.

### Verdict

| Platform | `swift test` | New tests | Fix iterations |
|---|---|---|---|
| macOS 27 arm64, Swift 6.4 | PASS 46 of 46 (21 prior + 25 new, one full run after the last edit) | 25 | 3 of 6 (cycle 1: compile, redeclared fixture name, missing fixture, generic inference; cycle 2 and 3: task(id:) test settled before the id change, then asserted a task event before the task had run) |
| Windows 11 x64, swift-6.4.0 | PASS 46 of 46 (exit 0, first run) | 25 | 0 of 6 |

The 21 prior tests stay green on both platforms. Windows run: `D:\Claude\sr0s-fresh-runtime-v6`, script
`D:\Claude\sr0s-ps\run-sr0s-tests.ps1` (Swift runtime bin on PATH; output in `swift-test-out.txt`).

### Changes by item

1. **Focus cleared on removal (all containers).** `.focused(_:equals:)` carries a `FocusLink` (isFocused, focus, release).
   Removing a focused node calls `release`, which resets the FocusState to its default (nil) only while it still names that
   row. Mac trace: removal gives `focused=none` in List, VStack and LazyVStack alike.
   **Decision (conflict resolved from the oracle):** the brief said a reinserted row is not focused. The Mac F3 trace says
   otherwise for `List`: focus is restored to the reinserted row (`reinsert-focus focused`, 3 runs at 1 s, plus the 0 s and 3 s
   tables). VStack and LazyVStack do not restore. The runtime therefore restores focus on reinsert for `List` only, through
   `RowStateCache` (`takeFocus`), and not for the other containers. Tests: `FocusContainerTests`.
2. **Tree release after teardown.** `Graph.tearDown()` runs disappear, cancels tasks, drops motions and text state, releases
   every node (`releaseContents`: @State storage, environment values, view values, row caches, text state), emits one final
   record with a nil root, clears the commit sink, and closes the graph (later flush/tick commit nothing).
   **Retention found and fixed:** (a) observation `onChange` closures captured the node and the graph strongly. They sit in
   each `StateBox` registrar, so `node -> storage -> box -> registrar -> closure -> node` was a cycle that never broke. Fixed
   with `NodeHandle` (a weak link to the node) and `[weak self]`. Verified: restoring the strong capture makes the release test
   fail on both the graph and every node. (b) `TaskOwnerToken` held the node strongly, so a task that outlives its cancel
   (the F9 engine case) kept its node alive. Now it holds a `NodeHandle`. Not separately tested (see gaps). (c) `RowStateCache`
   retained removed rows' storage and focus until eviction. It is now cleared with the node. (d) Focus registry: none in the
   runtime; focus lives in the FocusState cell, and the focus link closures capture the binding, not a node. Tests:
   `TeardownTests` (weak refs to graph, nodes, @State value, List rows with row cache, final record, no commit after teardown).
3. **`task(id:)`.** A non-nil id restarts the task when it changes: the old run is cancelled, its token stops matching
   (generation bump), and the new run starts. Same id re-evaluation does not restart. Disappear cancels as before. The
   `task(name:)` form is unchanged. Tests: `TaskIDTests`.
4. **LazyVStack and ScrollView.** `LazyVStack` realizes all rows like VStack (no virtualization) and resets a reinserted row's
   @State (Mac oracle, LazyVStack in a ScrollView). `ScrollView` is vertical only: it takes the proposal, lays content out at
   its ideal height, shifts it by the scroll offset, and clamps the offset to `[0, content - viewport]`. `Graph.scroll(_:to:)`
   sets the offset; the next flush applies it. No clipping is modeled; off-viewport rows appear in the commit record.
   Tests: `LazyContainerTests`, `ScrollViewTests`.
5. **Animation transactions on the injected clock.** `withAnimation(_:_:completion:)` (SwiftUI shape). `Animation` gains
   duration and curve (`linear`, `easeIn`, `easeOut`, `easeInOut`, each a constructor). `Graph.tick(now:)` advances motions;
   each commit that changes a layout target or target opacity starts a motion from the node's presented value (so an
   interruption retargets from the current value). A new `.opacity(_:)` modifier animates. Insertions fade in (opacity 0 to
   target). Removals are not animated (no ghost nodes). `accessibilityReduceMotion` (settable through `setRootEnvironment`,
   read per node) snaps and still delivers the completion. Completions run once: after every motion the transaction started
   has finished or been superseded, or at its commit if it started none. Tests: `AnimationTests`.
   **Decisions:** (a) the Mac F6 burst (two inserts in one turn) is reproduced: both transactions start motions, the first is
   superseded and completes at the second's commit, the second completes at its end. (b) Completion on supersession is our
   semantics, not measured on the Mac; the Mac F6 oracle only records that both complete. (c) `.animation(_:value:)` changes
   create a transaction for the flush, so they animate the whole flush, not only their subtree. (d) Transactions are applied in
   queue order per flush. The completion of a transaction that changes nothing fires at its commit.
6. **IME and marked text.** `TextInputState` per TextField node, with UTF-16 selection, marked range and composition location,
   and operations named after the bridge `TextStore`: `replaceAndMark(range:text:newSelection:)`, `unmark()`,
   `replace(range:text:)`, `setSelection(_:)`, plus read-only `display`, `committed`, `markedRange`, `substring(_:)`.
   Decisions, recorded in `TextInput.swift`: (a) the bound String holds committed text only. Marked text is written to the
   binding only on commit (`unmark`, `replace`, an edit or selection that leaves the marked range). (b) While composing, an
   edit replaces the whole marked text. A range outside it first commits the composition. (c) Replacing a non-empty
   selection to start a composition removes that selected text from the binding at once; it is a commit, not marked text.
   (d) `setSelection` outside the marked range commits. (e) Ranges are in displayed coordinates; an emoji is two units.
   The F7 identity rule holds: the state is per node, so a composition survives an insert above it. Tests: `TextInputTests`.

### Gaps and open items (not closed in this lane)

- F9 Windows fixture was not re-run. This pass is headless only. The retention fixes address the cause recorded for `tree-released`
  (graph-owned retention), but the fixture verdict is unverified until the Windows F9 run is repeated.
- Task-token retention (fix b) is not directly tested. A test needs a task that outlives its cancel without leaking its own
  continuation, and none was written.
- F6 interruption is verified against our own motion model, not against Mac timing. Mac F6 raw traces still vary in sibling
  order (see the fixtures RESULT). Canonical order is what this runtime asserts.
- ScrollView is vertical only, with no clipping, no bounce, and no scroll-position binding. LazyVStack does not virtualize.
- The List row state bound (64 retired rows, oldest first) is still provisional.
- Text-input composition is headless only. The Windows bridge still uses its own text store; no route into this runtime is wired.
