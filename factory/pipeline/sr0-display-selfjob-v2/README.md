# SR0 displayed-workload self-job v2

v1 is retained as rejected history.  v2 uses reviewed
`pilot-next-source-v1/windows-capture-v1/Sr0OwnedJobProcess-v15.cs`.
`CreateCurrentProcess(1073741824)` admits only `JobMemoryOnlyFlags=0x200`;
there is no kill-on-close flag.  `WaitForOnlyCurrent` & `RequireOnlyCurrent`
prove current task is sole remaining job member before job disposal, so closing
job handle cannot kill task before receipt/terminal exit.

`FrozenTaskPath` & `HelperPath` require explicit SHA-256 pins.  Frozen source is
bounded to 2 MiB & must contain direct `ProcessStartInfo`/`WorkloadWin.exe`
launch; scheduled-task creation is rejected.  Workload receipt is bounded to
2 MiB.  Receipt joins separately require retained host kernel handles,
`kernel_terminal=1`, worker/display sampler terminal, all runs valid,
task-quiescent, no stream/timeout fault, active self-only, & lock release.
Failures preserve lock & write `status=failed`.

Source controls, run by root:

```powershell
$repo='D:\Claude\swiftright'
$src="$repo\factory\pipeline\sr0-display-selfjob-v2"
$helper="$repo\factory\pipeline\pilot-next-source-v1\windows-capture-v1\Sr0OwnedJobProcess-v15.cs"
$out="$repo\.factory-work\sr0-display-selfjob-v2"
New-Item -ItemType Directory -Force $out | Out-Null
py -3.11 -I "$src\test-selfjob-controls-v2.py" `
  --source "$src\interactive-selfjob-v2.ps1" --helper $helper `
  --output "$out\controls.json"
```

Root must refresh both source hashes from explicit files, then schedule one
interactive task after controls pass:

```powershell
$repo='D:\Claude\swiftright';$src="$repo\factory\pipeline\sr0-display-selfjob-v2"
$base="$repo\.work\sr0-r12-workload-v1";$out="$repo\.work\sr0-display-selfjob-v2"
$helper="$repo\factory\pipeline\pilot-next-source-v1\windows-capture-v1\Sr0OwnedJobProcess-v15.cs"
$frozen="$repo\qualification\tuple12-takeover\workload-controls-v8\task-workload.ps1"
$helperSha=(Get-FileHash $helper -Algorithm SHA256).Hash.ToLowerInvariant();$frozenSha=(Get-FileHash $frozen -Algorithm SHA256).Hash.ToLowerInvariant()
$arg="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$src\interactive-selfjob-v2.ps1`" -Base `"$base`" -ControlRoot `"$repo\qualification\tuple12-takeover\workload-controls-v8`" -FrozenTaskPath `"$frozen`" -HelperPath `"$helper`" -FrozenTaskSha256 $frozenSha -HelperSha256 $helperSha -RunRoot `"$base\runs\sr0-display-selfjob-v2`" -ResultFile `"$out\result-workload.txt`" -MemoryReceiptPath `"$out\memory-receipt.json`" -Lock `"D:\Claude\desktop.lock`" -Tag sr0-display-selfjob-v2 -Runs 1 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 -NoActivate"
$action=New-ScheduledTaskAction -Execute powershell.exe -Argument $arg -WorkingDirectory $repo
$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 12) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName SR0-display-selfjob-v2 -Action $action -Principal $principal -Settings $settings -Force
Start-ScheduledTask -TaskName SR0-display-selfjob-v2
```

Root retains both receipts, verifies scheduled task terminal, & only then
removes task.  Display evidence remains observational; PresentMon displayed-row
& occlusion admission remain separate.
