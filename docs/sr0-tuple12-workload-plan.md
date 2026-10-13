# SR0 tuple12 WorkloadWin source plan

Status: source prepared; no Dell build or workload run admitted.

Pinned source is commit `0e201571e4320a3b6ccce14313fd2ad67e523904`. Closure manifest is [qualification/tuple12-workload-source-manifest.json](../qualification/tuple12-workload-source-manifest.json), SHA-256 `a780e651a1506fde772453548fd4defb4831731588c00e8772c224e47696cf28`; generator is [qualification/prepare-tuple12-workload-source.py](../qualification/prepare-tuple12-workload-source.py). It binds 41 Swift/package/header files, current workload scripts, background & run-workload overlays, & opt-in WorkloadWin CBT overlay. `.build`, tests, prior results, & macOS output are excluded.

Renderer input is recovered ABI 0.6 DLL SHA-256 `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`; ABI header is `12764e1f5e24457617a2a46b993ce405bde3f9b25625882425a997e4a8f2689b`. Stage root must be fresh: `D:\Claude\swiftright\.work\sr0-r12-workload-v1`. Preserve original workload scripts under archive-only paths, then apply [qualification/tuple12-workload-run-overlay.patch](../qualification/tuple12-workload-run-overlay.patch), SHA-256 `64f07966b59ccada882f64c2e84b02d559fa7fea7e48478ece320b4b5b53ea72`, to orchestrator & [qualification/tuple12-workload-background-overlay.patch](../qualification/tuple12-workload-background-overlay.patch), SHA-256 `94eb787802dc3e8864b54ba537b834db2cfa2bb5f671a8e737bb9699147ff83f`, to task script. Overlay is opt-in in source semantics: default foreground branch stays unchanged; `-NoActivate` passes `--sr0-noactivate` to WorkloadWin, uses `ShowWindow(SW_SHOWNOACTIVATE)` & `SetWindowPos(HWND_BOTTOM, SWP_NOACTIVATE|SWP_SHOWWINDOW)`, validates positive client metrics, records `background_noactivate=PASS`, & continues window-targeted `WM_CHAR` `PostMessage` plus existing QPC/input/activity/resource metrics. [qualification/tuple12-workload-startupguard-overlay.json](../qualification/tuple12-workload-startupguard-overlay.json) adds WorkloadWin-only `SR0WorkloadStartupGuard` with `SwiftRightBridge` import: same-thread `WH_CBT` vetoes `HCBT_ACTIVATE` & `HCBT_SETFOCUS`, installs before `bridge.run`, uses `defer` through full run, & exits 78 on install failure. Default flag remains unchanged; renderer/runtime/ABI are untouched.

Root Dell sequence, from fresh stage only:

```powershell
$Stage = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1'
Set-Location "$Stage\src\probes\sr0-b\workload"
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
swift build --jobs 1 -c release --product WorkloadWin --scratch-path "$Stage\scratch" '-Xlinker' '/MANIFEST:EMBED' '-Xlinker' $dep
if ($LASTEXITCODE -ne 0) { throw "WorkloadWin build failed: $LASTEXITCODE" }
$Bin = (& swift build --jobs 1 -c release --scratch-path "$Stage\scratch" --show-bin-path).Trim()
if ($LASTEXITCODE -ne 0 -or -not $Bin) { throw 'show-bin-path failed' }
```

Stage recovered DLL beside `WorkloadWin.exe`, verify bytes against `7578cd5d...aeac2`, verify embedded ComCtl v6 manifest, & seal compiler version, argv, source manifest, executable hash, DLL hash, lock hash `0e28d8bbbb13208c1951341741ec28a66b9c9e74a351708070207d973c478c9c`, stderr, stdout, & exit codes. Build must use fresh scratch/output; existing build script has `Copy-Item -Force` and old defaults (`D:\Claude\sr0b-workload`, renderer `7533...`), so pass explicit paths or use argv above. Do not run incremental script for this tuple.

Historical workload policy is 3 timed runs/configuration, 10 s warmup, 60 s measured, rows 200, `WM_CHAR` mode, & existing PresentMon/all-metric capture. This is not a three-run cross-compare exception: paired Mac/Windows comparison remains 20 runs per side per user instruction. Full Windows workload closure therefore requires 3 workload runs plus 20 paired comparison runs where comparison is in scope; no result is admitted from old tuple 10/11 receipts.

Run only after build & background/startup gates are sealed, using unique tag/output:

```powershell
& "$Stage\src\probes\sr0-b\workload\scripts\run-workload.ps1" -Base $Stage -Runs 3 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 -NoActivate -Tag tuple12-r10-background -ExpectDll 7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2
```

That command is a source-plan command only; root owns Dell lock, PresentMon, scheduled task, native process, & receipt admission. Workload remains pending until output proves target HWND ownership, background/noactivate, startup guard, positive WindowMetrics, all timing/resource streams, renderer/DLL/source joins, & required denominators.
