# Tuple12 takeover ledger

Updated 11 October 2026. This ledger is source/readiness state; it claims no new qualification result.

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
| F1 Windows | fresh r4 run root-managed | assemble only after archive fetch & exact 20 passed receipts |
| Mac F1 | existing 20-run packet | source `0e201571…`; signed recorder is F1-only |

`qualification/tuple12-candidate.json` now carries recovered renderer pin at top level, while seven member hashes remain null until byte-bound receipts are supplied. `qualification/tuple12-fill.py` now rejects any populated `windows_renderer` member whose bytes disagree with top-level renderer pin; positive/fault controls pass, including this join. Candidate SHA-256: `3ca472267702ff2dc5b739885e96accda9c17d82f8058411a5f91e988387d666`.

## Automatable closure

1. Fetch & verify F1 Windows r4 archive; run `qualification/assemble-tuple12-windows-f1.py` with r5 driver, EXE/DLL/source/manifest pins. Require `status=qualified`, 20/20, retained handles, terminal kernel proofs, startup owner/client markers, native 17/17, targeted `fg_changes=0`.
2. Run full 16-config Windows matrix with `run-matrix-v3.ps1`, r5 driver, worker-v3 `8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6`, coordinator-v3 `4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4`, `Runs=20`, fresh output.
3. Build tuple12 WorkloadWin against renderer `7578cd5d…`; run three R10 runs & analyze. Existing E280 workload receipt is historical & cannot bind tuple12.
4. Run tuple12 native preflight/static checks, then IME F7/F7live/F8 & Narrator automatable checks. Existing tuple11 receipts are historical & cannot bind tuple12.
5. Produce tuple12 MSIX/DMG artifacts & sealed package run receipts; fill seven candidate members through `qualification/tuple12-fill.py`, revalidating every prepopulated member source.
6. Assemble Mac/Windows 20-per-side comparisons with pair-v2; run comparator/fault controls & manifest joins.

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
$BASE = 'D:\Claude\swiftright\.work\sr0-r12-typecheck\src'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$BASE\probes\sr0-b\workload\scripts\run-workload.ps1" `
  -Base $BASE -Runs 3 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 `
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

## Holds

- **W08:** external RightKit repair-helper proof required: install-registration, genuine cancellation to `Modified, NeedsRemediation`, helper command/state transition, relaunch, data-integrity, legacy-path & final signed-source receipts. Current release availability is not proof.
- **Mac full16:** held on generalized recorder with same Team/signature & process-level no-prompt signing proof. Existing trusted F1 recorder supports F1 packet only; no permission prompt may be introduced.
- **Narrator speech:** human listening remains after automated qualification; automated provider checks do not close speech-content item.
- **Freeze:** held until tuple12 stage/source binding, renderer, F1/full16, native, workload, package, W08 & 20-per-side comparison receipts pass.
