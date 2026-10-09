# SR0 workload orchestrator (Windows). Run as a FILE from an ELEVATED session (PresentMon needs ETW rights):
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0b-workload\probes\sr0-b\workload\scripts\run-workload.ps1 -Instr full"
# 1) artifact identity gate (exe + renderer DLL hashes) and quiet-host gate (no builds/other desktop tests running)
# 2) PresentMon 2.6.0, ALL-process capture (no --process_name), QPC time, started first and confirmed recording
# 3) a one-shot INTERACTIVE scheduled task runs task-workload.ps1 (3 runs: 10 s warm-up + 60 s measured each, PostMessage script)
# 4) PresentMon stopped, task removed, analyze_workload.py joins input QPC stamps to presented frames (PID match, as frame-clock batch 5)
# Nothing here touches the desktop of another application: keys are sent only while the workload window is foreground.
param(
  [string]$Base = 'D:\Claude\sr0b-workload',
  [string]$Instr = 'full',            # full | light (light = overhead A/B baseline; analyzer reports it as such)
  [int]$Runs = 3,
  [int]$Warmup = 10,
  [int]$Measure = 60,
  [string]$Tag = '',
  [string]$ExpectDll = '777F14C4FF11822BF6E2174E127B3A4A325D83A6B322FA599C7FC4408B335441',
  [double]$ExpectScale = 1.0,
  [switch]$SkipQuietCheck
)
$ErrorActionPreference = 'Continue'
if (-not $Tag) { $Tag = (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$Instr" }
$scripts  = "$Base\probes\sr0-b\workload\scripts"
$analysis = "$Base\probes\sr0-b\workload\analysis"
$runRoot  = "$Base\runs\$Tag"
$pmExe    = 'D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe'
$pmCsv    = "$runRoot\presentmon.csv"
$pmCon    = "$runRoot\presentmon.console.txt"
$pmCmd    = "$runRoot\pm-run.cmd"
$result   = "$runRoot\result-workload.txt"
$orchLog  = "$runRoot\orchestrator.log"
$taskName = 'SR0BWorkload'
New-Item -ItemType Directory -Force $runRoot | Out-Null
function Log([string]$m) { $l = "{0} {1}" -f (Get-Date -Format o), $m; Add-Content -Path $orchLog -Value $l; $l }
function Read-Shared([string]$p) {
  if (-not (Test-Path $p)) { return '' }
  try {
    $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { $sr = New-Object IO.StreamReader($fs); $t = $sr.ReadToEnd(); $sr.Dispose(); return $t } finally { $fs.Dispose() }
  } catch { return '' }
}
function Stop-Pm {
  Log 'stop presentmon (terminate_existing_session)'
  & $pmExe --terminate_existing_session --session_name SR0BWL *> "$runRoot\pm-stop.txt"
  $d = (Get-Date).AddSeconds(60)
  while ((Get-Process -Name 'PresentMon-2.6.0-x64' -ErrorAction SilentlyContinue) -and (Get-Date) -lt $d) { Start-Sleep -Seconds 2 }
}

Log "run-workload tag=$Tag instr=$Instr runs=$Runs warmup=$Warmup measure=$Measure"
$null = Log ("whoami=" + (whoami) + " elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

# 1) gates
$art = & "$scripts\verify-artifacts.ps1" -Base $Base -ExpectDll $ExpectDll
$art | ForEach-Object { Log $_ }
if (-not ($art -match 'ARTIFACT_OK')) { Log 'ABORT: artifact gate failed'; exit 2 }
if (-not $SkipQuietCheck) {
  $busy = Get-Process | Where-Object { $_.ProcessName -match '^(rk2|swift-build|swift-frontend|swiftc|cargo|rustc|link|cl|msbuild|node|chrome|msedge)' } | Select-Object -ExpandProperty ProcessName -Unique
  if ($busy) { Log ("ABORT: host not quiet, running: " + ($busy -join ',')); exit 3 }
}

# 2) PresentMon: all-process capture, QPC time, no process filter. Total capture window with margin.
$timed = $Runs * ($Warmup + $Measure + 25) + 60
"@echo off`r`n`"$pmExe`" --v1_metrics --qpc_time --no_track_gpu --no_track_input --no_console_stats --write_display_metadata --session_name SR0BWL --stop_existing_session --output_file $pmCsv --timed $timed --terminate_after_timed > $pmCon 2>&1`r`n" | Set-Content -Encoding ascii $pmCmd
Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $pmCmd) -WindowStyle Hidden | Out-Null
$started = $false; $d = (Get-Date).AddSeconds(60); $csvLen = 0
while (-not $started -and (Get-Date) -lt $d) {
  Start-Sleep -Milliseconds 500
  $alive = [bool](Get-Process -Name 'PresentMon-2.6.0-x64' -ErrorAction SilentlyContinue)
  $csvLen = if (Test-Path $pmCsv) { (Get-Item $pmCsv).Length } else { 0 }
  $started = $alive -and ($csvLen -ge 2000)
}
Log "presentmon started=$started csv_bytes=$csvLen"
if (-not $started) { Stop-Pm; Log 'ABORT: PresentMon not recording'; exit 4 }
Start-Sleep -Seconds 5

# 3) interactive one-shot task
$arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scripts\task-workload.ps1`" -Base `"$Base`" -RunRoot `"$runRoot`" -ResultFile `"$result`" -Runs $Runs -Warmup $Warmup -Measure $Measure -Instr $Instr"
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $Base
$pri = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes (($Runs * ($Warmup + $Measure + 60)) / 60 + 10)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $act -Principal $pri -Settings $set -Force | Out-Null
Log "registered $taskName"
Start-ScheduledTask -TaskName $taskName
$fin = $false; $st = 'Running'; $d = (Get-Date).AddSeconds($Runs * ($Warmup + $Measure + 90) + 120)
do {
  Start-Sleep -Seconds 5
  $st = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State
  $fin = (Read-Shared $result) -match 'finished='
} while (-not $fin -and $st -eq 'Running' -and (Get-Date) -lt $d)
Log "harness finished=$fin task_state=$st"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Stop-Pm

# 4) analysis (python 3.11, isolated mode)
Copy-Item "$Base\build.json" "$runRoot\build.json" -Force
& py -3.11 -I "$analysis\analyze_workload.py" --os windows --root $runRoot --expect-scale $ExpectScale --out "$runRoot\report" 2>&1 | Tee-Object -FilePath "$runRoot\analysis-console.txt"
Log "analysis rc=$LASTEXITCODE report=$runRoot\report"
