# CROSS-ALL: Mac SwiftUI vs Windows fresh runtime, schema-v0 cross-compare of all 16 configs (T1)

10 Oct 2026, repo HEAD cfca6d6 plus the uncommitted T1 changes. Mac: macOS 27.0.1 (26A434) arm64, Swift 6.4. Windows: Dell, tuple 08 FreshOnBridge `7673A2D5139172D8...` with renderer `E280F4A9FD9ECA0A...` (all 48 Windows runs record both hashes in `cross-evidence/<config>/win-run-w*.log`), UIARecorder `D255A25579C37751...` built on the Dell from `uia-recorder/`.

## Result

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
| R1 | Mac reported the selection of a focused element without an `AXIdentifier` (AppKit field editor / first responder), Windows reports none | F3-vstack, F3-lazy, F5 | `F1Assemble`: selection belongs to the focused canonical node |
| R2 | Effect order across nodes: sibling `.task` start order over 10 rows and the engine's release order are scheduler order; the comparator compares `effects` as an ordered list | F4, F3-vstack, F3-lazy, F5 | `F1Assemble` canonicalizes like digest v2: between two driver operations lines are grouped by node, per-node order kept |
| R3 | `AXOpaqueProviderGroup`, the AX wrapper SwiftUI adds around LazyVStack content, was not a named stripped container (123 diffs) | F3-lazy x2 | added to the stripped Mac containers (adaptation A10); CONTRACT §5 list should name it |
| R4 | `AXZoomButton` window chrome (resizable window) was not in the dropped chrome subroles | F5 | added to A4 |
| R5 | Initial window size differs (Mac 480x560, Windows exe 640x480), so the first layout mode differed; the mode also flickers while a window settles | F5 | both platforms resize to 720x560 in `initial`; only the mode a step ends in is compared |
| R6 | Mac typed the IME stimulus as two commits (`n`, `a`), the Windows runtime commits `na` once (`onChange` count 2 vs 1) | F7 | new op `typeChunk`: one key event carrying `na` (single commit). Composition mid-state is not comparable on Mac (CONTRACT §5) |
| R7 | Mac `AXValue` writes are ignored by SwiftUI `TextField` (probed: model unchanged with AXValue, AXValue+AXConfirm, or focus first), so the "set value" step never reached the model | F8 | new op `replaceText`: AXSelectedTextRange=all, then AXSelectedText (reaches the model, `local-edit` fires) |
| R8 | Interactive Mac fixture exits when its last window closes, so late engine releases (Windows script releases after close) cannot exist | F9 | stimulus `ignoreEffectsInSteps: ["close_window"]`; Windows self-test asserts the late-result rejection itself |
| R9 | AppKit restores the previous window frame from the app defaults | F5 | `F1MacRecord` clears `NSWindow Frame *` before launch |
| R10 | The Mac AX tree was read once; a re-walk until two consecutive trees agree (bounded 6 s) is used, duplicates stay visible if they persist | all | `F1MacRecord` settle loop |
| R11 | Assembler mapped any Windows `start` lifecycle event (the self-test's own) to an animation start | all Windows | mapping now requires node `animation` |

Windows side: typing is window-targeted `WM_CHAR` posted to the fixture HWND (`SR0O_KEY_DELIVERY=targeted`), resize is `MoveWindow` and close is `WM_CLOSE` on that HWND, activation is UIA Invoke, value is ValuePattern. No global input was sent.

### Contract-permitted (22 diffs, each a narrow Mac-to-Windows value mapping with a written reason in `cross/<config>/adapt-v0.json`)

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

Unit tests (`qualification/test_run.py`, 136 tests, all pass, 1 skipped: needs `SR0A_BUILD_ROOT`): fault injection alters a copy only, a comparator that passes the altered trace fails the control, every config has matching stimulus and step files, adaptations are reasoned value mappings (no `allowAnyValue` beyond N1), compare input resolution, per-config win-replay recording, and the F6 mirror below.

## F6 unordered completions (653b253)
`qualification/run.py` `canonical_body` now mirrors `normalize-hash.py f6_unordered_completions`. Tests: B-first completion passes, duplicate or missing or relocated completion fails, other fixtures untouched. Both candidate directories under `conformance/candidates/F6/` and `r6/f6/run{1,13,23,24,25}.jsonl` canonicalize to the accepted F6 digest, so mac-oracle F6 no longer reports 2 variants. The cross-compare itself never needs the order: lifecycle is compared as a multiset and all 6 cross runs completed `A,B`.

## Not proven / limits
- 3 runs per side per config, not 20.
- Mac baselines for F2-F9 are the first Mac recording (`cross/<config>/mac-trace-v0.json`, evidence of three equal runs in `cross-evidence/`). They are **not promoted**: `conformance/accepted/<config>/trace-v0.json` exists only for F1, and only `promote --approved-by` may write it. The runner prefers an accepted file and labels the fallback "unpromoted Mac cross recording". `sourceHash` is the hash of `stimulus.json`, so a changed stimulus invalidates its baselines.
- F7: Windows composition is driven in-process through the text-store API, Mac commits `na` with one key event; only the committed outcome, identity, focus and AX tree are compared, not the open marked-text state.
- F5 containment, paint, hit-test and AX bounds are not in schema v0 (frames excluded). F6 intermediate frames are not compared. F9 post-close late-result rejection is not compared (R8).
- Initial focus, the AX tree under List after moves, and focus after activation differ by platform (P1-P5); they are allowed only as the exact value pairs listed, never as `allowAnyValue`.
- The runner's `win-replay` per-config recording path (`win_cross_trace`) is unit-tested with a fake transport only. The 96 live recordings used `scripts/win-cross.sh`, which calls the same `schedule-cross.ps1`; the `win-replay` stage assembles with `F1Assemble` built from the committed tree, so it needs the T1 changes committed first.
- Comparator notes (not edited): `axNodes.duplicateId` reports a diff whenever either side has duplicate ids even when the two counts are equal; `declaredOrder` is read from the accepted side only.

## Dell protocol
Lock `D:\Claude\desktop.lock` taken as `T1 <timestamp>` and written `free` after each batch by `scripts/win-cross.sh` (waits in a background loop while another owner holds it; batches 15:30-15:35, 18:48-18:49, 18:49-18:57, 18:59-19:00 IST). Window-targeted input only. Nothing was deleted on the Dell: the temp archives of the file sync were left in `%TEMP%` (a copy of `scripts/sync-to-win.sh` without its cleanup was used), the first F5 attempt files were overwritten by the rerun with the same tags, and each run's one-shot scheduled task unregisters itself as in the existing `schedule-f1.ps1` pattern. No window titles are in the committed logs (the harness never reads them).

## Reproduce
1. Dell: sync `scripts/`, `cross/`, `uia-recorder/` to `D:\Claude\sr0o-f1` (sync without cleanup), run `scripts\build-rec.ps1`.
2. `python3 probes/sr0-o/f1-cross/scripts/gen-cross.py` regenerates `cross/` (stimulus, both step files, adaptations).
3. Windows: `FIRST=1 scripts/win-cross.sh <out> 3 <config>...`; assemble with `F1Assemble win --rec ... --side ... --events ... --stimulus cross/<config>/stimulus.json --keep-lists`.
4. Mac (signed recorder and fixture built under the scratch root, never run from /Volumes/D): `scripts/record-mac.sh <F1MacRecord> <FixtureApp> <F1Assemble> <out> <tag> <config>...`. Recorder: Developer ID, team 6KLGD3LLKF, identifier `com.orthiclabs.swiftright.f1macrecord`, executable sha256 `5f1ac0c75398a401...`; FixtureApp `123827e157aa9e70...` from tree 1b4affaf44f8; F1Assemble `733256008ab0dd81...`.
5. `SR0A_BUILD_ROOT=<scratch> SR0A_OUT_ROOT=<scratch> python3 -I qualification/run.py run --stages compare --win-candidate-dir probes/sr0-o/f1-cross/cross`.
