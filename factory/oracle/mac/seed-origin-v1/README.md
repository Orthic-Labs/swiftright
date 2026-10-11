# Seed compiler-origin source packet v1

Review packet only. No fresh capture/build has run from this namespace.

Scope: seed `14577611000270672472`, exact five corrected cases, exact witness/case/recipe copies under `inputs/`.

`capture_origin.py` preserves existing capture behavior while replacing only host compile step with direct resolved `swiftc` execution. It records resolver & compiler argv, PID, UTC start/end, exit, timeout, raw stdout/stderr, compiler/xcrun hashes, pre/post Witness+adapted CaptureHost snapshots & emitted binary hash. Source drift blocks success. `verify_receipt.py` rejects missing, changed, mismatched or nonzero receipts.

Required pre-capture review: inspect `capture_origin.py`, `verify_receipt.py`, `receipt-schema.json` & stage manifest. Actual capture remains pending review/authorization.
