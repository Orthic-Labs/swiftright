# Full16 R6 F6-reduced failure diagnosis

R6 Count1 smoke reached F6-reduced after 12 prior passes. Archived case:
`probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-full16-smoke-r6-r2/F6-reduced-19aca42aef29472f95c376c4f06007dd`.

Receipt SHA-256 is `5c40cb0780c96fff03ed210135cd5fb0770c229c252f8c99d90cd6c870c1979b`; trace SHA-256 is `ca5f66418ec516e6b9b3518284daef42d0883b9556d0e5555acea71787c95024`. Driver and child both exited 0 with terminal/readable kernel proofs, retained handles, exact R6 driver `0b95be…`, EXE `87b8cb…`, and renderer `7578cd…` joins.

Product trace records `SELFTEST-STAGES F6-reduced:` and `SELFTEST F6-reduced: PASS (11/11 asserted; blocked=0; end=window-closed)`. Worker-v4 builds its expected label as `F6 reduced`, so it rejected only missing literal `SELFTEST-STAGES F6 reduced:` and returned exit 1. This is worker predicate/label mismatch; native semantics, denominator, input, noactivate, process, and cleanup evidence pass.

Isolated successor `matrix-controls-v6` changes only F6/reduced expected label to `F6-reduced`, adds worker-v5 provenance, and offers `F6Reduced` 20-run mode. Full mode remains 16 configurations × 20 runs. Pure controls pass with one wrong-label rejection; root must parse, run targeted 20, then decide broader matrix retry.
