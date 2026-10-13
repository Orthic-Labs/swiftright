# Full16 x20 r4 archive diagnosis

Source-only review of `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-full16-20-r4` completed 2026-10-11.

Transport is verified by `root-transport-review.json`: ZIP SHA-256 `65c049cb33a6e83129d1230cdf1ff4cb57c86527028f9ff782b5709f754a528f`, 407249 bytes, exhaustive 367 files, `nativeActions=0`, `deleted=false`.

Archive has 41 worker receipts: 40 passed F1/F2 cases & one failed F3 variant:

- Failed case: `F3-list-0s-r1-27cc97641b97468596b0125e38d1ee3c`
- Worker receipt SHA-256: `533c0ad1eab616808fe738df879defb769f4cc60778f3b8d79faf9dd3e7e5170`
- Receipt status: `failed`, worker exit 1; driver exit 0; child exit 0; driver/child kernel terminal & streams drained all true.
- Raw trace SHA-256: `803de9af633d59138db714019ed60858bf6aa4072780eb420e9e29009f839695`
- Raw trace: `F3 list-0s` emits `SELFTEST F3 list-0s: PASS (15/15 asserted; blocked=0; end=window-closed)` plus all variant-qualified stage/assertion lines.
- Worker-v3 required literal `SELFTEST F3: PASS`, so failure is worker predicate mismatch, not fixture semantic failure. Driver trace has `fg_changes=0`, `driver_abort=none`, `exit=0`, retained same HWND/process/handle & clean kernel exits.

Outer stdout has 40 PASS lines through F2 run 20 but no final `MATRIX_PASS`; outer stderr has generic unbound `F1 semantic proof failed` from prior matrix wrapper line 90. Preserve all records. Full16 remains unsealed because failed F3 receipt & missing final matrix seal are real evidence.

Prepared matrix v4 source successor under `qualification/tuple12-takeover/matrix-controls-v4`: fixture+variant-qualified verdict labels, exact 16 denominator map, stage assertions, worker/coordinator/runner pins, explicit `MATRIX_PASS`. No assertions are weakened.
