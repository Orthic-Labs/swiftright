# F12 source receipt independent review

This source-only review rechecks frozen source-receipt-refresh-v2 against current bytes. It binds all 56 receipts, 26 journeys, & 107 demand associations. Existing statuses remain unchanged: 61 unmapped, 46 source-inventory-only, null registry IDs, & zero promotion. No native, compiler, registry, or source mutation occurs.

Run:

```sh
python3 factory/shell/journey-audit/source-receipt-refresh-v2/test_refresh_v2.py
```
