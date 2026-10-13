# Tuple 12 workload lifecycle review

Review is source-only. It covers current workload scripts, not any Windows run.

## Pinned source

```text
probes/sr0-b/workload/scripts/run-workload.ps1  8c6122576d9be8c7191e821aff3ac1b3371a520ae8edec885d32c677f89bbf90
probes/sr0-b/workload/scripts/task-workload.ps1 b854a260589a3bf198ada7292fbcb0be39d38c4cc19047e573513383783c9e22
qualification/tuple12-workload-run-overlay.patch 64f07966b59ccada882f64c2e84b02d559fa7fea7e48478ece320b4b5b53ea72
qualification/tuple12-workload-background-overlay.patch 94eb787802dc3e8864b54ba537b834db2cfa2bb5f671a8e737bb9699147ff83f
```

## Findings

- `run-workload.ps1` uses fixed task name `SR0BWorkload`, `Register-ScheduledTask -Force`, & unconditional `Unregister-ScheduledTask`. It does not reject existing `Running`/`Queued` state, retain task/child PID, query task-child kernel terminal state, or prove quiescence before removal.
- `$ErrorActionPreference = 'Continue'` leaves registration/start/copy failures non-fatal. Analysis exit code is logged but is not returned by orchestrator.
- Task script retains `$proc`, but timeout calls `Kill()` without `WaitForExit()`/refresh before writing `pid_exit`; `-1` can therefore be recorded while process remains alive. Sampler has same post-kill gap.
- Task receipt records workload PID, HWND, client metrics, foreground observations, & child exit when available. It does not bind parent PID/full path, retained-handle terminal proof, post-drain proof, or task identity to receipt. HWND ownership is observed only through `MainWindowHandle` polling.
- No-activate overlay is opt-in & fail-closed for `BottomNoActivate`; it does not repair task lifecycle or prove process startup was non-activating. Default behavior remains unchanged.

These are lifecycle evidence gaps. They do not justify weakening native 17/17, input, foreground, renderer, or workload assertions.

## Opt-in successor contract

Root may apply successor only in fresh workload stage, preserving current source & receipts:

1. Add `-LifecycleProof` switch to run/task scripts; default stays current behavior.
2. In proof mode, reject pre-existing task state `Running` or `Queued`; use unique task name from run tag; remove `-Force`.
3. Record task name, task state, task action, worker PID, worker executable full path, workload PID, HWND, & parent PID in receipt. Require HWND owner PID/full path match workload process before input.
4. After timeout, call `Kill()`, `WaitForExit()`, `Refresh()`, then query retained process handle with `GetExitCodeProcess`; record numeric terminal code. Do same for sampler. Never classify `-1` as terminal.
5. Require `finished=` only after every run has terminal worker proof, sampler is terminal or explicitly disabled, raw stdout/stderr are sealed with exclusive-create, & task state is neither `Running` nor `Queued`.
6. Unregister only after proof; then re-read task state and write `task_removed=true`. On semantic failure, release task only when process/quiescence proof passes; return non-zero after receipt is sealed.
7. Return analyzer status as process exit status. Preserve raw receipt if analysis fails.

Required mutation controls: existing running task, task-start failure, timeout before worker exit, worker PID/path mismatch, HWND owner mismatch, kill without terminal code, sampler still running, stale `finished=`, duplicate receipt path, & analyzer non-zero. Each must reject admission while still emitting cleanup proof.

## Root execution order

After Workload exact source build receipt is sealed:

```text
1. Parse/typecheck successor scripts offline.
2. Run pure positive + mutation controls.
3. Stage fresh workload namespace; do not touch historical tuple 10/11 receipts.
4. Run opt-in targeted workload with `-NoActivate -LifecycleProof` under desktop lock.
5. Assemble workload receipt only when task/worker/sampler terminal proofs join source, renderer, WorkloadWin, & startup-guard hashes.
```

Current Full16 Windows command paths use `.work\\sr0-matrix-controls-v1\\tuple12-startupguard-matrix-v1\\` for driver, worker, & coordinator. Workload run path remains root-managed `.work\\sr0-r12-workload-v1` once build receipt is admitted.

Opt-in patch candidate (not applied to current Workload source payload):

```text
qualification/tuple12-workload-lifecycle-overlay-v1.patch
SHA-256 56d254c2ac990bb0790d3af9af9e2387f3ac11360295ffab1087d5b4282ae6ec
```

Patch dry-run applies cleanly to both pinned scripts. PowerShell execution/typecheck remains root-owned on Windows.

Apply order for clean patch context: base scripts -> lifecycle overlay -> existing run/background overlays (or rebase lifecycle patch onto already-overlaid scripts before Windows parse).

## v2 materialization

v1 patch is superseded by materialized source under `qualification/tuple12-takeover/workload-controls-v2/`. v2 removes literal variable escapes, checks native terminal code against `259` & .NET `ExitCode`, bounds worker/sampler stdout/stderr drains, & keeps legacy `-Force` only outside `-LifecycleProof` branch.

```text
run  f7a325861f13181965f60a2391ea1fd4674f50b1b1d6d20230b8acbd1c54d57c
 task 9baee40253510a57f31e3c8111dcaf65618c5a7ffe639f1beba3c2283cfabf4e
pins 579b609a69c1888e52e526f30dd6cb1de2b2046b6443741363661a107ee13197
controls 1926192aae50112405afab7b28e7d1f929746360a46b2b91cb36705a8373e642
```

`python3 qualification/test_tuple12_workload_lifecycle_v2_controls.py` passes positive path + eight mutation faults.

## v3 materialization (current source candidate)

v3 supersedes v2 for root parser/typecheck. It fixes duplicate `GetWindowThreadProcessId`, sets sampler terminal aggregate false on start failure, gives PresentMon an owned `ProcessStartInfo` handle & bounded stdout/stderr drains, uses unique `SR0BWL-$Tag` session, & adds explicit `-ControlRoot`/`-AnalysisRoot` overrides while preserving defaults. It does not alter compiled 65-file workload source closure.

```text
run       494ede1a50db4fd8fa7702a0c9ff079dcef3a3e1ab9886e1c2921709d1379e86
 task     caecff705f7faebe88792f3f875263ee1069638447f145c3c6f05457c7a8d571
verify    d412213c28c4e716f76ef59b6a609c4297f566f05cf1942ceb0c520b6c2c8e82
sampler   90b2bc9fda6c2b5e0c7ca244508e1a7d84e9a5640d2089394ea51e7cc6d11b13
controls  d9bda02269fd4aa179d0142a646362e5191c5c955e601baaf1f4ee644ccb2a00
```

`python3 qualification/test_tuple12_workload_lifecycle_v3_controls.py` passes positive path + nine mutation faults. Windows PowerShell parse & `Add-Type` remain root-owned before any native run.
