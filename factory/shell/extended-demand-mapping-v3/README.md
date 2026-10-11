# Extended demand mapping v3

Source-only F12 denominator-preserving candidate built from immutable v1/v2 mappings & current catalogue/source snapshots.

All 107 rows remain present. Exact current source/USR usage is bound for 2 rows: `List/ForEach/onMove` & `TextField/FocusState`. Remaining rows retain held dispositions with exact source inventory references where available; service/platform ownership, ambiguous declarations & unmapped demands emit no registry links. Registry mappings remain `0`.

Inputs, source snapshot bytes & catalogue USR checks are pinned in `raw-pins-v3.json`. No registry, catalogue, demand or historical v1/v2 file is modified.

Run offline:

```text
PYTHONDONTWRITEBYTECODE=1 python3 generate.py
PYTHONDONTWRITEBYTECODE=1 python3 test_mapping_v3.py
```
