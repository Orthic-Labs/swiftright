# SR0 slice contract v1.0: freeze proposal

**PROPOSAL, not frozen. Updated 10 Oct 2026 against HEAD `d4d2ca4`; the freeze terms below are bound to tuple 08, the final snapshot tuple (`docs/sr0-snapshot.md` section 2d; section 2c, tuple 06, is superseded).** Compiled from repository evidence only; each claim cites a path or commit. Contract under review: `conformance/sr0-slice/CONTRACT.md`, which is still DRAFT v0.1 (C1-C8 are not applied to it; applying them and bumping to v1.0 is lane R11 and is PENDING). Freeze rule from the CONTRACT header: after freeze, changes need a documented revision and a rerun of both seeds (architecture §11); the fork seed is early-disqualified (`probes/sr0-s/COMPARISON.md`), so a rerun means the fresh runtime.

**Contract on disk is stale (G21):** `conformance/sr0-slice/CONTRACT.md` is still DRAFT v0.1 and its F6 text is superseded by the proposed change C6 in section 3. Read this file together with that contract, not the contract alone.

**Final tuple, tuple 08 (what v1.0 is proposed to freeze on; `docs/sr0-snapshot.md:83`):** renderer DLL `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93` (ABI 0.6; built from `9c261d4` on top of `02b3cc0`, no ABI change), runtime `b8702bb`, fixture host FreshOnBridge `7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960` (from `c0fc401`), BridgeSmoke `21992F16954E92449F467BD137C3DEE9F0812377E9122179A10E4F3B981DF1A5`, WorkloadWin `0815DF499371CEDE032758B00A6B254726DD524B9A0930C2D96B57089A74070F`, SliceApp MSIX 0.1.0.0 `c80c6947…` / 0.1.1.0 `0ff65165…` (`examples/SliceApp/RESULT-R5-08.md:12`), `@rightkit/release` 0.2.146. Tuples 06 (`7533963D`, `AA4353CE`) and 07 (`97CA28E8`) are history. The renderer changed after the 0.6 header (`862997c`) with no ABI change: header untouched, startup validation `abi 0.6 fn_count=16 stats_size=200` on the final DLL.

**Status: NOT FROZEN.** Bridge, matrix, text-geometry, modal, native-interaction, runner and Windows package receipts exist on tuple 08 (section 1: WIN-M9, SMOKE, NATIVE, PKG, RUNNER). The freeze is withheld until the remaining user-dependent items close or are accepted as limitations (section 6): R6 Mac oracle (Mac free about 10 min), Narrator listen (about 2 min), the R10 overlay-off run, and the decision to accept W08 and W5 as known limitations. Sections below keep the reconciliation text for clauses not touched since; section 1 and the tables in sections 3, 4 and 5 are updated.

## 1. Evidence base

| Label | Evidence | State |
|---|---|---|
| MAC-20 | `probes/sr0-o/fixtures/REPEAT20.md` (commit 4ff202f): 17 configs x 20 runs, all PASS, 1 canonical trace each, 0 relaunches | complete |
| MAC-3 | `probes/sr0-o/fixtures/RESULT.md`: per-fixture 3-run matrix, F3 container table, findings | complete |
| HL | `probes/sr0-s/fresh-runtime/RESULT.md` (commit 000679e): headless `swift test` 46/46 on macOS 27 arm64 and 46/46 on Windows 11 x64 (lines 344-345) | complete |
| WIN-F1 | `probes/sr0-s/fresh-on-bridge/RESULT.md`: F1 self-test 15/15 on real renderer (ABI v0, Windows) | complete, historical |
| WIN-M1 | `probes/sr0-s/fresh-on-bridge/out/matrix` (commit 4112d8c): F1 15/15, F2 11/11, 7 configs pass (per `out/matrix-rev2/RESULT.md`) | superseded |
| WIN-M2 | `probes/sr0-s/fresh-on-bridge/out/matrix-rev2/RESULT.md` (commit 2aa1983): 15 configs x 3, **all FAIL** (regression). Fixed in cc605bf (no post-close teardown commit; List AX roles) and 8f3ffeb (F9 asserts on ABI 0.5) | recorded regression |
| WIN-M3 | `probes/sr0-s/fresh-on-bridge/out/matrix-rev3/` (commit 96fcd30): partial, superseded by WIN-M4 | superseded |
| WIN-M4 | `probes/sr0-s/fresh-on-bridge/out/matrix-rev4/RESULT.md` (cc4c93a, ee5a4db): 44/45 PASS, F9 run3 failed (pump ended by renderer, GPUI quit-on-last-window); `matrix-rev4b` on renderer d45c98c (DLL sha256 2DC4B6F783EF7BC78163C3B02B6413CD4539CD0F9A0D64C92C0B4C0254EBF1E1): F9 3/3, F9-notasks 3/3, F6 override-on 3/3. **All 15 configs 3/3 PASS.** Root causes fixed: cc605bf, cc4c93a, d45c98c | complete (3 runs) |
| WIN-M5 | `probes/sr0-s/fresh-on-bridge/out/matrix-20b/` (`65e0f29`): 15 configs x 20 runs = **300/300 PASS**, ABI 0.5, FreshOnBridge sha256 `DD6C9CE6…`, DLL `2DC4B6F7…`; one run (F2 run9) needed a foreground retry. Earlier partial `matrix-20` (`3d2d57f`) exposed an F3 vstack settle race, fixed in the self-test. Lacks the F3 3 s variants (`list-3s`, `vstack-3s`, `lazy-3s`); real IME and screen reader not covered | complete on ABI 0.5; rerun on 0.6 plus F3 3 s (plan R1b) |
| XCMP | `probes/sr0-o/f1-cross/` (`7a91608`, `96fcd30`, `eaf40dc`): F1 Mac-vs-Windows compare, 317 diffs -> 52 (List AX roles) -> **0 diffs** for Windows w6 vs Mac m1..m5 (`eaf40dc`). Only F1 was compared; Mac side used the unsigned-grant terminal route. Signed recorder (`F1MacRecord.app`, `7a91608`) still needs Adrian's AX grant | PASS for F1 on ABI 0.5; F1-F9 on the signed recorder and ABI 0.6 PENDING (plan R6) |
| WIN-M6 | `probes/sr0-s/fresh-on-bridge/out/matrix-abi06c/RESULT.md` (`69ad73b`, `73fd9a6`): ABI 0.6, 15 configs incl. F3 3 s variants x 20 runs: **316/320 first time** (3 infrastructure: two scheduled tasks ended 0xC000013A while the Dell was busy, one task vanished with foreground taken; 1 driver UIA lookup race, F8 r9), reruns 12/12 on a quiet Dell. Fixture `3593209A…D68BA`, renderer `777F14C4…` (now superseded) | complete on the old 0.6 renderer; history for the final tuple |
| WIN-M7 | `probes/sr0-s/fresh-on-bridge/out/matrix-abi06f/` (`c31f1b5`): renderer `4FB068F0…`, fixture `30FBE599…`: F1-F7, F9 20/20; **F8 0/20** (fixture defect: AX button focus logged as a `focus` event masked the row-focus check; now `ax-button-focus`) | history (fixture repaired) |
| WIN-M8 | `probes/sr0-s/fresh-on-bridge/out/matrix-abi06g/RESULT.md` (`a6fdcad`): renderer `4FB068F0…`, fixture `AFE131A1…`: **318/320 first time**, 16 configs; both misses infrastructure (F3 lazy-1s r3: scheduled task removed by another process; F7 r15: no output), reruns 6/6 (3 each); F8 20/20 | history (renderer superseded) |
| WIN-M9 | `probes/sr0-s/fresh-on-bridge/out/matrix-08/RESULT.md:7` (tuple 08, fixture `7673A2D5…`, renderer `E280F4A9…`, runtime `b8702bb`): **319/320 PASS**, 16 configs x 20, every run ARTIFACT_OK; the one failure (F3 list-0s r16) is external typed input ("and the " reached the row), rerun of the config 3/3 PASS; 3 foreground-loss harness retries passed on attempt 2; run under normal host use. Tuple 06 `matrix-final` 320/320 (`5a67f23`) is history | **complete on tuple 08** |
| SMOKE | `examples/BridgeSmoke/result-smoke-rev08.txt:83` (40/40) and `result-smoke-timeout08.txt:84` (41/41): exe `21992F16…`, renderer `E280F4A9…`; plus text geometry `examples/BridgeGeoModal/result-textgeom08.txt:93` (20/20) and real modal paths `result-modal08.txt:268` (20/20, 0 stalls in 120 modals) with A/B proofs `result-modalfix-*.txt`, `result-textgeom-axfix.txt`; earlier smokes (tuple 06 `541129c`, rev06c `777F14C4`, rev06f `4FB068F0`) are history | complete on tuple 08 |
| NATIVE | Tuple 08 (`840f9ec`): `probes/sr0-b/native-interaction/out/native-ime-{f7,f7live,f8}-tuple08.txt`, `native-narrator-tuple08.txt`; renderer `E280F4A9…`, fixture `7673A2D5…`: real Microsoft Japanese IME **F7 20/20, F7live 20/21, F8 18/19** (the single failing check in F7live and F8 is `candidate-window-follows-layout-move`); Narrator **8/8 automatable PASS** (reaches and activates Delete, model updated, state restored), 2 not automatable. Earlier final run on `4FB068F0…` / `30FBE599…` (`probes/sr0-b/native-interaction/out/RESULT.md`, `050d28e`, `277b92d`): F7 20/20, F7live 20/20, F8 18/19 | complete except the limitation in section 6 and Narrator speech (audio, PENDING Adrian about 2 min) |
| PKG | `examples/SliceApp/RESULT-R5-08.md` (`d4d2ca4`): MSIX 0.1.0.0 `c80c6947…` / 0.1.1.0 `0ff65165…` on renderer pin `E280F4A9`, signed, swift-only proof ok, Windows Sandbox offline **13/14** (W08 FAIL), network W00/W01/W12 PASS; tuple 06 pair `4cc9a7f0…` / `c2897a68…` (`RESULT-R5.md`, 14/15) is history; `examples/SliceApp/RESULT-R2.md` (`b476c85`, old pair on `777F14C4`, history); `examples/SliceApp/PACKAGING.md` R3 (`1aee425`, `f02244c`, `ea879dc`: DMG signed, notarized, stapled, history); R3 final DMG `b976ac70…` and 0.1.1 `75f3cd75…` on 0.2.144: PASS (repo records `examples/SliceApp/r3-final/`, `r3-final-011/`; Mac packages carry no renderer, unchanged on tuple 08); `examples/SliceApp/RESULT-R7.md` (`c7ddb7d`, `94b81ac`: Mac VM install/upgrade/rollback/corrupt/uninstall PASS, Gatekeeper baseline PASS, atomic-swap `--recover` PASS on 0.2.142) | partial: R5 W08 FAIL (known limitation candidate, section 6); R7 quarantined launch on the stapled `.app` PASS 10/10 (`2403117`, `RESULT-R7.md`) |
| WORKLOAD | `probes/sr0-b/workload/results/r10-20261010-tuple08-renderere280-windows.txt` (tuple 08, WorkloadWin `0815DF49…`): all thresholds pass except **W5 zero missed vblanks** (5, 1, 1 in r1-r3, lines 40, 79, 118; `OVERALL: FAIL` line 285); leak slope 3.21-4.42 MB/min PASS (limit 5.0); history `ITERATION.md`, `edb1784` to `33987c2` | NOT MET (W5); overlay-off run PENDING (Adrian) |
| RUNNER | `qualification/run.py`, `docs/qualification.md` (`1b7cdc1`, `2c8b765`): canonical form v2, strict runner, receipt schema v2; F6 shows 2 canonical results under v2 | hardened; full runner run on tuple 08 (win-replay, compare, smoke, package) committed in `qualification/out/r8-tuple08/` (see `docs/sr0-status.md`); mac-oracle part rides on R6 |
| SAME-SRC | `probes/sr0-c/same-source/RESULT.md` (cited by CONTRACT §8): identical screen compiles on both targets; `NavigationSplitView` negative fixture fails on Windows only | complete |

Windows 20-run requirement (CONTRACT §3 last paragraph): met on ABI 0.5 by WIN-M5 (300/300) and **met on the final ABI 0.6 tuple by WIN-M9 (320/320 first time, including the F3 3 s variants)**. C9 is decided (keep 20).

## 2. Clause-by-clause status

Legend: PROVEN = evidence on both sides as the clause requires; MAC = Mac oracle only; PENDING = named evidence missing.

### §1 Pinned tuple
- Pins Mac mini macOS 27.0.1, Xcode 27.0, Swift 6.4; Windows XPS 15 build 26300 x64, Swift 6.4 (swift-6.4-RELEASE); renderer gpui 0.2.2 / accesskit 0.25.1 / accesskit_windows 0.35.1; dispatch ordinal 23.
- Evidence: MAC-3/MAC-20 ran on macOS 27.0.1 arm64 Swift 6.4; HL and WIN-* on Windows 11 x64 Swift 6.4.0; renderer pins mirrored in `render/README-abi-v0.md`.
- Windows arm64 and Intel Mac are out of scope under scope revision 1 (`docs/architecture.md` §9), not pending. Status: **PROVEN for Windows x64 and Mac arm64 on the evidence above; to be re-pinned to the 0.6 snapshot.**

### §2 Slice inventory
- Same-source compile: SAME-SRC PASS on both targets.
- Runtime implementation of the inventory: HL 46/46 both OSes.
- Negative fixtures (`.onReceive`, `ObservableObject`/`@StateObject`, `NavigationSplitView`, `Timer.publish`): all four fail Windows compilation with a diagnostic, as CONTRACT §2 requires (`probes/sr0-c/same-source`, `probes/sr0-c/negative-fixtures/RESULT.md`, commit 5afd873). **MET.** Note: on macOS `.onReceive` and `ObservableObject` also fail against the slice, but `Timer.publish` compiles (Foundation on Darwin provides it), so the slice cannot reject it on Mac by compilation alone.
- `ForEach($items) { $item in }`: `probes/sr0-c/same-source/RESULT.md` records the `$`-projected closure parameter fails on Windows (cited in `probes/sr0-o/fixtures/RESULT.md` finding 2). Fixtures use `ForEach($model.rows, id: \.id) { row in }`. See change C3.

### §3 Fixtures F1-F9

| Fixture | Mac oracle | Fresh runtime headless | Fresh runtime on real Windows bridge |
|---|---|---|---|
| F1 | MAC-20 20/20, 1 canonical | HL PASS | WIN-M4 3/3 PASS; WIN-M2 FAIL (row5-not-torn-down, caret=nil) fixed since |
| F2 | MAC-20 20/20 | HL PASS | WIN-M4 3/3 PASS; WIN-M2 FAIL (no-teardown-on-move) |
| F3 list/vstack/lazy | MAC-20 8 configs 20/20 each; reinsert-state outcome per container in MAC-3 table | HL PASS (F3 aligned to List retention, `fresh-runtime/RESULT.md` line 282) | WIN-M4 3/3 PASS (all F3 configs, 15/15 total matrix) |
| F4 | MAC-20 20/20 | HL PASS | WIN-M4 3/3 PASS |
| F5 | MAC-20 20/20; zero-width pass logged as OBSERVE | HL covers layout engine (`fresh-runtime/RESULT.md`, line 171 section) | WIN-M4 3/3 PASS |
| F6, F6-reduced | MAC-20 20/20 each; raw traces vary (4 distinct for F6), canonical 1 under v1 (2 under canonical v2, `docs/qualification.md:130`; R6 A/B swaps 4 of 100, `probes/sr0-o/R6-RESULT.md`) | HL animation tests (commit 000679e `AnimationTests.swift`) | WIN-M4 3/3 PASS (incl. F6 override-on, rev4b) |
| F7 | MAC-20 20/20 (bounded I/O only) | HL TextInput/IME tests (000679e) | WIN-M2 FAIL (no-teardown); WIN-M4 3/3 PASS; WIN-M6 20/20 on 0.6 (old renderer); WIN-M9 20/20 on the final tuple; NATIVE real IME F7 20/20, F7live 20/21 (limitation, section 6) |
| F8 | MAC-20 20/20 | HL PASS | WIN-M2 FAIL (toolbar-task-restarts-per-request); WIN-M4 3/3 PASS |
| F9 | MAC-20 20/20 with `tree-released` as OBSERVE only | HL teardown coverage (000679e) | WIN-M2 3 BLOCKED (no post-close pump, no live-node counter in ABI 0.4); ABI 0.5 supplies both; WIN-M4 3/3 PASS (F9 and F9-notasks, rev4b) |

Mac F3 outcome (MAC-3): `List` preserves reinserted `@State` (0/1/3 s gaps, focused after reinsert); `VStack`+`ForEach` and `LazyVStack` reset it (1/3 s, not focused). Deterministic. In MAC-20, `reinsert-focus` is stable across runs per config (1 distinct value), but `reinsert-local-state` shows 9-20 distinct values per config, which are the per-run local counters, not the preserved/fresh outcome; the contract wording is "follows the container's recorded Mac outcome".

Run-count rule: "Each Mac fixture runs 20 times; all normalized assertions must agree": **PROVEN** (MAC-20, canonical distinct = 1 everywhere; F6 and lazy F3 have raw variance, recorded and absorbed by the within-step order-insensitivity rule). "Each Windows seed runs 20 times": **PROVEN on the final tuple** (WIN-M9, 320/320; C9 decided).

### §4 Stimuli and native mappings
- Mac: stimuli posted via `CGEvent.postToPid` (CONTRACT §5 rules); used by all MAC-20 runs.
- Windows: Ctrl mappings and virtual-key SendInput implemented in `probes/sr0-o/uia-recorder/` (RESULT.md "Stimuli" section); IME composition uses virtual keys, not Unicode packets (`docs/sr0-status.md` host facts).
- Microsoft Japanese IME romaji composition end-to-end on the bridge: evidenced by NATIVE (F7 20/20, F7live 20/21, F8 18/19) on tuple 08. Known limitation, deferred to SR1: when layout moves the composing field while the candidate list is open, the renderer re-places the IME windows (`ime_replace reason=layout`) but Windows 11's modern IME does not move the open list; a TSF text store (`ITfContextView::GetTextExt`) is the likely fix. The contract does not require candidate-list tracking across layout moves.
- Injected fake engine and clock: used by all fixtures (`probes/sr0-o/fixtures/Sources/SliceFixtures/Common/`). PROVEN.

### §5 Observation routes
- Model/lifecycle/effects in-process: PROVEN (MAC-20 EventLog).
- Mac AX tree/identifier/press/focus/selection/bounds: PROVEN (`probes/sr0-o/ax-routes`, CONTRACT §5 evidence paragraph). Signed recorder with its own AX grant: still needed (`docs/sr0-status.md` SR0-O row; plan R6, separate macOS test user) -> **PENDING**.
- Windows UIA tree and Invoke: PROVEN (`probes/sr0-d/render-composition`; recorder `probes/sr0-o/uia-recorder`). Automation-id on the bridge: ABI 0.5 smoke rev05c shows 5/5 (`examples/BridgeSmoke/result-smoke-rev05c.txt`): **PROVEN**.
- Windows TextPattern: empty-edit TextPattern PASS in smoke (`examples/BridgeSmoke/result-smoke-rev05.txt`, `empty_edit_textpattern=PASS`). Populated-field selection and caret rect: **MET** (text geometry run 4, 35/35, degenerate caret via raw UIA, `fcc999d`; probe-tree bridge, rerun on 0.6 per snapshot item 6).
- Canonical roles window, button, text-field, list, list-item, static-text: Mac normalizer rules in CONTRACT §5; Windows roles in ABI `SWR_ROLE_*`; List/list-item emission added in cc605bf. Cross-platform shape match: XCMP 0 diffs for F1 (`eaf40dc`); F2-F9 never compared cross-platform: **PENDING** (R6).
- Visible-response endpoint per OS: **DECIDED** 9 Oct 2026 and recorded in CONTRACT §5. Implementation and measurement run in the §11 workload lane (R10).

### §6 Bridge ABI vocabulary
Governed by the companion proposal `docs/sr0-freeze-bridge-interface.md`. Contract-side change C4 below.

### §7 Budgets
- Presentation budget revision 1 (zero missed vblanks, p95 <= refresh + 0.1 ms): MET with the standalone probe host, batch 5, 30/30 valid runs (commit 011c83e). **The §11 full workload on the selected runtime has now run on Windows (lane R10, WORKLOAD in section 1): p95 <= refresh + 0.1 ms passes (16.73 ms in the final-source runs), zero missed vblanks does NOT (1-8 per 60 s run in undisturbed runs, median 2; GPU render-complete bursts on a hybrid-GPU laptop with the NVIDIA overlay loaded).** The other §11 thresholds pass; the leak slope passes after `33987c2`. PENDING: one run with the overlay off (Adrian); Mac windowed workload result (not committed).

### §8 Open before freeze
- Same-source compile: closed (SAME-SRC).
- TextPattern on populated Windows edit nodes: closed (`fcc999d`). Mac AX caret route: proven (`probes/sr0-o/ax-routes`).
- Visible-response endpoint: decided (CONTRACT §5).
- Closed since: real Japanese IME and Narrator automatable checks on tuple 08 (R9, NATIVE); matrix on tuple 08 (WIN-M9); BridgeSmoke, text geometry and modal paths on the final renderer (SMOKE). Still open (user-dependent): Narrator speech content (listen, about 2 min); §11 W5 (R10, overlay-off run); Mac oracle re-record and cross-compare (R6, Mac free about 10 min); the decision to accept W08 and W5 as known limitations.

## 3. Proposed changes versus the current contract (v0.1 -> v1.0)

| # | Change | Basis |
|---|---|---|
| C1 | **F9 tree release**: state explicitly that tree release after close is a Windows runtime requirement asserted on the bridge via `swr_stats.live_nodes == 0` after close and `swr_shutdown_complete`; on Mac it is OBSERVE only. | CONTRACT §3 F9 row already says this in prose; MAC-3 finding 4 (AppKit keeps closed `NSWindow` alive, `isReleasedWhenClosed=false`); MAC-20 F9 `tree-released` OBSERVE-only; ABI 0.5 `live_nodes` (10c4877) |
| C2 | **F3 outcome table into the contract text**: record List = preserved, VStack/LazyVStack = fresh with focus outcomes, as the normative Mac oracle (currently only a summary sentence). | MAC-3 F3 table; MAC-20 F3 rows |
| C3 | **Binding-projection form**: replace `ForEach($items) { $item in }` in the §2 inventory with the form actually supported and tested: `ForEach($rows, id: \.id) { row in }` with a `Binding<Row>` parameter, or record `$item in` as an unsupported Windows form. | `probes/sr0-c/same-source/RESULT.md`; `probes/sr0-o/fixtures/RESULT.md` finding 2 |
| C4 | **§6 cache key**: state that text colour is part of the measure cache key (colour baked into shaped runs). | `render/README-abi-v0.md` "Deferred" bullet ("CONTRACT section 6's key omits it"); CONTRACT §6 line already carries a parenthetical, convert to normative |
| C5 | **F9 Windows teardown protocol**: no teardown commit after `window_closed` (rejected with `SWR_E_SHUTDOWN`); cleanup observed in the post-close pump; assertions read evidence as of close. | WIN-M2 common failure; commit cc605bf; `render/README-abi-v0.md` rev 0.5 (b) |
| C6 | **F6 raw-trace variance**: add a sentence that raw traces may vary within a step; canonical order-insensitive comparison is the qualification form. | MAC-3 finding F6; MAC-20 (F6 raw 4, canonical 1); CONTRACT §3 already has the within-step rule, make F6's variance explicit. Status note (G13): Windows F6 3/3 PASS in WIN-M4 (rev4b) predates the canonical v2 per-node order check, and the Mac F6 canonical count is 2 under v2 (`docs/qualification.md:130`); the A/B completion decision is `docs/sr0-findings.md` L16 and T11 |
| C7 | **F5 harness rule**: window frame restoration cleared before launch; zero-width passes reported as OBSERVE not assertion failures. | MAC-3 F5 root cause; MAC-20 `zero-width-placement-passes` |
| C8 | **Fixture CLI rule** (harness, not semantic): `--self-test` last in argv. | MAC-3 diagnosis |
| C9 | Windows repeat count: **decided, keep 20** (met on ABI 0.5 by WIN-M5; rerun on 0.6). | §3 last paragraph; WIN-M5 |

None of C1-C8 changes a pass/fail semantic that the Mac oracle recorded; C3 changes contract text and requires a decision; C9 is decided (no text change).

## 4. Remaining freeze blockers (close plan v2)

Closed: WIN-M4 15 configs x 3 (`ee5a4db`); Windows repeat count on ABI 0.5 (matrix-20b, `65e0f29`) and on the final ABI 0.6 tuple (WIN-M9, `5a67f23`); BridgeSmoke 40/40 and 41/41 on the final renderer (`541129c`); XCMP F1 compare, 0 diffs (`eaf40dc`); negative fixtures (`5afd873`); Windows TextPattern on populated nodes (`fcc999d`); UIA AutomationId 5/5 (rev05c, repeated in the 0.6 smokes); visible-response endpoint decided (CONTRACT §5); real IME and Narrator automatable checks (NATIVE, `541129c`); signed MSIX on the final renderer pin and the final Mac DMG (PKG).

Open, in plan lane order:

| # | Blocker | Lane | State |
|---|---|---|---|
| 1 | Windows matrix on the final tuple, 20 runs per config incl. F3 3 s | R1b | **CLOSED**: WIN-M9 matrix-08 319/320 plus rerun 3/3 (tuple 08) |
| 2 | Signed Mac recorder with its own AX grant; re-record F1-F9 and compare cross-platform on the final tuple; 100-run F6 sample | R6 | PENDING (user-dependent): Mac free about 10 min. The signed recorder exists (`7a91608`); the AX grant was reported done by the lead (no committed record) |
| 3 | Per-node-ordered canonical digest (plan F4), fault-injection test, recompute baselines | R8 | Code and offline recompute committed (`1b7cdc1`, `2c8b765`; 15 of 16 configs single result). Runner run on tuple 08 (win-replay, compare, smoke, package) done: `qualification/out/r8-tuple08/`; mac-oracle stage PENDING (needs the Mac free, with R6). F6 A/B completion order decision open (2 canonical results, 1 of 20 Mac runs) |
| 4 | Real IME and Narrator/NVDA with model-state effects | R9 | DONE for automatable checks on tuple 08 (`840f9ec`); Narrator speech PENDING (listen, about 2 min); candidate-list-on-layout-move recorded as an SR1 limitation (section 6) |
| 5 | §11 workload: 200 rows, 10 s warm-up, 3 x 60 s, all thresholds, both OSes | R10 | Windows run on tuple 08, NOT MET: W5 zero missed vblanks fails (5, 1, 1 per run); PENDING one run with the NVIDIA overlay off (Adrian) and a Mac windowed result (it6-it8 files are committed, `00e7b3e`) |
| 6 | Apply C1-C8 and C3 text to CONTRACT.md; bump to v1.0; name the snapshot tuple | R11 | PENDING (blockers 2, 3, 5 and 7 decided) |
| 7 | Package qualification on the final tuple | R2, R3, R5, R7 | MSIX pair on renderer pin `E280F4A9` built and signed; Sandbox offline 13/14 with **W08 FAIL** (MSIX update cancelled in the registration phase leaves `NeedsRemediation`; no manual Repair during a 10-min hold, platform `RegisterByPackageFullName` at hold end, `RESULT-R5-08.md:32-34`; RightKit documented the recovery, `@rightkit/release` README `e93ac2df`); R3 final DMG PASS (repo record committed); R7 quarantined launch PASS 10/10 |

Non-blocking: Windows arm64 and Intel Mac are out of scope (scope revision 1), not exclusions to be lifted by this freeze.

## 5. Proposed freeze decision

Freeze as v1.0 on tuple 08 (`docs/sr0-snapshot.md` section 2d: runtime `b8702bb`, ABI 0.6 header `862997c`, bridge package `33987c2`, renderer DLL sha256 `E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93`, fixture host `7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960`, BridgeSmoke `21992F16954E92449F467BD137C3DEE9F0812377E9122179A10E4F3B981DF1A5`) when blockers 2, 3, 5 and 7 are closed or accepted as limitations (section 6) and C1-C8 plus C3 are applied to `CONTRACT.md`. The 0.5 renderer hash `2DC4B6F7…` and the intermediate 0.6 renderers `777F14C4…` and `4FB068F0…` named in earlier drafts are superseded. Seed decision: fresh runtime selected, fork early-disqualified and never run through the real backend (`probes/sr0-s/COMPARISON.md`). After freeze any change triggers a rerun of the fresh runtime's affected stages.

## 6. Known limitations to list in the frozen contract

Each is recorded, not hidden; the contract text does not require the behaviour named.

1. **IME candidate list under a mid-composition layout move (SR1, TSF).** F7live 20/21 and F8 18/19 each fail only `candidate-window-follows-layout-move`: the renderer re-places the IME windows (`ime_replace reason=layout`) but Windows 11's modern IME does not move the already-open list; a TSF text store (`ITfContextView::GetTextExt`) is the likely fix (`probes/sr0-b/native-interaction/out/native-ime-f8-tuple08.txt`; `RESULT.md` in the same directory).
2. **Narrator speech** is audio only: content and Narrator-start attribution are not machine-verifiable (2 not automatable in `native-narrator-tuple08.txt`); a person listening, about 2 min: PENDING.
3. **W5 zero missed vblanks** is not met on the Dell hybrid-GPU laptop under normal host use: 1-6 missed vblanks per 60 s run (tuple 08: 5, 1, 1, `r10-20261010-tuple08-renderere280-windows.txt:40,79,118`; `33987c2`; `ITERATION.md`), PENDING one run with the NVIDIA overlay off. All other R10 thresholds pass.
4. **F6 on the Mac oracle:** under canonical v2 the interrupted-animation completion order A/B differs in 1 of 20 saved runs; the R6 100-run sample ran and failed the runner verdict (4 of 100 B-first, `probes/sr0-o/R6-RESULT.md`); the permitted-ordering decision is `docs/sr0-findings.md` L16 and T11 (`docs/qualification.md`; close plan F10).
5. **R5 W08:** an MSIX update cancelled about 240 ms after staging leaves the old package `Modified, NeedsRemediation` until the update is re-applied; data intact (`examples/SliceApp/RESULT-R5-08.md:28-34`; tuple 08 Sandbox, 6 genuine interruptions, 2 left `NeedsRemediation`). Platform behaviour; RightKit documented the recovery (`@rightkit/release` README, `e93ac2df`; recovery probe `80a9b45`): only re-applying the update recovers, data kept. Accept-as-limitation decision PENDING.
6. **RightKit `install-app` swap window:** SIGKILL between the two renames leaves the install path absent until `install-app --recover` (`examples/SliceApp/RESULT-R7.md`).
7. **App Installer production host and TLS chain** has not been tested (W12 used a guest-local self-signed feed); **hardware-GPU rendering in the Sandbox guest** not covered (`<vGPU>Disable</vGPU>`) (`RESULT-R5.md`).
8. **Cold first dialog open** can exceed the 50 ms `modal_open_one_off` bound: 60.90 ms once in tuple 07 (`examples/BridgeGeoModal/result-modal07.txt:4`, run 01, cold first open); tuple 08 maxima 29.30-39.59 ms across 20 runs (`result-modal08.txt:262`). Underline and image painting are accepted by the renderer but not asserted (no per-primitive draw counter).
9. **Renderer knobs outside the ABI:** the environment variables `SWR_PAINT_PHASE_MS`, `SWR_AX_MIN_MS`, `SWR_AX_OFF`, `SWR_FRAME_LOG`, `SWR_MEM_DEEP` (`render/README-abi-v0.md`, `173ac08`) tune and diagnose the renderer and are proposed as not part of the frozen surface.
10. The Windows evidence is from one machine (Dell XPS 15 9530, Windows NT 10.0.26300 for the matrix and workload; the Sandbox guest is Windows 11 24H2 build 26100 per `RESULT-R5.md`).
