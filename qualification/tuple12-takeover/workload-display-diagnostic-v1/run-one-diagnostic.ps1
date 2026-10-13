# SR0 tuple12 one-run display diagnostic envelope.
# Reuses workload-controls-v8 run-workload under existing desktop.lock, then runs read-only sampler.
# This envelope adds no GUI operation, input, permission change, task registration, or process kill.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][string]$AnalysisRoot,
  [Parameter(Mandatory)][string]$OutRoot,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [string]$Lock = 'D:\Claude\desktop.lock',
  [string]$Tag = '',
  [ValidateRange(10,180)][int]$LockWaitSeconds = 60,
  [ValidateRange(1,60)][int]$Warmup = 10,
  [ValidateRange(5,120)][int]$Measure = 30,
  [ValidateRange(5,90)][int]$DiscoverySeconds = 45,
  [ValidateRange(1,120)][int]$SamplerSeconds = 35
)
$ErrorActionPreference = 'Stop'
$expectedExe = $ExpectExe.ToLowerInvariant(); $expectedDll = $ExpectDll.ToLowerInvariant()
if ($expectedExe -notmatch '^[0-9a-f]{64}$' -or $expectedDll -notmatch '^[0-9a-f]{64}$') { throw 'expected artifact hash is not SHA-256' }
foreach ($path in @($Base,$ControlRoot,$AnalysisRoot)) { if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "required directory missing: $path" } }
if (-not (Test-Path -LiteralPath $Lock -PathType Leaf)) { throw "desktop lock missing: $Lock" }
if (-not $Tag) { $Tag = 'tuple12-display-diagnostic-' + [guid]::NewGuid().ToString('N') }
if ($Tag -notmatch '^[A-Za-z0-9._-]+$') { throw 'tag contains unsafe characters' }
$outFull = [IO.Path]::GetFullPath($OutRoot); if (Test-Path -LiteralPath $outFull) { if (@(Get-ChildItem -LiteralPath $outFull -Force).Count -ne 0) { throw 'OutRoot must be fresh' } } else { [IO.Directory]::CreateDirectory($outFull) | Out-Null }
$runRoot = Join-Path $Base ("runs\" + $Tag); $receipt = Join-Path $outFull 'diagnostic-receipt.json'; $orchestratorStdout = Join-Path $outFull 'run-workload.stdout.txt'; $orchestratorStderr = Join-Path $outFull 'run-workload.stderr.txt'; $samplerStdoutPath = Join-Path $outFull 'display-context.stdout.txt'; $samplerStderrPath = Join-Path $outFull 'display-context.stderr.txt'; $raw = Join-Path $outFull 'display-context.jsonl'; $summary = Join-Path $outFull 'display-context-summary.json'
foreach ($path in @($receipt,$orchestratorStdout,$orchestratorStderr,$samplerStdoutPath,$samplerStderrPath,$raw,$summary,$runRoot)) { if (Test-Path -LiteralPath $path) { throw "fresh output already exists: $path" } }
$build = Get-Content -LiteralPath (Join-Path $Base 'build.json') -Raw | ConvertFrom-Json
if ([string]$build.exe_sha256 -cne $expectedExe -or [string]$build.dll_sha256 -cne $expectedDll) { throw 'build.json artifact pins differ from expected inputs' }
$bin = Split-Path ([string]$build.exe); $exe = Join-Path $bin 'WorkloadWin.exe'; $dll = Join-Path $bin 'swiftright_render.dll'
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedExe) { throw 'WorkloadWin.exe hash mismatch' }
if ((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedDll) { throw 'renderer hash mismatch' }
$runScript = Join-Path ([IO.Path]::GetFullPath($ControlRoot)) 'run-workload.ps1'; $samplerScript = Join-Path $PSScriptRoot 'display-context-sampler-v1.ps1'
foreach ($path in @($runScript,$samplerScript)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "pinned diagnostic source missing: $path" } }
$lockOwner = "SR0-T12-DISPLAY-$Tag $([DateTimeOffset]::UtcNow.ToString('o'))"; $lockHeld = $false; $lockReleased = $false; $releaseAllowed = $false; $releaseError = $null; $failure = $null
$runProc = $null; $runHandle = [IntPtr]::Zero; $runOutTask = $null; $runErrTask = $null; $runOutFile = $null; $runErrFile = $null; $runTerminal = $false; $runStdoutDrained = $false; $runStderrDrained = $false; $runExit = $null
$samplerProc = $null; $samplerHandle = [IntPtr]::Zero; $samplerOutTask = $null; $samplerErrTask = $null; $samplerOutFile = $null; $samplerErrFile = $null; $samplerTerminal = $false; $samplerStdoutDrained = $false; $samplerStderrDrained = $false; $samplerExit = $null
$targetPid = $null; $targetHwnd = $null; $samplerStarted = $false; $targetDiscovery='not-observed'; $resultText=''; $taskQuiescent=$false; $resultPath=Join-Path $runRoot 'result-workload.txt'; $runBudgetSeconds=$Warmup+$Measure+360
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sr0DisplayDiagnosticKernel {
  [DllImport("kernel32.dll", EntryPoint="WaitForSingleObject", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll", EntryPoint="GetExitCodeProcess", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
}
'@
function Quote-Arg([string]$value) { '"' + $value.Replace('"','\"') + '"' }
function Lock-Text([IO.FileStream]$stream) { $stream.Position=0; $bytes=New-Object byte[] ([int]$stream.Length); if ($bytes.Length) { [void]$stream.Read($bytes,0,$bytes.Length) }; [Text.Encoding]::UTF8.GetString($bytes).Trim() }
function Lock-Free([string]$text) { if ($text -eq 'free') { return $true }; try { $obj=$text|ConvertFrom-Json; foreach($field in @('state','status','value')) { if ($obj.PSObject.Properties.Name -contains $field -and [string]$obj.$field -eq 'free') { return $true } } } catch {}; return $false }
function Try-Acquire-Lock {
  try { $stream=[IO.File]::Open($Lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); try { if (-not (Lock-Free (Lock-Text $stream))) { return $false }; $bytes=[Text.Encoding]::UTF8.GetBytes("$lockOwner`r`n"); $stream.SetLength(0); $stream.Position=0; $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true); return $true } finally { $stream.Dispose() } } catch [IO.IOException] { return $false }
}
function Release-Lock {
  $stream=[IO.File]::Open($Lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); try { if ((Lock-Text $stream) -cne $lockOwner) { throw 'desktop lock ownership changed; preserving lock' }; $bytes=[Text.Encoding]::UTF8.GetBytes("free`r`n"); $stream.SetLength(0); $stream.Position=0; $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Kernel-Terminal([Diagnostics.Process]$process,[IntPtr]$handle,[ref]$code) { $code.Value=259; try { $process.Refresh(); if (-not $process.HasExited) { return $false }; [uint32]$native=259; $ok=[Sr0DisplayDiagnosticKernel]::GetExitCodeProcess($handle,[ref]$native); $code.Value=$native; return ($ok -and [Sr0DisplayDiagnosticKernel]::WaitForSingleObject($handle,0) -eq 0 -and $native -ne 259) } catch { return $false } }
function Start-PowerShellScript([string]$script,[string[]]$arguments,[string]$stdout,[string]$stderr) {
  $psi=New-Object Diagnostics.ProcessStartInfo; $psi.FileName=Join-Path $PSHOME 'powershell.exe'; $tokens=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$script) + @($arguments); $psi.Arguments=(($tokens | ForEach-Object { Quote-Arg ([string]$_) }) -join ' '); $psi.WorkingDirectory=$Base; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
  $process=[Diagnostics.Process]::new(); $process.StartInfo=$psi; if (-not $process.Start()) { throw "script did not start: $script" }; $handle=$process.Handle
  $out=[IO.File]::Open($stdout,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read); $err=[IO.File]::Open($stderr,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  [pscustomobject]@{ Process=$process; Handle=$handle; OutFile=$out; ErrFile=$err; OutTask=$process.StandardOutput.BaseStream.CopyToAsync($out); ErrTask=$process.StandardError.BaseStream.CopyToAsync($err) }
}
function Task-Quiescent { try { $task=Get-ScheduledTask -TaskName ("SR0BWorkload-$Tag") -ErrorAction SilentlyContinue; return ($null -eq $task -or $task.State -notin @('Running','Queued')) } catch { return $false } }
try {
  $lockDeadline=[DateTime]::UtcNow.AddSeconds($LockWaitSeconds); while (-not $lockHeld -and [DateTime]::UtcNow -lt $lockDeadline) { $lockHeld=Try-Acquire-Lock; if (-not $lockHeld) { Start-Sleep -Seconds 1 } }
  if (-not $lockHeld) { throw 'desktop lock did not become free within bounded wait' }
  $runArgs=@('-Base',([IO.Path]::GetFullPath($Base)),'-ControlRoot',([IO.Path]::GetFullPath($ControlRoot)),'-AnalysisRoot',([IO.Path]::GetFullPath($AnalysisRoot)),'-Instr','full','-Runs','1','-Warmup',"$Warmup",'-Measure',"$Measure",'-Rows','200','-KeyRate','10','-NoActivate','-LifecycleProof','-Tag',$Tag,'-ExpectDll',$expectedDll)
  $run = Start-PowerShellScript $runScript $runArgs $orchestratorStdout $orchestratorStderr; $runProc=$run.Process; $runHandle=$run.Handle; $runOutFile=$run.OutFile; $runErrFile=$run.ErrFile; $runOutTask=$run.OutTask; $runErrTask=$run.ErrTask
  $discoveryDeadline=[DateTime]::UtcNow.AddSeconds($DiscoverySeconds)
  while (-not $samplerStarted -and [DateTime]::UtcNow -lt $discoveryDeadline -and -not $runProc.HasExited) {
    if (Test-Path -LiteralPath $resultPath -PathType Leaf) { $resultText=[IO.File]::ReadAllText($resultPath) }
    $pm=[regex]::Match($resultText,'(?m)^pid run=r1 pid=([0-9]+)'); $wm=[regex]::Match($resultText,'(?m)^window run=r1 hwnd=([0-9-]+)')
    if ($pm.Success -and $wm.Success) {
      $targetPid=[int]$pm.Groups[1].Value; $targetHwnd=[IntPtr]::new([int64]$wm.Groups[1].Value); $targetDiscovery='observed-r1-pid-hwnd'
      $samplerArgs=@('-TargetPid',"$targetPid",'-TargetHwnd',"$($targetHwnd.ToInt64())",'-Out',$raw,'-Summary',$summary,'-DurationSeconds',"$SamplerSeconds",'-SampleMilliseconds','250')
      $sampler=Start-PowerShellScript $samplerScript $samplerArgs $samplerStdoutPath $samplerStderrPath; $samplerProc=$sampler.Process; $samplerHandle=$sampler.Handle; $samplerOutFile=$sampler.OutFile; $samplerErrFile=$sampler.ErrFile; $samplerOutTask=$sampler.OutTask; $samplerErrTask=$sampler.ErrTask; $samplerStarted=$true
    }
    if (-not $samplerStarted) { Start-Sleep -Milliseconds 500; $runProc.Refresh() }
  }
  $runDeadline=[DateTime]::UtcNow.AddSeconds($runBudgetSeconds); while (-not $runProc.HasExited -and [DateTime]::UtcNow -lt $runDeadline) { Start-Sleep -Seconds 1; $runProc.Refresh() }
  [uint32]$runCode=259; $runTerminal=Kernel-Terminal $runProc $runHandle ([ref]$runCode); if ($runTerminal) { $runExit=[int64]$runCode }
  $runStdoutDrained=$runOutTask.Wait(15000); $runStderrDrained=$runErrTask.Wait(15000)
  if ($samplerStarted) { $samplerDeadline=[DateTime]::UtcNow.AddSeconds($SamplerSeconds+20); while (-not $samplerProc.HasExited -and [DateTime]::UtcNow -lt $samplerDeadline) { Start-Sleep -Milliseconds 500; $samplerProc.Refresh() }; [uint32]$samplerCode=259; $samplerTerminal=Kernel-Terminal $samplerProc $samplerHandle ([ref]$samplerCode); if ($samplerTerminal) { $samplerExit=[int64]$samplerCode }; $samplerStdoutDrained=$samplerOutTask.Wait(15000); $samplerStderrDrained=$samplerErrTask.Wait(15000) }
  if (Test-Path -LiteralPath $resultPath -PathType Leaf) { $resultText=[IO.File]::ReadAllText($resultPath) }; $taskQuiescent=Task-Quiescent
  $releaseAllowed=$runTerminal -and $runStdoutDrained -and $runStderrDrained -and $taskQuiescent -and $samplerStarted -and $samplerTerminal -and $samplerStdoutDrained -and $samplerStderrDrained
} catch { $failure=$_.Exception.Message }
finally {
  foreach ($stream in @($runOutFile,$runErrFile,$samplerOutFile,$samplerErrFile)) { if ($stream) { try { $stream.Flush(); $stream.Dispose() } catch {} } }
  if ($lockHeld -and $releaseAllowed) { try { Release-Lock; $lockReleased=$true } catch { $releaseError=$_.Exception.Message } }
  $status=if ($lockReleased -and $samplerStarted -and $samplerTerminal) { 'observed' } else { 'failed' }
  $obj=[ordered]@{ kind='sr0-tuple12-workload-display-diagnostic-v1'; status=$status; tag=$Tag; lockOwner=$lockOwner; lockHeld=$lockHeld; lockReleased=$lockReleased; releaseAllowed=$releaseAllowed; releaseError=$releaseError; runScript=$runScript; runRoot=$runRoot; runBudgetSeconds=$runBudgetSeconds; runHandle=$runHandle.ToInt64(); runTerminal=$runTerminal; runExit=$runExit; runStdoutDrained=$runStdoutDrained; runStderrDrained=$runStderrDrained; samplerScript=$samplerScript; samplerStarted=$samplerStarted; samplerHandle=$samplerHandle.ToInt64(); samplerTerminal=$samplerTerminal; samplerExit=$samplerExit; samplerStdoutDrained=$samplerStdoutDrained; samplerStderrDrained=$samplerStderrDrained; targetPid=$targetPid; targetHwnd=$(if($null -ne $targetHwnd){$targetHwnd.ToInt64()}else{$null}); targetDiscovery=$targetDiscovery; taskQuiescent=$taskQuiescent; resultWorkload=$resultPath; rawContext=$raw; contextSummary=$summary; failure=$failure; nativeConclusion='display-context-only; strict PresentMon displayed-row gate unchanged' }
  $bytes=[Text.Encoding]::UTF8.GetBytes(($obj|ConvertTo-Json -Depth 12)+"`r`n"); $stream=[IO.File]::Open($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read); try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }; if($runProc){$runProc.Dispose()}; if($samplerProc){$samplerProc.Dispose()}; $obj|ConvertTo-Json -Depth 12|Write-Output
}
if ($status -eq 'observed') { exit 0 } else { exit 1 }
