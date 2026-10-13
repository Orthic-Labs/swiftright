# SR0 v5-r6 drain + nested-PID integration

Factory-only prospective packet. Frozen qualification sources, renderer/runtime, prior raw receipts & `stream_drains` parser remain unchanged.

## Inputs & joins

`collector-selfjob-v7-drain-pidjoin.ps1` is copied from v5-r6 PID repair. It resolves nested `WorkloadWin.exe` identity before PresentMon CSV validation, then passes repaired task copy `task-workload-drain-v1.ps1` into direct workload launch. Collector verifies explicit SHA-256 pins for frozen task provenance, repaired task, collector helper, drain helper, parser, identity helper & PresentMon. Receipt records `drainTaskSha256` & `drainHelperSha256` alongside nested `workloadTargetPid`/`workloadTargetPath`.

`task-workload-drain-v1.ps1` dotsources `workload-drain-helper-v1.ps1`. Helper uses one monotonic deadline across process terminal wait & both async stream waits; no parameterless `WaitForExit()` or multiplied per-stream timeout. Exact parser line remains:

`stream_drains run=<id> worker_stdout=<0|1> worker_stderr=<0|1> sampler_stdout=<0|1> sampler_stderr=<0|1>`

Additional diagnostics do not replace parser line. Timeout leaves stream handles/tasks observable & emits timeout marker; qualification stays held until terminal, stream, job, source & display gates pass.

Collector custom output tasks use one shared 30-second drain deadline across all presentmon/workload/stop/query tasks. This bounds aggregate drain wait rather than multiplying eight independent waits. Existing native stop/query receipts remain preserved.

## Source controls

`test-workload-drain-controls-v1.ps1` invokes same production helper for zero exit, natural exit 17, delayed output, inherited-pipe delay via `cmd.exe` nested writer & nonterminal 1-second timeout. Controls require bounded elapsed time, expected terminal state, stream completion & cleanup. They make no qualification claim.

## Root staging

Stage fresh ignored run root & pass repository-relative or absolute explicit paths:

```powershell
pwsh -NoProfile -File .\collector-selfjob-v7-drain-pidjoin.ps1 `
  -Base D:\Claude\swiftright\.work\sr0-r12-workload-v1 `
  -ControlRoot <control-root> `
  -FrozenTaskPath <frozen-v8-task> `
  -DrainTaskPath <packet>\task-workload-drain-v1.ps1 `
  -HelperPath <owned-job-helper> `
  -DrainHelperPath <packet>\workload-drain-helper-v1.ps1 `
  -ParserPath <frozen-receipt-parser> `
  -IdentityHelperPath <packet>\workload-identity-v6.ps1 `
  -FrozenTaskSha256 <frozen-sha256> `
  -DrainTaskSha256 <drain-task-sha256> `
  -HelperSha256 <owned-job-helper-sha256> `
  -DrainHelperSha256 <drain-helper-sha256> `
  -ParserSha256 <parser-sha256> `
  -IdentityHelperSha256 <identity-sha256> `
  -RunRoot <fresh-run-root> `
  -ResultFile <fresh-run-root>\result-workload.txt `
  -MemoryReceiptPath <fresh-run-root>\memory.json `
  -StartReceiptPath <fresh-run-root>\start.json `
  -TaskName <existing-disabled-task> `
  -PresentMonExe D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe `
  -PresentMonSha256 b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af `
  -NoResources -NoActivate
```

Before native launch, root runs parser & source controls against fresh staged copies. Expected first receipt is diagnostic/held unless nested PID, terminal, streams, job self-only, lock & strict displayed rows all pass. Failed raw v5 receipt stays immutable.
