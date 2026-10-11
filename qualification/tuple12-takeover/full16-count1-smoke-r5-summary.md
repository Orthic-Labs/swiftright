# Tuple12 Full16 Count1 smoke binding

Status: source/admission record only. Combined Count1 coverage is complete across two root-managed archives; no 16x20 qualification exists.

## Actual archives

- F1 through F6 full cases: `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-full16-smoke-r6-r2`. Twelve cases passed before immutable F6-reduced worker-label failure. Preserve failed receipt `5c40cb0780c96fff03ed210135cd5fb0770c229c252f8c99d90cd6c870c1979b` & trace `ca5f66418ec516e6b9b3518284daef42d0883b9556d0e5555acea71787c95024`.
- F6-reduced, F7, F8, F9: `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-remaining4-r5-r2`. Root reports all four worker receipts passed, lock free, & owned FreshOnBridge processes zero after cleanup. Archive contains `runs/` & `stage/`; transport receipt remains root-owned.

The old F6-reduced failure is not rewritten: product emitted `F6-reduced`, while frozen worker-v4 expected `F6 reduced`. Matrix-v6 worker-v5 changes only that label predicate; native denominator remains 11 & all strict assertions remain.

## Exact source pins for Count1 admission

- base `0e201571e4320a3b6ccce14313fd2ad67e523904`
- EXE `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374`
- renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`
- driver-v6/R6 `0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c`
- worker-v5 `qualification/tuple12-takeover/matrix-controls-v6/worker-v5.ps1`, SHA-256 `b039d4dce888e3dabbb7c3109bcd64abbf2b6313fdc818b4b11398460cdbac39`
- coordinator-v5 `qualification/tuple12-takeover/matrix-controls-v6/coordinator-v5.ps1`, SHA-256 `e85c3c8f57b8e36d0df440bd60a884d28ce516824f8c127b5577345d1f982d6f`
- runner-v6 `qualification/tuple12-takeover/matrix-controls-v6/run-matrix-v6.ps1`, SHA-256 `cdff0f6771d8a380b3919a50f07a4637fc60db2af3df4395b6fa4573d1cbb437`
- strict assembler source `qualification/assemble-tuple12-windows-full-v1.py`, SHA-256 `85d8457b5734c4102e00ff6e2d692d67c63d827a59a84adc12505e3f8d967ec9`
- assembler source-pins `qualification/tuple12-takeover/matrix-assembler-v4/source-pins.json`, SHA-256 `76488365d111e321c063b12dfcc933e58eea9e6ae5a311614a3df5402e5c32ab`
- assembler controls `qualification/test_tuple12_windows_full_assembler_controls.py`, SHA-256 `0bfb3c9e31d341e724ae33a4ad16d834c17efd2d9d040103da00f9fb551f17c3`

Pure source controls to run under root supervision before packet assembly:

```powershell
py -3.11 -I qualification/test_tuple12_matrix_controls_v6_f6_controls.py
py -3.11 -I qualification/test_tuple12_windows_full_v4_controls.py
```

Assembler must bind all 16 configurations × 20 runs = 320 for final qualification. Count1 smoke proves source/driver readiness only; it does not satisfy 20-run denominators, paired Mac20, workload, package, W08, Narrator, or freeze.
