# Tuple12 takeover ledger

Updated 11 October 2026. This ledger records tuple12 source/readiness plus sealed F1×20 semantic evidence; full tuple12 qualification remains open.

## Pinned candidate

| Item | Current pin/state | Evidence or next gate |
|---|---|---|
| Source | `0e201571e4320a3b6ccce14313fd2ad67e523904` | 91-file source manifest `f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca` |
| RightKit | `@rightkit/release 0.2.151` | installed release has no accepted W08 helper proof |
| Renderer | DLL `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`, 11,887,616 bytes | recovered with Cargo `--jobs 1`; closure receipt `status-jobs1-r3.stdout.bin` |
| Fixture | `FreshOnBridge.exe` `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374`, 4,758,016 bytes | source-bound build r4 PASS |
| Cargo.lock | `0e28d8bbbb13208c1951341741ec28a66b9c9e74a351708070207d973c478c9c`, 181,537 bytes | recovered closure artifact |
| StartupGuard | r5 driver `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4` | post-ready owner PID/client revalidation; fail-closed HWND |
| Smoke | r5 receipt exit 0, native F1 17/17, lock free | `observed-matrix-smoke-r5`; no F1×20 claim |
| F1 Windows | qualified 20/20 fresh r4 | `windows-f1-report-r4-v3.json`, SHA `dd12aa9741db69059a89e828ed2ece441ceff947bca83709aa4db6295ec82aa5` |
| Mac F1 | qualified existing 20-run packet | `mac-f1-report-r1.json`, SHA `bd60e535212ecbcfa6470040c250cfd12229b1da02afe30a993929750ed8c0b9`; signed recorder is F1-only |

`qualification/tuple12-candidate.json` now carries recovered renderer pin at top level, while seven member hashes remain null until byte-bound receipts are supplied. `qualification/tuple12-fill.py` now rejects any populated `windows_renderer` member whose bytes disagree with top-level renderer pin; positive/fault controls pass, including this join. Candidate SHA-256: `3ca472267702ff2dc5b739885e96accda9c17d82f8058411a5f91e988387d666`.

## Automatable closure

1. Fetch & verify F1 Windows r4 archive; run `qualification/assemble-tuple12-windows-f1.py` with r5 driver, EXE/DLL/source/manifest pins. Require `status=qualified`, 20/20, retained handles, terminal kernel proofs, startup owner/client markers, native 17/17, targeted `fg_changes=0`.
2. Run full 16-config Windows matrix with `run-matrix-v3.ps1`, r5 driver, worker-v3 `8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6`, coordinator-v3 `4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4`, `Runs=20`, fresh output.
3. Build tuple12 WorkloadWin against renderer `7578cd5d…`; run three R10 runs & analyze. Existing E280 workload receipt is historical & cannot bind tuple12.
4. Run tuple12 native preflight/static checks, then IME F7/F7live/F8 & Narrator automatable checks. Existing tuple11 receipts are historical & cannot bind tuple12.
5. Produce tuple12 MSIX/DMG artifacts & sealed package run receipts; fill seven candidate members through `qualification/tuple12-fill.py`, revalidating every prepopulated member source.
6. F1 pair-v2 is qualified: `probes/sr0-s/fresh-on-bridge/out/tuple12-f1-paired-report-v2-r1.json`, SHA `e58341e1d5371ae062f06572e3445d73efc9619a7a06e5126c102135e93bc320`; timing remains observational. Full 16-config 20-per-side comparison remains open; run comparator/fault controls & manifest joins after matrix.

## Exact root-managed commands

F1 report & Full-16 command are in `docs/sr0-tuple12-qualification.md` §Current r5 F1 qualification commands. Source pins for both:

```text
EXE 87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374
DLL 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2
DRIVER 5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4
WORKER 8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6
COORDINATOR 4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4
```

After source-bound WorkloadWin build is installed in `BASE`, root runs from interactive Dell session:

```powershell
$BASE = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$BASE\probes\sr0-b\workload\scripts\run-workload.ps1" `
  -Base $BASE -Runs 3 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 -NoActivate `
  -Tag tuple12-r10-full -ExpectDll 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2
```

After staging native scripts into same `BASE`, root reserves desktop lane & runs:

```sh
BASE_DIR='D:\\Claude\\swiftright\\.work\\sr0-r12-typecheck\\src' \
EXPECT_EXE_SHA256='87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374' \
EXPECT_DLL_SHA256='7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2' \
DESKTOP_LANE_FREE=1 TAG=tuple12-r9 \
sh probes/sr0-b/native-interaction/scripts/run-native.sh ime-f7 ime-f7live ime-f8 narrator
```

After package harness writes fresh sealed run directories & candidate members are filled:

```sh
TUPLE=qualification/tuple12-candidate.json \
qualification/tuple12-run.sh --confirm-windows-gui \
  --stages workload native package \
  --workload-windows probes/sr0-b/workload/results/r10-tuple12-renderer7578-windows.txt \
  --workload-mac probes/sr0-b/workload/results/r10-20261010-mac.txt \
  --native-dir probes/sr0-b/native-interaction/out \
  --native-tag tuple12-r9 \
  --package-receipts qualification/receipts/package/tuple12
```

Use `--dry-run` first for closure-plan validation. Root owns Dell desktop lock, scheduled tasks, native input, workload, package signing & all remote effects.

## F1×20 paired semantic result

Strict source-bound assembly passed 20 Mac + 20 Windows F1 runs. Windows report: `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/windows-f1-report-r4-v3.json` (SHA-256 `dd12aa9741db69059a89e828ed2ece441ceff947bca83709aa4db6295ec82aa5`). Mac report: `probes/sr0-s/fresh-on-bridge/out/tuple12-mac-preflight-takeover-v1/mac-f1-report-r1.json` (SHA-256 `bd60e535212ecbcfa6470040c250cfd12229b1da02afe30a993929750ed8c0b9`). Pair report: `probes/sr0-s/fresh-on-bridge/out/tuple12-f1-paired-report-v2-r1.json` (SHA-256 `e58341e1d5371ae062f06572e3445d73efc9619a7a06e5126c102135e93bc320`). Source is `0e201571e4320a3b6ccce14313fd2ad67e523904`; EXE/DLL/r5 driver/worker-v3/coordinator-v3 joins pass; timing remains observational.

## Workload source closure

Source-only plan: `docs/sr0-tuple12-workload-plan.md`. Manifest `qualification/tuple12-workload-source-manifest.json` SHA-256 `a780e651a1506fde772453548fd4defb4831731588c00e8772c224e47696cf28`; generator `qualification/prepare-tuple12-workload-source.py` SHA-256 `77b046b19a4087f253ac531f946d560e2b999ed1b7d1a56094cf14ffeab2268b`; run-workload overlay patch `qualification/tuple12-workload-run-overlay.patch` SHA-256 `64f07966b59ccada882f64c2e84b02d559fa7fea7e48478ece320b4b5b53ea72`; background overlay patch `qualification/tuple12-workload-background-overlay.patch` SHA-256 `94eb787802dc3e8864b54ba537b834db2cfa2bb5f671a8e737bb9699147ff83f`; WorkloadWin CBT overlay `qualification/tuple12-workload-startupguard-overlay.json` SHA-256 `87bce39cc049e7a14eadf0a756fb208b4cda56e6f0108332cbed9f97a3c537e0`; startupguard controls `qualification/test_tuple12_workload_startupguard_controls.py` SHA-256 `dd9cf75d44dbda58e0aa1e8cbb9d4d7dbfacffa556dafc6ff49f82fb3c6d215d` PASS positive + 5 mutation faults; overlay controls `qualification/test_tuple12_workload_overlay_controls.py` SHA-256 `c4e32da509fe6b60bf5581aacfe0fa224d0f110986cc6b742c0c7fedef3248e5` PASS positive + 4 background + 3 orchestrator mutation faults. Closure pins source `0e201571…`, renderer `7578cd5d…`, WorkloadWin build `--jobs 1`; workload policy remains 3 timed runs/configuration, while paired comparison remains 20 per side. Overlay records post-HWND `HWND_BOTTOM`/`SWP_NOACTIVATE` & retains targeted `WM_CHAR`/QPC/resource metrics; CBT guard now provides source-bound pre-HWND activation/focus veto during full `bridge.run`.

## Holds

- **W08:** external RightKit repair-helper proof required: install-registration, genuine cancellation to `Modified, NeedsRemediation`, helper command/state transition, relaunch, data-integrity, legacy-path & final signed-source receipts. Current release availability is not proof.
- **Mac full16:** held on generalized recorder with same Team/signature & process-level no-prompt signing proof. Existing trusted F1 recorder supports F1 packet only; no permission prompt may be introduced.
- **Narrator speech:** human listening remains after automated qualification; automated provider checks do not close speech-content item.
- **Freeze:** held until tuple12 stage/source binding, renderer, F1/full16, native, workload, package, W08 & 20-per-side comparison receipts pass.

## Full-16 Windows assembler

Source-only strict assembler `qualification/assemble-tuple12-windows-full-v1.py` SHA-256 `85d8457b5734c4102e00ff6e2d692d67c63d827a59a84adc12505e3f8d967ec9`; controls `qualification/test_tuple12_windows_full_assembler_controls.py` SHA-256 `0bfb3c9e31d341e724ae33a4ad16d834c17efd2d9d040103da00f9fb551f17c3`, PASS positive + six faults. It admits only exact 16 fixture/variant groups × 20 runs, `mode=Full`, r5/worker-v3/coordinator-v3/EXE/DLL joins, retained-handle/kernel proofs, noactivate telemetry, & native denominator/assertion lines. Full output is not yet present; no matrix result claim exists.

## Workload coordinator v1 source candidate

`qualification/tuple12-takeover/workload-coordinator-v1/workload-coordinator.ps1` SHA-256 `19e6da864f2d35919cb72ae93bcaf156d60f4ad40d0f1a65f4fab1ba1532d83d`; controls `qualification/test_tuple12_workload_coordinator_controls.py` pass positive + eight mutation faults. It binds stage `.work\\sr0-r12-workload-v1`, controls-v3, explicit analysis source, EXE `7e749248…`, renderer `7578cd5d…`, 3×(10 s warmup + 60 s measured), 200 rows, 10 keys/s, `-NoActivate`, & `-LifecycleProof`. Root must parse/build.json-hash-gate before native execution; no Workload result exists yet.

Mac signing hold remains explicit: observed `actualSessionCreate100001` pre-signing state is required evidence before any generalized recorder signing. Existing trusted F1 recorder remains F1-only; no prompt route is admitted. This hold does not close any general SR0 stage.

## 2026-10-11 Full16 r4 & Workload lifecycle source successors

Full16 r4 archive review is recorded in `qualification/tuple12-takeover/full16-r4-diagnosis.md`: transport verified 367 files, all 40 case receipts individually passed, outer stdout has 40 PASS lines but no MATRIX_PASS, outer stderr has unbound generic F1 semantic failure with no variant/receipt. Full16 remains unsealed.

Prepared source-only workload lifecycle v4 in `qualification/tuple12-takeover/workload-controls-v4` while preserving v3. v4 requires sampler aggregate proof initialized true then cleared on start/terminal/drain fault, retains sampler handle, drains/writes sampler stdout+stderr, emits per-run stream-drain records, & proves PresentMon native handle terminal with kernel/.NET exit equality. Controls pass positive + 6 mutation faults. Pins: run `43c3b1b34a90a4802c71e572b654b07a9f6a5a8b0f0ff9a73eb44998b96e5e04`, task `d9b8eff89832768bf808ec0a8db5c988a3639425fe9727c14fff4c0377d99615`, controls `170281de0810f1a40872a790daf3d2d1533ad5b36f3fd636c37a229c93dcbd76`.

Prepared coordinator v2 in `qualification/tuple12-takeover/workload-coordinator-v2`, fixing malformed PowerShell argument formatting & requiring exact 3-run terminal/drain records plus one PresentMon session terminal/drain record before lock release. Controls pass positive + 6 mutation faults. Pins: source `899ed3d008bd00df368a0804c57f4092fbcc2b8e33cd704b120fa86fb5e59666`, controls `f3074c654115bd249a6a477bca9a5d40f2c81e80cdeceeb95fdbe0757c9b8008`. Root must parse & headless-test before native use.

Correction: Full16 r4 contains 41 worker receipts, not 40. Forty F1/F2 cases passed; F3 `list-0s` failed worker-v3 predicate only: raw trace SHA `803de9af633d59138db714019ed60858bf6aa4072780eb420e9e29009f839695` emits qualified `SELFTEST F3 list-0s: PASS (15/15...)`, while worker required unqualified `SELFTEST F3: PASS`. Driver/child exits & kernel cleanup passed. Matrix v4 source successor under `qualification/tuple12-takeover/matrix-controls-v4` binds exact fixture+variant labels & all 16 denominators; controls PASS positive + 6 faults.

Coordinator v2 cleanup policy now releases lock after own orchestrator terminal + streams drained + task quiescent + PresentMon terminal/session proof, even when one of three semantic run records fails; semantic receipt remains failed. Three-run proof is still required for `passed` status.

## 2026-10-11 Full16 R6 F6-reduced correction

R6 Count1 archive `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-full16-smoke-r6-r2` reached 12 passing cases, then F6-reduced failed only at worker label admission. Product emitted `SELFTEST-STAGES F6-reduced:` and `SELFTEST F6-reduced: PASS (11/11...)`; worker-v4 required the space form. Driver/child both exited 0 with exact R6/EXE/renderer pins & retained terminal kernel proofs. Frozen receipt SHA is `5c40cb0780c96fff03ed210135cd5fb0770c229c252f8c99d90cd6c870c1979b`; trace SHA is `ca5f66418ec516e6b9b3518284daef42d0883b9556d0e5555acea71787c95024`.

Isolated matrix-v6 worker-v5/coordinator-v5/runner-v6 corrects this product-label join only. Pure controls pass. Strict assembler v4 binds matrix-v6 & R6 driver while preserving 16 configurations × 20 runs = 320 & native denominator F6-reduced 11. Root must parse/typecheck & run fresh F6-reduced/F7/F8/F9 checks; no qualification claim exists.

W08 upstream repair-helper, generalized Mac signer no-prompt proof, later Narrator listening, & freeze approval remain open. Workload v7/co6 source remains frozen pending root native qualification.

## 2026-10-11 Workload v7 actual receipt & strict source successors

Observed archive `probes/sr0-b/workload/out/tuple12-source-build-v1/observed-workload-r10-v7-r1` is transport-verified (zip SHA `9627d71189c8fde642cd3b3bb7e320bb3918842efacfed1d0782df6ef6ab1bcd`, 92 files, no native actions, no deletion). Coordinator receipt SHA `29e0a8570d92198e171f405da47e63c777f414ab490e6d7f3d0f12627b261887` is `failed`, but records `orchestratorTerminal=true`, `orchestratorExit=2`, `streamsDrained=true`, `taskQuiescent=true`, `runProof=true`, `semanticRunProof=true`, `presentMonProof=true`, `presentMonSessionAbsent=true`, `cleanupProof=true`, 3 workers, 3 samplers, `lockReleased=true`, & `lifecycleProof=false`.

Raw workload semantics are not admitted: report SHA `6dd39043ea673bc54a18264d994bedbfab5992347da20058f4df18bdac93b61d` is `INCOMPLETE`. Evidence has three valid app runs, but analyzer source rejected v7 `pid ... handle=... start_utc=...` lines, so each PID/QPC join became `pid=None`; CSV contains real WorkloadWin rows (r1 PID 47488 confirmed). Run also lacks analyzer-required `presentmon.console.txt`, build receipt lacks `configuration=release`, & `incremental.json` is absent. Analysis additionally records genuine r2 W2/W6 threshold failures; no gate was relaxed.

Prepared immutable source successors: workload controls v8 `qualification/tuple12-takeover/workload-controls-v8/source-pins.json` SHA `bf494d8d7ba96444041a95a6b39a675af18ed3889a85ad9ed59897d8699ebcdd`, run script SHA `4fbb5774e8c62bee0ff387b2a5d1c537f7ea2b089676ce780435bf55afe8268d`; analyzer v2 `qualification/tuple12-takeover/workload-analysis-v2/source-pins.json` SHA `4ff991cd2cd2b63d747a066750be9d16c66267e28d429d5932ef7524e5e604f6`, analyzer SHA `c122ad43f7ffc0523ccc6898e13f4810ae9af0908f123922f7505e4449c5285b`. v8 writes joined PresentMon console after bounded drains & binds `Base\incremental.json` explicitly; v2 accepts only positive retained handle or legacy PID form. Pure controls `qualification/test_tuple12_workload_v8_controls.py` SHA `ca4d2aac72a243e887943d5c1760ea5bcc7b53aa15eccf6c606e74eaecdc2eb7` passed supervised exit 0. Root must parser/typecheck, provide release build metadata & genuine incremental receipt, then run fresh native workload; no qualification claim exists.

Post-v2 read-only replay of preserved v7 packet (supervised exit 2, output outside archive) proves PID parser repair only: C rows become 3599/3356/3601, but displayed rows are 52/62/56, so each run remains invalid under strict display gate; QPC calibration p95 is 983.0526/983.2905/983.1207 ms against 2 ms. r2 W2 p95/p99 and W6 p99 also fail. This is genuine background/noactivate capture evidence, not parser noise; no assertion was weakened and no qualification claim exists. Root must decide source-bound workload presentation policy while preserving noactivate & display/calibration gates.

Prepared scoped workload assembler `qualification/assemble-tuple12-workload-v1.py` SHA `434d45c28a8fb5714cc259662b05f165e8b7cba7e095f07467a3e36b7ba78afd`; pins `qualification/tuple12-takeover/workload-assembler-v1/source-pins.json`. It hashes explicit receipt/result/orchestrator/build/report/console/CSV members, requires coordinator v5 status `passed`, exit 0, all lifecycle/cleanup/PresentMon proofs, 3 workers/samplers, release build metadata, exact EXE/DLL, report `PASS` with no refusal reasons, & three-run/noactivate result lines. Supervised assembly of preserved v7 packet correctly returned `incomplete` (exit 1); output was written outside archive. Root may rerun against fresh v8 packet only after release + incremental metadata & strict native gates pass.

## 2026-10-11 v7 clock calibration & incremental source recipe

Read-only supervised replay of preserved v7 packet with analyzer v3 is source-valid for PID joins & clock calibration: report ` .factory-work/sr0-v7-v3-analysis-r1/report/report.json` was emitted outside archived inputs, SHA-256 `b42a77b9ec5604df6e51b13ac96733e721422dc341ad2f08acb77d15215b3aa2`. Captured WorkloadWin rows are 3599, 3356, 3601; calibration p95 is 0.1173, 0.1595, 0.1063 ms. Display eligibility remains strict at 52, 62, 56 rows; r2 W2/W6 remain failed. Independent r1 calculation found 4201/3,356/4,201 captured starts with all-start calibration p95 below 0.2 ms, while displayed-only calibration was about 983 ms; this confirms sparse displayed rows caused 983 ms calibration, not timestamp-unit error. No gate or displayed evidence was relaxed. Analyzer v3 `qualification/tuple12-takeover/workload-analysis-v3/analyze_workload.py` SHA-256 `35330066332c30e96d5e3a6232a0188889760ad73b7d4c04f1d9fb9f178b535a`; controls `qualification/test_tuple12_workload_analysis_v3_controls.py` SHA-256 `a846bbafa63168048069abd55ce444d14f7dc123e87aaab6786170a6caf3d4d2` passed supervised exit 0. The preserved v7 packet remains incomplete.

Incremental source-build recipe `qualification/tuple12-takeover/workload-v7-incremental-recipe.md` SHA-256 `9e2fcae269a66eb6743fa3e89319c1e3eb1e1c757af27c5847c675ea29ae7483` binds source commit `0e201571…`, 54-file materialized source manifest `26705e8f…`, WorkloadWin `7e749248…`, renderer `7578cd5d…`, v8 controls, analyzer v3, & strict assembler. It records a concrete path mismatch in legacy `build-incremental.ps1` (`Base\probes` versus tuple12 `Stage\src\probes`) & refuses silent invocation; root must review/pin tuple12 adaptation with separate stage/source roots, three edits, Rust shim total 0, byte-identical renderer/exe, & fresh `incremental.json` before workload. v8 coordinator command is source-only here; no new native result exists.

## 2026-10-11 Full16 Count1 smoke completion

Root-managed Count1 smoke now covers all 16 configurations across preserved `observed-full16-smoke-r6-r2` (first 12 cases) & `observed-remaining4-r5-r2` (F6-reduced/F7/F8/F9; four worker receipts passed, lock free, owned FreshOnBridge processes zero). Frozen earlier F6-reduced worker-label failure remains immutable; product emitted `F6-reduced`, while old worker expected `F6 reduced`. Source-only binding & exact hashes are recorded in `qualification/tuple12-takeover/full16-count1-smoke-r5-summary.md` (SHA-256 `83748f753d7b3df6543d78c62a5797df5de1f61f60a77c737b155767e14cd096`). Matrix-v6 worker-v5 changes only this label predicate; denominator remains 11 & strict native/process/handle/kernel/drain proofs remain. Count1 does not qualify full16: 20 runs per each of 16 configurations (320), paired Mac20, workload, package, W08, Narrator & freeze remain open.

## 2026-10-11 tuple12 incremental adapter v1

Added source-only tuple12 adapter under `qualification/tuple12-takeover/workload-incremental-v1/`. Adapter `build-incremental-tuple12.ps1` SHA-256 `31fdb6ccaf066d53ff0d90ea78fe3657e1e5db274e56ba2ec1c6a820b83fdc28` binds exact 54-file source manifest `26705e8f…`, source `0e201571…`, release WorkloadWin `7e749248…`, renderer `7578cd5d…`, Swift 6.4 Asserts path/hash, `--jobs 1`, & three genuine `WorkloadScreen.swift` edits. It retains original compiler handles before waits, kernel wait/GetExitCodeProcess, .NET exit, stdout/stderr drains, Rust shim count, owned run namespace, source restoration, & byte identity of owned EXE/DLL. It has no lock, GUI, task, native input, deletion, or global process control. Pure controls SHA-256 `a23e3349961b4a74bca7fa3fce31015ac7ea404c8f2a2717bd4c73dfe4d717b5` passed supervised exit 0 with seven mutation faults.

Release metadata derivation `derive-release-metadata.ps1` SHA-256 `345ad21ae9b5055eed479316d8dbb2fc0886dcb440c1ec6e99d2b535d54e201f` accepts original sealed receipt only when argv proves `build --jobs 1 -c release --product WorkloadWin`, exit 0, 54 verified files, retained compiler handle, manifest verifier success, zero native/lock actions, & exact executable/DLL hashes. It emits `configuration=release` as receipt-derived metadata; no field is fabricated. Root must parse & run on Dell; no compiler result exists for adapter v1.

## 2026-10-11 v7 display-row diagnosis & incremental adapter source

The v7 packet has 3599+ captured WorkloadWin starts per run but only 52/62/56 displayed rows. With `background_noactivate=PASS` & `HWND_BOTTOM`, this is consistent with PresentMon dropped/occluded presentation under background desktop policy; it is not evidence that timestamps use wrong units. Raw v7 also records r2 foreground events (`CutRight`, `MailRight`) & W2/W6 failures, so foreground ownership/desktop contention remains an observational cause to disconfirm. Display gate stays strict. Read-only probe `qualification/tuple12-takeover/workload-analysis-v3/display-context.ps1` SHA-256 `7c47dcea44b88162ce4d1f0fab6deb72e42ccd0cde196f46b3fabdd50009c631` captures target HWND/client/work-area/foreground/session facts with CreateNew output, no input/window mutation; pure controls SHA-256 `70c0e6ac320beb6c34ec4e2b91c392047b5ae7f520f0271684cad3b53044218c` passed supervised exit 0.

Tuple12 incremental adapter v1 is now source-ready under `qualification/tuple12-takeover/workload-incremental-v1/`: adapter SHA `31fdb6ccaf066d53ff0d90ea78fe3657e1e5db274e56ba2ec1c6a820b83fdc28`, release derivation SHA `345ad21ae9b5055eed479316d8dbb2fc0886dcb440c1ec6e99d2b535d54e201f`, pure controls SHA `a23e3349961b4a74bca7fa3fce31015ac7ea404c8f2a2717bd4c73dfe4d717b5`. Root must parse then run adapter on Dell with exact 54-file source/build receipt; no compiler effect or incremental qualification exists yet.

## 2026-10-11 tuple12 incremental adapter v2

v1 remains immutable. v2 successor: `qualification/tuple12-takeover/workload-incremental-v2/`; adapter `bcd7a0ae2ef9e7a2983eb2158b8a4a2f27ae878819b8452af9de91318442e5ad`, deriver `c7945c1fc4e01f48ce65ce92a0bf5fda2373a5c6aa7e5bd27f1a54c93391d8c4`, controls `e7b3a4a2e0bffedad9a24d2f3822d05f2dde0daca00a1fefd11e2b21b0ef15b6`. Deriver joins sealed build receipt `14789302c49ca5a1ebd405715a12006f5eb249913cf524b6fa754581fabbb579`, source commit `0e201571e4320a3b6ccce14313fd2ad67e523904`, source manifest `26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468`, plan manifest `a780e651a1506fde772453548fd4defb4831731588c00e8772c224e47696cf28`, exact release argv, 54 verified files, materialized `files` array length 54, `sourceFiles` count 42, three patches, `SwiftRightBridge` import, & hold-build-native state.

Adapter measures three genuine UI-only edits with shim count before compiler start & after terminal/drain, exact total shim lines, one-second kernel polling, 900-second deadline, 1 GiB job cap, bounded stdout/stderr/shim logs, owned compiler descendants, kernel/.NET exit, bounded drains before restoration, compiled-manifest file/hash joins, source/artifact restoration, & CreateNew outputs. Receipt uses `final_noop_identity_check=false` & `artifact_restoration_only=true`; it makes no final restored-source build claim. Controls passed supervised exit 0 with owned no-op count/timeout/drain exercises & nine mutation faults (`.factory-work/sr0-incremental-v2-controls-r5`). No v2 compiler/native result exists; root parse/build/run remains pending.

## 2026-10-11 tuple12 incremental adapter v3 & matrix7 source successors

v2 remains immutable historical/source-only & is not admitted: its job layout used
per-process memory flag `0x100`, launched before assignment, lacked active-job
quiescence proof, & default artifact bound rejected recovered 11,887,616-byte
renderer. v3 source successor is `qualification/tuple12-takeover/workload-incremental-v3/`:
adapter SHA `c89d7bd56457d572404a3b32d80f83c1eb651235eb784ce7db76020a4eda2027`,
deriver SHA `c1da626cddc999a5c4caf340305d24cedd9fbfc38e327e66988dab995175cd97`,
source controls SHA `e442c4f6e35fa94aac1e295c18fc61d5cdf5abc9d2542fbd5727ee8c655f84bf`,
job controls SHA `4857849d31644ef0d263475c53bc31273851c1cbe99971877c07e5427bd9bb02`,
& pins SHA `0d0aa674fb9742a456e1562aeb9bd40aab0c6c5bd3af61ad8eacb6efc5ca81d7`.

v3 binds source `0e201571…`, build receipt `14789302…`, source manifest
`26705e8f…`, plan `a780e651…`, WorkloadWin `7e749248…`, & renderer
`7578cd5d…`. It configures `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_JOB_MEMORY`
(`0x2000 | 0x200`, 1 GiB), creates compiler suspended, assigns exact process
handle before `ResumeThread`, drains both streams, polls kernel terminal state,
queries `JobObjectBasicAccountingInformation` until active count is zero, &
terminates exact owned job on timeout/output/drain/quiescence faults. Renderer
artifact bound is 32 MiB. Adapter remains source-only; no compiler/native/lock
execution exists for v3.

`job-controls-v1.ps1` is root-owned headless lifecycle control. Positive mode &
wrong-memory fault must exit 0 with explicit PASS; resume-before-assignment &
active-query omission faults must exit nonzero after exact-child cleanup. Root
must parser/typecheck, run controls under resource supervisor, then decide any
Dell adapter execution. Matrix7 source successor remains pending same root
review; no new matrix/native result is claimed.

Matrix7 bounded runner source remains `qualification/tuple12-takeover/matrix-controls-v7/run-matrix-v7.ps1`
SHA `93fd5533c6f2309b8a4c7541ab50bbb1fb16e18f2feb1b0aa397a731a3a7e292`.
It retains each coordinator's original kernel handle, bounds 300-second
execution/8 MiB streams/2 GiB RSS, kills only exact coordinator on bounded
failure, preserves raw output, & aborts remaining cases. Headless owned-process
controls are `headless-controls.ps1` SHA
`46fed3a38cd97b0309a1c3523afbb9c849a8a33f0611de0e084e73ec73e2f97f`;
source pins SHA `ab075db49243c6e06e2aa312d55c2b8ad84784e175126458e5a68c4c07f8e0db`.
Neither matrix7 controls nor native matrix has run in current source lane.
