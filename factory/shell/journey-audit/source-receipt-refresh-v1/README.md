# F12 source receipt refresh audit v1

This packet audits current bytes against 56 historical F12 inventory receipts & joins all 107 demand rows to their owning journey evidence IDs. It preserves `factory/shell/inventory.json`, `factory/shell/demand.json`, frozen mapping overlays, null registry IDs, & source-only status.

`associationKind=journey-evidence-association-only` is bookkeeping, not API proof, runtime proof, acceptance, parity, or registry promotion. Current external source edits are reported per receipt; no automatic re-pinning occurs.

Run from repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/shell/journey-audit/source-receipt-refresh-v1/audit.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s factory/shell/journey-audit/source-receipt-refresh-v1 -p 'test_audit.py' -v
```
