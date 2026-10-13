# SR0 workload orchestrator (Windows). Run as a FILE from an ELEVATED session (PresentMon needs ETW rights):
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0b-workload\probes\sr0-b\workload\scripts\run-workload.ps1 -Instr full"
# 1) artifact identity gate (exe + renderer DLL hashes); host load is recorded as context, never gated (R10: the Dell is in normal use)
# 2) PresentMon 2.6.0, ALL-process capture (no --process_name), QPC time, started first and confirmed recording
# 3) a one-shot INTERACTIVE scheduled task runs task-workload.ps1 (3 runs: 10 s warm-up + 60 s measured each, PostMessage script)
# 4) PresentMon stopped, task removed, analyze_workload.py joins input QPC stamps to presented frames (PID match, as frame-clock batch 5)
# Nothing here touches the desktop of another application: keys are POSTED to the workload window only (it need not be foreground).
# Stress / resources (R10): -Rows (200 default; stress 1000, 5000) and -KeyRate (10 default; stress 30) go to task-workload.ps1 (-Rows reaches the app as
# `--rows N`; an app build that ignores it is caught by the analyzer, which compares meta.json total_rows). Every run samples CPU / threads / memory / GPU
# into <run>\resources.csv unless -NoResources (overhead A/B). scripts\run-stress.ps1 runs the Rows x KeyRate series through this script.
param(
  [string]$Base = 'D:\Claude\swiftright\.work\sr0-r10\workload',
  [string]$ControlRoot = '',
  [string]$AnalysisRoot = '',
  [string]$Instr = 'full',            # full | light (light = overhead A/B baseline; analyzer reports it as such)
  [int]$Runs = 3,
  [int]$Warmup = 10,
  [int]$Measure = 60,
  [int]$Rows = 200,                   # editable rows the app runs with (200 = the section 11 workload; stress series 1000, 5000)
  [double]$KeyRate = 10,              # keys per second posted to the workload window (10 = the section 11 workload; stress series 30)
  [switch]$NoResources,               # skip the resource sampler (overhead A/B)
  [switch]$LifecycleProof,             # tuple12 opt-in: retain task/process terminal proof before removal
  [string]$PaintPhaseMs = '',         # R10 A/B: SWR_PAINT_PHASE_MS handed to the renderer through task-workload.ps1 (0 = pacing off; '' = renderer default)
  [switch]$MemDeep,                   # R10 memory diagnosis: SWR_MEM_DEEP=1 for the renderer (heap and address-space walk every 5th memory sample; diagnostic run, perturbs timing)
  [switch]$NoActivate,                 # tuple12 opt-in: pass startup guard & bottommost window policy to task-workload.ps1
  [string]$Tag = '',
  [string]$ExpectDll = 'E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93',
  [double]$ExpectScale = 2.5,         # Dell tuple: 250% (dpi 240); every SR0 Dell record is scale 2.5
  [int]$MaxIdleCpu = 25,              # ignored since R10 (no quiet-host gate; the host is in normal use)
  [int]$CpuSampleSeconds = 20,        # ignored since R10
  [switch]$Force,                     # bypass the quiet-host gate; receipt is marked host_quiet=forced
  [switch]$SkipQuietCheck             # legacy alias for -Force
)
$ErrorActionPreference = 'Continue'
if (-not $Tag) { $Tag = (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$Instr" }
$controlRoot = if ($ControlRoot) { [IO.Path]::GetFullPath($ControlRoot) } else { "$Base\probes\sr0-b\workload\scripts" }
$analysis = if ($AnalysisRoot) { [IO.Path]::GetFullPath($AnalysisRoot) } else { "$Base\probes\sr0-b\workload\analysis" }
$scripts  = $controlRoot
$runRoot  = "$Base\runs\$Tag"
$pmExe    = 'D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe'
$pmSession = "SR0BWL-$Tag"
$pmProc = $null
$pmHandle = [IntPtr]::Zero
$pmStdout = $null
$pmStderr = $null
$pmStdoutPath = "$runRoot\presentmon.stdout.txt"
$pmSessionLog = "$runRoot\presentmon.session.txt"
$pmCsv    = "$runRoot\presentmon.csv"
$pmCon    = "$runRoot\presentmon.console.txt"
$pmCmd    = "$runRoot\pm-run.cmd"
$result   = "$runRoot\result-workload.txt"
$orchLog  = "$runRoot\orchestrator.log"
$taskName = 'SR0BWorkload'
$pmKernelTerminal = $false
[uint32]$pmKernelExit = 259
[int64]$pmDotnetExit = 259
$pmStdoutDone = $false
$pmStderrDone = $false
$pmForcedStop = $false
$pmStopMode = 'unknown'
$pmKernelExitSigned = 259L
[uint64]$pmKernelExitRaw = 259
$pmSessionStopExit = $null
$pmSessionAbsent = $false
$pmSessionStopOutput = ''
$pmSessionQueryOutput = ''
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class Sr0Tuple12PresentMonKernel {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    public static long SignedDword(uint code) { return unchecked((int)code); }
    public static bool Terminal(IntPtr h, Process p, out uint code) {
        code = 259;
        try {
            p.Refresh();
            if (!p.HasExited) return false;
            if (WaitForSingleObject(h, 0) != 0) return false;
            if (!GetExitCodeProcess(h, out code)) return false;
            return code != 259;
        } catch { return false; }
    }
}
'@
if ($LifecycleProof) {
  if ($Tag -notmatch '^[A-Za-z0-9._-]+$') { throw 'LifecycleProof requires an alphanumeric task tag' }
  $taskName = "SR0BWorkload-$Tag"
}
if ($LifecycleProof -and (Test-Path $runRoot)) { throw "LifecycleProof requires fresh run root: $runRoot" }
New-Item -ItemType Directory -Force $runRoot | Out-Null
if ($LifecycleProof -and (Test-Path $result)) { throw "LifecycleProof requires fresh result path: $result" }
function Log([string]$m) { $l = "{0} {1}" -f (Get-Date -Format o), $m; Add-Content -Path $orchLog -Value $l; $l }
function Read-Shared([string]$p) {
  if (-not (Test-Path $p)) { return '' }
  try {
    $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { $sr = New-Object IO.StreamReader($fs); $t = $sr.ReadToEnd(); $sr.Dispose(); return $t } finally { $fs.Dispose() }
  } catch { return '' }
}
function Invoke-Logman([string[]]$arguments) {
  $exe=Join-Path $env:SystemRoot 'System32\logman.exe'
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return [ordered]@{ available=$false; exit=$null; stdout=''; stderr='logman.exe missing' } }
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$exe; $psi.Arguments=(($arguments | ForEach-Object { '"' + ([string]$_).Replace('"','\"') + '"' }) -join ' ')
  $psi.WorkingDirectory=$runRoot; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
  $p=[Diagnostics.Process]::Start($psi); if ($null -eq $p) { return [ordered]@{ available=$false; exit=$null; stdout=''; stderr='logman did not start' } }
  $h=$p.Handle; $so=$p.StandardOutput.ReadToEndAsync(); $se=$p.StandardError.ReadToEndAsync(); $p.WaitForExit()
  $so.Wait(15000); $se.Wait(15000); $code=[int64]$p.ExitCode
  $obj=[ordered]@{ available=$true; handle=$h.ToInt64(); exit=$code; stdout=$so.Result; stderr=$se.Result }
  $p.Dispose(); return $obj
}
function Stop-UniquePresentMonSession {
  $stop=Invoke-Logman @('stop',$pmSession,'-ets'); $script:pmSessionStopExit=$stop.exit; $script:pmSessionStopOutput=([string]$stop.stdout + [string]$stop.stderr)
  $deadline=[DateTime]::UtcNow.AddSeconds(30); $last=''
  while ([DateTime]::UtcNow -lt $deadline) {
    $q=Invoke-Logman @('query',$pmSession,'-ets'); $script:pmSessionQueryOutput=([string]$q.stdout + [string]$q.stderr); $last=$script:pmSessionQueryOutput
    $notFound=($q.exit -eq -2144337918 -or $last -match '(?i)data collector set was not found|data collectors? set.*not found|does not exist|not found')
    if ($notFound) { $script:pmSessionAbsent=$true; return }
    Start-Sleep -Seconds 1
  }
  $script:pmSessionAbsent=$false
}
function Stop-Pm {
  if (-not $pmProc) { return }
  try { $pmProc.Refresh(); if (-not $pmProc.HasExited) { [void]$pmProc.WaitForExit(60000) } } catch { }
  try { $pmProc.Refresh() } catch { }
  if (-not $pmProc.HasExited) { $script:pmForcedStop = $true; try { $pmProc.Kill() } catch { }; try { [void]$pmProc.WaitForExit(15000) } catch { }; try { $pmProc.Refresh() } catch { } }
  try { $pmProc.Refresh() } catch { }
  # Preserve signed .NET exit & raw DWORD separately; unchecked conversion keeps -1 bit-exact.
  $script:pmDotnetExit = if ($pmProc.HasExited) { [int64]$pmProc.ExitCode } else { [int64]259 }
  $script:pmKernelExit = 259
  $script:pmKernelTerminal = [Sr0Tuple12PresentMonKernel]::Terminal($pmHandle, $pmProc, [ref]$script:pmKernelExit)
  $script:pmKernelExitRaw=[uint64]$script:pmKernelExit
  $script:pmKernelExitSigned=[Sr0Tuple12PresentMonKernel]::SignedDword($script:pmKernelExit)
  $script:pmStopMode = if ($script:pmForcedStop) { 'forced-owned' } else { 'natural' }
  Stop-UniquePresentMonSession
  $script:pmTerminal = $script:pmKernelTerminal -and ($script:pmKernelExit -ne 259) -and ($script:pmKernelExitSigned -eq $script:pmDotnetExit)
  $script:pmStdoutDone = if ($pmStdout) { $pmStdout.Wait(15000) } else { $true }
  $script:pmStderrDone = if ($pmStderr) { $pmStderr.Wait(15000) } else { $true }
  $pmOut = if ($script:pmStdoutDone) { $pmStdout.Result } else { '<presentmon-stdout-drain-timeout>' }
  $pmErr = if ($script:pmStderrDone) { $pmStderr.Result } else { '<presentmon-stderr-drain-timeout>' }
  [IO.File]::WriteAllText($pmStdoutPath, $pmOut)
  [IO.File]::WriteAllText($pmSessionLog, "session=$pmSession terminal=$script:pmTerminal kernel_terminal=$script:pmKernelTerminal kernel_exit_raw=$script:pmKernelExitRaw kernel_exit=$script:pmKernelExitSigned dotnet_exit=$script:pmDotnetExit exit=$script:pmDotnetExit stop=$script:pmStopMode handle=$pmHandle stdout_drained=$script:pmStdoutDone stderr_drained=$script:pmStderrDone session_stop_exit=$script:pmSessionStopExit session_absent=$script:pmSessionAbsent")
  [IO.File]::WriteAllText("$runRoot\pm-stderr.txt", $pmErr)
  Log "presentmon terminal=$script:pmTerminal kernel_terminal=$script:pmKernelTerminal kernel_exit_raw=$script:pmKernelExitRaw kernel_exit=$script:pmKernelExitSigned dotnet_exit=$script:pmDotnetExit exit=$script:pmDotnetExit stop=$script:pmStopMode session=$pmSession handle=$pmHandle stdout_drained=$script:pmStdoutDone stderr_drained=$script:pmStderrDone session_stop_exit=$script:pmSessionStopExit session_absent=$script:pmSessionAbsent"
}

Log "run-workload tag=$Tag instr=$Instr runs=$Runs warmup=$Warmup measure=$Measure rows=$Rows key_rate=$KeyRate noactivate=$(if ($NoActivate) { 'on' } else { 'off' }) resources=$(if ($NoResources) { 'off' } else { 'on' }) paint_phase_ms=$(if ($PaintPhaseMs -eq '') { 'default' } else { $PaintPhaseMs })"
$null = Log ("whoami=" + (whoami) + " elevated=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

# 1) gates
$art = & "$scripts\verify-artifacts.ps1" -Base $Base -ExpectDll $ExpectDll
$art | ForEach-Object { Log $_ }
if (-not ($art -match 'ARTIFACT_OK')) { Log 'ABORT: artifact gate failed'; exit 2 }
# 1b) host context (R10: NO quiet-host gate). The Dell is a working machine (the user's own apps, agents, a build now and then) and the product has to
# meet its budget under that normal load, so nothing here can stop a run. What was running is recorded: build/test processes and SR0 scheduled tasks
# seen now (host-quiet.txt, receipt state `context_only`); the harness adds per-run user input, foreground owners, overlay hooks and the CPU by process
# over each run, and the sampler records total CPU every second. The analyzer voids a run only for a window that stopped presenting / was minimized or
# a CPU saturated above ~90 % for most of the measured window. -Force / -SkipQuietCheck / -MaxIdleCpu / -CpuSampleSeconds are accepted and ignored.
$hostRcpt   = "$runRoot\host-quiet.txt"
$buildNames = @('cargo','rustc','swift-build','swift-frontend','swiftc','link','cl','clang','lld-link','msbuild','makeappx','signtool')
$ownPattern = '^(FreshOnBridge|BridgeSmoke|SliceApp|Workload|SwiftHost)'
$seen = @()
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
  $pth = try { $p.Path } catch { $null }
  $isOurs = [bool]($pth -and $pth.StartsWith($Base, [StringComparison]::OrdinalIgnoreCase))
  if (($buildNames -contains $p.ProcessName) -or (($p.ProcessName -match $ownPattern) -and -not $isOurs)) { $seen += "$($p.ProcessName)($($p.Id))" }
}
$hostLines = @()
foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'SR0*' -and $_.TaskName -ne $taskName })) { $hostLines += "sched_sr0=$($t.TaskName) state=$($t.State)" }
$seenTxt = if ($seen.Count) { $seen -join ',' } else { 'none' }
Set-Content -Path $hostRcpt -Value (@('host_quiet=context_only', "build_or_test_processes_seen=$seenTxt") + $hostLines) -Encoding ascii
Log "host context (not a gate): build/test processes seen=$seenTxt"

# 2) PresentMon: all-process capture, QPC time, unique owned session, no process filter. Total capture window with margin.
$timed = $Runs * ($Warmup + $Measure + 25) + 60
$pmArgs = @('--v1_metrics','--qpc_time','--no_track_gpu','--no_track_input','--no_console_stats','--write_display_metadata','--session_name',$pmSession,'--output_file',$pmCsv,'--timed',"$timed",'--terminate_after_timed')
try {
  # ProcessStartInfo owns stdout/stderr pipes, so retained process handle + bounded drains are real, rather than Start-Process file redirection plus an unusable stream.
  $pmPsi = New-Object System.Diagnostics.ProcessStartInfo
  $pmPsi.FileName = $pmExe
  $pmPsi.Arguments = (($pmArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ } }) -join ' ')
  $pmPsi.WorkingDirectory = $runRoot
  $pmPsi.UseShellExecute = $false
  $pmPsi.CreateNoWindow = $true
  $pmPsi.RedirectStandardOutput = $true
  $pmPsi.RedirectStandardError = $true
  $pmProc = [System.Diagnostics.Process]::Start($pmPsi)
  $pmHandle = $pmProc.Handle
  $pmStdout = $pmProc.StandardOutput.ReadToEndAsync()
  $pmStderr = $pmProc.StandardError.ReadToEndAsync()
  Set-Content -Path $pmSessionLog -Value ("session=$pmSession pid=$($pmProc.Id) handle=$pmHandle") -Encoding ascii
} catch {
  Log "ABORT: PresentMon start failed: $($_.Exception.Message)"; exit 4
}
$started = $false; $d = (Get-Date).AddSeconds(60); $csvLen = 0
while (-not $started -and (Get-Date) -lt $d) {
  Start-Sleep -Milliseconds 500
  try { $pmProc.Refresh() } catch { }
  $alive = $pmProc -and -not $pmProc.HasExited
  $csvLen = if (Test-Path $pmCsv) { (Get-Item $pmCsv).Length } else { 0 }
  $started = $alive -and ($csvLen -gt 0)
}
Log "presentmon started=$started csv_bytes=$csvLen session=$pmSession pid=$($pmProc.Id) handle=$pmHandle"
if (-not $started) { Stop-Pm; Log 'ABORT: PresentMon not recording'; exit 4 }

Start-Sleep -Seconds 5

# 3) interactive one-shot task
$controlArg = if ($ControlRoot) { " -ControlRoot `"$controlRoot`"" } else { '' }
$arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scripts\task-workload.ps1`" -Base `"$Base`"$controlArg -RunRoot `"$runRoot`" -ResultFile `"$result`" -Runs $Runs -Warmup $Warmup -Measure $Measure -Instr $Instr -Rows $Rows -KeyRate $KeyRate$(if ($LifecycleProof) { ' -LifecycleProof' })$(if ($NoActivate) { ' -NoActivate' })$(if ($NoResources) { ' -NoResources' })$(if ($PaintPhaseMs -ne '') { " -PaintPhaseMs $PaintPhaseMs" })$(if ($MemDeep) { ' -MemDeep' })"
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $Base
$pri = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes (($Runs * ($Warmup + $Measure + 60)) / 60 + 10)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
if ($LifecycleProof) {
  $prior = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($prior -and $prior.State -in @('Running', 'Queued')) { Log "ABORT: existing task state=$($prior.State)"; Stop-Pm; exit 6 }
  Register-ScheduledTask -TaskName $taskName -Action $act -Principal $pri -Settings $set -ErrorAction Stop | Out-Null
  Log "registered $taskName lifecycle_proof=on"
  Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
} else {
  Register-ScheduledTask -TaskName $taskName -Action $act -Principal $pri -Settings $set -Force | Out-Null
  Log "registered $taskName"
  Start-ScheduledTask -TaskName $taskName
}
$fin = $false; $st = 'Running'; $d = (Get-Date).AddSeconds($Runs * ($Warmup + $Measure + 90) + 120)
do {
  Start-Sleep -Seconds 5
  $st = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State
  $fin = (Read-Shared $result) -match 'finished='
} while (-not $fin -and (($LifecycleProof -and $st -in @('Running', 'Queued')) -or (-not $LifecycleProof -and $st -eq 'Running')) -and (Get-Date) -lt $d)
$proofText = Read-Shared $result
$proof = $proofText -match 'worker_terminal=1' -and (($proofText -match 'sampler_terminal=1') -or $NoResources) -and $proofText -match 'task_quiescent=1'
if ($LifecycleProof -and (-not $fin -or -not $proof)) { Log "ABORT: lifecycle proof missing finished=$fin proof=$proof task_state=$st"; Stop-Pm; exit 7 }
while ($LifecycleProof -and $st -in @('Running', 'Queued') -and (Get-Date) -lt $d) { Start-Sleep -Seconds 2; $st = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State }
if ($LifecycleProof -and $st -in @('Running', 'Queued')) { Log "ABORT: task not quiescent state=$st"; Stop-Pm; exit 8 }
Log "harness finished=$fin task_state=$st lifecycle_proof=$proof"
if ($LifecycleProof) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop } else { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3
Stop-Pm
if ($LifecycleProof -and (-not $pmKernelTerminal -or -not $pmStdoutDone -or -not $pmStderrDone -or $pmKernelExitSigned -ne $pmDotnetExit -or -not $pmSessionAbsent)) { Log 'ABORT: PresentMon terminal/exit/drain proof missing'; exit 9 }

# 4) analysis (python 3.11, isolated mode)
Copy-Item "$Base\build.json" "$runRoot\build.json" -Force
& py -3.11 -I "$analysis\analyze_workload.py" --os windows --root $runRoot --expect-scale $ExpectScale --out "$runRoot\report" 2>&1 | Tee-Object -FilePath "$runRoot\analysis-console.txt"
$analysisRc = $LASTEXITCODE
Log "analysis rc=$analysisRc report=$runRoot\report"
if ($LifecycleProof) { exit $analysisRc }
