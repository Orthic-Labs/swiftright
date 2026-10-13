# Tuple12 workload display root launch v1

Source-only root packet. Root stages exact listed paths & runs parser/headless controls before any scheduled task. Scheduler uses current interactive user with `RunLevel Highest`; no UAC/permission UI is requested by packet. Any permission prompt stops run.

`run-display-root-launch-v1.ps1` requires explicit child/helper paths, checks active console session before child creation, owns child through suspended creation → readers → job assignment → resume, retains original handles, & records terminal, drained streams, active-process zero, task receipt, & lock release. Child job uses `JOB_OBJECT_LIMIT_JOB_MEMORY` (`0x200`, 1 GiB) only; `KILL_ON_JOB_CLOSE` is absent. Failure preserves lock & receipt.

Root command, after source review:

```powershell
& 'D:\Claude\swiftright\qualification\tuple12-takeover\workload-display-root-launch-v1\schedule-root-launch-v1.ps1' `
  -Root 'D:\Claude\swiftright' `
  -Base 'D:\Claude\swiftright\.work\sr0-r12-workload-v1' `
  -OutRoot 'D:\Claude\swiftright\.work\sr0-r12-display-root-launch-v1'
```

Exact staged inputs:

- envelope: `run-display-root-launch-v1.ps1`
- scheduler: `schedule-root-launch-v1.ps1`
- child: `qualification/tuple12-takeover/workload-display-diagnostic-v3/run-one-diagnostic.ps1`
- sampler: `qualification/tuple12-takeover/workload-display-diagnostic-v3/display-context-sampler-v1.ps1`
- workload controls: v8 `run-workload.ps1` & `task-workload.ps1`
- analysis: v3 `analyze_workload.py`
- owned process helper: v6 `Sr0OwnedJobProcess.cs`
- source controls: `test-display-root-launch-v1-controls.py` (source-only; root runs separately)

Artifact identity remains pinned by v8 build metadata & runtime script: WorkloadWin.exe `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`; renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`. No artifact path is guessed.

Root reviews final envelope receipt, child diagnostic receipt, scheduled-task state, `taskQuiescent`, `lockReleased`, memory flags/limit, `activeProcesses=0`, terminal & stream drains before interpreting observation.

Envelope completion additionally requires child & sampler exit code `0`, no timeout, output-cap, or RSS-cap flags; v3 `observed` alone cannot admit completion.
