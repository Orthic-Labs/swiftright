# F12 source receipt refresh v2

V2 binds each of 56 inventory receipts to current source bytes & exact current anchors, while retaining historical hash/line/text records. It resolves one changed SettingsPanel declaration to its current `props` signature at line 173. V1 & frozen inventory remain unchanged.

All 107 demand associations retain null registry IDs, 61 `unmapped`, 46 `source_inventory_only`, & `sourceProof=false`. Associations identify owning journey evidence only; they do not promote catalogue symbols, prove runtime behavior, or establish acceptance.

Run from repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/journey-audit/source-receipt-refresh-v2/refresh.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s factory/shell/journey-audit/source-receipt-refresh-v2 -p 'test_refresh_v2.py' -v
```
