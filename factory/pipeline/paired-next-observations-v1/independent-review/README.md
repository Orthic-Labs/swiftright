# Independent review v1

`review_report.py` independently hashes all 409 raw input files listed in
`source-inputs-v1.json`, validates its pinned case/source identities, then
reconstructs Mac AX label sequences and Windows UIA text sequences directly
from those raw files. It checks report joins, process/case identity, compositor
capture hashes, repeated Windows paint receipts, stage-file hashes and the
recorded 10-test pass. It does not import producer code or alter producer
inputs.

Result: `clear-for-bounded-observational-report`. Each of three cases has one
Windows observation compared with 20 Mac runs, with exact observed role/label
sequence matches. This result does not qualify rendering parity, timing,
hit-testing, occlusion, provider readback or a golden.

Replay offline from repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/pipeline/paired-next-observations-v1/independent-review/review_report.py
```
