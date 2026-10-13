# Extended demand mapping v7

V7 is requirements-only overlay over frozen v6. Denominator remains 107, with 5 unresolved rows & 3 ambiguous rows held. Existing per-row demand counts & partial overlaps remain governed by v6. No SDK identity, full-demand resolution, registry promotion, or coverage claim is added.

Each held row records exact evidence needed before any identity can be considered: source declaration, source range & USR, plus recipe/gate or consumer join where applicable. Registry snapshot is pinned & reports 10 blocks.

Replay:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v7/generate.py
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v7/verify_v7.py
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/extended-demand-mapping-v7/test_mapping_v7.py
```

Seven mutation controls reject denominator, row-set, promotion, base-overlay, registry, resolution, & identity-claim drift.
