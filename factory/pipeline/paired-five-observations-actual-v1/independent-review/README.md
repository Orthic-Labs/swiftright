# Paired five observations actual v1 independent review

Reviewed stage manifest SHA-256:
`06dbd5dbd2646a53495fca2b1c930a75a8c7b743c18e9a9d7bc735c96ba84eb0`.

Independent checker rehashes all 11 pinned raw roots: four Windows native-v5
20-run batches, one preference v3 single-run packet, one failed preference v5
attempt, and five Mac 20-run archives. It rechecks every source/case/executable/
compile receipt/raw file join, reconstructs each AX/UIA label sequence from raw
files, and verifies report timing entries are verbatim per-provider records.

Four Windows cases have 20 valid observations each. Preference preserves one
usable v3 Windows observation and v5 first-attempt failure with all 25 raw
files. Exact `AXStaticText` → `ControlType.Text` sequences match all 20 Mac
runs for stack, padding, scroll and preference. Custom Mac external AX stays
held; Windows UIA has zero children in all 20 runs, with no empty-content or
parity claim. Seven source/case/executable/semantic/raw/failure/qualification
fault controls rejected their mutations.

Parity, qualified paint, focus, occlusion, timing qualification, goldens and
qualification remain held. Replay offline from repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/pipeline/paired-five-observations-actual-v1/independent-review/review.py
```
