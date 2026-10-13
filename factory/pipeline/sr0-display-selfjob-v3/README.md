# SR0 displayed-workload self-job v3

v3 is stageable source for one interactive workload run. It admits reviewed
`factory/pipeline/pilot-next-source-v1/windows-capture-v1/Sr0OwnedJobProcess-v15.cs`
with `CreateCurrentProcess(1073741824)`, `JobMemoryOnlyFlags=0x200`,
`WaitForOnlyCurrent`, & `RequireOnlyCurrent`; kill-on-close remains disabled.

Frozen direct workload entrypoint is
`qualification/tuple12-takeover/workload-controls-v8/task-workload.ps1`.
It is invoked in current self-job, so `WorkloadWin.exe` & its sampler inherit
same job. Scheduled-task APIs are rejected in both envelope & frozen source.
Root supplies fresh SHA-256 pins for both files.

Receipt parser consumes only fields emitted by v8. It normalizes CRLF, then
requires per run: `pid_exit` with nonzero retained host handle,
`exit=0`, `kernel_terminal=1`, `kernel_exit_raw`, `kernel_exit`,
`dotnet_exit=0`; `resources` with nonzero sampler handle,
`sampler_exit=0`, `sampler_kernel_terminal=1`, raw/signed/dotnet exits,
`stdout_drained=1`, `stderr_drained=1`; `stream_drains` must report all four
worker/sampler streams drained; final
`finished=... runs_valid=N of N`, `worker_terminal=1`,
`sampler_terminal=1`, `task_quiescent=1`. No invented receipt fields are
required. `WaitForOnlyCurrent` & `RequireOnlyCurrent` run before lock release.

Root source controls:

```powershell
$repo='D:\Claude\swiftright';$src="$repo\factory\pipeline\sr0-display-selfjob-v3"
$helper="$repo\factory\pipeline\pilot-next-source-v1\windows-capture-v1\Sr0OwnedJobProcess-v15.cs"
$frozen="$repo\qualification\tuple12-takeover\workload-controls-v8\task-workload.ps1"
$out="$repo\.factory-work\sr0-display-selfjob-v3"
New-Item -ItemType Directory -Force $out | Out-Null
py -3.11 -I "$src\test-selfjob-controls-v3.py" `
  --source "$src\interactive-selfjob-v3.ps1" --helper $helper --frozen-task $frozen `
  --output "$out\controls.json"
```

After controls pass, root refreshes pins & schedules one interactive task:

```powershell
$repo='D:\Claude\swiftright';$src="$repo\factory\pipeline\sr0-display-selfjob-v3"
$base="$repo\.work\sr0-r12-workload-v1";$out="$repo\.work\sr0-display-selfjob-v3"
$helper="$repo\factory\pipeline\pilot-next-source-v1\windows-capture-v1\Sr0OwnedJobProcess-v15.cs"
$frozen="$repo\qualification\tuple12-takeover\workload-controls-v8\task-workload.ps1"
$helperSha=(Get-FileHash $helper -Algorithm SHA256).Hash.ToLowerInvariant();$frozenSha=(Get-FileHash $frozen -Algorithm SHA256).Hash.ToLowerInvariant()
$arg="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$src\interactive-selfjob-v3.ps1`" -Base `"$base`" -ControlRoot `"$repo\qualification\tuple12-takeover\workload-controls-v8`" -FrozenTaskPath `"$frozen`" -HelperPath `"$helper`" -FrozenTaskSha256 $frozenSha -HelperSha256 $helperSha -RunRoot `"$base\runs\sr0-display-selfjob-v3`" -ResultFile `"$out\result-workload.txt`" -MemoryReceiptPath `"$out\memory-receipt.json`" -Lock `"D:\Claude\desktop.lock`" -Tag sr0-display-selfjob-v3 -Runs 1 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 -NoActivate"
$action=New-ScheduledTaskAction -Execute powershell.exe -Argument $arg -WorkingDirectory $repo
$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 12) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName SR0-display-selfjob-v3 -Action $action -Principal $principal -Settings $settings -Force
Start-ScheduledTask -TaskName SR0-display-selfjob-v3
```

Root retains `result-workload.txt` & `memory-receipt.json`, verifies scheduled
task terminal, then removes task. Displayed-row/occlusion admission stays
separate from this lifecycle proof.
