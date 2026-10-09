# SR0 workload orchestrator (Windows). Run as a FILE from an ELEVATED session (PresentMon needs ETW rights):
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0b-workload\probes\sr0-b\workload\scripts\run-workload.ps1 -Instr full"
# 1) artifact identity gate (exe + renderer DLL hashes) and quiet-host gate (no builds/other desktop tests running)
# 2) PresentMon 2.6.0, ALL-process capture (no --process_name), QPC time, started first and confirmed recording
# 3) a one-shot INTERACTIVE scheduled task runs task-workload.ps1 (3 runs: 10 s warm-up + 60 s measured each, PostMessage script)
# 4) PresentMon stopped, task removed, analyze_workload.py joins input QPC stamps to presented frames (PID match, as frame-clock batch 5)
# Nothing here touches the desktop of another application: keys are sent only while the workload window is foreground.
# Stress / resources (R10): -Rows (200 default; stress 1000, 5000) and -KeyRate (10 default; stress 30) go to task-workload.ps1 (-Rows reaches the app as
# `--rows N`; an app build that ignores it is caught by the analyzer, which compares meta.json total_rows). Every run samples CPU / threads / memory / GPU
# into <run>\resources.csv unless -NoResources (overhead A/B). scripts\run-stress.ps1 runs the Rows x KeyRate series through this script.
param(
  [string]$Base = 'D:\Claude\sr0b-workload',
  [string]$Instr = 'full',            # full | light (light = overhead A/B baseline; analyzer reports it as such)
  [int]$Runs = 3,
  [int]$Warmup = 10,
  [int]$Measure = 60,
  [int]$Rows = 200,                   # editable rows the app runs with (200 = the section 11 workload; stress series 1000, 5000)
  [double]$KeyRate = 10,              # keys per second posted to the workload window (10 = the section 11 workload; stress series 30)
  [switch]$NoResources,               # skip the resource sampler (overhead A/B)
  [string]$Tag = '',
  [string]$ExpectDll = '4FB068F0B6C73DE9A5DDE1A536E97EEDD08E2FEA3C0DD8B92FC0E4A78E53298F',
  [double]$ExpectScale = 2.5,         # Dell tuple: 250% (dpi 240); every SR0 Dell record is scale 2.5
  [int]$MaxIdleCpu = 25,              # abort if average total CPU % over the sample window exceeds this (Dell idle baseline ~17-19%: Membrane, Defender)
  [int]$CpuSampleSeconds = 20,
  [switch]$Force,                     # bypass the quiet-host gate; receipt is marked host_quiet=forced
  [switch]$SkipQuietCheck             # legacy alias for -Force
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

Log "run-workload tag=$Tag instr=$Instr runs=$Runs warmup=$Warmup measure=$Measure rows=$Rows key_rate=$KeyRate resources=$(if ($NoResources) { 'off' } else { 'on' })"
$null = Log ("whoami=" + (whoami) + " elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

# 1) gates
$art = & "$scripts\verify-artifacts.ps1" -Base $Base -ExpectDll $ExpectDll
$art | ForEach-Object { Log $_ }
if (-not ($art -match 'ARTIFACT_OK')) { Log 'ABORT: artifact gate failed'; exit 2 }
# 1b) quiet-host gate. BLOCKS only on build/test activity. Measures background CPU. Logs everything else.
$forceQuiet = [bool]($Force.IsPresent -or $SkipQuietCheck.IsPresent)
$hostRcpt   = "$runRoot\host-quiet.txt"
function Write-HostReceipt([string]$state, [string[]]$lines) {
  $hdr = @("host_quiet=$state", "max_idle_cpu_pct=$MaxIdleCpu", "sample_seconds=$CpuSampleSeconds") + $lines
  Set-Content -Path $hostRcpt -Value $hdr -Encoding ascii
}
function Get-CpuMap {
  $m = @{}
  foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    try { $m[$p.Id] = [pscustomobject]@{ Name = $p.ProcessName; Cpu = $p.TotalProcessorTime.TotalSeconds } } catch {}
  }
  return $m
}
$buildNames = @('cargo','rustc','swift-build','swift-frontend','swiftc','link','cl','clang','lld-link','msbuild','makeappx','signtool')
$ownPattern = '^(FreshOnBridge|BridgeSmoke|SliceApp|Workload|SwiftHost)'
$blockers = @()
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
  $pth = try { $p.Path } catch { $null }
  $isOurs = [bool]($pth -and $pth.StartsWith($Base, [StringComparison]::OrdinalIgnoreCase))
  if (($buildNames -contains $p.ProcessName) -or (($p.ProcessName -match $ownPattern) -and -not $isOurs)) {
    $blockers += "$($p.ProcessName)($($p.Id))"
  }
}
$hostLines = @()
foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'SR0*' -and $_.TaskName -ne $taskName })) {
  $hostLines += "sched_sr0=$($t.TaskName) state=$($t.State)"
  if ($t.State -eq 'Running') { $blockers += "task:$($t.TaskName)" }
}
$blockTxt = if ($blockers.Count) { $blockers -join ',' } else { 'none' }
$hostLines = @("blockers=$blockTxt") + $hostLines
if ($blockers.Count -and -not $forceQuiet) {
  Log "ABORT: build/test activity running: $blockTxt"
  Write-HostReceipt 'blocked' $hostLines
  exit 3
}
if ($forceQuiet) {
  Log "host_quiet=forced: quiet gate bypassed (-Force); blockers seen: $blockTxt"
  Write-HostReceipt 'forced' (@('cpu_avg_pct=not_sampled') + $hostLines)
} else {
  Log "cpu sampling ${CpuSampleSeconds}s (gate: average total CPU <= $MaxIdleCpu%)"
  $snapA = Get-CpuMap
  $ctr = Get-Counter -Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples $CpuSampleSeconds
  $snapB = Get-CpuMap
  $cpuAvg = [math]::Round(($ctr.CounterSamples | Measure-Object -Property CookedValue -Average).Average, 1)
  $cores = [Environment]::ProcessorCount
  $raw = foreach ($id in $snapA.Keys) {
    if ($snapB.ContainsKey($id) -and $snapB[$id].Name -eq $snapA[$id].Name) {
      $d = $snapB[$id].Cpu - $snapA[$id].Cpu
      [pscustomobject]@{ Name = $snapA[$id].Name; Id = $id; Pct = [math]::Round($d / ($CpuSampleSeconds * $cores) * 100, 2) }
    }
  }
  $rows = @($raw | Sort-Object Pct -Descending)
  $cpuLines = $hostLines + @("cpu_avg_pct=$cpuAvg")
  foreach ($r in ($rows | Select-Object -First 5)) { $l = "top_cpu=$($r.Name)($($r.Id)) $($r.Pct)%"; Log $l; $cpuLines += $l }
  foreach ($r in ($rows | Select-Object -Skip 5 | Where-Object { $_.Pct -ge 1.0 })) { $l = "notable_cpu=$($r.Name)($($r.Id)) $($r.Pct)%"; Log $l; $cpuLines += $l }
  if ($cpuAvg -gt $MaxIdleCpu) {
    Log "ABORT: host busy, average total CPU $cpuAvg% > $MaxIdleCpu%"
    Write-HostReceipt 'busy' $cpuLines
    exit 5
  }
  Log "host_quiet=pass avg_cpu=$cpuAvg% blockers=$blockTxt"
  Write-HostReceipt 'pass' $cpuLines
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
  # stdout is block-buffered when redirected ('Started recording.' appears only at exit), and the CSV grows only when
  # something presents. Live signal: process alive and the CSV header written (the ETW session is open).
  $started = $alive -and ($csvLen -gt 0)
}
Log "presentmon started=$started csv_bytes=$csvLen"
if (-not $started) { Stop-Pm; Log 'ABORT: PresentMon not recording'; exit 4 }
Start-Sleep -Seconds 5

# 3) interactive one-shot task
$arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scripts\task-workload.ps1`" -Base `"$Base`" -RunRoot `"$runRoot`" -ResultFile `"$result`" -Runs $Runs -Warmup $Warmup -Measure $Measure -Instr $Instr -Rows $Rows -KeyRate $KeyRate$(if ($NoResources) { ' -NoResources' })"
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
