# Paired stack/custom actual v4 independent review

Reviewed candidate stage manifest SHA-256:
`519df923250e311c7c455f2c6232f5790fab2bcc46297e67ff2c636774621634`.

The review independently rehashed all four candidate files and all four raw
source trees, then checked 20 unique Windows runs per case against exact Mac
source/case archives. Each Windows row's plan, dispatch, compile observation,
native receipt, process/capture ownership, executable and compile receipt
hashes, native file hashes and raw UIA/pixel records were joined. Custom case
has zero Windows UIA children in all 20 rows; Mac custom external AX remains
held. Stack has one UIA `ControlType.Text` child named `+` in each row; Mac AX
also exposes `+`, but report makes no cross-provider role/label/enabled
mapping claim. Report keeps raw channel counts & files only.

The six protected fault controls were replayed: source hash, case hash, batch
count, raw inventory and semantic mutation faults were rejected; forged
qualification was rejected. Candidate remains observational: parity, timing,
pixel interpretation, color, occlusion, focus, native diff, goldens and
qualification are held or unavailable.

Replay offline from repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/pipeline/paired-stack-custom-actual-v4/independent-review/review.py
```
