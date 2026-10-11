# Paired padding settled v5

v5 preserves original Mac `capture.json` envelopes byte-for-byte & routes them through reader verification, existing workflow collection, comparator, F9 report builder & recorded F10 `gate_evidence` plan. No new Mac capture IDs or reconstructed envelopes are created.

Windows peer JSON remains adjunct quarantine facts: requested20, started18, prior host-error-free15, invalid host runs3/16, deadline run18, not started19/20. It is not passed as typed Windows captures because archive lacks `windowsExitProof`.

Current host lacks `jsonschema`, so workflow collection, comparator & recorded gate evidence emit explicit dependency holds. F9 still receives actual seeded case, actual reader-verified Mac20 envelopes & blocked comparator-held verdict. Counts distinguish `readerVerified20` from `schemaCollected20`; origin verification is 0; parity qualification is 0.

```sh
PYTHONPATH=. PYTHONDONTWRITEBYTECODE=1 python3 factory/pipeline/paired-padding-settled-v5/report.py --output factory/pipeline/paired-padding-settled-v5
PYTHONPATH=. PYTHONDONTWRITEBYTECODE=1 python3 factory/pipeline/paired-padding-settled-v5/report.py --fault-controls
```
