# SR0-O fixtures: RESULT (incomplete, runtime blocked)

Scope: `probes/sr0-o/fixtures/` only. No commits, branches, TCC or system-setting changes. The comparator directory was not touched.

## Verdict

| Item | Result |
|---|---|
| `swift build` (Swift 6.4, Swift 6 mode, macOS 15 floor) | PASS, clean, no warnings |
| `FixtureApp --self-test` per fixture F1..F9, 3 runs each | NOT COMPLETED. The window never presented in the runs attempted, so no assertion was executed. |
| Determinism across 3 runs | NOT EVALUATED (no completed runs) |
| Per-fixture self-test PASS/FAIL | NONE RECORDED. Do not read the self-test assertions as verified. |

## Runtime blocker (environment, not fixture logic)

- The app's `Window` scene intermittently fails to present its content. The `root-appear` lifecycle event never fires, the process stays alive, and `System Events` reports 0 windows.
- Reproduced in both root variants: the real `FixtureRootView` and a trivial `Text` root inside the session library. A bare `Text` body in the entry file showed a window 3 of 3 at one point, then failed later.
- `probes/sr0-o/ax-routes/.build/debug/FixtureApp` still presents its window 2 of 2 at the end of this session, so the desktop session is not blanket-broken. The difference is unexplained. It is the next thing to isolate, starting with the session-backed root in `Sources/SliceFixtures/Session/FixtureSession.swift`.
- `scripts/run-self-test.sh` relaunches (up to 8 times) only when `root-appear` is absent within 8 s and records each attempt in `out/<name>.launch.txt`. The last F1 run exhausted all 8 attempts. Harness relaunch does not hide fixture failures: a launched run is never retried after assertions.
- Fix iteration: one real defect of mine was found and fixed during debugging. A cleanup `sed` removed the root `.onAppear { session.attach() }`, so the self-test never started. Iterations used: 1 of 4 on the self-test path, no further fixture-level iterations were possible without a presented window.

## What is in place

- `Sources/SliceFixtures/Common/`: `EventLog` (thread-safe JSONL: fixture, step, kind, node_id, payload, mono_ns), `FakeEngine` (operations suspend until the driver releases a key; cancellation is observed but never resumes the operation, so late results are delivered), `RowModel` (deterministic row UUIDs, owner generations, the single commit gate `commitAllowed`), `SharedViews` (editable row with per-identity `@State`, list with `ForEach($model.rows, id:)`, focus and toolbar scaffold, `TreeProbe` for release).
- `Sources/SliceFixtures/Screens/`: one screen struct per fixture F1..F9; `F5Screen.swift` holds the custom `Layout` (`sizeThatFits` and `placeSubviews` only).
- `Sources/SliceFixtures/Session/`: config parsing (`--fixture`, `--self-test`, `--events`, `--reduced-motion-variant`), session, root view, driver (stdin JSON-lines or self-test steps), and the self-test script and assertions for each fixture.
- `Sources/FixtureApp/FixtureApp.swift`: the `@main` App with one `Window`.

## Design notes and contract findings (unverified at runtime)

1. Import block: CONTRACT §2/§3 import block includes `SwiftRightUI` under `#if os(macOS)`. The Mac fixture has no `SwiftRightUI` target, so the import is omitted and only `Foundation`, `Observation`, and `SwiftUI` (macOS) are imported. Add it when the target exists.
2. Row binding: the contract inventory lists `ForEach($items) { $item in }`. `probes/sr0-c/same-source/RESULT.md` already records that the `$`-projected closure parameter fails on Windows. This fixture uses `ForEach($model.rows, id: \.id) { row in ... }` (a plain `Binding<Row>` parameter, no `$`). Not compiled for Windows here; the SR0-S/SR1 team should confirm the form.
3. F6 reduced motion: `accessibilityReduceMotion` is read-only through the public API, and the brief forbids changing system settings. The `--reduced-motion-variant` flag only forces the animation-policy branch. The real OS setting is not exercised. Intermediate-frame observation is out of process.
4. F9: `onDisappear` is attached to the scaffold and sets the closed flag, and the commit gate checks it. Whether SwiftUI cancels tasks and releases the tree on close is an open observation; the self-test asserts it and has not run.
5. The layout records placements through `emitIfChanged`, so SwiftUI's call count does not affect determinism.
6. Caret, marked text, and paint or hit-test agreement are not observable in-process and remain out of process by design.

## Not done

- No completed self-test or three-run determinism result exists. The per-fixture PASS/FAIL table is empty by necessity.
- Fixture-level iteration on any failing assertion was not reached.

## Primary diagnosis & results (2026-10-09)

**Window "failed to present" root cause:** argument order, not SwiftUI. AppKit parses `-option value` pairs from argv. `--fixture F1 --self-test --events <path>` pairs `--self-test` with `--events`, leaving `<path>` unpaired; AppKit treats it as a document to open and the `Window` scene's default window is not created. Putting `--self-test` last fixed it (verified 4/4 alternating launches before, 30/30 after). `scripts/run-self-test.sh` now passes `--self-test` last. Rule for all fixture CLIs: never leave a bare path as the last unpaired argument.

**Self-test runs (3 each, macOS 27.0.1 arm64):**

| Fixture | Verdict ×3 | Distinct normalized traces (mono_ns stripped, SHA-256) |
|---|---|---|
| F1 | PASS 7/7 | 1 |
| F2 | PASS 6/6 | 1 |
| F3 | FAIL 6/7 (`reinserted-fresh-state`) | 1 |
| F4 | PASS 6/6 | 1 |
| F5 | FAIL 4/5 (`all-placements-contained`) | 2 |
| F6 | PASS 5/5 | 1 |
| F6-reduced | PASS 3/3 | 1 |
| F7 | PASS 5/5 | 1 |
| F8 | PASS 7/7 | 1 |
| F9 | no verdict printed; exit 0 | 1 |

Findings:
- **F3 is an oracle observation, not a fixture bug:** real SwiftUI `List` on macOS 27 preserved row 4's `@State` (`local=1`) across remove → reinsert of the same UUID, after `onDisappear` had fired. The self-test expectation (fresh state) came from the draft contract and was wrong; CONTRACT F3 now defers to the recorded outcome. Repeat with a longer gap and with a non-`List` container before accepting it as the oracle. The fresh runtime's F3 test assumes fresh state and must follow whatever is accepted.
- **F5 nondeterminism & containment:** traces differ across runs and one placement check fails; diagnose before F5 becomes an oracle.
- **F9:** closing the last window terminates the app before the self-test prints its verdict; print before closing or keep the app alive after last window close in self-test mode.

## Follow-up: F3 oracle, F5 nondeterminism, F9 verdict (2026-10-09, macOS 27.0.1 arm64, Swift 6.4)

Scope: `probes/sr0-o/fixtures/` only. No commits, branches, or system-setting changes. Runs go through `scripts/run-self-test.sh`, with `--self-test` last. Hashes: `scripts/normalize-hash.py` (hashlib SHA-256 over normalized lines, `mono_ns` removed). Two hashes are reported: `raw` (line order kept) and `canonical` (order-insensitive within each driver step, because sibling events inside one SwiftUI pass may interleave differently).

### Changes made

- **App entry (F9):** `FixtureAppDelegate.applicationShouldTerminateAfterLastWindowClosed` returns false only when `--self-test` is present. The self-test waits (bounded, 3 s) for the `tree released` event after close, then prints the verdict.
- **F5 root cause:** AppKit restored `NSWindow Frame main` from the app's defaults. Initial width varied between runs. A 0-width `placeSubviews` pass (window collapsing during restore) reported `contained=false` on every failing run. Self-test now clears `NSWindow Frame *` defaults before launch. Layout events now log `bounds`, `outside` frames and a `degenerate` flag. The containment assertion excludes degenerate (0-width) passes, which are reported as an OBSERVE line (`zero-width-placement-passes`).
- **F3 oracle:** the assertion `reinserted-fresh-state` was removed. The outcome is now an OBSERVE record (`fresh`/`preserved`, focus, gap ms). Variant flag `--f3-variant <list|vstack|lazy>-<1|3>s`, placed before `--self-test`. The runner accepts an optional third argument.
- **F6:** attempted two changes (split the burst into driver steps; `completionCriteria: .removed`). Neither produced an interruption: A completes about 6-11 ms after start, so a later insert never overlaps. Reverted to the original same-turn burst, which produces overlap. Iterations used on F6: 3 of 4. The remaining trace variance is recorded as a finding below.

### F3 oracle table (container × gap → reinserted row local state)

| Container | Gap | Run 1 | Run 2 | Run 3 | Deterministic? | Focus after reinsert |
|---|---|---|---|---|---|---|
| List | 0 (immediate, default) | preserved (local=1) | preserved | preserved | yes | focused |
| List | 1 s (1.22-1.26 s measured) | preserved | preserved | preserved | yes | focused |
| List | 3 s (3.25-3.39 s measured) | preserved | preserved | preserved | yes | focused |
| VStack + ForEach | 1 s | fresh (local=0) | fresh | fresh | yes | not focused |
| VStack + ForEach | 3 s | fresh | fresh | fresh | yes | not focused |
| LazyVStack in ScrollView | 1 s | fresh | fresh | fresh | yes | not focused |
| LazyVStack in ScrollView | 3 s | fresh | fresh | fresh | yes | not focused |

Finding: the outcome depends on the container, not the gap. Only `List` preserves `@State` across remove → reinsert of the same UUID, on macOS 27.0.1. Every run is deterministic for this outcome. The draft contract's "fresh state" expectation holds for VStack and LazyVStack only. The Windows runtime must not assume either outcome as an oracle until it has been checked against the same container.

### Full matrix: 3 runs each

Assertions (asserted checks only; OBSERVE lines do not count):

| Config | Verdict ×3 | Raw hash distinct (of 3) | Canonical hash distinct (of 3) |
|---|---|---|---|
| F1 | PASS 7/7 ×3 | 1 | 1 |
| F2 | PASS 6/6 ×3 | 1 | 1 |
| F3 (default = List, immediate) | PASS 5/5 ×3 | 1 | 1 |
| F4 | PASS 6/6 ×3 | 1 | 1 |
| F5 | PASS 5/5 ×3 | 1 | 1 |
| F6 | PASS 5/5 ×3 | 3 | 2 |
| F6-reduced | PASS 3/3 ×3 | 1 | 1 |
| F7 | PASS 5/5 ×3 | 1 | 1 |
| F8 | PASS 7/7 ×3 | 1 | 1 |
| F9 | FAIL 4/5 ×3 (`tree-released`) | 1 | 1 |
| F3 `list-1s` | PASS 5/5 ×3 | 1 | 1 |
| F3 `list-3s` | PASS 5/5 ×3 | 1 | 1 |
| F3 `vstack-1s` | PASS 5/5 ×3 | 1 | 1 |
| F3 `vstack-3s` | PASS 5/5 ×3 | 2 | 1 |
| F3 `lazy-1s` | PASS 5/5 ×3 | 3 | 1 |
| F3 `lazy-3s` | PASS 5/5 ×3 | 3 | 1 |

Fixture pass rate: 9 of 10 configs PASS ×3 (F9 FAIL ×3). F5 all-placements-contained now passes ×3; before this follow-up it failed 3 of 3.

### Findings

1. **F5 (resolved in fixture):** trace variance came from window-frame restoration (above). With restoration cleared, the canonical and raw hashes match across runs.
2. **F6 (SwiftUI variance, recorded, not masked):** `interruption-recorded` passes ×3. The raw trace varies in 3 of 3 runs, and the canonical trace varies in 2 of 3. Run 2 shows an extra appear/disappear pair for row B (`...201`), which runs 1 and 3 do not. Row A's `disappear`/`appear` pair is in all three runs. The burst step's completion order is not fixed, and SwiftUI rebuilds an interrupted row in some passes. Treat F6's raw trace as nondeterministic on this macOS build.
3. **F3 variant nondeterminism (recorded):** for `vstack` and `lazy`, the raw trace varies (order of sibling `appear` and `task-start` within one insert pass; the `focus` event lands before or after the row-load start). The canonical hash is identical within each container and matches across containers, so the difference is event order only, not outcome.
4. **F9 (open finding, assertion kept failing):** the verdict now prints after close, and the first four assertions pass (tasks cancelled at close: 11; no commit after close; late results rejected: 11; cleanup after close: 11). `tree-released` fails ×3. The diagnostic observed the closed window still retained by AppKit (`titled=1 visible=0 isReleasedWhenClosed=false`). In self-test mode the process stays alive, so the window and its SwiftUI tree are not released. The assertion is not relaxed. Whether the tree should be released on close is an open question for the Windows side of the contract.

### Not done

- The F6 interruption cannot be forced deterministically from the driver on this build. It is observed only through the same-turn burst. A dedicated interruption probe would need a view-model change beyond this follow-up's scope.
- F9 `tree-released` is open. The fixture does not release the window; this needs a decision (close-then-quit in the self-test versus asserting retention).

## Primary verification (2026-10-09)

Primary reran F3 `list-1s`, `vstack-1s`, `lazy-1s` and F5 once each: List reinsert appears with `local=1` (preserved), VStack and LazyVStack with `local=0` (fresh); F5 PASS 5/5. CONTRACT F3 now records per-container outcomes; F9 tree release is reclassified as a Windows runtime requirement rather than a Mac oracle assertion. F6 raw-trace variance (extra appear/disappear pair in one run) must be resolved as a declared permitted ordering or a fixture change before F6 becomes an oracle.
