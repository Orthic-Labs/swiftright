# SR0-S seed comparison

Status: DECISION DRAFT, 9 October 2026. Selection becomes final when the fresh runtime passes the rerun Windows matrix (`fresh-on-bridge/out/matrix-rev2`) and the first cross-platform trace comparison (`probes/sr0-o/f1-cross`).

Criteria (architecture §12 SR0-S): both seeds execute the same slice through the same backend; select only a fully passing seed; among passing seeds prefer fewer semantic overrides and lower measured cost. Retry cap: one initial attempt plus one targeted repair per candidate.

| Evidence | Fresh runtime | SwiftCrossUI-core fork |
|---|---|---|
| Headless semantic suite | 46/46 macOS & Windows (`fresh-runtime`) | 17/22 macOS & Windows, 5 blocked (`scui-fork`) |
| Blocked areas | none | Observation granularity (+8 body evaluations per unrelated change), relayout re-measure, transactions/animation, custom `Layout`, sub-point geometry |
| Semantic overrides to reach its result | n/a (written to the contract) | 5 overrides, ~370 lines; a sixth (skip clean children) attempted and reverted |
| Real Windows renderer (ABI v0) | F1–F9 matrix run; rerun on fixed runtime in progress | not run |
| Mac-oracle-specific outcomes (F3 per-container state/focus) | implemented and tested | List retention added as override O3; focus outcomes untested |

Assessment:
- The fork's blocked areas are core runtime mechanisms the slice depends on (F5 width layout, F6 interrupted animation, pixel-aligned bounds for the AX/paint agreement, fine-grained invalidation for bridge cost). Passing them means replacing SwiftCrossUI's scheduler, invalidation, layout and transaction model — a rewrite, not a targeted repair. The fork's initial attempt plus its override round is its SR0 attempt; it cannot become a fully passing seed within the retry cap.
- Running the fork through the real renderer would not change this outcome: the blocked assertions fail before any backend is involved.
- Reusable from the fork under MIT with notice, if useful later: nothing the fresh runtime still lacks; the assessment's "reusable" list (State carry-over, keyed ForEach, Binding, Environment) is already covered by the fresh runtime.

Draft selection: **fresh runtime**, provisional on the two pending Windows results above. If either fails on a runtime defect, repair under SR0-S's cap and rerun both affected stages.
