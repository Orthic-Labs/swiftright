# Tuple12 startupguard matrix controls v4

Source-only successor to frozen matrix v3. Worker v4 binds selftest label to exact fixture+variant (`F3 list-0s`), requires all 16 fixture/variant denominators, stage assertions, native verdict denominator, lifecycle/window/process proofs, & exact artifact joins. Coordinator v4 admits worker v3/v4 for staged transition, uses fixture-qualified task labels, & preserves strict terminal/quiescence cleanup. Runner v4 emits explicit `MATRIX_PASS`, omits empty `-Variant`, & admits only worker v3/v4 receipts.

Known r4 failure fixed at source predicate: trace contained `SELFTEST F3 list-0s: PASS (15/15...)`; worker-v3 required unqualified `SELFTEST F3: PASS`.

Frozen source provenance: base `0e201571e4320a3b6ccce14313fd2ad67e523904`, driver `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4`, WorkloadWin `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374`, renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`.
