# Tuple12 matrix controls v8

v8 is source-only successor to matrix-controls-v7. It preserves v7 inputs & receipts, then runs each coordinator through exact shared `Sr0OwnedJobProcess` from workload-incremental-v6: `CreateProcess(CREATE_SUSPENDED)` -> `AssignProcessToJobObject` -> `ResumeThread`, 1 GiB job memory, retained handles, bounded streams, active-process query, & owned cleanup proof.

Root runs parser, C# compile, headless controls, then matrix runner on Dell. `TotalMatrixTimeoutSeconds` defaults to 10800 (3 hours); `CoordinatorTimeoutSeconds` defaults to 1200 (20 minutes), with 1-second polling. `OutRoot` must be fresh. Each case preserves coordinator streams & JSON receipt. Desktop lock is checked before each launch; no lock is released by this source.

```powershell
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\run-matrix-v8.ps1 `
  -Base $base -Driver $driver -Worker $worker -Coordinator $coordinator `
  -ExpectWorker $workerSha -ExpectCoordinator $coordinatorSha -SmokeReceipt $smoke `
  -ExpectExe $exeSha -ExpectDll $dllSha -ExpectDriver $driverSha `
  -OutRoot 'D:\Claude\swiftright\.work\sr0-r12-workload-v1\matrix-v8-out' -Mode F1 -Runs 20
```

No compiler, native, GUI, remote, lock mutation, or matrix run has been performed in source lane.
