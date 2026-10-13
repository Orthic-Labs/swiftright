# SR0 displayed-workload self-job v1

Existing display diagnostic v3 owns `run-workload.ps1` & sampler child jobs,
but its scheduled workload task is a separate process.  Its memory admission
therefore does not prove WorkloadWin/renderer descendants inherit one job.
This successor is scheduled directly in active interactive session.  It joins
current task to one kill-on-close job with `JobObjectLimitJobMemory` `0x200` &
`1GiB` before invoking frozen `workload-controls-v8/task-workload.ps1`.
WorkloadWin, renderer, & resource/display worker inherit that job.

`interactive-selfjob-v1.ps1` requires explicit Base, ControlRoot,
FrozenTaskPath, HelperPath, RunRoot, ResultFile, MemoryReceiptPath, & lock.  It
proves active count `1` before frozen task; after frozen task it requires bounded
receipt fields `finished=`, `worker_terminal=1`, `sampler_terminal=1`,
`task_quiescent=1`, `runs_valid=Runs of Runs`, no timeout/stream fault, & active
count `1` (self only).
Lock release occurs only after all proofs.  Any failure preserves lock ownership
in receipt & reports `failed`; no global process kill occurs.

Source control:

```powershell
$repo='D:\Claude\swiftright'
$src="$repo\factory\pipeline\sr0-display-selfjob-v1"
$control="$repo\.factory-work\sr0-display-selfjob-v1"
New-Item -ItemType Directory -Force $control | Out-Null
py -3.11 -I "$repo\factory\pipeline\sr0-display-selfjob-v1\test-selfjob-controls-v1.py" `
  --source "$src\interactive-selfjob-v1.ps1" `
  --output "$control\controls.json"
```

Root runs one scheduled task after source controls:

```powershell
$repo='D:\Claude\swiftright'
$src="$repo\factory\pipeline\sr0-display-selfjob-v1"
$base="$repo\.work\sr0-r12-workload-v1"
$out="$repo\.work\sr0-display-selfjob-v1"
$helper="$repo\factory\pipeline\pilot-next-source-v1\windows-task-memory-v1\Sr0OwnedJobProcess.cs"
$frozen="$repo\qualification\tuple12-takeover\workload-controls-v8\task-workload.ps1"
$run="$out\result-workload.txt"
$memory="$out\memory-receipt.json"
$arg="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$src\interactive-selfjob-v1.ps1`" -Base `"$base`" -ControlRoot `"$repo\qualification\tuple12-takeover\workload-controls-v8`" -FrozenTaskPath `"$frozen`" -HelperPath `"$helper`" -RunRoot `"$base\runs\sr0-display-selfjob-v1`" -ResultFile `"$run`" -MemoryReceiptPath `"$memory`" -Lock `"D:\Claude\desktop.lock`" -Tag sr0-display-selfjob-v1 -Runs 1 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 -NoActivate"
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $repo
$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 12) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'SR0-display-selfjob-v1' -Action $action -Principal $principal -Settings $settings -Force
Start-ScheduledTask -TaskName 'SR0-display-selfjob-v1'
```

Root must retain task receipt & memory receipt, then verify task terminal before
removal.  Renderer/display proof remains observational; PresentMon displayed-row
qualification & occlusion admission remain separate.  No UI activation, input
injection, permission change, or session creation is performed by envelope.
