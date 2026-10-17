# SR0 tuple12 qualification handoff

Updated 11 October 2026. F1 background smoke r3 is admitted with native 17/17. F1×20 archive r1 contains 8 passed runs; run 9 hit transient blank/invalid CIM `ExecutablePath`, leaving driver kernel wait `258`/exit `259`; archive remains immutable and no 20-run qualification is claimed. Successor `worker-v3.ps1` (`8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6`) with coordinator-v3 (`4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4`) retries path publication & drains processes before kernel sampling.

## Pinned inputs

- source commit: `0e201571e4320a3b6ccce14313fd2ad67e523904`
- canonical tuple 12 stage commit (17 Oct, sage adjudication): `a9556b77f50315afcae27fc8fc44c0cd274959e2` (base `0e201571` + overlay r2 `0d537b83…`; source manifest `f45b9e0d…`); `--source-commit 0e201571` in the commands below is kept because it ties recorded receipts
- renderer: `7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2`
- RightKit release adopted by source: `@rightkit/release` `0.2.151`
- tuple candidate: `qualification/tuple12-candidate.json`
- last qualified baseline: tuple11; tuple12 candidate binds recovered Cargo.lock `0e28d8bbbb13208c1951341741ec28a66b9c9e74a351708070207d973c478c9c` (181,537 bytes), renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`, fixture `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374`, source manifest `f45b9e0d…`

Candidate JSON has exactly seven members accepted by `qualification/run.py`. Fill it only from reviewed byte-bound binary or sealed run receipts with `qualification/tuple12-fill.py`; helper records source & artifact SHA-256 joins, rejects unsafe paths, & requires fresh source revalidation for every prepopulated member on later invocations. Null hashes or missing source files intentionally fail launcher validation. Controls are archived in `qualification/tuple12-fill-controls-results.json`.

## Root-owned sequence

1. Transfer archived no-delete stage tools to isolated Dell `.work\sr0-stage-tools`; run parser preflight, read-only audit, then fresh tuple12 stage under unique `.work\sr0-r12`. Preserve any partial tree; never delete Dell data.
2. Verify source commit, renderer hash, toolchain paths, and every stage receipt. Build fixture, smoke, package, workload, and native artifacts only after tuple12 stage passes. Bind each receipt to source commit and renderer hash above.
3. Fill seven tuple pins from receipts. Run `qualification/tuple12-run.sh --confirm-windows-gui` with explicit tuple12 workload/native/package paths. Launcher forces `--runs 20 --win-runs 20`; `--dry-run` is available for plan inspection.
4. F1×20 is currently running through source-bound worker-v2/coordinator-v2 after admitted smoke r3. Assemble only after archive fetch with `qualification/assemble-tuple12-windows-f1.py`; then run full 16-config Windows matrix with `RUNS=20` through `qualification/tuple12-windows-matrix.sh`. Root holds `D:\Claude\desktop.lock`, logs first-ready UTC, PID/HWND, `WindowMetrics`, `GetClientRect`, DPI, & verifies same-process HWND through close before releasing lock.
5. Run 20 Windows cross recordings per config with `qualification/tuple12-cross20.sh`; set `BIN`, `EXPECT_EXE`, `EXPECT_RENDERER`, and unique output path. Compare against 20 Mac observations per config from approved tuple12 Mac fixture receipts. Cross config keys are `F1`, `F2`, `F3`, `F3-list-1s`, `F3-list-3s`, `F3-vstack-1s`, `F3-vstack-3s`, `F3-lazy-1s`, `F3-lazy-3s`, `F4`, `F5`, `F6`, `F6-reduced`, `F7`, `F8`, `F9` (16 total; matrix uses its `F3:list-0s` spelling).
6. Re-run native R9 & workload R10 receipt analyzers against tuple12 renderer. W08 remains open until upstream repair-helper proof passes on actual installed release; no limitation acceptance. Required W08 artifact set: RightKit helper source/version/hash & install-registration receipt; clean package old/new hashes; genuine cancellation receipt showing `Modified, NeedsRemediation`; helper command/exit/state-transition receipt; relaunch receipt; data-integrity/legacy-path receipt; final package status & signed-source receipt. Manual Settings Repair or same-version redeploy receipts cannot substitute for upstream helper proof.
7. Freeze stays held until stage, renderer/source binding, matrix, native/workload, package, W08, and 20-per-side comparison receipts all pass. Narrator audio remains human-listen follow-up after automated qualification.

## F1 receipt assembly after archive fetch

Run from Mac or Dell against fetched, immutable F1×20 output root. Command returns `incomplete` until exactly 20 passed receipts; it writes no report unless `--out` is supplied, and output path must be new:

```sh
python3 qualification/assemble-tuple12-windows-f1.py \
  --root /Volumes/D/claude/swiftright/probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-matrix-v1/F1-20 \
  --out /Volumes/D/claude/swiftright/probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-matrix-v1/F1-20-report.json \
  --expected-exe 87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374 \
  --expected-renderer 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 \
  --expected-driver 5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4 \
  --source-commit 0e201571e4320a3b6ccce14313fd2ad67e523904 \
  --source-manifest-sha256 f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca \
  --base-path 'D:\\Claude\\swiftright\\.work\\sr0-r12-typecheck\\src' \
  --driver-path 'D:\\Claude\\swiftright\\.work\\sr0-stage-tools\\tuple12-startupguard-matrix-v1\\drive-fixture-noactivate-focus-r5.ps1' \
  --worker-path 'D:\\Claude\\swiftright\\.work\\sr0-stage-tools\\tuple12-startupguard-matrix-v1\\worker-v3.ps1' \
  --coordinator-path 'D:\\Claude\\swiftright\\.work\\sr0-stage-tools\\tuple12-startupguard-matrix-v1\\coordinator-v3.ps1' \
  --fault-controls
```

If root archives under another fresh namespace, change only `--root` & preserve receipt paths/hashes. Do not rename cases, fill missing receipts, or reuse prior r1/r2 output.

## Safe command shapes

```sh
# plan only; no Dell effect
qualification/tuple12-run.sh --dry-run --stages mac-oracle win-replay compare workload native smoke package

# Windows matrix, root supplies reviewed values
BASE_DIR='D:\Claude\swiftright\.work\sr0-r12\src' \
EXPECT_EXE_SHA256='<tuple12 FreshOnBridge sha256>' \
EXPECT_DLL_SHA256='7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2' \
OUT_DIR='qualification/out/tuple12-windows-20' \
qualification/tuple12-windows-matrix.sh

# cross recordings, root holds D:\Claude\desktop.lock
BIN='D:\Claude\swiftright\.work\sr0-r12\src\scratch\out\Products\Release-windows-x86_64' \
EXPECT_EXE='<tuple12 FreshOnBridge sha256>' \
EXPECT_RENDERER='7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2' \
qualification/tuple12-cross20.sh qualification/out/tuple12-cross-20
```

These wrappers are prepared only. Root serializes remote Windows, native, GUI, signing, and desktop-lock execution.

## Strict Full-16 Windows assembler (source plan)

`qualification/assemble-tuple12-windows-full-v1.py` is read-only & admits exactly 16 declared fixture/variant groups × 20 runs = 320 cases. It joins each `matrix-run.json` to one worker receipt & one driver trace, requires `mode=Full`, exact r5/worker-v3/coordinator-v3/EXE/DLL pins, retained handles plus terminal kernel proofs, startup owner/client checks, targeted `fg_changes=0`, noactivate ordering, fixture-native `SELFTEST-STAGES`/assertions, & exact native denominators: F1 17, F2 13, F3 variants 15, F4 12, F5 13, F6 16, F6-reduced 11, F7 20, F8 15, F9 11. Missing, duplicate, unknown, symlinked, stale, or failed case leaves report `incomplete`; no partial result is promoted.

Assembler SHA-256 `85d8457b5734c4102e00ff6e2d692d67c63d827a59a84adc12505e3f8d967ec9`. Pure controls: `qualification/test_tuple12_windows_full_assembler_controls.py` SHA-256 `0bfb3c9e31d341e724ae33a4ad16d834c17efd2d9d040103da00f9fb551f17c3`, positive 1 + six mutation rejections. Run after root fetches fresh Full output:

```sh
python3 qualification/assemble-tuple12-windows-full-v1.py \
  --root /Volumes/D/claude/swiftright/probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-matrix-v1/Full-16-r5 \
  --out /Volumes/D/claude/swiftright/probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-matrix-v1/Full-16-r5-report.json \
  --expected-exe 87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374 \
  --expected-renderer 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 \
  --expected-driver 5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4 \
  --expected-worker 8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6 \
  --expected-coordinator 4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4 \
  --source-commit 0e201571e4320a3b6ccce14313fd2ad67e523904 \
  --source-manifest-sha256 f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca \
  --base-path 'D:\\Claude\\swiftright\\.work\\sr0-r12-typecheck\\src' \
  --driver-path 'D:\\Claude\\swiftright\\.work\\sr0-stage-tools\\tuple12-startupguard-matrix-v1\\drive-fixture-noactivate-focus-r5.ps1' \
  --worker-path 'D:\\Claude\\swiftright\\.work\\sr0-stage-tools\\tuple12-startupguard-matrix-v1\\worker-v3.ps1' \
  --coordinator-path 'D:\\Claude\\swiftright\\.work\\sr0-stage-tools\\tuple12-startupguard-matrix-v1\\coordinator-v3.ps1'
```

## Closure split

Computable close jobs: tuple12 stage/audit, source/header/hash binding, 16-config matrix, native R9, workload R10, package receipts, W08 helper proof, 20 Mac + 20 Windows cross traces/config, comparator controls, and manifest/freeze receipts. Human-only follow-up: listen to retained Narrator speech recordings on qualified tuple12 package, record listener/date/verdict, then attach receipt; it cannot turn failed automated gates green.

## Strict F1 Mac/Windows pairing

After fresh Windows F1×20-r4 fetch (using r5 driver), assemble each side independently, then run pure pair join:

```sh
python3 qualification/assemble-tuple12-f1-paired-v2.py \
  --mac-report /path/to/mac-f1-report.json \
  --windows-report /path/to/windows-f1-report.json \
  --mac-root /path/to/actual-mac20/F1 \
  --windows-root /path/to/F1-20-r3 \
  --out /path/to/f1-paired-report.json
```

Pair assembler v2 requires both reports `qualified` at exactly 20/20, exact source `0e201571e4320a3b6ccce14313fd2ad67e523904`, product/fixture/recorder/assembler identities, Windows r5 driver `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4`, post-ready `renderer_window_revalidate=PASS`, `client_ok=True`, & `same_process=True`, worker-v3 `8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6`, coordinator-v3 `4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4`, & 20 semantic traces per side. Timing remains observational: Mac monotonic timestamps, Windows UTC/start/end timestamps, & host scheduling latency are retained separately & never normalized into semantic admission.

Historical r4 pair assembler SHA-256 `76f9ac926a4af276c126931d8b0e5c23ccb9a9d50fa11297942ea4521f74511d`; r5 pair-v2 SHA-256 `ef2026d47e2c1e5af552291adab4bd9d1e46d65fbf2aeef83bb95a81c4b01798`; r5 controls SHA-256 `f20b6d046dc7e34f2c95b8a2ef6caefb4096854196530e3a1923934749a1f1f4`, positive 4 & four mutation rejections.


## Current r5 F1 qualification commands (source plan; no result claim)

After root verifies fresh r5 archive, assemble exactly 20 F1 runs with current renderer/EXE pins:

```sh
python3 qualification/assemble-tuple12-windows-f1.py \
  --root /Volumes/D/claude/swiftright/probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-matrix-v1/F1-20-r4 \
  --out /Volumes/D/claude/swiftright/probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-matrix-v1/F1-20-r4-report.json \
  --expected-exe 87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374 \
  --expected-renderer 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 \
  --expected-driver 5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4 \
  --source-commit 0e201571e4320a3b6ccce14313fd2ad67e523904 \
  --source-manifest-sha256 f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca \
  --base-path 'D:\\Claude\\swiftright\\.work\\sr0-r12-typecheck\\src' \
  --driver-path 'D:\\Claude\\swiftright\\.work\\sr0-stage-tools\\tuple12-startupguard-matrix-v1\\drive-fixture-noactivate-focus-r5.ps1' \
  --worker-path 'D:\\Claude\\swiftright\\.work\\sr0-stage-tools\\tuple12-startupguard-matrix-v1\\worker-v3.ps1' \
  --coordinator-path 'D:\\Claude\\swiftright\\.work\\sr0-stage-tools\\tuple12-startupguard-matrix-v1\\coordinator-v3.ps1' \
  --fault-controls
```

Run full 16-config Windows matrix only after F1 report is `qualified`; root uses fresh output & same r5 source pins:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tuple12-startupguard-matrix-v1\run-matrix-v3.ps1 `
  -Base D:\Claude\swiftright\.work\sr0-r12-typecheck\src `
  -Driver D:\Claude\swiftright\.work\sr0-stage-tools\tuple12-startupguard-matrix-v1\drive-fixture-noactivate-focus-r5.ps1 `
  -Worker D:\Claude\swiftright\.work\sr0-stage-tools\tuple12-startupguard-matrix-v1\worker-v3.ps1 `
  -Coordinator D:\Claude\swiftright\.work\sr0-stage-tools\tuple12-startupguard-matrix-v1\coordinator-v3.ps1 `
  -ExpectDriver 5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4 `
  -ExpectWorker 8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6 `
  -ExpectCoordinator 4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4 `
  -SmokeReceipt D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-smoke-v1\observed-matrix-smoke-r5\receipts\worker-8063b657c12442619659f73164264582.json `
  -ExpectExe 87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374 `
  -ExpectDll 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 `
  -Mode Full -Runs 20 `
  -OutRoot D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-matrix-v1\Full-16-r4
```

These commands are prepared for root-managed Dell execution. Existing r3/r4 archives stay immutable; no prior runs combine with r5.

## r5 smoke admission evidence

Root-managed r5 smoke is transport-verified at `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-matrix-smoke-r5`: zip SHA-256 `ad9a3d3cfdd33935c33b49cf075ce3451a99f9eac240cff399d29000d2f708e9`, manifest SHA-256 `ae5e83e29d2dc552cd763fb55440afdd137bcbe04d9c9d91174d341e22fd7114`, receipt SHA-256 `3f29152778018faf32c32a88b323f5f3edeb4942cdbfe7d3f4b63e801b7e6ff4`, & trace SHA-256 `15fc1bb79fdea86641564427469ffaecf1103c4e7437505ff45c3c83ec319153`. Receipt proves worker/driver/child exit 0, retained handles, terminal kernel proof, exact EXE/DLL/r5-driver hashes, & lock-free release; trace proves post-ready owner/client revalidation, native F1 17/17, targeted `fg_changes=0`, & logical-focus assertions. Root has launched fresh F1×20-r4 with same r5 pins; no 20-run result claim exists.
