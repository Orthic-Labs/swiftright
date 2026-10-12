# Observer source r2

`observer-source-r2.ps1` is source successor for root-owned one-run observation. It admits `Sr0RootTransportJobV1` before bounded plan read, verifies helper bytes/hash, enforces inner memory-only self-job, compares `schedulePath` bytes/hash to `plan.scheduleSha256`, launches schedule with redirected 8MiB drains, retains schedule handle before waiting, joins raw/signed/.NET exits, then discovers worker by independent exact `-NoProfile`, `-ExecutionPolicy Bypass`, `-WindowStyle Hidden`, pinned `-File`, & pinned `-ManifestPath` argv tokens, exact PowerShell path, start time, session through bounded WTS kernel API, retained handle, terminal state, and exit identity. One monotonic `Stopwatch` budget covers schedule, discovery, worker wait, scheduler grace, drains, cleanup. If launcher receipt becomes terminal before worker discovery, observer emits held status for missing original-handle certificate rather than inventing worker proof. Any failure emits held scalar receipt with initialized fields; output remains atomic & fresh.

Root must refresh hashes after copying source. Required files:

- `observer-source-r2.ps1`
- `test-observer-source-controls-r2.ps1`
- `root-transport-job-v1/test-memory-failure-controls-v1.ps1`
- `root-transport-job-v1/Sr0RootTransportJobV1.cs`
- `one-run-plan-r1.json`
- plan-pinned `schedulePath`, `worker`, `launcherHelper`, `collector`, `coordinator`, `wrapper`, `frozenTask`, `helper`, `parser`, `workloadExe`, `rendererDll`, `presentMonExe`

Source-control invocation, run without native actions:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-v4\test-observer-source-controls-r2.ps1 `
  -SourcePath .\factory\pipeline\sr0-display-selfjob-v4\observer-source-r2.ps1 `
  -OutputPath .\.work\sr0-r12-workload-v1\observer-source-controls-r2.json
```

Plan admission is exact: `schema=sr0-display-selfjob-v4-fresh-one-run`, `deadlineSeconds=900`, `pollSeconds=1`, `runs=1`, `memoryLimitFlags=0x200`, `noActivate=true`, `noResources=true`, `killOnJobClose=false`, existing `wscriptPath`, & `taskName=tag`. Observer launch uses one outer monotonic `1100` second budget; output & both schedule stream sidecars must be fresh inside plan `factoryRoot`.

Observer creates & validates output parent immediately after plan admission, then checks receipt plus both stream paths are absent before starting schedule, so drain files exist before any child writes.

Before observer launch, root must create empty `plan.runRoot` as a directory while leaving `one-shot-manifest.json`, `start-receipt.json`, `collector-receipt.json`, `coordinator-verdict.json`, & `launcher-receipt.json` absent. Manifest path must be directly under `plan.runRoot`; `base` & `controlRoot` must already exist. Frozen schedule performs these same checks before task registration.

Root launch fields after source controls:

```powershell
$observerArgs = @(
  '-PlanPath', $planPath,
  '-OutputPath', $observerReceiptPath,
  '-TransportHelperPath', $transportHelperPath,
  '-TransportHelperSha256', $transportHelperSha256,
  '-DeadlineSeconds', '1100'
)
```

Run observer only through already admitted outer root transport, with `ScriptPath` pinned to `observer-source-r2.ps1`, fresh `OutputPath` inside plan `factoryRoot`, and exact helper hash refreshed from copied helper. Expected observer receipt kind is `sr0-display-selfjob-v4-fresh-observer-r2`; `status=passed` requires schedule streams sealed, worker exit identity, launcher aggregate self-only proof, scheduler stopped, and final inner active count `1`.

Root launch evidence must retain observer receipt, outer transport receipt, schedule stdout/stderr sidecars, outer stdout/stderr sidecars, launcher receipt, & worker identity. Receipt fields required for review include plan/schedule paths & hashes; active console session; schedule PID/original-handle/terminal/raw/signed/.NET exit join; schedule stream bytes/hashes/cap/drain/sealed state; worker PID/path/full command/start UTC/session/handle/terminal/raw/signed/.NET exit join; launcher status, aggregate active count & descendant quiescence; scheduler state; inner transport initial/final flags, limits, active counts & peak bytes; elapsed/within-deadline; failure/errors. Any missing field or cleanup proof keeps status `held`.

Receipt diagnosis order:

1. `observer.status`, `failure`, `errors`, `overallWithinDeadline`, & `transportFinalActive` establish outer admission, deadline, & self-only state.
2. `scheduleStdoutDrainError`, `scheduleStderrDrainError`, `scheduleStreamsSealed`, `scheduleExitIdentity`, & `scheduleExit` distinguish output-path/drain faults from schedule parameter or frozen preflight failures.
3. `workerPid`, `workerPath`, `workerCommandLine`, `workerStartTimeUtc`, `workerSessionMatch`, `workerOriginalHandleAcquired`, & `workerExitIdentity` distinguish discovery/session/handle faults from worker exit faults.
4. `launcherStatus`, `aggregateActiveAfter`, `aggregateDescendantsQuiesced`, `launcherReceiptPath`, `schedulerState`, & `schedulerRunning` establish run-once cleanup and task quiescence.
5. Read collector `status`, `failure`, `lockReleased`, `releaseAllowed`, `activeSelfOnly`, `presentMonSessionAbsent`, `workloadExitIdentity`, `presentMonExitIdentity`, `outputExceeded`, `timedOut`, & `workloadProof.qualificationPass`; `qualification-failed` remains diagnostic failure, never observer success.
6. Read coordinator `status`, `parentCertificatePresent`, `parentKernelTerminal`, `parentExitSigned`, `parentExitDotnet`, `lockOwnerObserved`, & `errors`; preserve lock when any ownership proof is missing.

Strict archive verifier is `verify-fresh-one-run-archive-v1.ps1`; it joins plan, observer, outer transport, one-shot manifest, launcher, collector, coordinator, workload result, PresentMon CSV, source pins, & bounded stream hashes. It emits `passed` only when collector workload qualification, retained parent exit `0`, lock release, active-self-only, PresentMon absence, stream drains, & all process exits pass.

Source controls:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-v4\test-archive-verifier-controls-v1.ps1 `
  -SourcePath .\factory\pipeline\sr0-display-selfjob-v4\verify-fresh-one-run-archive-v1.ps1 `
  -OutputPath .\.work\sr0-r12-workload-v1\archive-verifier-controls-v1.json
```

Root archive invocation after observer completion:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-v4\verify-fresh-one-run-archive-v1.ps1 `
  -PlanPath $planPath -ObserverReceiptPath $observerReceiptPath -OuterReceiptPath $outerReceiptPath `
  -ObserverSourcePath $observerSourcePath -ObserverSourceSha256 $observerSourceSha256 `
  -OutputPath $archiveVerifierPath
```
