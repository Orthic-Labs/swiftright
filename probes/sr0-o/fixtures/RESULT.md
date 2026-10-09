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

## SR0-O F6 trace variance (2026-10-09, macOS 27.0.1 arm64, Swift 6.4)

Scope: `probes/sr0-o/fixtures/` only (one source edit, `Sources/SliceFixtures/Screens/Screens.swift`). No commits, branches, or system settings. Runs via `scripts/run-self-test.sh` (`--self-test` last). Hashes via `scripts/normalize-hash.py` (`raw` keeps line order; `canonical` is order-insensitive within each driver step). Fixture iterations used: 1 of 4.

### Correction to the earlier F6 note

The earlier note said the extra appear/disappear pair for row B occurs "one run in three". The larger sample shows it is not a fixed rate. Across 13 runs with the original code (runs 1-3 and 11-20), the B pair appeared in 7 of 13 (runs 2, 12, 15, 17, 18, 19, 20). Row A's pair (appear, disappear, appear) appeared in all 13. The `canonical` hash took 2 values across runs 11-20 (6 and 4 runs), and `raw` took 3.

### Data

| Build | Runs | Row B extra pair | Row A pair | Canonical distinct | Raw distinct | Assertions |
|---|---|---|---|---|---|---|
| F6, original (implicit `.animation(_:value: rows.count)` on F6Screen root) | 11-20 | 6 of 10 | 10 of 10 | 2 | 3 | 5/5 ×10 |
| F6, edited (implicit modifier removed) | 21-30 | 10 of 10 | 10 of 10 | 1 | 4 (7 runs share one) | 5/5 ×10 |
| F6-reduced, edited | 21-30 | n/a (no B insert path variance) | n/a | 1 | 1 | 3/3 ×10 |

Animation counts in edited F6 runs: 2 `start` and 2 `complete` per run. The F6-reduced assertions also pass: no animation transactions, policy disabled, final order correct.

### Which events vary

- The variance was row B's extra appear/disappear pair, in the original build only. It made the per-step lifecycle multiset differ between runs, which is the `lifecycle.count` check in TraceKit.
- Row A's pair is constant. It was present in every run of both builds, so it is not variance.
- Raw variance that remains in the edited build is only the order of sibling events within one step (for example `A200:appear` before or after `anim:complete:A`). TraceKit already permits any permutation of lifecycle events within a step except declared edges, so this is not a semantic difference.

### Cause

Not SwiftUI-internal, as far as the evidence goes. F6Screen drove the same row-count change with two animation sources: an explicit `withAnimation` transaction per insert (in `RowModel.insertRow`), and a value-keyed `.animation(_:value: model.rows.count)` on the screen root. Their interaction made B's extra pair intermittent. Removing the implicit modifier made the pair deterministic (10 of 10) and the canonical hash identical (10 of 10). The explicit transaction still drives both animations, and the two-animations/interruption assertions still pass.

Not proven: why B's pair and A's pair occur at all. They are deterministic now. A's pair is consistent with a List row being rebuilt when it moves from index 0 to index 1 on a same-turn insert above it. That is a hypothesis, not a measured result. No declared permitted-ordering entry was written, because the pairs are now deterministic and nets to the same final state. Any accepted F6 baseline must contain them.

### Resolution

- Classification: fixture defect (double animation driver on one mutation). Fixed by removing the implicit modifier from `Sources/SliceFixtures/Screens/Screens.swift` (F6Screen). The original is kept outside the repo.
- Canonical hash identical 10 of 10 for F6 and for F6-reduced. Raw hash identical 10 of 10 for F6-reduced; F6 raw has 4 distinct sibling-order variants, which the comparator's lifecycle permutation rule permits.
- The comparator test for a permitted-ordering declaration was not written: the variance it would cover no longer occurs.
- CONTRACT F6 row was not edited. Its "completion order" wording still needs a decision on whether sibling order within a step is asserted or permuted.
- Open: raw sibling-order variance in F6 is not zero. If SR0-O requires raw identity, this needs a decision, not a fixture change.


## SR1 fixtures G1-G8 (2026-10-09, macOS 27.0.1 arm64, Swift 6.4): INTERRUPTED

Status: INTERRUPTED. The 20x sweep was stopped by the coordinator because it was disrupting the user's work on this Mac. No runs were started after the stop. G8 was never repeated, and G6 run 20 and G7 run 2 were cut off by the stop. Nothing here is an oracle-qualified SR1 baseline except the configs marked yes below.

Scope: `probes/sr0-o/fixtures/` only (Sources, `scripts/sr1-repeat20.sh`, `scripts/sr1-summary.py`). No commits, branches, or system settings changed.

Method: each fixture is driven by `scripts/run-self-test.sh`. Stimuli are model writes, pid-posted keys (`CGEvent.postToPid`), and in-process AX reads and actions. Each action records one `observe` event. Checks assert only internal consistency (the driver ran every step, the model holds its own last write). The recorded outcomes are the oracle. `normalize-hash.py --canonical` decides agreement.

Results at interruption (from `scripts/sr1-summary.py` over `out/sr1/`, completed runs only):

| Config | Self-test PASS | Runs completed | Raw distinct | Canonical distinct | Oracle-qualified |
|---|---|---|---|---|---|
| G1 Toggle | 20 | 20/20 | 1 | 1 | yes |
| G2 TextEditor | 20 | 20/20 | 2 | 2 | no |
| G3 List(selection:) single and multi | 20 | 20/20 | 1 | 1 | yes |
| G4 onDelete | 20 | 20/20 | 1 | 1 | yes |
| G5 contextMenu / Menu | 20 | 20/20 | 1 | 1 | yes (as UNAVAILABLE, see below) |
| G6 alert / confirmationDialog | 19 | 19/20 (run 20 cut off) | 2 | 2 | no |
| G7 keyboardShortcut | 2 | 2/20 | 1 | 1 | no (incomplete) |
| G8 Image / Label / Divider / disabled | not run | 0/20 | n/a | n/a | no |

Recorded outcomes (G1 and G5 read back in detail; the rest are in `out/sr1/`):
- G1: Space on the focused Toggle changed value 0 to 1. AXPress changed 1 back to 0. A model write set it to 1. Role AXCheckBox, action AXPress, focus on. Identical in 20 of 20 runs.
- G5: the target element advertises AXShowMenu. The "More actions" button advertises AXPress. The popup was not observed in-process and no item was invoked. Recorded as `AX-unavailable (in-process)`. This is not a menu conformance PASS.

Findings and open items:
- G2 (TextEditor) and G6 (alert and dialog) are non-deterministic in the canonical hash across runs. They were not diagnosed. Do not treat them as oracles until the cause is understood.
- G5: AXShowMenu on a SwiftUI context menu or Menu cannot be driven in-process. The call either blocked the main thread or returned with no popup observed. A run-loop timer scheduled before the call and an AXShowMenu call on a background thread both failed. Astra (gpt-6-astra, high effort) recommended recording it as UNAVAILABLE in-process and using the out-of-process AX recorder for popup coverage. That recorder route is not built here.
- Fix iterations used: G5 used 4 of 4 (diagnostic dump, timer after call, detached thread, timer before call). Then the cases were replaced with the UNAVAILABLE record. The other configs needed no fix iterations.
- Two sweep loops were briefly running at once during the first attempt. Overlapping output was moved aside, not deleted, to `out/sr1-discarded-overlap/` (67 files). It is not evidence. The sweep script now holds a PID lock at `out/sr1/.sweep.pid`.
- G8 and G7 repeats remain. Rerun after the stop is lifted, in a single sweep: `OUT_DIR=out/sr1 scripts/sr1-repeat20.sh G2 G6 G7 G8`, or fresh per config with `RUNS`. Do not run it on the user's active session.

## G2/G6 variance analysis (offline, 2026-10-09)

Scope: saved JSONL in `out/sr1/` only (`out/sr1-discarded-overlap/` ignored). No app was launched, no run was repeated, no source was edited, nothing committed. Tools: `scripts/sr1-summary.py`, `scripts/normalize-hash.py` (`--canonical`, `--diff`), plus an ad hoc multiset diff of event sequences per config.

### Groups

| Config | Complete runs | Canonical groups | Members |
|---|---|---|---|
| G2 | 20 | A = 15 runs, B = 5 runs | B: 11, 12, 15, 16, 20 |
| G6 | 19 (run 20 truncated, no `RC=`, 7 of 43 lines) | A = 18 runs, B = 1 run | B: 14 |

G6 run 20 was cut off by the stop. It is excluded by `sr1-summary.py` (no RC line) and is not variance. The summary's "2 distinct" for G6 comes from run 14 alone.

### G2 (TextEditor): one extra transient `binding-write`

- The only difference between groups is one extra event in step `g-text:type-ab`: `state`, node `g2/editor`, payload `{"op":"binding-write","text":"a","lines":1}`. It occurs 3.6 to 4.7 ms before the normal `{"text":"ab"}` write (checked in runs 11, 12, 15). Group A has only the `ab` write.
- Every other event is identical in both groups. Order is identical. The `observe` records (`typed`, `text-value`, `text-selection`) match in all 20 runs.
- Frequency: 5 of 20 runs (25%). The variant runs cluster in the second half of the sweep (11 to 20), but 5 runs is too few to call that a trend, and it was not tested.
- Mechanism: `SR1AX.typeText` (`Common/SR1AX.swift:171-180`) posts key-down and key-up for `a` and then `b` back to back with `postToPid`, with no pause. Whether SwiftUI's `onChange(of: model.note)` delivers `"a"` as its own update depends on whether the main run loop commits a transaction between the two keystrokes. Sometimes it does (the intermediate value is delivered). Sometimes both characters land in one transaction (not delivered).
- Classification: (b) fixture defect, with a SwiftUI timing root. The fixture logs every `onChange` delivery as a contract `state` event (`Screens/SR1Screens.swift:60-65`). The number of intermediate deliveries is timing-dependent and is not part of the contract. The contract-bound outcome, the settled text, is identical in all 20 runs.
- Not genuine contract variance. A permitted-ordering rule (per-node order significant, sibling order unordered) would not cover this. The extra event is a count difference, not a reorder, and `canonical_digest` does not drop events. Expressing it in the comparator would need a new rule ("within one step, consecutive `binding-write` events for the same node collapse to the last"). I do not recommend that rule, because it hides a real instrumentation choice.

Proposed fixture fix (not applied, not run). Stop emitting per-delivery text writes. The settled value is already recorded by the `g-snap` observe (`text-value`) and by `g-model`:

```diff
--- a/probes/sr0-o/fixtures/Sources/SliceFixtures/Screens/SR1Screens.swift
+++ b/probes/sr0-o/fixtures/Sources/SliceFixtures/Screens/SR1Screens.swift
@@ G2Screen.body
                 .frame(width: 400, height: 180)
-                .onChange(of: model.note) { _, value in
-                    model.log.emit("state", node: "g2/editor", payload: [
-                        "op": "binding-write", "text": value, "lines": value.components(separatedBy: "\n").count,
-                    ])
-                }
```

Alternative if a per-step write record is wanted: the `g-snap` branch in `SR1Steps.snapshot` emits it once per snapshot, from `model.note`, rather than from `onChange`. The G2 case checks (`twelve-actions-observed`, `model-holds-last-write`) do not read these events, so removing them does not change any check. The hash will change, so G2 needs a 20-run repeat after the edit.

### G6 (alert / confirmationDialog): one lost window activation

- The only difference in group B (run 14) is the first observe: `window / activate` payload `{"key-window":false,"responder":"nil"}`, versus `{"key-window":true,"responder":"AppKitWindow"}` in the other 18 runs. Everything after is identical in order and content (the sheet, cancel, escape, delete, and dump observations all match).
- Frequency: 1 of 19 complete runs (5%).
- Mechanism (likely, not verified offline): `g-activate` calls `NSApplication.activate(ignoringOtherApps:)` once, waits 300 ms, and records whatever state exists. On macOS, activation is cooperative and can be denied while another app is frontmost. This Mac was in use during the sweep. The driver recorded a lost activation as an outcome instead of a precondition failure.
- Classification: (b) fixture driver defect (driver step racing window activation). Nothing in the SwiftUI presentation changed; the alert itself presents correctly in run 14.

Proposed fixture fix (not applied, not run). Make activation a bounded precondition. Retry until our window is key. If it never becomes key, record a driver error instead of a contract observation, so the run fails instead of qualifying with a recorded `false`:

```diff
--- a/probes/sr0-o/fixtures/Sources/SliceFixtures/Session/SR1Steps.swift
+++ b/probes/sr0-o/fixtures/Sources/SliceFixtures/Session/SR1Steps.swift
@@ case "g-activate":
         case "g-activate":
-            activate()
-            await pause(pauseMs)
+            var keyed = false
+            for _ in 0..<20 where !keyed {
+                activate()
+                await pause(100)
+                keyed = appWindow()?.isKeyWindow == true
+            }
+            if !keyed { log.emit("lifecycle", node: "driver", payload: ["phase": "activation-failed"]) }
             observe(log, node: "window", phase: label, ["responder": responder(), "key-window": NSApp.keyWindow != nil])
```

and in `SR1Cases.swift` for G6 (and G1-G8 generally), add one check next to `no-unknown-steps`: `e.check("activation-held", e.find(node: "driver", tag: "activation-failed").isEmpty)`. The observe payload shape is unchanged, so the 19 agreeing runs keep their hashes. Run 14 would be rejected, or would match if activation succeeds on retry.

### Oracle-validity notes (not variance, but they affect what the "recorded outcome" means)

- G2 `g2/editor / after-typing` records `found: false` in all 20 runs. The identifier lookup fails right after typing, then succeeds at `range-1-2`. The result is stable, so it does not cause variance, but a recorded "not found" should not be accepted as an oracle without an explanation. Probable cause: the AX tree changes once the editor has text and focus. Unverified. A candidate check is to run `SR1AX.everything()` once after typing and see whether the TextEditor is nested under a different element.
- G6 `title/Cancel` and `title/Delete` record `ax-status: -25205` (kAXErrorAttributeUnsupported) in all 19 runs, yet the alert actions fire (`g6/alert` `action` events are present). The status code is not a reliable success signal for AXPress on alert buttons. Keep the effect event as the oracle, not the AX status.

### Summary

| Config | Variant | Count | Class | Fix |
|---|---|---|---|---|
| G2 | extra transient `binding-write "a"` | 5/20 | (b) fixture instrumentation on timing | remove per-delivery `onChange` emit (diff above) |
| G6 | `window/activate` key-window false | 1/19 | (b) fixture driver precondition race | bounded activation retry plus `activation-failed` check (diff above) |

Neither variant is genuine SwiftUI contract variance. The comparator needs no permitted-ordering rule for these two configs. Both still need a 20-run repeat after the fixes, and G2 and G6 should not be treated as qualified until then. Sources were not edited, so the saved 20-run evidence still matches the current source.

### Fixes applied (2026-10-09, after the offline analysis above)

- G2: per-delivery `onChange` `binding-write` emit removed from `G2Screen` (`Screens/SR1Screens.swift`).
- G6: `g-activate` (shared by all configs) now retries activation for up to 2 s until the window is key. Failure emits `driver / activation-failed`, checked by `activation-held` in the G6 case (`Session/SR1Cases.swift`).
- `swift build` (headless) passes. The app was not run.
- The 20 saved runs in `out/sr1/` predate these fixes. G2 and G6 (and the remaining G7 runs and G8) need a fresh 20-run repeat when Adrian's Mac is free. Their qualification is open until then.
