# SR0 slice contract v1.0: freeze proposal

**PROPOSAL — pending evidence noted inline.** Nothing here is frozen. Compiled 9 October 2026 from repository evidence only; each claim cites a path or commit. Contract under review: `conformance/sr0-slice/CONTRACT.md` (DRAFT v0.1; SR0-C row in `docs/sr0-status.md`). Freeze rule from CONTRACT header: after freeze, changes need a documented revision and a rerun of both seeds (architecture §11).

## 1. Evidence base

| Label | Evidence | State |
|---|---|---|
| MAC-20 | `probes/sr0-o/fixtures/REPEAT20.md` (commit 4ff202f): 17 configs x 20 runs, all PASS, 1 canonical trace each, 0 relaunches | complete |
| MAC-3 | `probes/sr0-o/fixtures/RESULT.md`: per-fixture 3-run matrix, F3 container table, findings | complete |
| HL | `probes/sr0-s/fresh-runtime/RESULT.md` (commit 000679e): headless `swift test` 46/46 on macOS 27 arm64 and 46/46 on Windows 11 x64 (lines 344-345) | complete |
| WIN-F1 | `probes/sr0-s/fresh-on-bridge/RESULT.md`: F1 self-test 15/15 on real renderer (ABI v0, Windows) | complete, historical |
| WIN-M1 | `probes/sr0-s/fresh-on-bridge/out/matrix` (commit 4112d8c): F1 15/15, F2 11/11, 7 configs pass (per `out/matrix-rev2/RESULT.md`) | superseded |
| WIN-M2 | `probes/sr0-s/fresh-on-bridge/out/matrix-rev2/RESULT.md` (commit 2aa1983): 15 configs x 3, **all FAIL** (regression). Fixed in cc605bf (no post-close teardown commit; List AX roles) and 8f3ffeb (F9 asserts on ABI 0.5) | recorded regression |
| WIN-M3 | `probes/sr0-s/fresh-on-bridge/out/matrix-rev3/` (untracked, no RESULT.md yet). Present on disk: F1 3/3 PASS (15/15 asserted), F2 3/3 PASS (11/11), F3 list-0s 3/3, list-1s 3/3, vstack-1s 3/3 (each 11/11), lazy-1s 1 run PASS. Absent: F3 lazy-1s r2-r3, lazy-3s, vstack-3s, list-3s, F4-F9 | **running / incomplete** |
| XCMP | `probes/sr0-o/f1-cross/` (untracked): F1 Mac-vs-Windows trace compare. Recorded compares `out/compare-strict-m1-w{2,3,4}.json` FAIL on AX shape (`role=list-item` absent). Fix patch `out/ax-listitem-fix.patch`; no post-fix compare result on disk | **PENDING** |
| SAME-SRC | `probes/sr0-c/same-source/RESULT.md` (cited by CONTRACT §8): identical screen compiles on both targets; `NavigationSplitView` negative fixture fails on Windows only | complete |

Windows 20-run requirement (CONTRACT §3 last paragraph: "Each Windows seed runs 20 times with all passing") is **not met by any evidence**: the matrices run 3 runs per config.

## 2. Clause-by-clause status

Legend: PROVEN = evidence on both sides as the clause requires; MAC = Mac oracle only; PENDING = named evidence missing.

### §1 Pinned tuple
- Pins Mac mini macOS 27.0.1, Xcode 27.0, Swift 6.4; Windows XPS 15 build 26300 x64, Swift 6.4.0; renderer gpui 0.2.2 / accesskit 0.25.1 / accesskit_windows 0.35.1; dispatch ordinal 23.
- Evidence: MAC-3/MAC-20 ran on macOS 27.0.1 arm64 Swift 6.4; HL and WIN-* on Windows 11 x64 Swift 6.4.0; renderer pins mirrored in `render/README-abi-v0.md`.
- Gap: Windows arm64 lane blocked (no host; `docs/sr0-status.md` SR0-D). Status: **PROVEN for x64/arm64-Mac; arm64 Windows PENDING and carried as a known exclusion.**

### §2 Slice inventory
- Same-source compile: SAME-SRC PASS on both targets.
- Runtime implementation of the inventory: HL 46/46 both OSes.
- Negative fixtures (`.onReceive`, `ObservableObject`/`@StateObject`, `NavigationSplitView`, `Timer.publish`): all four fail Windows compilation with a diagnostic, as CONTRACT §2 requires (`probes/sr0-c/same-source`, `probes/sr0-c/negative-fixtures/RESULT.md`). **MET.** Note: on macOS `.onReceive` and `ObservableObject` also fail against the slice, but `Timer.publish` compiles (Foundation on Darwin provides it), so the slice cannot reject it on Mac by compilation alone.
- `ForEach($items) { $item in }`: `probes/sr0-c/same-source/RESULT.md` records the `$`-projected closure parameter fails on Windows (cited in `probes/sr0-o/fixtures/RESULT.md` finding 2). Fixtures use `ForEach($model.rows, id: \.id) { row in }`. See change C3.

### §3 Fixtures F1-F9

| Fixture | Mac oracle | Fresh runtime headless | Fresh runtime on real Windows bridge |
|---|---|---|---|
| F1 | MAC-20 20/20, 1 canonical | HL PASS | WIN-M3 3/3 PASS (r1-r3); WIN-M2 FAIL (row5-not-torn-down, caret=nil) fixed since |
| F2 | MAC-20 20/20 | HL PASS | WIN-M3 3/3 PASS; WIN-M2 FAIL (no-teardown-on-move) |
| F3 list/vstack/lazy | MAC-20 8 configs 20/20 each; reinsert-state outcome per container in MAC-3 table | HL PASS (F3 aligned to List retention, `fresh-runtime/RESULT.md` line 282) | WIN-M3 list-0s, list-1s, vstack-1s 3/3; remainder **PENDING** (WIN-M3 incomplete) |
| F4 | MAC-20 20/20 | HL PASS | **PENDING** (not in WIN-M3 on disk) |
| F5 | MAC-20 20/20; zero-width pass logged as OBSERVE | HL covers layout engine (`fresh-runtime/RESULT.md`, line 171 section) | **PENDING** |
| F6, F6-reduced | MAC-20 20/20 each; raw traces vary (4 distinct for F6), canonical 1 | HL animation tests (commit 000679e `AnimationTests.swift`) | **PENDING** |
| F7 | MAC-20 20/20 (bounded I/O only) | HL TextInput/IME tests (000679e) | WIN-M2 FAIL (no-teardown); WIN-M3 **PENDING** |
| F8 | MAC-20 20/20 | HL PASS | WIN-M2 FAIL (toolbar-task-restarts-per-request); WIN-M3 **PENDING** |
| F9 | MAC-20 20/20 with `tree-released` as OBSERVE only | HL teardown coverage (000679e) | WIN-M2 3 BLOCKED (no post-close pump, no live-node counter in ABI 0.4); ABI 0.5 supplies both; WIN-M3 **PENDING** |

Mac F3 outcome (MAC-3): `List` preserves reinserted `@State` (0/1/3 s gaps, focused after reinsert); `VStack`+`ForEach` and `LazyVStack` reset it (1/3 s, not focused). Deterministic. In MAC-20, `reinsert-focus` is stable across runs per config (1 distinct value), but `reinsert-local-state` shows 9-20 distinct values per config, which are the per-run local counters, not the preserved/fresh outcome; the contract wording is "follows the container's recorded Mac outcome".

Run-count rule: "Each Mac fixture runs 20 times; all normalized assertions must agree": **PROVEN** (MAC-20, canonical distinct = 1 everywhere; F6 and lazy F3 have raw variance, recorded and absorbed by the within-step order-insensitivity rule). "Each Windows seed runs 20 times": **PENDING** (3 runs only).

### §4 Stimuli and native mappings
- Mac: stimuli posted via `CGEvent.postToPid` (CONTRACT §5 rules); used by all MAC-20 runs.
- Windows: Ctrl mappings and virtual-key SendInput implemented in `probes/sr0-o/uia-recorder/` (RESULT.md "Stimuli" section); IME composition uses virtual keys, not Unicode packets (`docs/sr0-status.md` host facts).
- Microsoft Japanese IME romaji composition end-to-end on the bridge: not evidenced (F7 Windows **PENDING**).
- Injected fake engine and clock: used by all fixtures (`probes/sr0-o/fixtures/Sources/SliceFixtures/Common/`). PROVEN.

### §5 Observation routes
- Model/lifecycle/effects in-process: PROVEN (MAC-20 EventLog).
- Mac AX tree/identifier/press/focus/selection/bounds: PROVEN (`probes/sr0-o/ax-routes`, CONTRACT §5 evidence paragraph). Signed recorder with its own AX grant: still needed (`docs/sr0-status.md` SR0-O row) -> **PENDING**.
- Windows UIA tree and Invoke: PROVEN (`probes/sr0-d/render-composition`; recorder `probes/sr0-o/uia-recorder`). Automation-id on the bridge: ABI rev 0.5 smoke shows 0/5 found (see bridge doc); **PENDING rerun**.
- Windows TextPattern: empty-edit TextPattern PASS in smoke (`examples/BridgeSmoke/result-smoke-rev05.txt`, `empty_edit_textpattern=PASS`). Selection, `GetBoundingRectangles` caret rect on a populated field: **PENDING** (CONTRACT §8 open item).
- Canonical roles window, button, text-field, list, list-item, static-text: Mac normalizer rules in CONTRACT §5; Windows roles in ABI `SWR_ROLE_*`; List/list-item emission added in cc605bf. Cross-platform shape match: XCMP **PENDING** (recorded compares fail pre-fix).
- Visible-response endpoint per OS: **PENDING** (CONTRACT §8; not chosen anywhere in the evidence reviewed).

### §6 Bridge ABI vocabulary
Governed by the companion proposal `docs/sr0-freeze-bridge-interface.md`. Contract-side change C4 below.

### §7 Budgets
- Presentation budget revision 1 (zero missed vblanks, p95 <= refresh + 0.1 ms): MET, batch 5, 30/30 valid runs (commit 011c83e; `docs/sr0-status.md` SR0-B row). **PROVEN** on the Windows lane tested.

### §8 Open before freeze
- Same-source compile: closed (SAME-SRC).
- TextPattern on Windows edit nodes: partial (empty field only). Mac AX caret route for SwiftUI `TextField`: AXSelectedTextRange/AXBoundsForRange proven in `probes/sr0-o/ax-routes`. **Remaining: Windows populated-field TextPattern.**
- Visible-response endpoint: open.

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
| C9 | Windows repeat count: either keep 20 (requires a 20-run Windows matrix) or amend to a stated smaller N with reason. **Decision needed.** | §3 last paragraph vs WIN-M3 (3 runs) |

None of C1-C8 changes a pass/fail semantic that the Mac oracle recorded; C3 and C9 change contract text and require a decision.

## 4. Freeze-blocking items

1. WIN-M3 completion: F3 remaining configs, F4-F9 on the bridge. Needs: `out/matrix-rev3/RESULT.md` showing all configs PASS, F9 using `live_nodes`, late-results-rejected and cleanup-after-close (8f3ffeb).
2. Windows repeat count per C9 (3 vs 20 runs).
3. XCMP: F1 Mac-vs-Windows compare passing after the List/list-item AX fix (cc605bf); needs a recorded compare result.
4. ~~Negative fixtures~~: MET (`probes/sr0-c/negative-fixtures/RESULT.md`).
5. Windows TextPattern on populated edit nodes (selection, caret rect); UIA AutomationId rerun (see bridge doc).
6. Visible-response endpoint per OS chosen and recorded (CONTRACT §8).
7. Signed Mac recorder with its own AX grant (`docs/sr0-status.md`).

Non-blocking for a v1.0 on x64 + Mac arm64: Windows arm64 lane (no host), noted as exclusion.

## 5. Proposed freeze decision

Freeze as v1.0 once blockers 1-3 are closed with receipts and C1-C9 are applied, after which any change triggers a rerun of both seeds. Selection of the fresh runtime remains provisional until WIN-M3 and XCMP land (`probes/sr0-s/COMPARISON.md` header).
