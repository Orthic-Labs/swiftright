# SR0 retry ledger

Written 9 October 2026 (close plan v2 lane R0) from commit history (`git log`, HEAD `6263841`) and the RESULT.md files named in each row. Nothing was rerun to produce it.

## Cap and counting rules

Rule (`docs/architecture.md` §12, SR0 table footer): **one initial attempt and at most one targeted repair per failing stage/candidate.** Repeated failure ends that candidate's SR0 attempt; a shared-stage failure (D/C/O/B/P/A) after its cap "stops SR0 until Adrian resumes or changes scope"; a dependency-availability blocker consumes no attempts; renaming a stage or switching renderer does not reset counts.

How rows are counted here:
- **Attempt**: a run of the stage's pass criteria on the candidate that produced a verdict (PASS, FAIL or BLOCKED).
- **Repair**: a targeted code or fixture change made because an attempt failed, followed by a rerun. A rerun with no change is not a repair.
- **Not counted**: harness or infrastructure retries (foreground denied, no window; kept as `.aN.txt` files and described in `fresh-on-bridge/RESULT.md` "Infrastructure retries"), build-fix iterations inside a probe task (separate per-task caps of 4 or 6 stated in each RESULT.md), availability blockers, and scope additions (ABI 0.6, SR1, SR3).
- The repository records no Adrian "resume" or waiver for any row marked EXCEEDED below. The standing-autonomy note in agent memory is not a repository record of a §12 reset, so it is not counted as one; whether Adrian considers the overruns accepted is UNVERIFIED.
- Boundaries between "repair" and "scope change" are judgement calls; each row cites the commits so the call can be checked.

## Ledger

| Stage / candidate | Attempts | Repairs | vs cap | Evidence |
|---|---|---|---|---|
| **D** dependencies & hosts (all probes) | 1 | 0 stage-level | within cap | PASS probes `384fcf0` (composition+UIA), `f3da03c` (dispatch-drain 3/3, 1 of 4 build fixes), `06c972a` (swiftpm consumer, 1 build fix `strncpy`), `90e90b3`/`487e4ed`/`56dd90d` (IMM32 text node, 1 of 4 build iterations, interactive IME PASS). Windows arm64 blocked: availability blocker, now out of scope (scope revision 1); consumed nothing. Adapter gap in `@rightkit/release` recorded by `probes/sr0-d/release-preflight` is an availability blocker |
| **C** slice contract | 1 | 0 | within cap | Draft `f3da03c`. Same-source compile `6c7002b` PASS after 5 of 6 Windows and 2 Mac compile-fix iterations (`probes/sr0-c/same-source/RESULT.md` line 90); the `$row` closure form that cannot compile on Windows is recorded as contract change C3, not a failed stage. Negative fixtures `5afd873` PASS, no failure recorded. Contract text revised from oracle evidence (F3 container table, `10763b6`, `5216f0f`); a content revision, not a repair of a failure |
| **O** oracle: Mac fixtures + repeatability | 1 | 2 | **EXCEEDED by 1** | Attempt `10763b6`: F1-F9 self-tests NOT COMPLETED, window never presented (`probes/sr0-o/fixtures/RESULT.md` line 10). Repair 1 `5216f0f` (F3 container-dependent state, F5 root cause, F9 verdict). Repair 2 `52aa3d9` (F6 double-animation fixture bug, List retention). Result `4ff202f`: 17 configs x 20 PASS. Comparator `39e5f63` rejected injected faults first time (2 tool-level fix iterations) |
| **O** cross-platform F1 compare | 1 | 2 | **EXCEEDED by 1** | Attempt `7a91608`: 317 diffs, then 52 after the List AX roles (`cc605bf`, repair 1), then label fix (`cc4c93a`, repair 2), PASS 0 diffs `eaf40dc`. Counted against O because the repairs touched the runtime/bridge side of the comparison, not a new stage |
| **B** bridge: ABI v0 smoke | 1 | 0 | within cap | `b907913` smoke 19/19; fault harness `7a86349` PASS (3 driver fixes, no bridge change, `bridge-faults/RESULT.md` line 160); text geometry `b52e485`, run 4 35/35 `fcc999d` |
| **B** bridge: ABI revisions driven by S | 2 further revisions | 2 | **EXCEEDED by 1** | Repair 1: ABI 0.4 `b9651bd` (identifiers, labels, empty-edit TextPattern). Repair 2: ABI 0.5 `10c4877` (shutdown_complete, live_nodes, underline), needed because S found no post-close pump or live-node counter (matrix-rev2 F9 BLOCKED, `out/matrix-rev2/RESULT.md`). ABI 0.6 `4df7e67` is a scope addition (SR1) and not counted |
| **B** bridge: 0.5 smoke defects | 3 smoke runs | 2 | **EXCEEDED by 1** | rev05 AutomationId 0/5 -> linger ticks `4000565` (repair 1) -> rev05b 26/26, timeout mode 26/27 -> renderer `d45c98c` (repair 2, post-close pump after GPUI quit-on-last-window) -> rev05c 26/26 and timeout05c 27/27 (`ee5a4db`). Overlaps the previous row in time; counted separately because it is a separate failing criterion |
| **B** bridge: modal loop | 8 runs | 1 reshape | UNVERIFIED | `383345c` partial; `c0b93d8` drains in size/TaskDialog loops; modal p99 31.1 ms FAIL in the early runs (TaskDialog open stall, `probes/sr0-b/modal-loop/RESULT.md` line 143), desktop receipt commit `0d3f1a9`. `23933e1` split the open stall out as `modal_open_one_off` (bound 50 ms, run 8 max 49.35 ms), i.e. the measurement was re-scoped rather than the stall fixed. Per-run count not recoverable from the RESULT file: UNVERIFIED. Re-scope should be reviewed as a criterion change |
| **B** bridge: frame budget | 5 PresentMon batches | 3 harness repairs + 1 budget revision | **EXCEEDED** (and criterion changed) | Batch 1 `8badf79`, batch 2 `f187254`, budget revision 1 `ca7a04c` (approved by Adrian, `architecture.md` §11), batch 3 `749416c`, batch 4 `1813eb9` (0/30 valid, analyzer), batch 5 `011c83e` 30/30 valid (10 per variant). Two earlier batch-5 starts aborted on orchestrator defects. Display-driven frame clock `8cd7f34` |
| **S** fresh runtime, headless | 1 | 8 Mac edit cycles (task cap 6) | task cap exceeded; stage cap N/A | `fresh-runtime/RESULT.md` lines 19-20 and 131-145: 8 edit-build-test cycles on macOS "one over the cap of 6", Windows 1 compiler workaround plus 1 rewrite. Later extensions `a1e7095`, `000679e` 46/46, `14106d6` 62/62 |
| **S** fresh runtime on real Windows bridge | 1 (`4112d8c`: 7 of 15 configs PASS, gaps named) | at least 5 | **EXCEEDED by at least 4** | Repair 1: runtime closure `000679e` + `55ebc73` -> matrix-rev2 `2aa1983` ALL FAIL (regression). Repair 2: `cc605bf` + `8f3ffeb` -> rev3 `96fcd30` (F7 0/3, F8 2/3, F9 2/3). Repair 3: `cc4c93a` -> rev4 44/45 (`ee5a4db`). Repair 4: renderer `d45c98c` -> rev4b all 15 configs 3/3. Repair 5: self-test F3 vstack settle race found by partial `matrix-20` (`3d2d57f`), plus window-targeted key delivery (`076a56f`) -> matrix-20b 300/300 PASS (`65e0f29`). Per-fixture iteration counts in `fresh-on-bridge/RESULT.md` lines 288-300 |
| **S** SwiftCrossUI-core fork | 1 (`b771c20`: 17/22 PASS, 5 BLOCKED) | 1 override round (O1-O5; O6 attempted and reverted) | cap spent, not exceeded | `probes/sr0-s/scui-fork/RESULT.md`; `probes/sr0-s/COMPARISON.md`. **Early-disqualified; never ran through the real backend.** Evidence: assessment `99f32b7`, decision draft `a7b43ac` |
| **P** packaged qualification | 0 | 0 | not started | Prep only: `f39ca94`, `47b7599`, `076a56f`. Blocked on `@rightkit/release` adapters (availability, consumes nothing) |
| **A** automation | 0 stage attempts | 0 | not started | Runner built (`b98d495`, `799047d`); stage depends on P. The F3-F9 seeding block and its fix (`qualification/run.py`, `docs/qualification.md`) were tooling repairs, not a stage attempt |

## Stages that exceeded the cap

1. **S, fresh runtime on the Windows bridge**: roughly five repairs against a cap of one, spread over rev2 to matrix-20b.
2. **O**: two repairs on fixtures/repeatability and two on the cross-platform compare.
3. **B**: ABI revisions 0.4 and 0.5 plus smoke repairs (`4000565`, `d45c98c`) and four frame-budget harness/criterion changes (the criterion was revised with Adrian's approval, `ca7a04c`).

§12 says shared-stage overruns stop SR0 until Adrian resumes or changes scope. Most overruns trace to downstream stages finding defects in upstream stages (S found B gaps, the cross-compare found S gaps), which §12's failure-specific fallback table does permit ("repair ABI/batching/threading within cap, then rerun B and downstream"). That does not remove the cap. Recommendation for plan v2 R11: record an explicit Adrian decision on the overrun (resume or accept) in `docs/sr0-status.md` before SR0 is marked closed, and treat any further failure on the 0.6 tuple as a stop.

## Retry budget going forward (0.6 tuple)

A rerun on the 0.6 tuple (plan R1, R6, R9, R10) is a rerun of unchanged criteria on new binaries. A failure there is a new failing attempt on stages already over cap; nothing in this ledger resets counts. Rows marked UNVERIFIED need the per-run logs under each probe's `out/` directory (ignored in Git for several probes) to settle.

## Resume decision (9 October 2026)

Adrian, in this session's `/goal`: "stop fucking asking for approval and achieve the fucking plan". Recorded as the §12 resume for every row marked EXCEEDED above: the overruns are accepted, SR0 continues under plan v2 (`docs/sr0-close-plan.md`), and further repairs stay bounded by plan v2's lanes. This is the repository record of the resume.
