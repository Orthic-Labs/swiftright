# Layout-rules regression (N=3, stage 3d3c6f5c2-0a0d1f39)

Records: `results.jsonl` (one line per case: stage, n, exit, prior, changed, tail). Decisions: `docs/sr1-decisions.md`, section "Verification, 16 October".

## Attribution correction (16 October)

Every record's `prior` is the closure run on `6459bb8cd`. The lane's commit message (`340a8b237`) also names `31c7cbcb5` as a comparison point for textfield submit and focus tab-order, but no record here holds a run at `31c7cbcb5`.

`31c7cbcb5` is not a clean pre-lane baseline: it contains `db29b0c5e` and `bbfea2f6f`, predates only `0a926b54e`, `0d84c2363` and `1b76fd6c6`, and is 67 commits after `6459bb8cd`. Do not read the verdict changes as caused by the layout lane.

Likely but unproven cause: F2 (`7d73e2ac6`, body 13 DIP) with the 0.7 renderer. Evidence: Windows first ink +3 px, baseline +2 px, ink height 21 to 23 px. `db29b0c5e` is not excluded.

Verdict changes with no comparison run at `31c7cbcb5` (every changed case except textfield submit and focus tab-order): focus-state bool-form-v1, programmatic-v1, shift-tab-v1; ime-marked-text ime-cancel-v1, ime-commit-v1, ime-composing-v1, ime-recompose-v1; opacity-transition opacity-text-v1; color-scheme text-dark-v1; alert confirm-cancel-v1.

The N=20 runs of the eight block-27 text cases (captured 15 October) were recompared with the strict scale guard on 16 October; each run dir now holds the verdict as `block-gate.json`.
