# Matrix v5 source review

Review is source-only; no matrix run performed.

## PASS controls

- Runner SHA-256 `f29f670ebdce71a27d363b68ca1cb63ae34cdd04266cf2b56978eb77028f8cd4` retains original coordinator handle before wait, samples `WaitForSingleObject` & `GetExitCodeProcess`, drains both redirected streams, rejects `259`, & seals `matrix-run.json` plus coordinator output with `CreateNew`.
- Each failed case increments aggregate failure, preserves raw outputs, writes sealed status, & continues; runner never calls `Remove-Item`, `Kill`, or scheduled-task unregister. Final `MATRIX_FAIL` preserves all case receipts.
- Lock ownership is delegated to coordinator v4. Runner checks lock is free before each case; it does not release or rewrite lock. Coordinator failure therefore remains visible for root recovery instead of being silently cleared.
- Pure controls passed: `python3 qualification/test_tuple12_matrix_v5_controls.py`; six mutation faults rejected. Controls SHA-256 `ee7eb41f230c4f59a9443cded59f1269408174473fd339bc936aae094d6b34e0`.

## Bounded review hold

`Start-Coordinator` waits without an outer deadline. This is safe only while coordinator v4's own lifecycle remains bounded; root should retain lock & inspect process state if coordinator hangs. `Lock-Free` accepts plain `free` or JSON `state/status/value=free`; CAS remains coordinator authority, so this is not an admission bypass.

No source change is proposed for v5.
