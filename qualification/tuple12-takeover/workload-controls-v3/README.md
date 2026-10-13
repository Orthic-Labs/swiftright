# Tuple12 workload lifecycle controls v3

Source-only successor for fresh WorkloadWin stage. v3 repairs v2 duplicate `GetWindowThreadProcessId`, marks sampler start failure non-terminal, uses owned PresentMon process + unique `SR0BWL-$Tag` session, & accepts explicit controls/analysis roots while preserving defaults.

Pinned build:

```text
commit       0e201571e4320a3b6ccce14313fd2ad67e523904
manifest     f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca
materialized 26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468
renderer     7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2
WorkloadWin  7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c
```

Controls:

```sh
python3 qualification/test_tuple12_workload_lifecycle_v3_controls.py
```

Root Windows parse/Add-Type must pass before any native run. Use fresh stage & explicit source roots so control scripts are not taken from stale stage paths:

```powershell
$Base = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1'
$Controls = 'D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-controls-v3'
$Analysis = 'D:\Claude\swiftright\.work\sr0-r12-workload-v1\src\probes\sr0-b\workload\analysis'
powershell -NoProfile -ExecutionPolicy Bypass -File "$Controls\run-workload.ps1" `
  -Base $Base -ControlRoot $Controls -AnalysisRoot $Analysis `
  -NoActivate -LifecycleProof -Runs 3 -Tag tuple12-r10
```

`-NoActivate` & `-LifecycleProof` remain opt-in; `-Force` legacy branch remains unchanged. PresentMon process handle, terminal state, stdout/stderr drains, unique session & sampler lifecycle receipts are required for tuple12 admission. Full16 workload policy remains 3 runs per configuration; cross-compare remains 20 per side.
