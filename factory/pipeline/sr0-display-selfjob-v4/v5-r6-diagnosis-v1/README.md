# v5-r6 workload identity diagnosis

This packet is prospective only. It leaves frozen workload controls, protected qualification, raw receipts, & prior v5-r6 evidence unchanged.

## Finding

`actual-native-raw/result-workload.txt` records wrapper WorkloadWin-task PID `46448` in collector context, but frozen task records nested WorkloadWin PID `17992`:

```text
worker run=r1 pid=17992 parent_pid=46448 ...
pid_exit run=r1 pid=17992 ... exit=0 kernel_terminal=1 kernel_exit_raw=0 kernel_exit=0 dotnet_exit=0
```

All WorkloadWin rows in `presentmon.csv` use ProcessID `17992`. Collector v5 passed `$workload.Id` (`46448`) to `Read-PresentMonCsvEvidenceV5`, producing false `PresentMon CSV workload ProcessID mismatch`. `collector-selfjob-v6-pidjoin.ps1` resolves nested worker identity from bounded receipt, validates wrapper parent & exit identity, then targets CSV validation with nested PID.

This correction does not convert this archived run into qualification: its frozen task has `stream_drains ... worker_stdout=0`, `finished=... runs_valid=0`, `worker_terminal=0`, `task_quiescent=0`, & `runs_valid=0`. Stream/timing/qualification gates remain unchanged.

## Files

- `workload-identity-v6.ps1`: production helper used by prospective collector.
- `collector-selfjob-v6-pidjoin.ps1`: v5 collector copy with nested PID join only.
- `test-workload-identity-controls-v1.ps1`: controls call same helper, with parent/PID/exit/worker-row fault fixtures.

## Root execution

First run parser controls on a fresh Windows packet, then run identity controls against explicit archived or fresh `result-workload.txt`:

```powershell
pwsh -NoProfile -File .\test-workload-identity-controls-v1.ps1 `
  -IdentityHelperPath .\workload-identity-v6.ps1 `
  -ResultPath <explicit-result-workload.txt> `
  -OutputPath <fresh-output>\identity-controls.json `
  -ExpectedRuns 1 -WrapperPid 46448 -ExpectedWorkerPid 17992 `
  -MutationRoot <fresh-output>\identity-faults
```

Stage helper beside collector & refresh all exact hashes before any native run. Expected control result is `passed-source-controls`; archived v5-r6 remains held on stream drain failure even when CSV identity joins.

Prospective collector invocation must pass `-IdentityHelperPath <staged workload-identity-v6.ps1>` & `-IdentityHelperSha256 1cd6c8a486a33cb318e5fab9b0613d888920b1fc9d52cac7849bd75e39d84309`; collector receipt records this separate pin.
