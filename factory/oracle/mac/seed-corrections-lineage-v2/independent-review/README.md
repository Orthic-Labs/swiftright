# Seed corrections lineage v2 independent review

Offline review verifies five separate `Witness.swift` files & five separate adapted `CaptureHost.swift` files, each exact source byte hash, v1 summary source/adapter/binary joins, & 100 instrumented raw joins. Every capture provenance `sourceHash` equals its own `instrumented.raw.json` bytes; no field relabeling or embedded-source inference is used.

Source-bound candidate observations pass. Compiler OS origin & parity qualification remain held because archived policy records an argv template only; actual compiler argv, PID, start/end timestamps, & return code are absent. Six mutation controls reject Witness, adapter, binary, raw, summary join, & process-proof changes.

Run offline with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 factory/oracle/mac/seed-corrections-lineage-v2/independent-review/review.py
```
