# Tuple12 noactivate matrix candidate

Current retained F1 focus smoke proves native logical focus without desktop foreground: `SELFTEST F1: PASS (17/17)`, `ASSERT F1 focus-stays-row5: PASS`, `ASSERT F1 row5-text: PASS`, `ASSERT F1 ax-focus-delivered: PASS`, Row 5 reaches `Row 5abcd`, targeted delivery has `fg_changes=0`, driver & child exit `0`. UIA provider `HasKeyboardFocus=False` is expected under CBT noactivate veto; old worker rejection of `focus[Row 5]=ok` & `focused_after_focus=[Row 5]` was stale admission logic.

Candidate overlay r3:

- `probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-smoke-v1/drive-fixture-noactivate-focus-r3.ps1`, SHA-256 `ec5e9ce17a9a3f1088ad15f08a15c1c32b7d9af0d45f091a66404d6ab5ef0780`
- manifest `qualification/tuple12-startupguard-focus-overlay-r3.json`, SHA-256 `cf28ab572a743f469c7badcf6067aede0fde51240a5cc5bf4cd6029ab0ded28a`
- frozen base remains SHA-256 `1683b96e2b0e9ac06cf93777d2274d5f4ece9c40092d90799de95b98e77436e9`

Matrix sources:

- `worker.ps1` SHA-256 `a71a960b9db01f05a9d97c2956b86fc6eba7474bb13304577f10887cd7aa9fe9`: generic F1..F9 worker-v2, retained process handles & kernel terminal proof, targeted/noactivate only, `fg_changes=0` admission, native self-test gates; F1 additionally requires 17/17, logical focus, text & AX-focus assertions.
- `coordinator.ps1` SHA-256 `8e45f2d39a1be1d38056dcf54700d07105484852e9c0708c2261b3d414770152`: hidden interactive task, exact lock CAS, no task unregister, lock release only after terminal/quiescent proof.
- `run-matrix.ps1` SHA-256 `d70b32d52c2777204d56a93d6319649c3132ba6fcf6f740a19d8c7644667bb62`: default F1 × 20; `-Mode Full` enables 16 configs × 20 only after admitted smoke; fresh outputs, no retries, no global input; empty `Variant` is omitted so Windows PowerShell cannot shift switches.
- `qualification/tuple12-startupguard-admission.py` SHA-256 `1eccc4bb240a387949d3199f9d8b5ec4c99ff1422ca0ae94576daab679271a8f`: pure trace gate & four in-memory fault controls (missing 17 assertions, wrong node, activation marker, input abort), plus `fg_changes=0`.

Root first runs worker/coordinator once with r3 overlay, then runs admission verifier against retained `driver-trace.txt` with EXE `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374` & renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tuple12-startupguard-matrix-v1\coordinator.ps1 `
  -Base D:\Claude\swiftright\.work\sr0-r12-typecheck\src `
  -Worker .\tuple12-startupguard-matrix-v1\worker.ps1 `
  -Driver .\tuple12-startupguard-smoke-v1\drive-fixture-noactivate-focus-r4.ps1 `
  -Fixture F1 -Variant '' -KeyMode char `
  -ExpectExe 87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374 `
  -ExpectDll 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 `
  -OutRoot D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-smoke-v1\observed-focus-admitted-r3
```

Then matrix runner command from same Dell source stage:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tuple12-startupguard-matrix-v1\run-matrix.ps1 `
  -Base D:\Claude\swiftright\.work\sr0-r12-typecheck\src `
  -Driver .\tuple12-startupguard-smoke-v1\drive-fixture-noactivate-focus-r4.ps1 `
  -Worker .\tuple12-startupguard-matrix-v1\worker.ps1 `
  -Coordinator .\tuple12-startupguard-matrix-v1\coordinator.ps1 `
  -SmokeReceipt D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-smoke-v1\observed-focus-admitted-r3\receipts\worker-<run>.json `
  -ExpectDriver 34d28b1f4cc6a4fccb279639ae767c069a40ae081290ef2b11aebafd52b441b4 `
  -ExpectExe 87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374 `
  -ExpectDll 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 `
  -OutRoot D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-matrix-v1\F1-20
```

Use `-Mode Full` only after F1 receipt passes; it schedules all 16 configs × 20 with same targeted/noactivate overlay. Root must hold interactive desktop lock, verify no SR0 task/process is running, preserve disabled tasks & every output, then attach receipts. Defaults remain frozen driver behavior outside explicit candidate overlay.

Receipt assembler: `qualification/assemble-tuple12-windows-f1.py` SHA-256 `bf5f1673eb63d3d5ba664e0589edf3ad6bed61f69d93eed546f0680eca5ab5b0`. It accepts only absolute source paths, 40-hex source commit, 64-hex source-manifest pin, exact EXE/DLL/driver pins, retained-handle/kernel-terminal proofs, `fg_changes=0`, native F1 17/17 logical assertions, & exactly 20 fresh case receipts. Fewer than 20 returns `status=incomplete`; no all-20 claim is emitted.

F1×20 archive r1 reached 8 passed runs, then run 9 hit transient blank/invalid CIM `ExecutablePath`; worker-v2 threw before its normal wait, leaving driver kernel wait `258`/exit `259`. Historical output remains immutable. Successor `worker-v3.ps1` SHA-256 `8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6` retries blank/invalid path observations, drains driver/child naturally & output streams on every failure path, then re-samples kernel proof without weakening any gate. Pure controls: `qualification/test_tuple12_matrix_worker_controls.py` SHA-256 `0515152ef62f3a0ff3f515c2bc6841e9f2531c31f63ae4948bbf26e17866462c`, positive 9, five mutation rejections.

Fresh F1×20 rerun must pass `worker-v3.ps1` as `-Worker`; preserve failed r1 archive & use new empty output namespace. Existing coordinator, driver, EXE, DLL, source commit, & source-manifest pins remain unchanged.

Coordinator-v3 SHA-256 `4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4`; runner-v3 SHA-256 `f1e4ba0abc704f0173aabc197b91f7b0474d73c503ee4aa61cbda27defd27174`. Coordinator-v3 accepts worker-v2/v3 receipt kinds, requires exact driver/worker source hashes, & emits per-gate `terminalChecks` plus `sourcePins`. Runner-v3 requires exact worker/coordinator hashes, passes driver/worker pins into coordinator, & writes v3 matrix manifests.

Root rerun shape, with fresh empty output:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tuple12-startupguard-matrix-v1\run-matrix-v3.ps1 `
  -Base D:\Claude\swiftright\.work\sr0-r12-typecheck\src `
  -Driver D:\Claude\swiftright\.work\sr0-stage-tools\tuple12-startupguard-matrix-v1\drive-fixture-noactivate-focus-r4.ps1 `
  -Worker D:\Claude\swiftright\.work\sr0-stage-tools\tuple12-startupguard-matrix-v1\worker-v3.ps1 `
  -Coordinator D:\Claude\swiftright\.work\sr0-stage-tools\tuple12-startupguard-matrix-v1\coordinator-v3.ps1 `
  -SmokeReceipt D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-smoke-v1\observed-matrix-smoke-r3\receipts\worker-48f3d8a6d8644416911b89950e4d250f.json `
  -ExpectDriver 34d28b1f4cc6a4fccb279639ae767c069a40ae081290ef2b11aebafd52b441b4 `
  -ExpectWorker 8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6 `
  -ExpectCoordinator 4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4 `
  -ExpectExe 87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374 `
  -ExpectDll 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 `
  -OutRoot D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-matrix-v3\F1-20-r2
```

`qualification/test_tuple12_matrix_v3_controls.py` SHA-256 `cf5b58d15f94fe0e65b77a291bb3a2495c20dcccfe0e7cd1c61456ea657a251f`; controls pass 14 coordinator pins, 8 runner pins, & five mutation rejections.

Retained r2 evidence was tested read-only: observed `1`, passed `0`, status `incomplete`; receipt status was old worker `failed` only because trace lacked new `setfocus_attempt[Row 5]=0 noactivate=True`. In-memory enrichment admitted unchanged native 17/17 trace; mutation controls rejected missing-17, wrong-node, activation, input-abort, & setfocus faults. No retained output was changed.

## r4 foreground observation candidate (2026-10-11)

F1×20-r2 exposed one false `fg_changes` at first targeted sample: `0 -> 395622` (`Claude`), while every targeted key retained identical `fg_before`/`fg_after`, provider focus stayed false under CBT veto, `driver_abort=none`, & native F1 remained 17/17. This is zero-state initialization, not probe focus loss. Frozen r3 remains unchanged. Candidate r4 adds one guarded baseline read after renderer-ready/metrics validation; later transitions stay counted/logged & targeted path still never acquires foreground.

- Driver r4: `probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-smoke-v1/drive-fixture-noactivate-focus-r4.ps1`, SHA-256 `34d28b1f4cc6a4fccb279639ae767c069a40ae081290ef2b11aebafd52b441b4`
- Overlay: `qualification/tuple12-startupguard-focus-overlay-r4.json`, SHA-256 `e94ffe94a9d35e5ca64e8ee75ffb796e94ff808a6a8c90a818e7222a4a05670b`
- Pure controls: `qualification/test_startupguard_driver_r4_controls.py`, SHA-256 `19b1faba69487f6d661be655ff7532ca0dbd16fe4b266412e3a2cf428e95d4d5`, positive 12 & three mutation rejections.

Root must stage r4 into fresh namespace, run parser/source controls, then fresh F1×20; prior r2 raw output remains immutable & cannot combine with successor runs.

## r3 startup identity failure & r5 candidate

Fresh F1×20-r3 stopped on first run. Raw trace proves no UIA/input occurred: `renderer_ready_event=True`, then `WindowMetrics pid=0 client_ok=False window_ok=False same_process=False`; driver logged `no window: UIA root unavailable`; self-test timed out waiting `row5 focused by AX`, child exit `1`, driver exit `0`. This is an invalid/stale HWND admission before semantic execution, not a focus assertion to weaken. Archive is immutable at `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-f1-20-actual-r3`.

Candidate r5 preserves r4 & adds post-ready `Process.MainWindowHandle` refresh, `GetWindowThreadProcessId` owner check, positive `GetClientRect`, explicit PASS/FAIL telemetry, & fail-closed HWND zero/`rendererReadyValid=false` before UIA/input. Driver r5 SHA-256 `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4`; overlay SHA-256 `72932060449ea82d9ff04b2c04dc21a5dcef1c48016cf32454ba9de401774fb6`; controls SHA-256 `d2223b6d43e62d98fc4020f7100b1afcfbbf4d6c1e4381d4009bda8e73d8422e`, PASS positive 12 & three mutation rejections. Root stages & parses r5 before any retry; native gates remain unchanged.

Machine-readable failure review: `qualification/tuple12-startupguard-r3-failure.json`, SHA-256 `1ac91c81a882fc6c890b38074757658fdb56ec7f09ebd088af89794957919990`.


## r5 strict admission & next matrix plan

R5 preserves r4 & rejects stale/invalid HWND state after renderer-ready: owner PID must equal renderer PID, client rect must be positive, & failure zeroes HWND plus `rendererReadyValid` before UIA/input. Driver `drive-fixture-noactivate-focus-r5.ps1` SHA-256 `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4`; overlay SHA-256 `72932060449ea82d9ff04b2c04dc21a5dcef1c48016cf32454ba9de401774fb6`; controls SHA-256 `d2223b6d43e62d98fc4020f7100b1afcfbbf4d6c1e4381d4009bda8e73d8422e`. Windows assembler now requires `renderer_window_revalidate=PASS`, startup `client_ok=True`, & `same_process=True`; pure assembler controls SHA-256 `74102a76229214a9e280124b626714108a2113f21a64834a8cbd02ef921ca566`, positive 1 & six mutation rejections.

Pair v2 pins r5 driver `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4`, worker-v3, coordinator-v3, exact EXE/DLL/source/manifest pins, & same 20 semantic traces per side. Pair v2 source SHA-256 `ef2026d47e2c1e5af552291adab4bd9d1e46d65fbf2aeef83bb95a81c4b01798`; controls SHA-256 `f20b6d046dc7e34f2c95b8a2ef6caefb4096854196530e3a1923934749a1f1f4`, PASS positive 4/four faults. No r5 native result or 20-run claim exists.

## r5 smoke receipt

Root-managed r5 smoke is transport-verified at `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-matrix-smoke-r5`: zip `ad9a3d3cfdd33935c33b49cf075ce3451a99f9eac240cff399d29000d2f708e9`, manifest `ae5e83e29d2dc552cd763fb55440afdd137bcbe04d9c9d91174d341e22fd7114`, receipt `3f29152778018faf32c32a88b323f5f3edeb4942cdbfe7d3f4b63e801b7e6ff4`, trace `15fc1bb79fdea86641564427469ffaecf1103c4e7437505ff45c3c83ec319153`. Receipt has exit 0, retained handles, terminal kernel proof, & lock-free release; trace has post-ready owner/client revalidation PASS, native F1 17/17, targeted `fg_changes=0`, & unchanged logical-focus gates. This smoke is not F1×20 qualification; r5 F1×20-r4 remains pending.

## Actual F1×20-r4 & paired result

Root-managed fresh r4 archive `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-f1-20-actual-r4` passed strict assembly 20/20 with r5 driver, worker-v3, coordinator-v3, EXE `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374`, & renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`. Windows report `windows-f1-report-r4-v3.json` SHA-256 `dd12aa9741db69059a89e828ed2ece441ceff947bca83709aa4db6295ec82aa5`; pure assembler controls passed positive + six fault rejections. Existing qualified Mac F1×20 report `mac-f1-report-r1.json` SHA-256 `bd60e535212ecbcfa6470040c250cfd12229b1da02afe30a993929750ed8c0b9` joined through pair-v2 report `tuple12-f1-paired-report-v2-r1.json` SHA-256 `e58341e1d5371ae062f06572e3445d73efc9619a7a06e5126c102135e93bc320`. Semantic pair status is qualified; cross-platform timing remains observational. Full 16-config matrix & broader tuple12 qualification remain open.
