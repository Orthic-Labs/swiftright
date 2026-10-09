# SR0-S: fresh runtime on bridge ABI v0, fixture F1 on Windows

Scope: `probes/sr0-s/fresh-on-bridge/` only. The fresh runtime (`probes/sr0-s/fresh-runtime`), the bridge
(`packages/SwiftRightBridge`) and the ABI header were used unchanged. Nothing committed, branched or pushed.

## Verdict

- Windows 11 x64, Swift 6.4.0, real renderer DLL (`swiftright_render.dll`, ABI v0 from the BridgeSmoke payload).
  Self-test **15 of 15 PASS** (run2, the reference run). Screenshot checked: the screen renders as specified.
- Mac: `swift build` compiles the package (type-checks the runtime, bridge and the glue). The binary
  reports `SWR_STARTUP_ERROR: ... only implemented on Windows` and exits 78, as designed.
- Fix iterations: 3 of 6 (listed below). None touched the runtime, the bridge or the header. No Codex
  consult was needed.

## Design

```
RowModel (@Observable, F1 logic)  <-- editText / insertRow / requestInsert --+
   ^                                                                        |
   | reads rows (tracked)                                                   |
F1Root -> VStack{ Button("Insert above"), List{ ForEach($rows,id:\.id){ EditableRowView } } }
   |  SwiftRightRuntime.Graph (retained tree, @State per identity, FocusState)
   |  commitSink(CommitRecord: resolved tree, frames in physical px, focus id)
   v
BridgeBackend.commit  -> one ABI Transaction per flush:
   node ids: runtime id string -> stable bridge id (0 = window root)
   Text: bridge.measure + draw run at frame origin; semantic staticText
   Button: rect + label child; semantic button (invoke, focus)
   TextField: field box + text run + caret rect when focused; semantic textField
              (value, focus/setValue/setSelection, AX text runs from cells)
   focus target = bridge id of the focused row's TextField
   removes = top-most ids that left the tree
   run handles released after commit (renderer keeps what it needs)

Bridge events -> BridgeBackend.handle:
   AX Focus(textField)  -> FocusState := row identity, caret := end
   AX Invoke(button)    -> Graph.tapButton(runtime id) -> RowModel.requestInsertAboveFromButton
   AX SetValue          -> RowModel.editText
   pointer down         -> focus field / tap button
   windowMetrics        -> Graph.rootProposal
TextStore (IME/VK text input) -> storeReplace -> RowModel.editText -> flush (deferred commit)

BridgeTextMeasurer: runtime TextMeasurer backed by Bridge.measure (logical <-> physical by scale).
Flush driving: the runtime schedules its own flush as a MainActor Task, which runs in the renderer's
drain callback; the backend also flushes a dirty flag on each display tick and after each event or
text write (so commits never wait for a drain).
```

Files (new, only under this directory):
- `Package.swift`: depends on `../fresh-runtime` and `../../../packages/SwiftRightBridge` by path; executable
  `FreshOnBridge`; `swiftLanguageModes: [.v5]` as in BridgeSmoke (bridge callbacks are not MainActor-annotated;
  the runtime itself stays Swift 6 mode).
- `Sources/FreshOnBridge/Fixture.swift`: RowModel, FakeEngine, EventLog (F1 subset of the Mac fixture).
- `Sources/FreshOnBridge/F1Views.swift`: F1Root, RowList, EditableRowView (runtime-supported API only).
- `Sources/FreshOnBridge/BridgeBackend.swift`: measurer, commit conversion, event path, TextStore adapter.
- `Sources/FreshOnBridge/SelfTest.swift`: stage machine and assertions.
- `Sources/FreshOnBridge/main.swift`: entry; `--self-test` selects the scripted run.
- `scripts/build-fresh.ps1`, `scripts/schedule-fresh.ps1`, `scripts/drive-fresh.ps1`: BridgeSmoke pattern.
- `out/`: evidence (`F1-bridge-run1.txt`, `F1-bridge-run2.txt`, `F1-bridge-run2.png`).

## Commands

```sh
# Mac: type-check (renderer loading is Windows-only, so the binary exits 78 here)
cd probes/sr0-s/fresh-on-bridge && swift build

# Stage (dereference the bridge header symlink), sync to the Windows host
rsync -a  --exclude .build probes/sr0-s/fresh-runtime   <stage>/probes/sr0-s/
rsync -a  --exclude .build probes/sr0-s/fresh-on-bridge <stage>/probes/sr0-s/
rsync -aL --exclude .build packages/SwiftRightBridge    <stage>/packages/
cp render/swiftright-abi/include/swiftright.h <stage>/render/swiftright-abi/include/
sh scripts/sync-to-win.sh <stage> 'D:\Claude\sr0s-bridge'

# Windows: build (ComCtl v6 + DPI flags, renderer DLL staged from the BridgeSmoke payload)
win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0s-bridge\probes\sr0-s\fresh-on-bridge\scripts\build-fresh.ps1'
#   cold 94.9 s, incremental 27.9 s; exit 0; FreshOnBridge.exe 2085376 bytes

# Windows: one-shot interactive run (task registered, run, deleted)
win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0s-bridge\probes\sr0-s\fresh-on-bridge\scripts\schedule-fresh.ps1 -Tag run2'
```

Stimuli (the driver, out of process): UIA `SetFocus` on the edit named "Row 5"; virtual keys `A`, `B`, `C`;
UIA Invoke of "Insert above"; the exe releases the fake engine (its own self-test step, as the Mac `release`
step); virtual key `D`; then UIA reads and a window screenshot. No Unicode packets are sent.

## Self-test output, run2 (verbatim, EVT lines trimmed; full file `out/F1-bridge-run2.txt`)

```
EVT {"kind":"lifecycle","node_id":"selftest","payload":{"phase":"start","row5":"F0000001-0000-4000-8000-000000000005"},"seq":0}
...  (10 appear events, window ready, ax focus on row 5, 3 text-store replaces, ax invoke, engine request/release/commit, insert appear, 'd' replace, 41 EVT lines in total)
OBSERVE F1 stages: 1:row5 focused by AX@5.81s | 2:typed abc@7.31s | 3:insert above invoked@8.72s | 4:engine released@8.73s | 5:insert committed@8.75s | 6:typed d; gathering frames@10.77s
OBSERVE F1 ticks=798 pointer-downs=0 key-events=4 ax-set-values=0 scale-changes=0
OBSERVE F1 renderer paints=800 commits_accepted=10 commits_rejected=0 commits_deferred=4 measure_calls=277 cache_hits=242 reentry_refused=0 events_pushed=13 ime_calls=8 ime_busy=0
OBSERVE F1 runtime measure_calls=61 commits=10
ASSERT F1 insert-committed-at-top: PASS top=Engine 0
ASSERT F1 row5-text: PASS text=Row 5abcd
ASSERT F1 row5-identity-index-shift: PASS index=5
ASSERT F1 row5-not-torn-down: PASS appear=1 disappear=0
ASSERT F1 row5-node-instance-kept: PASS instance before=35 after=35
ASSERT F1 row5-state-continuous: PASS local=4 (edits a,b,c,d since start; a reset would read 1)
ASSERT F1 focus-stays-row5: PASS model=F0000001-0000-4000-8000-000000000005 runtime=F0000001-0000-4000-8000-000000000005 bridge-target before=169 after=169
ASSERT F1 caret-follows-typing: PASS caret=9 expected=9 (end of text)
ASSERT F1 no-rejected-effects: PASS rejected=0 release-no-waiter=0
ASSERT F1 ax-focus-delivered: PASS ax-focus=2
ASSERT F1 ax-invoke-delivered: PASS ax-invoke=1
ASSERT F1 text-store-keystrokes: PASS replace calls=a,b,c,d
ASSERT F1 commits-accepted: PASS commits=10 errors=0
ASSERT F1 no-measure-or-draw-failures: PASS measure=0 draw=0
ASSERT F1 renderer-no-violations: PASS thread_violations=0 host_panics=0
SELFTEST F1-bridge: PASS (15/15)
```

Driver lines (same run, `drive-fresh.ps1`):

```
uia_focus_row5=ok
focused_after_uia_focus=[Row 5]
row5_value_after_abc=[Row 5abc]
uia_invoke_insert_above=ok
row5_value_after_insert=[Row 5abc]
focused_after_insert=[Row 5]
row5_value_final=[Row 5abcd]
focused_final=[Row 5]
screenshot=D:\Claude\sr0s-bridge\result-fresh-run2.png size=1632x1288 scaled_to=800x631
exit=0
```

Screenshot: `out/F1-bridge-run2.png` (after the 'd' input). Shows "Insert above", "Engine 0" at the top, the
row 5 field reading "Row 5abcd" with the caret at the end, and "local 4" on row 5 and "local 0" elsewhere.

## Per-assertion results against the Mac F1 self-test

Mac reference: `probes/sr0-o/fixtures/out/F1-run1.stdout` (`SELFTEST F1: PASS (7/7)`).

| Mac F1 assertion | Mac | Windows | Notes |
|---|---|---|---|
| insert-committed-at-top | PASS | PASS | |
| row5-text ("Row 5abcd") | PASS | PASS | Input is VK keystrokes via the text store. |
| row5-identity-index-shift (index 5) | PASS | PASS | |
| row5-not-torn-down | PASS | PASS | appear=1, disappear=0. |
| row5-state-continuous | PASS (local=2) | PASS (local=4) | Mac counts two programmatic edits; Windows counts four keystrokes. Continuity is the test: a reset would read 1. |
| focus-stays-row5 | PASS | PASS | Also checks the bridge focus target id (169 before and after). |
| no-rejected-effects | PASS | PASS | |

Bridge-specific checks added on Windows (all PASS): row5-node-instance-kept, caret-follows-typing,
ax-focus-delivered, ax-invoke-delivered, text-store-keystrokes, commits-accepted,
no-measure-or-draw-failures, renderer-no-violations.

Driver (UIA, out of process): row 5 keeps focus after the insert (`focused_after_insert=[Row 5]`);
row 5 Value reads "Row 5abcd" at the end.

## Gaps vs the Mac F1 trace

1. **Engine trigger.** Mac starts the "insert-above" engine call from the screen `.task` at appear. The Windows
   port starts it from the Insert above button, because the brief's stimulus is an AX invoke of that button.
   The guarded effect path (engine key, commit gate, insert) is the same.
2. **Local counter.** Mac `local=2` (two programmatic `setText` steps). Windows `local=4` (four keystrokes).
   The assertion checks continuity (value equals the edit count since start).
3. **Input.** Mac drives the model directly. Windows uses real VK input through the renderer text store and
   AX/UIA focus and invoke. The Mac F1 recorder (out-of-process AX) is not reproduced; the driver's UIA
   reads stand in for it.
4. **Not ported** (F1 only, per brief): F2 to F9 screens, `.toolbar`, `.onChange`, row `.task`, `withAnimation`,
   reduced motion, window close and tree-release, the F3 container variants.
5. **Identity exposure.** Mac exposes `row/<uuid>/field` as an AXIdentifier. ABI v0's `SemanticNode` has no
   identifier field, so the Windows row is labelled "Row N" (N is the row's original slot, stable across
   inserts). This is the one ABI gap: **bridge change request:** add an identifier (or test-id) string to
   `SemanticNode`. Not edited here.
6. **Runtime gaps hit (no runtime edits).** No `onChange`, so local-edit counting moved onto the single
   text-write path. No `.toolbar`. `TextField` is sized to its text only (an empty field has zero size and
   cannot be hit), so the backend draws the field box with a 6 DIP inset. Buttons have no padding modifier,
   so the backend inflates the button box by 12x6 DIP. Bridge bounds are the drawn boxes. List spacing is 0.
7. **Text.** Fixed style (Segoe UI 16 DIP, 24 DIP line). Wrap width for multi-line text is the runtime frame
   width plus 1 px, which is adequate for greedy wrapping but not proven. F1 texts are single line, so this
   path is not exercised.
8. **IME composition.** `replaceAndMark` is a plain replace. Composition (Mac F7) is not exercised.
9. **Scale change.** Not supported: the runtime fixes its scale at construction. A change is logged as
   `scale-change-unsupported` (none occurred). Window size changes update the root proposal.
10. **Commits.** Full-tree upsert on every flush (10 commits in the run). No diffing. Each text run is measured
    per commit (cache hits: 242 of 277 measure calls).
11. **Keyboard.** Key-down events are counted, not handled (no Tab or Enter behavior).
12. **Foreground only.** The driver keeps the window foreground for input. The inactive-window path is not
    tested here (BridgeSmoke covers it: 172 paints while inactive).

Run 1 (`out/F1-bridge-run1.txt`, 14/14 in the exe) showed `row5_value_final=[NOT_FOUND]`. That was a harness
timing bug: the exe's frame-gathering window (60 ticks, about 1 s) closed before the driver's final read. Fix:
the window is now 240 ticks (about 4 s) and the caret assertion was added. Run 2 is the reference.

## Fix iterations (3 of 6)

1. Mac compile: `call to main actor-isolated static method 'slot(of:)'` in a nonisolated context. Fixed with
   `nonisolated static func` (the function is pure).
2. Windows build script: the listing line failed (`Get-ChildItem -Filter` with an array). Cosmetic; fixed
   with a `Where-Object` filter. The build itself succeeded on the first attempt.
3. Harness timing: the driver's final read ran after the exe closed (run 1). Fixed by extending the
   gather window and adding the caret check (run 2).

## SR0-S F2-F9 port on the fresh runtime, bridge ABI rev 0.4 (2026-10-09, Windows 11 x64, Swift 6.4.0, scale 2.5)

Scope: `probes/sr0-s/fresh-on-bridge/` only. Runtime (`probes/sr0-s/fresh-runtime`) and bridge (`packages/SwiftRightBridge`) not edited.
Nothing committed, branched or pushed. Mac oracle: `probes/sr0-o/fixtures/Sources/SliceFixtures` (Screens, SelfTest) and
`probes/sr0-o/fixtures/RESULT.md`.

### ABI revision and DLL used (every run below)

- Bridge and header: working-tree rev 0.4 (`identifier` on `swr_semantic`, 88-byte semantic / 144-byte node). Staged to
  `D:\Claude\sr0s-bridge` at 05:39 (`packages/SwiftRightBridge` dereferenced, `render/swiftright-abi/include/swiftright.h`).
  Working-tree `Types.swift` sha256 `1a0f0d56...`, matches the staged copy.
- Renderer DLL: `D:\Claude\sr0b-abi0\payload\bin\swiftright_render.dll`, 11731456 bytes (rev 0.4 payload, built 05:21).
  The rev 0.3 staging used for the F1 smoke run at 05:31 (before the coordinator's 0.4 notice) is not part of the matrix.
- The exe bootstraps and commits under 0.4 (`commits-accepted` PASS on every run).

### Verdict table (3 runs each; final matrix `out/matrix/`, earlier pass `out/matrix-pass1/`)

| Fixture | Verdict x3 | Asserted (pass/total per run) | Blocked per run | Status identical across the 3 runs |
|---|---|---|---|---|
| F1 | PASS x3 | 15/15 | 0 | yes |
| F2 | PASS x3 | 11/11 | 0 | yes |
| F3 list (0 s gap) | PASS x3 | 11/11 | 0 | yes |
| F3 list-1s | PASS x3 | 11/11 | 0 | yes |
| F3 vstack-1s | FAIL x3 | 10/11 | 0 | yes (`reinsert-focus-matches-mac-oracle`) |
| F3 lazy-1s | BLOCKED x3 (not run) | 0 | whole variant | yes |
| F4 | PASS x3 | 10/10 | 0 | yes |
| F5 | PASS x3 | 10/10 | 0 | yes |
| F6 normal | BLOCKED x3 | 6/6 | 3 | yes |
| F6 reduced (variant flag) | BLOCKED x3 | 7/7 | 1 | yes |
| F7 | BLOCKED x3 | 10/10 | 1 (IME) | yes |
| F8 | BLOCKED x3 | 12/12 | 1 (toolbar task id) | yes |
| F9 | FAIL x3 | 4/5 pass; `tree-released` FAIL | 4 | yes |
| F9 notasks (diagnostic) | FAIL x3 | 4/5 pass; `tree-released` FAIL | 4 | yes |

Determinism: every configuration gives the same PASS/FAIL/BLOCKED status for every assertion across its 3 runs.
Only the OBSERVE timing line (F3 `reinsert-gap-ms`) varies, by design.
Infrastructure retries (the runner repeats a run only when the driver reports `not_foreground`, with no keys sent, or
`no window`). Attempts used in the final matrix: F2 run3 2, F3 list-0s run3 2, F3 list-1s run3 3, F3 vstack-1s run2 3,
run3 3. The first final-pass F1 run1 got no window; F1 was rerun 3x and all three pass.

### Mismatches against the Mac oracle (recorded, not hidden)

1. **F1 `row5-state-continuous`**: Mac `local=2` (two programmatic `setText` steps); Windows `local=4` (four keystrokes a,b,c,d).
   The check asserts continuity (equals edits since start); a reset would read 1. Input-granularity difference.
2. **F2 `local-state-kept`**: Mac `local=1` (one programmatic edit); Windows `local=2` (keystrokes `-`,`x`). Same reason.
3. **F3 vstack `reinsert-focus-matches-mac-oracle`**: Mac: VStack reinsert is not focused (SwiftUI clears focus when the focused
   row is removed). Windows: focused. Runtime gap: `FocusState` keeps the tag of a removed row, so the reinserted field is focused.
   FAIL, real. List reinsert focus matches the Mac (focused).
4. **F3 reinsert state**: List preserves `@State` (second local 1) and VStack resets it (second local 0), matching the Mac oracle
   table on 0 s and 1 s gaps. Not run at 3 s (time budget).
5. **F9 `tree-released`**: Mac also FAILs this assertion (`tree-released` 4/5 x3 in `probes/sr0-o/fixtures/RESULT.md`). Windows
   FAILs for a different measured reason: the probe is not released (0 events) after window close, with pending row tasks
   (normal) and also without any tasks (notasks). The host dropped the graph and cleared its own view references
   (11 references: focus binding and per-row text handlers); the tree is still retained. Cause is inside the runtime's graph
   retention. Not investigated further (runtime is read-only for this task).
6. **F6**: Mac normal PASS 5/5. Windows: `two-animations-started` and `final-order` PASS, the rest BLOCKED (no interpolation or
   completion; OS reduce-motion unreadable). The reduced variant's policy path PASSes (variant flag only).

### Fixture gaps (exact missing API; BLOCKED, not faked)

- F3 lazy: `LazyVStack` and `ScrollView` absent. Variant not run; the exe prints BLOCKED and exits 3.
- F6 interruption and completion: `withAnimation` records a tag per commit only. No `completionCriteria`/completion callback,
  no duration or interpolation. Start is observed (model-opened transactions).
- F6 OS reduce motion: no `EnvironmentValues.accessibilityReduceMotion` key.
- F7 IME composition: no marked-text state in `TextField`; bridge `replaceAndMark` is a plain replace.
- F8 toolbar restart: no `task(id:)`. The button action starts the effect (as in F1); the check is blocked, not asserted.
- F9 close semantics: no unmount or teardown API on `Graph`, so window close does not cancel tasks. `window_closed` is the last
  host callback and the MainActor executor is not pumped afterwards, so late engine results cannot resume.
  `swr_stats` has no live-node count, so "zero live nodes" is blocked.
- No `onChange`: local-edit counting moved to the text-write path (as in F1). No `.toolbar`: the insert button is in the body.
  Accessibility identifiers: the runtime has none; the bridge sets them (see below).

### ABI 0.4 identifiers

`BridgeBackend` sets `row/<uuid>/field` (TextField), `row/<uuid>/delete` (Delete button) and `toolbar/insert` (Insert above).
F8 `row-identifiers-committed` PASSes on every run (the backend records the committed identifiers). The driver reads the UIA
element names; AutomationId is not separately read back by the driver.

### Driver facts

- Input is UIA (`SetFocus`, `Invoke`, `ValuePattern.SetValue`) and VK `keybd_event` only; no Unicode packets.
- Keys are sent only while the test window is the foreground window. A person and other agents' windows share this desktop; a
  failed foreground acquire skips the keys and reports `not_foreground`, so no keystroke reaches another application
  (observed: `SR0-B frame-clock`, `Work with Codex`, a human typing into the field once).
- Close is `WM_CLOSE` via PostMessage (UIA `WindowPattern` is unsupported on this window). The exe quits its run loop after the
  close (`requestQuit` is called on every finish; without it the renderer loop did not return).
- Schedules: one-shot interactive task per run, deleted after (`schedule-fixture.ps1`). No leftover windows or tasks after the
  matrix (checked: no FreshOnBridge, BridgeSmoke or SwiftHost process).
- Superseded: `scripts/drive-fresh.ps1` and `scripts/schedule-fresh.ps1` (F1 path of run1/run2, invoke-driven). The F1 run2
  evidence is kept under `out/`. The current F1 starts its insert at appear, as the Mac does, so the old driver is not compatible.

### Fix iterations (per fixture, max 4)

- F1: 0 new code fixes (port works; the F1 insert is now engine-started at appear, Mac order).
- F2: 0 code fixes (driver foreground and text checks only).
- F3: 2 (settle between remove and reinsert: the runtime sees remove+insert in one turn as no change; task modifier placed
  innermost so teardown runs disappear before cancel, as on the Mac).
- F4, F5: 0 code fixes.
- F6, F7, F8: identifiers (F8) only.
- F9: 1 (quit after close; tree-release measurement split into `tree-released-at-graph-drop` and post-clearing).
No Codex consult was needed.

### Evidence

- `out/matrix/*.txt` (final, per run: driver lines, exe stdout incl. EVT, stderr), `out/matrix/run-log.txt`.
- `out/matrix-pass1/` (first full pass; superseded by the final pass for F3 and F9, and by F1 rerun).

## Primary verification (2026-10-09)

Primary tallied `out/matrix/`: final run files match the table above. The `.aN.txt` files are earlier attempts of the same run that ended early (window lost foreground on the shared desktop, keys withheld) and were retried; they are kept as evidence, not counted. Retries mean these results show correctness under a quiet desktop, not robustness to foreground theft — repeatability counts for the oracle protocol must report attempts as well as passes.

Runtime gaps to fix next (fresh runtime): focus cleared when the focused row is removed (Mac behaviour, F3 vstack); graph releases the tree after window close (F9); `task(id:)` restart (F8); LazyVStack/ScrollView (F3 lazy); animation interpolation, completion and interruption plus OS reduce-motion (F6); IME composition through the runtime text model (F7).
