# Tuple12 Workload coordinator v1

Source-only launcher envelope for root Windows execution. It acquires `D:\Claude\desktop.lock` through silent exclusive CAS, holds lock through hidden Workload v3 orchestrator, retains orchestrator handle, drains raw streams, verifies lifecycle/quiescence, then releases lock only after terminal proof. It never deletes tasks, processes, lock, or outputs.

Pinned inputs:

```text
stage       D:\Claude\swiftright\.work\sr0-r12-workload-v1
controls    D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-controls-v3
analysis    D:\Claude\swiftright\.work\sr0-r12-workload-v1\src\probes\sr0-b\workload\analysis
WorkloadWin 7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c
renderer    7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2
```

Root parser & headless controls must pass before native execution. Root command shape:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-coordinator-v1\workload-coordinator.ps1 `
  -Base D:\Claude\swiftright\.work\sr0-r12-workload-v1 `
  -ControlRoot D:\Claude\swiftright\src\qualification\tuple12-takeover\workload-controls-v3 `
  -AnalysisRoot D:\Claude\swiftright\.work\sr0-r12-workload-v1\src\probes\sr0-b\workload\analysis `
  -OutRoot D:\Claude\swiftright\probes\sr0-b\workload\out\tuple12-coordinator-v1 `
  -ExpectExe 7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c `
  -ExpectDll 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2
```

Workload policy is exactly 3 runs, 10 s warmup, 60 s measured, 200 rows, 10 keys/s, targeted `-NoActivate`, & `-LifecycleProof`. Full16 workload matrix remains separate from F1 20-per-side evidence.
