# SR0 slice contract v1.0: freeze proposal

**PROPOSAL, not frozen. Reconciled 9 Oct 2026 against HEAD `6263841` and `docs/sr0-close-plan.md` v2 (scope revision 1).** Compiled from repository evidence only; each claim cites a path or commit. Contract under review: `conformance/sr0-slice/CONTRACT.md` (DRAFT v0.1; SR0-C row in `docs/sr0-status.md`). Freeze rule from the CONTRACT header: after freeze, changes need a documented revision and a rerun of both seeds (architecture §11); the fork seed is early-disqualified (`probes/sr0-s/COMPARISON.md`), so a rerun means the fresh runtime. The freeze binds to the ABI 0.6 snapshot tuple in `docs/sr0-snapshot.md`; all Windows evidence below was produced on ABI 0.5 and is history until rerun on that tuple.

**Close-out update (9 Oct 2026 evening, HEAD `c31f1b5`): STILL NOT FROZEN.** Final tuple: renderer `4FB068F0B6C73DE9A5DDE1A536E97EEDD08E2FEA3C0DD8B92FC0E4A78E53298F`, fixture host `AFE131A1B75C70B0939CD2077C5A5E3E4788FA198E8739FC80EC48F0E8617B0F` (matrix-abi06g PENDING). Evidence added since the reconciliation: ABI 0.6 matrix 316/320 + 12/12 reruns on renderer `777F14C4` (WIN-M6), matrix-abi06f on the final renderer with an F8 fixture defect (WIN-M7), real Microsoft Japanese IME and Narrator (NATIVE), signed MSIX/DMG and clean-guest results (PKG). Open and PENDING: R1b on the final fixture (matrix-abi06g), R6 signed Mac recorder cross-compare (needs Adrian), R8 per-node digest and runner, R10 workload, R5 Windows Sandbox run, MSIX rebuild on the final renderer. Recorded limitations: IME candidate list under a mid-composition layout move (SR1, TSF); RightKit `install-app` swap gap (RightKit helper). Sections below keep the reconciliation text; the tables in sections 1, 2 (F7, §4 notes) and 4 are updated for the new evidence.

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
| WIN-M7 | `probes/sr0-s/fresh-on-bridge/out/matrix-abi06f/` (`c31f1b5`): final renderer `4FB068F0…`, fixture `30FBE599…`: F1-F7, F9 20/20 so far; **F8 0/20** (fixture defect: AX button focus logged as a `focus` event masked the row-focus check; now `ax-button-focus`). `matrix-abi06g` with fixture `AFE131A1…`: **PENDING** (uncommitted) | INCOMPLETE |
| NATIVE | `probes/sr0-b/native-interaction/out/RESULT.md` (`277b92d`, final run `050d28e`): real Microsoft Japanese IME F7 20/20, F7live (insert-above mid-composition, identity and composition survive) 20/20, F8 18/19; Narrator 8/8 automatable PASS (reaches and activates Delete, model updated, state restored). Renderer `4FB068F0…`, fixture `30FBE599…` | complete except the limitation below and Narrator speech (audio, PENDING Adrian about 2 min) |
| PKG | `examples/SliceApp/RESULT-R2.md` (`b476c85`: MSIX 0.1.0.0/0.1.1.0 signed, signtool OK), `examples/SliceApp/PACKAGING.md` R3 (`1aee425`, `f02244c`, `ea879dc`: DMG signed, notarized, stapled), `examples/SliceApp/RESULT-R7.md` (`c7ddb7d`, `94b81ac`: Mac VM install/upgrade/rollback/corrupt/uninstall PASS, Gatekeeper baseline PASS, atomic-swap `--recover` PASS on 0.2.142) | partial: MSIX not on the final renderer (rebuild PENDING), R5 Windows Sandbox run PENDING |
| SAME-SRC | `probes/sr0-c/same-source/RESULT.md` (cited by CONTRACT §8): identical screen compiles on both targets; `NavigationSplitView` negative fixture fails on Windows only | complete |

Windows 20-run requirement (CONTRACT §3 last paragraph): **met on ABI 0.5** by WIN-M5 (300/300), **not yet met on the ABI 0.6 tuple** and not met for the F3 3 s variants. C9 is decided (keep 20).

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
| F6, F6-reduced | MAC-20 20/20 each; raw traces vary (4 distinct for F6), canonical 1 | HL animation tests (commit 000679e `AnimationTests.swift`) | WIN-M4 3/3 PASS (incl. F6 override-on, rev4b) |
| F7 | MAC-20 20/20 (bounded I/O only) | HL TextInput/IME tests (000679e) | WIN-M2 FAIL (no-teardown); WIN-M4 3/3 PASS; WIN-M6 20/20 on 0.6 (old renderer); WIN-M7 20/20 on the final renderer (so far); NATIVE real IME F7 20/20, F7live 20/20 |
| F8 | MAC-20 20/20 | HL PASS | WIN-M2 FAIL (toolbar-task-restarts-per-request); WIN-M4 3/3 PASS |
| F9 | MAC-20 20/20 with `tree-released` as OBSERVE only | HL teardown coverage (000679e) | WIN-M2 3 BLOCKED (no post-close pump, no live-node counter in ABI 0.4); ABI 0.5 supplies both; WIN-M4 3/3 PASS (F9 and F9-notasks, rev4b) |

Mac F3 outcome (MAC-3): `List` preserves reinserted `@State` (0/1/3 s gaps, focused after reinsert); `VStack`+`ForEach` and `LazyVStack` reset it (1/3 s, not focused). Deterministic. In MAC-20, `reinsert-focus` is stable across runs per config (1 distinct value), but `reinsert-local-state` shows 9-20 distinct values per config, which are the per-run local counters, not the preserved/fresh outcome; the contract wording is "follows the container's recorded Mac outcome".

Run-count rule: "Each Mac fixture runs 20 times; all normalized assertions must agree": **PROVEN** (MAC-20, canonical distinct = 1 everywhere; F6 and lazy F3 have raw variance, recorded and absorbed by the within-step order-insensitivity rule). "Each Windows seed runs 20 times": **PENDING** (3 runs only; C9 OPEN).

### §4 Stimuli and native mappings
- Mac: stimuli posted via `CGEvent.postToPid` (CONTRACT §5 rules); used by all MAC-20 runs.
- Windows: Ctrl mappings and virtual-key SendInput implemented in `probes/sr0-o/uia-recorder/` (RESULT.md "Stimuli" section); IME composition uses virtual keys, not Unicode packets (`docs/sr0-status.md` host facts).
- Microsoft Japanese IME romaji composition end-to-end on the bridge: evidenced by NATIVE (F7 20/20, F7live 20/20, F8 18/19) on the final renderer. Known limitation, deferred to SR1: when layout moves the composing field while the candidate list is open, the renderer re-places the IME windows (`ime_replace reason=layout`) but Windows 11's modern IME does not move the open list; a TSF text store (`ITfContextView::GetTextExt`) is the likely fix. The contract does not require candidate-list tracking across layout moves.
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
- Presentation budget revision 1 (zero missed vblanks, p95 <= refresh + 0.1 ms): MET, batch 5, 30/30 valid runs (commit 011c83e; `docs/sr0-status.md` SR0-B row). **PROVEN** on the Windows lane tested with the standalone probe host; the §11 full workload on the selected runtime has never run (plan F7, lane R10).

### §8 Open before freeze
- Same-source compile: closed (SAME-SRC).
- TextPattern on populated Windows edit nodes: closed (`fcc999d`). Mac AX caret route: proven (`probes/sr0-o/ax-routes`).
- Visible-response endpoint: decided (CONTRACT §5).
- Closed since: real Japanese IME and Narrator automatable checks on the final renderer (R9, NATIVE). Still open and PENDING: Narrator speech content (Adrian listening, about 2 min); §11 workload (R10); signed recorder re-record and cross-compare (R6, needs Adrian); matrix on the final fixture (matrix-abi06g).

## 3. Proposed changes versus the current contract (v0.1 -> v1.0)

| # | Change | Basis |
|---|---|---|
| C1 | **F9 tree release**: state explicitly that tree release after close is a Windows runtime requirement asserted on the bridge via `swr_stats.live_nodes == 0` after close and `swr_shutdown_complete`; on Mac it is OBSERVE only. | CONTRACT §3 F9 row already says this in prose; MAC-3 finding 4 (AppKit keeps closed `NSWindow` alive, `isReleasedWhenClosed=false`); MAC-20 F9 `tree-released` OBSERVE-only; ABI 0.5 `live_nodes` (10c4877) |
| C2 | **F3 outcome table into the contract text**: record List = preserved, VStack/LazyVStack = fresh with focus outcomes, as the normative Mac oracle (currently only a summary sentence). | MAC-3 F3 table; MAC-20 F3 rows |
| C3 | **Binding-projection form**: replace `ForEach($items) { $item in }` in the §2 inventory with the form actually supported and tested: `ForEach($rows, id: \.id) { row in }` with a `Binding<Row>` parameter, or record `$item in` as an unsupported Windows form. | `probes/sr0-c/same-source/RESULT.md`; `probes/sr0-o/fixtures/RESULT.md` finding 2 |
| C4 | **§6 cache key**: state that text colour is part of the measure cache key (colour baked into shaped runs). | `render/README-abi-v0.md` "Deferred" bullet ("CONTRACT section 6's key omits it"); CONTRACT §6 line already carries a parenthetical, convert to normative |
| C5 | **F9 Windows teardown protocol**: no teardown commit after `window_closed` (rejected with `SWR_E_SHUTDOWN`); cleanup observed in the post-close pump; assertions read evidence as of close. | WIN-M2 common failure; commit cc605bf; `render/README-abi-v0.md` rev 0.5 (b) |
| C6 | **F6 raw-trace variance**: add a sentence that raw traces may vary within a step; canonical order-insensitive comparison is the qualification form. | MAC-3 finding F6; MAC-20 (F6 raw 4, canonical 1); CONTRACT §3 already has the within-step rule, make F6's variance explicit |
| C7 | **F5 harness rule**: window frame restoration cleared before launch; zero-width passes reported as OBSERVE not assertion failures. | MAC-3 F5 root cause; MAC-20 `zero-width-placement-passes` |
| C8 | **Fixture CLI rule** (harness, not semantic): `--self-test` last in argv. | MAC-3 diagnosis |
| C9 | Windows repeat count: **decided, keep 20** (met on ABI 0.5 by WIN-M5; rerun on 0.6). | §3 last paragraph; WIN-M5 |

None of C1-C8 changes a pass/fail semantic that the Mac oracle recorded; C3 changes contract text and requires a decision; C9 is decided (no text change).

## 4. Remaining freeze blockers (close plan v2)

Closed: WIN-M4 15 configs x 3 (`ee5a4db`); Windows repeat count on ABI 0.5 (matrix-20b, `65e0f29`); XCMP F1 compare, 0 diffs (`eaf40dc`); negative fixtures (`5afd873`); Windows TextPattern on populated nodes (`fcc999d`); UIA AutomationId 5/5 (rev05c); visible-response endpoint decided (CONTRACT §5).

Open, in plan lane order:

| # | Blocker | Lane | Needs |
|---|---|---|---|
| 1 | Re-run the Windows matrix on the 0.6 tuple, 20 runs per config, including the F3 3 s variants (plan F5) | R1b | PARTIAL: WIN-M6 316/320 + 12/12 on the old 0.6 renderer; final renderer: matrix-abi06g with fixture `AFE131A1…` PENDING (matrix-abi06f F8 fixture defect fixed in the rebuild) |
| 2 | Signed Mac recorder with its own AX grant; re-record F1-F9 and compare cross-platform on the 0.6 tuple | R6 | PENDING: Adrian, Mac free about 10 min for the oracle run with the signed recorder (Accessibility grant) |
| 3 | Per-node-ordered canonical digest (plan F4, CONTRACT §3 per-node order), fault-injection test, recompute accepted baselines and the 20-run results from saved JSONL | R8 | PENDING (no committed work) |
| 4 | Real IME (Microsoft Japanese) and Narrator/NVDA with model-state effects | R9 | DONE for automatable checks (NATIVE, `277b92d`); Narrator speech PENDING (Adrian, about 2 min); candidate-list-on-layout-move recorded as SR1 limitation |
| 5 | §11 workload: 200 rows, 10 s warm-up, 3 x 60 s, all thresholds, raw samples, both OSes | R10 | PENDING: probe and analyzer built (`4d69e55`), no result; quiet Dell and Mac test user |
| 6 | Apply C1-C8 and C3 text to CONTRACT.md; bump to v1.0; name the snapshot tuple | R11 | blockers 1-5 and 7; PENDING |
| 7 | Package qualification on the final tuple: MSIX rebuilt on the final renderer, R5 Windows Sandbox run (`examples/SliceApp/R5-RUNBOOK.md`) | R2, R5 | PENDING (R7 Mac VM results are committed; the install-app swap gap is a RightKit helper item) |

Non-blocking: Windows arm64 and Intel Mac are out of scope (scope revision 1), not exclusions to be lifted by this freeze.

## 5. Proposed freeze decision

Freeze as v1.0 when blockers 1-5 and 7 have receipts bound to one snapshot tuple (`docs/sr0-snapshot.md`: runtime commit, bridge/header commit, renderer DLL sha256 `4FB068F0B6C73DE9A5DDE1A536E97EEDD08E2FEA3C0DD8B92FC0E4A78E53298F` for ABI 0.6, fixture host `AFE131A1B75C70B0939CD2077C5A5E3E4788FA198E8739FC80EC48F0E8617B0F`, binary hashes) and C1-C8 plus C3 are applied. The 0.5 renderer hash `2DC4B6F7…` named in earlier drafts is superseded. Seed decision: fresh runtime selected, fork early-disqualified and never run through the real backend (`probes/sr0-s/COMPARISON.md`). After freeze any change triggers a rerun of the fresh runtime's affected stages.
