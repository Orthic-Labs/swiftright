# Tuple12 interactive display diagnostic v1

Root schedules `run-interactive-diagnostic.ps1` as one interactive task under active user session. Envelope rejects SSH/session0 before child launch, then owns v3 child through exact v6 helper: suspended creation, readers before assignment/resume, 1 GiB job, 8 MiB streams, bounded deadline, terminal/drain/active=0 proof, retained handles. v3 owns desktop lock & preserves it on failure.

Root invocation after source controls, with `D:\Claude\swiftright` checkout:

```powershell
$tag='tuple12-display-interactive-v1'
$root='D:\Claude\swiftright'
$out="$root\.work\sr0-r12-display-interactive-v1"
$arg="-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$root\qualification\tuple12-takeover\workload-display-interactive-v1\run-interactive-diagnostic.ps1`" -Base `"D:\Claude\swiftright\.work\sr0-r12-workload-v1`" -ControlRoot `"$root\qualification\tuple12-takeover\workload-controls-v8`" -AnalysisRoot `"$root\qualification\tuple12-takeover\workload-analysis-v3`" -OutRoot `"$out`" -ExpectExe 7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c -ExpectDll 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 -Lock `"D:\Claude\desktop.lock`" -Tag $tag"
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $root
$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "SR0-$tag" -Action $action -Principal $principal -Settings $settings -Force
Start-ScheduledTask -TaskName "SR0-$tag"
```

Root owns scheduling, task observation, & final receipt review. No UI activation, permissions, session creation, global kill, or input injection.
