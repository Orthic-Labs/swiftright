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
