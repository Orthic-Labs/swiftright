# Paired padding settled v6

v6 preserves original Mac `capture.json` envelopes byte-for-byte & routes them through repo-root `artifact_reader` for workflow collection & recorded F10 `gate_evidence`, with Mac-root `origin_reader` reserved for native origin guards. Existing comparator & F9 report builder receive actual original envelopes. No new Mac capture IDs or reconstructed envelopes are created.

Windows peer JSON remains adjunct quarantine facts: requested20, started18, prior host-error-free15, invalid host runs3/16, deadline run18, not started19/20. It is not passed as typed Windows captures because archive lacks `windowsExitProof`.

Venv replay executes workflow collection, comparator & recorded gate evidence. F9 remains blocked by Windows origin proof. Counts distinguish `readerVerified20` & `schemaCollected20`; origin verification is 0; parity qualification is 0. Controls observe exact `mac-origin:missing-origin` for all 20 Mac rows & retain Windows adjunct status without typed Windows captures.

```sh
PYTHONPATH=. PYTHONDONTWRITEBYTECODE=1 python3 factory/pipeline/paired-padding-settled-v5/report.py --output factory/pipeline/paired-padding-settled-v5
PYTHONPATH=. PYTHONDONTWRITEBYTECODE=1 python3 factory/pipeline/paired-padding-settled-v5/report.py --fault-controls
```
