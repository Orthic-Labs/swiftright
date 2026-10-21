# Block 41 open edges A and B and the test-comment gap (issue #59)

Finding: A and B are already fixed in the runtime (issue #2, H29/H36/H38, CLOSED 17 Oct). #59 is stale documentation, not runtime work.
Paths below are under `probes/sr0-s/fresh-runtime`.

Source text (`docs/sr1-status.md:58`, repeated in `docs/proven-controls.json:2629` and H27(c), `docs/sr1-decisions.md:378`):
"a completion can run while an outer withAnimation is still open, so its writes animate with the outer transaction (SwiftUI runs completions asynchronously); an outer completion can fire early when a segment commit changes no layout; a test-comment gap at TransactionBoundaryScopeTests.swift:272".
Row 58 and `generate.py` REVIEWED["swiftui.compat"] were never updated after H29. The status row (`sr1-status.md:321`) still says "open".

## Edge A: completion runs inside an open outer withAnimation
- Introduced in `7796b0b81` (inner-wins rework): a completion's write took whatever frame was open.
- Current state: closed. `TransactionContext.drainDeferred` (Animation.swift:589-596) runs completions only while `frames.isEmpty` and no live graph queues a transaction. `end` calls `drainIfIdle` (Animation.swift:569). Tick and other-window commits are gated the same way (H36).
- SwiftUI: completions run after the transaction closes, asynchronously (https://developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:)).
- Change needed: none. Existing tests: `testNestedCompletionWritesDoNotInheritTheOuterAnimation` (TransactionBoundaryScopeTests.swift:353), `testTickWhileOuterTransactionIsQueuedDoesNotRunTheNestedCompletion` (:431), `testAnotherWindowsCommit...` (:457), `testCompletionInOneWindow...` (:486), `testTickSettledCompletion...` (:518).
- Evidence: CI run 38984220953, `completion-timing-v1` 80/80 pairs exact (H29 evidence, `sr1-decisions.md:424`).

## Edge B: outer completion fires early when a segment commit changes no layout
- Current state: closed. `AnimationTransaction.frameOpen` (Animation.swift:244) is set in `begin` (:536), cleared in `end` (:544). `settleIfDone` returns while it is set (:275), so a segment commit that applies the transaction to no changed node cannot settle it.
- Change needed: none. Test: `testOuterCompletionFiresAfterTheOuterWriteCommitsAndSettles` (:380) writes 5 then 0 so the layout is unchanged, and asserts the completion fires only after the tick at 1.0.
- Remaining sub-edge (H29 "known edge", tick with no frame open while an unrelated transaction is queued) was closed by H36 (`testTickSettledCompletionDoesNotTakeAnUnrelatedQueuedTransaction`, :518).

## Test-comment gap (TransactionBoundaryScopeTests.swift:272 at 7796b0b81, now :293)
- Current state: `testNestedWithAnimationWritesTakeTheInnermostOpenTransaction` (:294) has the comment "z under the outer again" (:293), but the body writes only x (`trigger`) and y (`third`). There is no z write, and `mid[1]` (`follower`) is never asserted. The line `_ = records.items.dropFirst(base)` (:302) is dead.
- Fix (preferred, adds coverage): after the inner `withAnimation` block, inside the outer one, add `model.follower = 40`. Replace the dead line by asserting `records.items.dropFirst(base).map { $0.animation }` equals the per-commit order the runtime emits (read it from the first run; expected `["linear", "linear", ...]`, no plain entry for the segments). Add `XCTAssertEqual(mid[1], 20, accuracy: 1e-9, "the write after the inner block returns to the outer 2 s animation")`.
- Fix (minimum): change the comment to "x written under the outer transaction, y under the inner one nested in it." and delete the dead `_ =` line and the unused `base`.
- Proposed test name: keep the name; optionally add `testWriteAfterInnerBlockReturnsToTheOuterTransaction` for the z case so the original stays minimal.
- SwiftUI behaviour: each write belongs to the innermost open transaction at write time (https://developer.apple.com/documentation/swiftui/withanimation(_:_:)), measured in block 41 `onchange-animation-v1`.

## Closing #59
1. Edit `docs/sr1-status.md:58,321`, `docs/hub-track.md:32` and `docs/proven-controls.json:2629,2672` to say A and B are closed (H29, H36, H38, run 38984220953) and keep only the comment fix. Regenerate with `factory/tools/proven-controls/generate.py`.
2. Apply the comment fix above. Run the runtime suite once (owner chat). Then close #59.
