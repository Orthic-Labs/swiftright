# SR0-S seed comparison

Status: SEED DISPOSITION RECORDED, 9 October 2026 (close plan v2, `docs/sr0-close-plan.md`). **Fresh runtime: selected. SwiftCrossUI-core fork: EARLY-DISQUALIFIED.** This is not a completed same-backend comparison (see "Seed disposition"). Selection becomes final with SR0 close: the fresh runtime's evidence must be re-bound to the ABI 0.6 tuple (`docs/sr0-snapshot.md`) and pass the remaining stages.

Criteria (architecture §12 SR0-S): both seeds execute the same slice through the same backend; select only a fully passing seed; among passing seeds prefer fewer semantic overrides and lower measured cost. Retry cap: one initial attempt plus one targeted repair per candidate.

| Evidence | Fresh runtime | SwiftCrossUI-core fork |
|---|---|---|
| Headless semantic suite | 46/46 macOS & Windows (`fresh-runtime`) | 17/22 macOS & Windows, 5 blocked (`scui-fork`) |
| Blocked areas | none | Observation granularity (+8 body evaluations per unrelated change), relayout re-measure, transactions/animation, custom `Layout`, sub-point geometry |
| Semantic overrides to reach its result | n/a (written to the contract) | 5 overrides, ~370 lines; a sixth (skip clean children) attempted and reverted |
| Real Windows renderer (bridge) | F1–F9: 15 configs x 3 PASS (`fresh-on-bridge/out/matrix-rev4`, `matrix-rev4b`, ABI 0.5), then 15 configs x 20 = 300/300 PASS (`out/matrix-20b`, commit `65e0f29`, ABI 0.5). Rerun on ABI 0.6 pending | **never run through the real backend** (headless only, `scui-fork/RESULT.md`) |
| Mac-oracle-specific outcomes (F3 per-container state/focus) | implemented and tested | List retention added as override O3; focus outcomes untested |

Assessment:
- The fork's blocked areas are core runtime mechanisms the slice depends on (F5 width layout, F6 interrupted animation, pixel-aligned bounds for the AX/paint agreement, fine-grained invalidation for bridge cost). Passing them means replacing SwiftCrossUI's scheduler, invalidation, layout and transaction model — a rewrite, not a targeted repair. The fork's initial attempt plus its override round is its SR0 attempt; it cannot become a fully passing seed within the retry cap.
- Running the fork through the real renderer would not change this outcome: the blocked assertions fail before any backend is involved. (This is a judgement, not a measurement; the fork was never run through the real renderer.)
- Reusable from the fork under MIT with notice, if useful later: nothing the fresh runtime still lacks; the assessment's "reusable" list (State carry-over, keyed ForEach, Binding, Environment) is already covered by the fresh runtime.

## Seed disposition

- **Fresh runtime: selected.** Headless 46/46 then 62/62 on macOS and Windows (`fresh-runtime/RESULT.md`, `000679e`, `14106d6`); F1 Mac-vs-Windows compare 0 diffs (`eaf40dc`); Windows matrix 15 configs x 20 runs all PASS on ABI 0.5 (`65e0f29`). Selection stays conditional on rebinding to the ABI 0.6 tuple and on the plan's remaining lanes (R1, R6, R9, R10). Retry usage is in `docs/sr0-retry-ledger.md`: the fresh candidate exceeded the §12 cap of one initial attempt plus one targeted repair.
- **SwiftCrossUI-core fork: EARLY-DISQUALIFIED.** Headless semantic suite 17/22 with 5 core areas blocked (observation granularity, relayout re-measure, transactions/animation, custom `Layout`, sub-point geometry) after 5 semantic overrides plus a reverted sixth (`scui-fork/RESULT.md`; commits `b771c20`, `a7b43ac`). Its retry cap is spent. **It did not run through the real backend**: it was never connected to the Windows renderer or the ABI bridge, so there is no F1-F9 Windows matrix, no UIA/IME run and no budget measurement for it. The disqualification rests on headless semantic failures alone. This is not recorded as a passing or completed same-backend comparison, and §12's wording "execute frozen slice through same qualified backend" was not satisfied for the fork.

Reopening the fork would be a scope change by Adrian, not a retry.
