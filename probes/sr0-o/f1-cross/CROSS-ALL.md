# CROSS-ALL: Mac SwiftUI vs Windows fresh runtime, schema-v0 cross-compare of all 16 configs (T1)

**Current verdict: see "Tuple 10" below: 11 of 16 configs pass, 5 fail on one remaining difference (launch selection). The tuple 09 section below is the previous run. The "After review" section is the pre-fix tuple 08 result; the first-pass "13 of 16" is superseded.**

10 Oct 2026, repo HEAD cfca6d6 plus the uncommitted T1 changes. Mac: macOS 27.0.1 (26A434) arm64, Swift 6.4. Windows: Dell, tuple 08 FreshOnBridge `7673A2D5139172D8...` with renderer `E280F4A9FD9ECA0A...` (all 48 Windows runs record both hashes in `cross-evidence/<config>/win-run-w*.log`), UIARecorder `D255A25579C37751...` built on the Dell from `uia-recorder/`.

## Tuple 11 (11 Oct 2026): 16 of 16

Windows: FreshOnBridge `073513142F25C454...` at `D:\Claude\sr0-r11\src` (runtime 8e47b89 plus the host AX selection-publish fix), renderer `E280F4A9FD9ECA0A...`, UIARecorder `D255A25579C37751...` (unchanged). All 48 runs (16 configs x3) record exe `07351314...` (`cross-evidence/<config>/win-run-w*.log`; the batch aborts on any other exe). Lock `D:\Claude\desktop.lock` taken as `cross11` at 06:52 IST and freed at 07:26 after matrix11; window-targeted input only; nothing deleted on the Dell. (My own wait loop did not notice the batch had finished: `pgrep -f win-cross.sh` matched the waiting shell itself. The pulls were complete at 07:26; the assemble and compare ran at 11:40.) Mac recordings unchanged. Reports and event log: `cross-evidence/runner-compare-tuple11/`.

| Config | Diffs | Allowed (besides N1) | Verdict |
|---|---|---|---|
| F1, F3-vstack-1s/3s, F3-lazy-1s/3s, F4, F5, F6-reduced, F7, F8 | 0 | 0 | PASS |
| F2 | 0 | P1 x6 | PASS |
| F3, F3-list-1s, F3-list-3s | 0 | P2 x2 | PASS |
| F6 | 0 | C11 x4 | PASS |
| F9 | 0 | P6 x1 | PASS |

16 of 16 pass, 0 diffs; launch selection now matches (Mac 0+5, Windows 0+5). The three Windows runs of each config agree; 69 negative controls, all rejected (event log: 85 passes, 0 failures). Remaining allowances, all scoped to one step: N1 (native input routes), P1 (F2 stale Mac AX tree, oracle-quirk), P2 (F3 List remove/reinsert, oracle-quirk, evidenced by the typeafter probe), C11 (proposed contract C11, F6 four counts), P6 (F9 `treeReleased`). Still UNPROVEN: R5, R6, R8.

### Offline runner stages on the final tuple (`qualification/tuple-final.json` re-pinned to tuple 11)

| Stage | Result |
|---|---|
| compare (all 16, with 69 controls) | PASS 16/16 |
| workload (`r10-20261011-tuple10-renderere280-windows.txt`) | PASS: W4 p95 48.73 ms vs Mac 75.94, W5 interval p95 16.74 vs 17.91; missed vblanks 1/1/1 reported, not gated. Bound to renderer E280F4A9 |
| native (`*-tuple10`, `ime-f7` from `tuple10b`) | receipts clean (F7 20/20, F7live 20/21 and F8 18/19 with the known `candidate-window-follows-layout-move`, Narrator 8/8 with speech pending a person) but the gate FAILS the binding: the preflights record FreshOnBridge `F136046B` (tuple 10), the pin is `07351314`. The native receipts have to be re-run on tuple 11 (or the pin accepted as host-only change by the lead) |
| package | Mac 12/12 PASS, Windows network profile PASS; Windows offline profile FAIL on `W08-interrupted-update` (known open item T12) |

## Tuple 10 (11 Oct 2026): Mac vs Windows after D2 and the D3 decision

Windows: FreshOnBridge `F136046BEFE7EE99...` at `D:\Claude\sr0-r10\src` (runtime 8e47b89), renderer `E280F4A9FD9ECA0A...`, UIARecorder `D255A25579C37751...` (both unchanged); all 48 runs (16 configs x3) record exe `f136046b...` in `cross-evidence/<config>/win-run-w*.log` and `win-cross.sh` aborts on any other exe (`-Bin` passed explicitly, so the Dell copy of the script's own default does not matter). Lock `D:\Claude\desktop.lock` taken as `cross10` after matrix10 and r5-10, freed at 01:28 IST; window-targeted input only; nothing deleted on the Dell. Mac recordings unchanged (stimulus unchanged). Reports and event log: `cross-evidence/runner-compare-tuple10/`.

| Config | Diffs | Allowed (besides N1) | Verdict |
|---|---|---|---|
| F1, F4, F6-reduced, F7, F8 | 0 | 0 | PASS |
| F2 | 0 | P1 x6 | PASS |
| F3, F3-list-1s, F3-list-3s | 0 | P2 x2 | PASS |
| F6 | 0 | **C11 x4** | PASS |
| F9 | 0 | P6 x1 | PASS |
| F3-vstack-1s/3s, F3-lazy-1s/3s, F5 | 1 each | 0 | **FAIL** (D2, below) |

11 of 16 pass, 5 fail, 5 diffs. Windows runs agree across the 3 runs of every config. 69 negative controls (65 plus the 4 new C11 ones), all rejected.

- **C11 (was D3), now allowed.** Scoped allowance `C11` in `cross/F6/adapt-v0.json`: step `initial`, leaf `lifecycle.count`, exactly the pairs `appear:row/...200` and `...201` 2 to 1 and `disappear:row/...200` and `...201` 1 to 0, reason per the lead decision (Mac re-creates every List row inserted under an animation when its insertion animation completes, row 201 too). Fault controls: each of the four pairs gets the count set outside the allowed value (and clear of the Mac value), all rejected. Proposed contract change C11 is next to C9 in `conformance/sr0-slice/CONTRACT.md`.
- **D2 is NOT fixed in the recordings (5 configs, 1 diff each).** `initial` selection: Mac `location=0 length=5`, Windows `location=5 length=0`, in 3 of 3 runs on each side, with the new exe. The focused node and `initialFocus` agree. The runtime does select all at launch (the new self-test assertion in the same F5 run: `selection-at-launch=0+5/5`, PASS), so the selection is correct in the runtime at the moment of focus but UIA (TextPattern selection of the focused field, read about 3 s after launch at the `initial` step) still reports the caret at the end. Either the selection is changed between launch and the snapshot (for example by the text-store focus handling or the AX publish) or the AccessKit text selection is published from a different source than the runtime selection. This is a product-side difference between runtime state and the published accessibility selection; it is not recorder timing (the same value in 3 of 3 runs and F5's later steps read 15, the end, as on the Mac). No allowance was added.

## Tuple 09 (10 Oct 2026): Mac vs Windows after the product fixes

Windows: FreshOnBridge `8650BBFC4118F079...` at `D:\Claude\sr0-r09\src`, renderer `E280F4A9FD9ECA0A...` (unchanged from tuple 08), UIARecorder `D255A25579C37751...` (unchanged); all 51 runs (16 configs x3 plus the P2 probe x3) record exe `8650bbfc...` in `cross-evidence/<config>/win-run-w*.log`, and `win-cross.sh` now aborts a batch whose run used another exe (a first batch of 51 runs went out on tuple 08 because the Dell copy of `schedule-cross.ps1` kept its old `-Bin` default; it was discarded, the script now passes `-Bin` and checks the exe hash). Lock `D:\Claude\desktop.lock` taken as `cross09`, freed after each batch; window-targeted input only; nothing deleted on the Dell; no window titles in the committed files. Mac: the recordings of the earlier sections (stimulus unchanged, Mac oracle unchanged) plus 3 new Mac runs of the P2 probe. Comparator and assembler from the working tree; reports and event log in `cross-evidence/runner-compare-tuple09/`.

| Config | Diffs | Allowed (besides N1) | Verdict | Remaining diff |
|---|---|---|---|---|
| F1, F4, F6-reduced, F7, F8 | 0 | 0 | PASS | (F8: focus after Invoke now matches; F6-reduced: conditions equal) |
| F2 | 0 | P1 x6 | PASS | |
| F3, F3-list-1s, F3-list-3s | 0 | P2 x2 | PASS | D1 is gone: `localEdit` and `local N` match |
| F9 | 0 | P6 x1 | PASS | |
| F3-vstack-1s/3s, F3-lazy-1s/3s | 1 each | 0 | FAIL | D2 |
| F5 | 1 | 0 | FAIL | D2 |
| F6 | 4 | 0 | FAIL | D3 |

11 of 16 pass, 5 fail, 9 diffs. The three Windows runs of every config agree, the Mac runs agree (`sr0o-trace repeat`). 65 negative controls, all rejected (event log: 16 compare verdicts, 11 pass and 5 fail, plus the 65 controls). Fixed since the pre-fix recordings: launch focus (the Windows build now focuses row 1 and logs `initialFocus`), focus after Invoke, the motion condition (`reduceMotion.effective` false on both: animations run on the Dell by design, OS animation setting not mapped to reduce motion), D1.

### Remaining diffs and their classification

- **D2 (5 configs): launch selection.** `initial` selection: Mac `location=0 length=5` (the whole text selected), Windows `location=5 length=0` (caret at the end). The focused node (row 1 field) and the `initialFocus` event now agree. Real difference, not recorder timing: the raw Mac AX at `initial` is an `AXTextField` without `AXIdentifier` holding selection 0+5, identical in 3 of 3 runs for each of the five configs, and Windows UIA reports the field with the caret at 5 in 3 of 3 runs. (The product agent's note that Mac AX reports no focus at `initial` was an artefact of the first-pass assembler, which dropped the unidentified field-editor focus; it is now named by the FocusState event, see "What changed" above.) Not allowed: it is a behaviour decision for the contract (AppKit selects all when a field becomes first responder at launch; the Windows runtime puts the caret at the end), either the Windows runtime selects all or CONTRACT F3/F5 states that launch selection is platform-defined, and then a scoped allowance on step `initial`, leaf `selection`, row 1 is justified.
- **D3 (F6): row rebuild.** Rows 200 and 201: `appear` Mac 2 / Windows 1 and `disappear` Mac 1 / Windows 0. SwiftUI recreates the interrupted animated rows; the fresh runtime keeps the views (also in the earlier run with animations off, so this is not the motion condition). Real difference in view identity during an interrupted animation; the CONTRACT F6 assertions (interruption recorded, completion order, final layout) are met on both. Needs the same decision as D2: Windows reproduces the rebuild, or CONTRACT F6 declares row view recreation unspecified and a scoped allowance (step `initial`, those four `lifecycle.count` pairs) is added.
- **P2 resolved by the probe `F3-list-1s-typeafter`** (3 Mac + 3 Windows runs). After the remove/reinsert the next typed `y` lands nowhere on the Mac (row 4 stays `Row 4`, no focus, `localEdit` 0) while on Windows it lands in row 4 (`yRow 4`, focus row 4 field, caret 1, `localEdit` 1). So the Mac's keyboard focus really is lost although its FocusState event says row 4 is focused: P2 is a Mac oracle quirk against its own FocusState event, not a Windows defect. P2 stays as a scoped allowance (step `type_x_remove_reinsert`, focus and selection only), status changed from unproven to oracle-quirk. The probe's own step is not allowed and fails by design (6 diffs: `model`, `focusedNodeId`, `selection`, `localEdit`, field value, `local` label); it is evidence, not one of the 16 configs.
- **Still allowed with reasons:** N1 (native input routes), P1 (F2 stale Mac AX tree), P2 (above), P6 (F9 `treeReleased`). Still UNPROVEN: R5, R6, R8 (see above).

### T14 closure gate (`qualification/run.py`)

Stages `workload` and `native` are in the default run, tuple-pinned like `smoke` and `package`; compare fails unless it covers all 16 configs.
- `workload`: the Windows R10 analyzer receipt must carry the tuple renderer hash, 3 timed runs, and every threshold PASS (W7 measured) except the two that section 11 of `docs/sr0-findings.md` replaces: W4 input-to-visible p95 and W5 presented-interval p95 must each be no worse than the median of the Mac receipt's per-run values (a re-analysis appended to a receipt replaces the orchestrator output). Missed vblanks are reported per run, not gated. Tuple 08 receipts: pass (Windows W4 p95 43.9 ms against Mac 75.9; interval p95 16.74 against 17.91).
- `native`: `preflight` bound to the tuple fixture exe and renderer, `static-check` CHECK_OK, and the `ime-f7`, `ime-f7live`, `ime-f8`, `narrator` receipts each with a `NATIVE_SUMMARY`; the only failing check allowed is the known limitation `candidate-window-follows-layout-move` (SR1), and the Narrator speech checks are reported as pending a person (U1), not gated. Tuple 08 receipts: pass.
- Defaults are the tuple 08 receipts; tuple 09 workload and native receipts do not exist yet: run with `--workload-windows`, `--workload-mac`, `--native-dir`, `--native-tag`. Two `TupleFileTests` fail until `qualification/tuple-final.json` is updated to tuple 09 (`run-matrix.sh` already defaults to tuple 09 hashes).

## After review (10 Oct 2026): the honest verdict on today's (pre-fix) Windows recordings

An independent review found the first-pass allowances too broad and some masking real Windows differences. This section is the
current verdict; everything below it ("Result" onward) is the first pass, kept as history, and is superseded where it disagrees.
No Mac GUI run and no Dell run were made: the 96 recordings are the same raw files, re-assembled and re-compared offline
(`scripts/reassemble.sh`; raw recorder output and in-process events are now committed under `cross-evidence/<config>/raw/` and
`mac-ev-*`/`win-events-*`; `ReassemblyTests` proves every committed trace is the assembler output of them).
The Windows recordings predate the product fixes (initial focus at launch, Invoke not moving focus, animations independent of the
Windows animation setting, `onChange` after List reinsertion), so the expected result is failures; a rerun after a new Windows
recording replaces this table.

### Result

Comparator and assembler from the working tree; event log, per-config reports and counts in `cross-evidence/runner-compare-after-review/`.

| Config | Diffs | Allowed (besides N1) | Verdict | What fails |
|---|---|---|---|---|
| F1 | 0 | 0 | PASS (promoted Mac baseline) | |
| F2 | 0 | P1 x6 | PASS | |
| F3 (List, 0 s) | **2** | P2 x2 (UNPROVEN) | FAIL | D1: `localEdit` 2 vs 1, label `local 2` vs `local 1` (recording predates the `onChange` fix 3ffcf95) |
| F3-list-1s | **2** | P2 x2 (UNPROVEN) | FAIL | D1, as F3 |
| F3-list-3s | **2** | P2 x2 (UNPROVEN) | FAIL | D1, as F3 |
| F3-vstack-1s | **3** | 0 | **FAIL (new)** | launch focus: Mac holds focus on row 1 (selection 0+5, `initialFocus` event), Windows none |
| F3-vstack-3s | **3** | 0 | **FAIL (new)** | launch focus, as above |
| F3-lazy-1s | **3** | 0 | **FAIL (new)** | launch focus, as above |
| F3-lazy-3s | **3** | 0 | **FAIL (new)** | launch focus, as above |
| F4 | 0 | 0 | PASS | |
| F5 | **7** | 0 | **FAIL (new)** | launch focus (3, as F3-vstack) and focus after launch in both later steps (4; was P3) |
| F6 | **5** | 0 | **FAIL (new)** | motion condition `reduceMotion.effective` false (Mac) vs true (Dell: Windows animation effects were off, `system_reduce: "on"`, `reduce_source: "os"`); rows 200/201 appear/disappear counts 2/1 vs 1/0 (4; was P4) |
| F6-reduced | 0 | 0 | PASS | both sides ran reduced (variant flag) |
| F7 | 0 | 0 | PASS | |
| F8 | **1** | 0 | **FAIL (new)** | focus after Invoke: Mac none, Windows `toolbar/insert` (was P5) |
| F9 | 0 | P6 x1 | PASS | |

6 of 16 configs pass (F1, F2, F4, F6-reduced, F7, F9), 10 fail, 31 diffs: 15 launch focus (F3-vstack/lazy x4, F5), 4 F5 focus after launch,
5 F6 (1 condition, 4 row rebuild), 1 F8, 6 D1 (F3 List x3). Before the review: 13 of 16 passed. The three Windows traces of a config
still agree in every compared field, and so do the three Mac traces (`sr0o-trace repeat`, 32 sets; the earlier F2 "2 duplicates | 2 duplicates"
comparator quirk is fixed: duplicate ids are a diff only when the two sides show different counts).

### What changed in the comparison

1. **Allowances are scoped.** Every allowance in `cross/<config>/adapt-v0.json` names `fixture`, `steps[]`, the leaf `field`, for node leaves the `nodeId`, and exact
   `expected -> actual` value pairs (plus `id`, `status`, `reason`). TraceKit `Adaptation` applies it only when all of them match; an entry missing any scope, with
   both or neither of `mapping`/`allowAnyValue`, with `allowAnyValue` anywhere but `steps.nativeMapping` (N1), or on `fixtureId`, `schemaVersion`, `sourceHash`,
   `conditions`, `steps.order` is ignored and the report notes why. The report lists every forgiven diff under `allowed`. N1 names every step of its own config
   and nothing else. The runner takes allowances from the cross plan only (a promoted `conformance/accepted/<config>/adapt-v0.json` predates the format; F1's is
   still the old unscoped N1 and is now unused).
2. **Allowances removed (product differences, not oracle facts):** P3 (F5 initial focus), P4 (F6 row rebuild), P5 (F8 focus after Invoke). They are failing diffs now.
3. **Recorder normalisations removed:** R1 (the assembler dropped the selection whenever the focused element had no canonical node; that hid the launch focus of
   F3 VStack/LazyVStack and F5, where the Mac field editor holds a 0+5 selection at launch) and the exclusion of in-process focus events. Now the selection is always
   kept; an unidentified focused Mac text field is named by the latest in-process FocusState event (`R1-field-editor`) or stays visible as `unmapped:AXTextField`;
   focus held by a container (outline, window) is still "no element focus" (A9). Launch focus events become the lifecycle fact `initialFocus:<row>` (later focus events are
   not compared as events: the Mac fixture logs every FocusState change, the Windows runtime only AX-sourced ones, payload `source: "ax"`; AX focus and selection of every step are compared).
4. **Run conditions are in the trace** (`conditions`: `reduceMotion.variant`, `reduceMotion.effective`; effective = the platform's `effective_reduce`, or `system_reduce || variant_reduce` on the Mac).
   They are compared exactly and cannot be allowed: Mac and Windows traces recorded under different motion conditions FAIL.
5. **Kept, with reasons:** P1 (F2 stale Mac AX tree after the focused row moved: CONTRACT F2 asserts the order is updated; scoped to step `type_dash_x_then_move`, 6 pairs, status oracle-quirk),
   P6 (F9 `treeReleased` after close: a Windows requirement, not a Mac oracle assertion; step `close_window`, status contract), N1.
6. **UNPROVEN, not settled, listed so nobody reads a PASS as proof** (each says what would settle it):

| ID | What is assumed | Why it is not proven | Probe that settles it |
|---|---|---|---|
| P2 (F3 List) | After remove/reinsert the Mac AX focus is the outline only because the AX route lags; Windows restoring focus to row 4 matches the FocusState oracle | the Mac AX focus (outline, no selection) disagrees with Mac's own FocusState event; nothing shows where a key would land | **Plan added: `cross/F3-list-1s-typeafter`** = F3-list-1s plus step `type_after_reinsert` (type `y`, no expectation). Record both platforms: if the character lands in row 4 on both (model, focus, selection agree) P2 is an AX-route quirk; if it lands nowhere on the Mac, Windows restores focus where the Mac does not and P2 is a product difference. Purely additive (base steps unchanged); needs one Mac and one Dell recording, not made here |
| R5 (F5 start size) | Both platforms resize to 720x560 in `initial`, so the first layout is comparable | hides that the platforms' own default sizes (Mac 480x560, Windows exe 640x480) pick different first layout modes; the intermediate layout passes while a window settles are not compared (only the mode a step ends in) | F5 launched at each platform's own default size with the expected layout mode taken from the contract breakpoint (not from the other platform), and all layout passes recorded to require a monotone settle |
| R6 (F7 composition) | One key event carrying `na` on the Mac is the same stimulus as the Windows in-process text-store composition | the Mac never composes (no IME), so Windows' marked text, underline and commit-on-focus-change have no Mac counterpart; only the committed outcome is compared | A Mac recording with a real input method (Kana) reading the field's marked range per step through a fixture debug event, against the Windows TSF text store driven by the same input source |
| R8 (F9 late results) | Ignoring effects in step `close_window` is harmless because the Windows self-test asserts the late-result rejection | Mac exits when its last window closes, so late engine releases never exist on the Mac; the Windows behaviour is never compared | An F9 Mac fixture variant that stays alive after the last window closes, the same late releases sent, then `ignoreEffectsInSteps` dropped |

### Fault controls (65, all rejected)

Each alters one fact of a copy of the Windows trace and must produce a NEW diff (new step, path and actual value) on the named leaf, otherwise the stage fails.
Per-config: F2 wrong focus; F3 and its six variants wrong focus, missing lifecycle event, wrong model text (21); F4 missing lifecycle; F5 wrong focus, wrong layout effect,
missing lifecycle; F6 wrong run condition, wrong effect, missing lifecycle; F6-reduced wrong run condition; F7 wrong focus, wrong role; F8 wrong focus (new), wrong role,
missing lifecycle; F9 missing lifecycle. Every config: altered logical action (proves N1 does not leak into the neighbouring leaf, 16). Every remaining allowance: the covered leaf set
to a value outside its pair at each step it names (P1 x6, P2 x2 in each of the three List configs, P6 x1 = 13). Unit tests: scoping (an allowance must not apply at another step, node,
fixture or value pair), invalid allowances, run conditions and duplicate ids (`AllowanceScopeTests.swift`; `swift test` in `comparator/`: 35 tests), allowance injectors and controls against stand-in comparators, the assembler rules,
and the real comparator over the committed recordings (`qualification/test_run.py`: 163 tests with `SR0A_BUILD_ROOT` set, was 136).

### Reproduce offline (no GUI, no Dell)
1. `swift build` the comparator (`probes/sr0-o/comparator`) and F1Assemble (`probes/sr0-o/f1-cross`) under a scratch root on the internal disk.
2. `probes/sr0-o/f1-cross/scripts/reassemble.sh <F1Assemble>` rebuilds the 96 traces and the compare inputs from the raw recordings.
3. `SR0A_BUILD_ROOT=<scratch> SR0A_OUT_ROOT=<scratch> python3 -I qualification/run.py run --stages compare --win-candidate-dir probes/sr0-o/f1-cross/cross`
   (the runner builds the comparator from the committed tree, so commit the comparator first).

## First pass (superseded by the review above): Result

| Config | Mac runs (3) | Win runs (3) | Raw diffs (only N1 allowed) | After the reasoned allowances | Verdict |
|---|---|---|---|---|---|
| F1 | identical | identical | 0 | 0 | PASS (accepted baseline) |
| F2 | identical (a) | identical | 6 | 0 | PASS |
| F3 (List, 0 s) | identical | identical | 4 | **2** | FAIL, runtime defect D1 |
| F3-list-1s | identical | identical | 4 | **2** | FAIL, runtime defect D1 |
| F3-list-3s | identical | identical | 4 | **2** | FAIL, runtime defect D1 |
| F3-vstack-1s | identical | identical | 0 | 0 | PASS |
| F3-vstack-3s | identical | identical | 0 | 0 | PASS |
| F3-lazy-1s | identical | identical | 0 | 0 | PASS |
| F3-lazy-3s | identical | identical | 0 | 0 | PASS |
| F4 | identical | identical | 0 | 0 | PASS |
| F5 | identical | identical | 4 | 0 | PASS |
| F6 | identical | identical | 4 | 0 | PASS |
| F6-reduced | identical | identical | 0 | 0 | PASS |
| F7 | identical | identical | 0 | 0 | PASS |
| F8 | identical | identical | 1 | 0 | PASS |
| F9 | identical | identical | 1 | 0 | PASS |

Totals: 28 raw diffs = 22 contract-permitted + 6 runtime defect (D1, three configs). 13 of 16 configs pass, 3 fail. Seven injected-fault controls: 7 of 7 rejected. 96 recordings (3 per platform per config); the three Windows traces of a config agree in every compared field, and so do the three Mac traces (a: for F2 the comparator prints "2 duplicates | 2 duplicates" on Mac run pairs, a comparator quirk, see "Comparator notes"). Cross-compare is `qualification/run.py run --stages compare --win-candidate-dir probes/sr0-o/f1-cross/cross`; its event log and reports are in `cross-evidence/runner-compare/` (`compare-events.jsonl`: 20 pass, 3 fail).

Raw diffs first pass (before any recorder fix, after removing one assembler bug of mine): F2 6, F3 x3 4, F3-vstack x2 3, F3-lazy x2 126, F4 1, F5 14, F6 4, F7 2, F8 7, F9 2, F1 and F6-reduced 0.

## Classification of every diff

### Recorder artifacts (fixed in the recorders, none remain)

| # | Artifact | Configs (first pass) | Fix |
|---|---|---|---|
| R1 | Mac reported the selection of a focused element without an `AXIdentifier` (AppKit field editor / first responder), Windows reports none | F3-vstack, F3-lazy, F5 | **WITHDRAWN by the review**: `F1Assemble` dropped the selection with the focus, which hid the Mac's launch focus (a real difference). The selection is kept; the field editor is named by FocusState or shown as `unmapped:AXTextField` |
| R2 | Effect order across nodes: sibling `.task` start order over 10 rows and the engine's release order are scheduler order; the comparator compares `effects` as an ordered list | F4, F3-vstack, F3-lazy, F5 | `F1Assemble` canonicalizes like digest v2: between two driver operations lines are grouped by node, per-node order kept |
| R3 | `AXOpaqueProviderGroup`, the AX wrapper SwiftUI adds around LazyVStack content, was not a named stripped container (123 diffs) | F3-lazy x2 | added to the stripped Mac containers (adaptation A10); CONTRACT §5 list should name it |
| R4 | `AXZoomButton` window chrome (resizable window) was not in the dropped chrome subroles | F5 | added to A4 |
| R5 | Initial window size differs (Mac 480x560, Windows exe 640x480), so the first layout mode differed; the mode also flickers while a window settles | F5 | both platforms resize to 720x560 in `initial`; only the mode a step ends in is compared. **UNPROVEN** (see After review) |
| R6 | Mac typed the IME stimulus as two commits (`n`, `a`), the Windows runtime commits `na` once (`onChange` count 2 vs 1) | F7 | new op `typeChunk`: one key event carrying `na` (single commit). Composition mid-state is not comparable on Mac (CONTRACT §5). **UNPROVEN** (see After review) |
| R7 | Mac `AXValue` writes are ignored by SwiftUI `TextField` (probed: model unchanged with AXValue, AXValue+AXConfirm, or focus first), so the "set value" step never reached the model | F8 | new op `replaceText`: AXSelectedTextRange=all, then AXSelectedText (reaches the model, `local-edit` fires) |
| R8 | Interactive Mac fixture exits when its last window closes, so late engine releases (Windows script releases after close) cannot exist | F9 | stimulus `ignoreEffectsInSteps: ["close_window"]`; Windows self-test asserts the late-result rejection itself. **UNPROVEN** (see After review) |
| R9 | AppKit restores the previous window frame from the app defaults | F5 | `F1MacRecord` clears `NSWindow Frame *` before launch |
| R10 | The Mac AX tree was read once; a re-walk until two consecutive trees agree (bounded 6 s) is used, duplicates stay visible if they persist | all | `F1MacRecord` settle loop |
| R11 | Assembler mapped any Windows `start` lifecycle event (the self-test's own) to an animation start | all Windows | mapping now requires node `animation` |

Windows side: typing is window-targeted `WM_CHAR` posted to the fixture HWND (`SR0O_KEY_DELIVERY=targeted`), resize is `MoveWindow` and close is `WM_CLOSE` on that HWND, activation is UIA Invoke, value is ValuePattern. No global input was sent.

### Contract-permitted in the first pass (22 diffs). Withdrawn by the review: P3, P4, P5. Kept: P1, P6. P2 is UNPROVEN. Allowances now carry fixture, steps and node (see above)

| ID | Config | Diffs | Mac | Windows | Reason |
|---|---|---|---|---|---|
| P1 | F2 | 6 | After the focused row 3 is moved, macOS 27 SwiftUI List reports a stale AX tree: row 3 listed twice at its new slot, row 2 missing (model read, `duplicateId`, presence of row 2, parent of row 3 x2). Persists after resize, heals only when focus leaves the row (probe: focus row 1 restores `1,2,4..`). Present in every Mac run (three final runs checked frame by frame, earlier runs too); absent when the moved row is not focused | accessibility order updated, row 2 present | CONTRACT F2 asserts the order is updated, which Windows meets; the stale tree is the Mac oracle's fault |
| P2 | F3, F3-list-1s, F3-list-3s | 6 (2 each) | After remove/reinsert the Mac `@FocusState` event says row 4 focused, but AX focus is the outline and there is no field selection | UIA focus on row 4, selection 0+0 | Windows matches the FocusState oracle in RESULT.md ("List restores focus"); the AX route is the quirk |
| P3 | F5 | 4 | AppKit gives the first text field initial focus (caret 15 after the async update) | no initial focus | initial focus is not an F5 assertion |
| P4 | F6 | 4 | SwiftUI rebuilds the interrupted rows: rows 200 and 201 appear twice, disappear once (the B pair varies run to run per fixtures RESULT.md) | rows kept: appear once, disappear zero | not an F6 assertion; completion order is `A,B` on both platforms in all 6 runs, so this is not the A/B order issue |
| P5 | F8 | 1 | AXPress leaves focus where it was | UIA Invoke moves keyboard focus to the invoked button (`ax-button-focus`, AccessKit) | CONTRACT F8 does not specify focus after activation |
| P6 | F9 | 1 | `treeReleased` absent | present | CONTRACT F9: tree release is a Windows requirement, not a Mac oracle assertion |

### Runtime defect (reported, not fixed)

**D1 (F3, F3-list-1s, F3-list-3s; 2 diffs each).** After a List row is removed and reinserted with the same identity, Mac preserves `@State` (`local` 1) and `.onChange(of: row.text)` fires once more because the reinserted text `Row 4` differs from the preserved last value `Row 4x`: 2 `local-edit` events, final label `local 2`. The Windows runtime preserves `@State` too (`appear` local 1, matching the oracle) but `onChange` does not fire: 1 `local-edit`, final label `local 1`.
Evidence: `cross-evidence/F3*/mac-ev-n{1,2,3}.jsonl` (`local-edit` for row 4: 2 in all 3 runs, `appear` locals `[0,1]`) against `win-events-w{1,2,3}.txt` (1 in all 3 runs, `appear` locals `[0,1]`); comparator diffs `lifecycle.count[localEdit:row/F0000003-...-000000000004]` 2 vs 1 and `axNodes.label[.../local]` `local 2` vs `local 1` in `cross-evidence/runner-compare/compare-F3*.json`. VStack and LazyVStack (fresh state on both) show 0 diffs. Likely cause: the `onChange` previous-value baseline is re-captured at reappearance instead of being kept with the preserved state. Not in any assertion of the Windows self-test (`reinsert-state-matches-mac-oracle` passes), so it was invisible until now.

### Mac oracle findings (not Windows defects)
1. SwiftUI `TextField` ignores `AXValue` writes (R7), so CONTRACT F8 "set value via AX" has no Mac AX route except AXSelectedText.
2. F2 stale AX tree while the moved row holds the field editor (P1).
3. List reinsertion: `@FocusState` and AX focus disagree (P2).

## Injected semantic faults (all rejected)

`qualification/run.py` `FAULT_CONTROLS`: after the real comparison of a config, a copy of the Windows trace is altered in one fact and must produce a new diff on the named leaf, otherwise the stage fails (so a vacuous comparator fails).

| Config | Fault | Altered fact | New diff |
|---|---|---|---|
| F2 | wrong focus target | final focus row 3 to row 1 | `focusedNodeId` |
| F4 | missing lifecycle event | drop `taskCancel` row 2 | `lifecycle.count[taskCancel:row/...002]` |
| F7 | wrong focus target | focus row 2 to row 1 | `focusedNodeId` |
| F7 | wrong AX role | row 1 field text-field to button | `axNodes.role[row/...001/field]` |
| F8 | wrong AX role | row 1 field text-field to button | `axNodes.role[row/...001/field]` |
| F8 | missing lifecycle event | drop `appear` row 10 | `lifecycle.count[appear:row/...010]` |
| F9 | missing lifecycle event | drop `taskStart` row 10 | `lifecycle.count[taskStart:row/...010]` |

Unit tests (first pass: `qualification/test_run.py`, 136 tests, all pass, 1 skipped: needs `SR0A_BUILD_ROOT`): fault injection alters a copy only, a comparator that passes the altered trace fails the control, every config has matching stimulus and step files, adaptations are reasoned value mappings (no `allowAnyValue` beyond N1), compare input resolution, per-config win-replay recording, and the F6 mirror below.

## F6 unordered completions (653b253)
`qualification/run.py` `canonical_body` now mirrors `normalize-hash.py f6_unordered_completions`. Tests: B-first completion passes, duplicate or missing or relocated completion fails, other fixtures untouched. Both candidate directories under `conformance/candidates/F6/` and `r6/f6/run{1,13,23,24,25}.jsonl` canonicalize to the accepted F6 digest, so mac-oracle F6 no longer reports 2 variants. The cross-compare itself never needs the order: lifecycle is compared as a multiset and all 6 cross runs completed `A,B`.

## Not proven / limits
- 3 runs per side per config, not 20.
- Mac baselines for F2-F9 are the first Mac recording (`cross/<config>/mac-trace-v0.json`, evidence of three equal runs in `cross-evidence/`). They are **not promoted**: `conformance/accepted/<config>/trace-v0.json` exists only for F1, and only `promote --approved-by` may write it. The runner prefers an accepted file and labels the fallback "unpromoted Mac cross recording". `sourceHash` is the hash of `stimulus.json`, so a changed stimulus invalidates its baselines.
- F7: Windows composition is driven in-process through the text-store API, Mac commits `na` with one key event; only the committed outcome, identity, focus and AX tree are compared, not the open marked-text state.
- F5 containment, paint, hit-test and AX bounds are not in schema v0 (frames excluded). F6 intermediate frames are not compared. F9 post-close late-result rejection is not compared (R8).
- (First pass, superseded) Initial focus, the AX tree under List after moves and focus after activation were allowed as exact value pairs (P1-P5). The review withdrew P3, P4, P5 and the R1 launch-focus rule; P1 and P6 stay scoped to one step; P2, R5, R6, R8 are UNPROVEN (see After review).
- The runner's `win-replay` per-config recording path (`win_cross_trace`) is unit-tested with a fake transport only. The 96 live recordings used `scripts/win-cross.sh`, which calls the same `schedule-cross.ps1`; the `win-replay` stage assembles with `F1Assemble` built from the committed tree, so it needs the T1 changes committed first.
- Comparator notes: `axNodes.duplicateId` used to report a diff whenever either side had duplicate ids even when the two counts were equal (fixed in the review: only unequal counts differ); `declaredOrder` is read from the accepted side only.

## Dell protocol
Lock `D:\Claude\desktop.lock` taken as `T1 <timestamp>` and written `free` after each batch by `scripts/win-cross.sh` (waits in a background loop while another owner holds it; batches 15:30-15:35, 18:48-18:49, 18:49-18:57, 18:59-19:00 IST). Window-targeted input only. Nothing was deleted on the Dell: the temp archives of the file sync were left in `%TEMP%` (a copy of `scripts/sync-to-win.sh` without its cleanup was used), the first F5 attempt files were overwritten by the rerun with the same tags, and each run's one-shot scheduled task unregisters itself as in the existing `schedule-f1.ps1` pattern. No window titles are in the committed logs (the harness never reads them).

## Reproduce
1. Dell: sync `scripts/`, `cross/`, `uia-recorder/` to `D:\Claude\sr0o-f1` (sync without cleanup), run `scripts\build-rec.ps1`.
2. `python3 probes/sr0-o/f1-cross/scripts/gen-cross.py` regenerates `cross/` (stimulus, both step files, adaptations).
3. Windows: `FIRST=1 scripts/win-cross.sh <out> 3 <config>...`; assemble with `F1Assemble win --rec ... --side ... --events ... --stimulus cross/<config>/stimulus.json --keep-lists`.
4. Mac (signed recorder and fixture built under the scratch root, never run from /Volumes/D): `scripts/record-mac.sh <F1MacRecord> <FixtureApp> <F1Assemble> <out> <tag> <config>...`. Recorder: Developer ID, team 6KLGD3LLKF, identifier `com.orthiclabs.swiftright.f1macrecord`, executable sha256 `5f1ac0c75398a401...`; FixtureApp `123827e157aa9e70...` from tree 1b4affaf44f8; F1Assemble `733256008ab0dd81...`.
5. `SR0A_BUILD_ROOT=<scratch> SR0A_OUT_ROOT=<scratch> python3 -I qualification/run.py run --stages compare --win-candidate-dir probes/sr0-o/f1-cross/cross`.

## R8 settled (11 October 2026): F9 late results after close

Probe `F9-keepalive` (`R8-PROBE.md`): a Mac fixture variant (`--variant keepalive`, off by default) stays alive after its last window closes and receives the same late releases; the cross config has no `ignoreEffectsInSteps` and no P6 allowance. Three Mac recordings (signed recorder `5f1ac0c7…`) and three Windows recordings on tuple 11 (FreshOnBridge `07351314…`). Result: **0 diffs in `effects` in all three pairs**: on both platforms every late result is rejected with `reason=window-closed` and then cleaned up (Mac: 11 rejections per run, `mac-ev-n*.jsonl`), and the model is unchanged. The 54 remaining diffs per pair are not about late results: 51 AX structure diffs (order, parent, presence: this probe's adapt file does not carry the wrapper adaptations the F9 config has), 2 `steps.nativeMapping` (N1), 1 `treeReleased` (P6, the tree release the F9 config allows). R8 is therefore settled: the `ignoreEffectsInSteps` in the F9 config hid no difference. Evidence: `cross-evidence/F9-keepalive/`.
