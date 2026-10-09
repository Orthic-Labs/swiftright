# SR0-B PresentMon batch 5 orchestrator. Runs with -File from the elevated SSH session.
# 1) starts PresentMon (session SR0B5, all processes, --timed 1200) and waits for "Started recording."
# 2) registers + starts a one-shot interactive task (SR0B5Desktop) that runs task-b5.ps1
# 3) waits for the harness "finished=" line (or task end), checks the first probe launched
# 4) stops PresentMon (--terminate_existing_session), unregisters the task, runs pm_an3.py
# Everything is logged to D:\Claude\sr0b-frame-clock\batch5\orchestrator.log.
$ErrorActionPreference = 'Continue'
$base     = 'D:\Claude\sr0b-frame-clock'
$b5       = "$base\batch5"
$pmExe    = 'D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe'
$pmCmd    = "$b5\pm-b5.cmd"
$pmCsv    = "$base\presentmon\pm-batch5.csv"
$pmCon    = "$base\presentmon\pm-batch5.console.txt"
$pmStop   = "$b5\pm-b5-stop.txt"
$result   = "$base\result-desktop-v3-batch5.txt"
$analysis = "$base\analysis-batch5.txt"
$taskName = 'SR0B5Desktop'
$log      = "$b5\orchestrator.log"
New-Item -ItemType Directory -Force $b5 | Out-Null

function Log([string]$m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format o), $m) }
function Read-Shared([string]$p) {
  if (-not (Test-Path $p)) { return '' }
  try {
    $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
    $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
    try { $sr = New-Object IO.StreamReader($fs); $t = $sr.ReadToEnd(); $sr.Dispose(); return $t } finally { $fs.Dispose() }
  } catch { return '' }
}
function Stop-Pm {
  Log 'stop presentmon (terminate_existing_session)'
  & $pmExe --terminate_existing_session --session_name SR0B5 *> $pmStop
  $d = (Get-Date).AddSeconds(60)
  while ((Get-Process -Name 'PresentMon-2.6.0-x64' -ErrorAction SilentlyContinue) -and (Get-Date) -lt $d) { Start-Sleep -Seconds 2 }
  Log ('presentmon still running: ' + [bool](Get-Process -Name 'PresentMon-2.6.0-x64' -ErrorAction SilentlyContinue))
}

Log 'batch5 start'
foreach ($f in @($pmCsv, $pmCon, $result, $analysis)) { if (Test-Path $f) { Remove-Item -Force $f } }

# 1) PresentMon, hidden cmd wrapper redirects stdout+stderr to the console file
Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $pmCmd) -WindowStyle Hidden | Out-Null
# stdout is block-buffered when redirected, so "Started recording." appears only at exit.
# The live signal is the CSV: PresentMon process alive and at least 20 lines written.
$started = $false; $d = (Get-Date).AddSeconds(60)
while (-not $started -and (Get-Date) -lt $d) {
  Start-Sleep -Milliseconds 500
  $alive  = [bool](Get-Process -Name 'PresentMon-2.6.0-x64' -ErrorAction SilentlyContinue)
  $csvLen = if (Test-Path $pmCsv) { (Get-Item $pmCsv).Length } else { 0 }
  $started = $alive -and ($csvLen -ge 2000)
}
Log "presentmon started=$started csv_bytes=$csvLen console_marker=$([bool]((Read-Shared $pmCon) -match 'Started recording'))"
if (-not $started) { Stop-Pm; Log 'ABORT: PresentMon not recording'; exit 2 }
Start-Sleep -Seconds 5

# 2) interactive one-shot task for the desktop harness
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$b5\task-b5.ps1`"" -WorkingDirectory $base
$pri = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 40) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $act -Principal $pri -Settings $set -Force | Out-Null
Log "registered $taskName"
Start-ScheduledTask -TaskName $taskName
Log 'task started'

# 3a) first probe launch check (first "pid run=" line)
$launched = $false; $abort = $false; $d = (Get-Date).AddSeconds(150)
while (-not $launched -and -not $abort -and (Get-Date) -lt $d) {
  Start-Sleep -Seconds 3
  $t = Read-Shared $result
  $launched = $t -match 'pid run='
  $abort = $t -match 'ABORT run='
}
Log "first probe launched=$launched abort=$abort"
if (-not $launched) { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue }

# 3b) wait for the harness to finish
$fin = $false; $st = 'Running'; $d = (Get-Date).AddMinutes(38)
do {
  Start-Sleep -Seconds 5
  $st  = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State
  $fin = (Read-Shared $result) -match 'finished='
} while (-not $fin -and $st -eq 'Running' -and (Get-Date) -lt $d)
Log "harness finished=$fin task_state=$st"

# 4) cleanup and analysis
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Log 'task unregistered'
Stop-Pm
if (Test-Path $result) {
  & py -3.11 -I "$base\scripts-v3\pm_an3.py" $pmCsv $result $pmCon | Out-File -Encoding utf8 $analysis
  Log "analysis written rc=$LASTEXITCODE"
}
Log 'batch5 end'
