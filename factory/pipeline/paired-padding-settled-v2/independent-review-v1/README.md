# Independent review v1 — paired padding settled v2

Status: `PASS_WITH_INTEGRATION_HOLD`. Frozen report reproduces exact Mac20 & Windows18 attempts: 15 eligible, 2 invalid-host (runs 3,16), & 1 deadline (run18); runs 19,20 were never started. Raw rows remain retained, native/pixel/provider parity & cross-platform timing remain held.

Review confirms report uses direct `Path.read_bytes`/`json.loads` in `report.py`; it does not call F8 `factory.comparison.compare_case`, F9 `factory.reports.build_report`, workflow `gate`/`gate_evidence`, or production `ArchiveByteReader`/`origin_reader`. This is an observational report only. Integration hold: route future admission through F8/F9 & production origin-reader callback before any gate/qualification claim.

Run from repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/pipeline/paired-padding-settled-v2/independent-review-v1/review.py
```

No native, GUI, compiler, Windows, or remote operation performed.
