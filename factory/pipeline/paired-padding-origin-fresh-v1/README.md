# Fresh Mac origin report v1

Fresh `padding-origin-fresh-v1/actual` contains 20 actual Mac capture envelopes. Report routes capture, case, recipe & workflow artifacts through repo-root/fresh-root `ArchiveByteReader`; origin descriptors route through exact `origin-reader-config.json` path map into archived bytes. All 20 rows pass independent origin descriptor reads.

Historical Mac case tuple `sr1-observed-r09` remains recorded as template metadata. Windows renderer/runtime source binding is recorded separately (`e280f4a9…`, runtime commit `37429120…`); no tuple migration, parity or promotion occurs. Windows facts remain adjunct/quarantine with typed count 0.

Replay:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. factory/.venv/bin/python factory/pipeline/paired-padding-origin-fresh-v1/report.py --output factory/pipeline/paired-padding-origin-fresh-v1/root-replay-rN
```

`fault-controls.json` covers positive 20-row origin proof, malformed origin bytes, malformed artifact bytes, missing origin, & Windows absence classification.
