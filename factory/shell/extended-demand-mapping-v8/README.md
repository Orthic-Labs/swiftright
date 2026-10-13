# Extended demand mapping v8

V8 is a requirements-only successor to frozen v7. It preserves the 107-demand denominator, five unresolved rows, three ambiguous rows, and zero full-demand resolutions or registry promotions. Each of eight held rows retains its exact v7 disposition and evidence requirements.

The verifier binds exact v7 bytes, v6 lineage, and registry snapshot. It checks held dispositions and exact evidence text, requires true integer count fields, and rejects the three previously accepted mutations along with v7's original seven controls.

Replay from repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v8/generate.py
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v8/verify_v8.py
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v8/test_mapping_v8.py
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v8/freeze_stage.py
```

V8 adds no API identity, demand coverage, or registry eligibility. Its overlay is an evidence checklist only.
