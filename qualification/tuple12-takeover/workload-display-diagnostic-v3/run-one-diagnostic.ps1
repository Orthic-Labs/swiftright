# SR0 tuple12 display diagnostic v3.
# Uses v6 Sr0OwnedJobProcess for workload-controls-v8 & read-only sampler.
# Every child is created suspended, assigned to a 1 GiB kill-on-close job,
# readers start before resume, and handles remain until terminal/drain/active=0.
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
  [ValidateRange(1,120)][int]$SamplerSeconds = 35,
  [ValidateRange(30,1200)][int]$ChildDeadlineSeconds = 420,
  [ValidateRange(1048576,67108864)][int64]$StreamCapBytes = 8388608,
  [ValidateRange(134217728,4294967296)][int64]$RssCapBytes = 2147483648
)
$ErrorActionPreference = 'Stop'
$expectedExe = $ExpectExe.ToLowerInvariant(); $expectedDll = $ExpectDll.ToLowerInvariant()
if ($expectedExe -notmatch '^[0-9a-f]{64}$' -or $expectedDll -notmatch '^[0-9a-f]{64}$') { throw 'expected artifact hash is not SHA-256' }
foreach ($path in @($Base,$ControlRoot,$AnalysisRoot)) { if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "required directory missing: $path" } }
if (-not (Test-Path -LiteralPath $Lock -PathType Leaf)) { throw "desktop lock missing: $Lock" }
if (-not $Tag) { $Tag = 'tuple12-display-diagnostic-' + [guid]::NewGuid().ToString('N') }
if ($Tag -notmatch '^[A-Za-z0-9._-]+$') { throw 'tag contains unsafe characters' }
$outFull = [IO.Path]::GetFullPath($OutRoot)
if (Test-Path -LiteralPath $outFull) { if (@(Get-ChildItem -LiteralPath $outFull -Force).Count -ne 0) { throw 'OutRoot must be fresh' } } else { [IO.Directory]::CreateDirectory($outFull) | Out-Null }
$runRoot = Join-Path $Base ("runs\" + $Tag)
$receipt = Join-Path $outFull 'diagnostic-receipt.json'
$runStdout = Join-Path $outFull 'run-workload.stdout.txt'; $runStderr = Join-Path $outFull 'run-workload.stderr.txt'
$samplerStdout = Join-Path $outFull 'display-context.stdout.txt'; $samplerStderr = Join-Path $outFull 'display-context.stderr.txt'
$raw = Join-Path $outFull 'display-context.jsonl'; $summary = Join-Path $outFull 'display-context-summary.json'
foreach ($path in @($receipt,$runStdout,$runStderr,$samplerStdout,$samplerStderr,$raw,$summary,$runRoot)) { if (Test-Path -LiteralPath $path) { throw "fresh output already exists: $path" } }
$build = Get-Content -LiteralPath (Join-Path $Base 'build.json') -Raw | ConvertFrom-Json
if ([string]$build.exe_sha256 -cne $expectedExe -or [string]$build.dll_sha256 -cne $expectedDll) { throw 'build.json artifact pins differ from expected inputs' }
$bin = Split-Path ([string]$build.exe); $exe = Join-Path $bin 'WorkloadWin.exe'; $dll = Join-Path $bin 'swiftright_render.dll'
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedExe) { throw 'WorkloadWin.exe hash mismatch' }
if ((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedDll) { throw 'renderer hash mismatch' }
$runScript = Join-Path ([IO.Path]::GetFullPath($ControlRoot)) 'run-workload.ps1'
$samplerScript = Join-Path $PSScriptRoot 'display-context-sampler-v1.ps1'
$helperPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\workload-incremental-v6\shared\Sr0OwnedJobProcess.cs'))
foreach ($path in @($runScript,$samplerScript,$helperPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "pinned diagnostic source missing: $path" } }
Add-Type -Path $helperPath
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class Sr0DiagnosticSessionV3 {
  [DllImport("kernel32.dll", EntryPoint="ProcessIdToSessionId", SetLastError=true)]
  private static extern bool ProcessIdToSessionId(uint pid, out uint session);
  [DllImport("kernel32.dll", EntryPoint="WTSGetActiveConsoleSessionId")]
  private static extern uint WTSGetActiveConsoleSessionId();
  public static bool CurrentMatchesActive(out uint current, out uint active) {
    current=0; active=WTSGetActiveConsoleSessionId();
    return ProcessIdToSessionId((uint)Process.GetCurrentProcess().Id, out current) && current == active;
  }
}
'@

$lockOwner = "SR0-T12-DISPLAY-$Tag $([DateTimeOffset]::UtcNow.ToString('o'))"; $lockHeld=$false; $lockReleased=$false; $releaseAllowed=$false; $releaseError=$null; $failure=$null; $sessionAdmission='not-checked'; [uint32]$currentSession=0; [uint32]$activeConsoleSession=0; $sessionMatch=$false
$runOwned=$null; $samplerOwned=$null; $runResult=$null; $samplerResult=$null; $targetPid=$null; $targetHwnd=$null; $targetDiscovery='not-observed'; $taskQuiescent=$false; $resultText=''; $resultPath=Join-Path $runRoot 'result-workload.txt'

function Lock-Text([IO.FileStream]$stream) { $stream.Position=0; $bytes=New-Object byte[] ([int]$stream.Length); if ($bytes.Length) { [void]$stream.Read($bytes,0,$bytes.Length) }; [Text.Encoding]::UTF8.GetString($bytes).Trim() }
function Lock-Free([string]$text) { if ($text -eq 'free') { return $true }; try { $obj=$text|ConvertFrom-Json; foreach($field in @('state','status','value')) { if ($obj.PSObject.Properties.Name -contains $field -and [string]$obj.$field -eq 'free') { return $true } } } catch {}; return $false }
function Try-Acquire-Lock { try { $stream=[IO.File]::Open($Lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); try { if (-not (Lock-Free (Lock-Text $stream))) { return $false }; $bytes=[Text.Encoding]::UTF8.GetBytes("$lockOwner`r`n"); $stream.SetLength(0); $stream.Position=0; $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true); return $true } finally { $stream.Dispose() } } catch [IO.IOException] { return $false } }
function Release-Lock { $stream=[IO.File]::Open($Lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); try { if ((Lock-Text $stream) -cne $lockOwner) { throw 'desktop lock ownership changed; preserving lock' }; $bytes=[Text.Encoding]::UTF8.GetBytes("free`r`n"); $stream.SetLength(0); $stream.Position=0; $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() } }
function Task-Quiescent { try { $task=Get-ScheduledTask -TaskName ("SR0BWorkload-$Tag") -ErrorAction SilentlyContinue; return ($null -eq $task -or $task.State -notin @('Running','Queued')) } catch { return $false } }

function Close-Owned([pscustomobject]$owned) {
  if ($null -eq $owned) { return }
  foreach ($stream in @($owned.OutPipe,$owned.ErrPipe,$owned.OutFile,$owned.ErrFile)) { if ($stream) { try { $stream.Dispose() } catch {} } }
  foreach ($handle in @($owned.Thread,$owned.Process,$owned.StdoutRead,$owned.StderrRead,$owned.Job)) { if ($handle -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($handle) | Out-Null } }
}

function Start-OwnedScript([string]$script,[string[]]$arguments,[string]$stdoutPath,[string]$stderrPath,[string]$workDir) {
  $job=[IntPtr]::Zero; $process=[IntPtr]::Zero; $thread=[IntPtr]::Zero; $stdoutRead=[IntPtr]::Zero; $stderrRead=[IntPtr]::Zero; $assigned=$false; $success=$false; $outPipe=$null; $errPipe=$null; $outFile=$null; $errFile=$null; $outTask=$null; $errTask=$null
  try {
    $job=[Sr0OwnedJobProcess]::CreateJob(); if ($job -eq [IntPtr]::Zero) { throw 'diagnostic job create failed' }
    if (-not [Sr0OwnedJobProcess]::ConfigureJob($job,1073741824)) { throw 'diagnostic job memory cap failed' }
    $tokens=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$script)+@($arguments)
    $argText=($tokens|ForEach-Object { [Sr0OwnedJobProcess]::QuoteWindowsArgument([string]$_) }) -join ' '; $powershell=Join-Path $PSHOME 'powershell.exe'; $cmdline=[Sr0OwnedJobProcess]::BuildCommandLine($powershell,$argText); [uint32]$childPid=0
    if (-not [Sr0OwnedJobProcess]::CreateSuspended($powershell,$cmdline,$workDir,[ref]$process,[ref]$thread,[ref]$stdoutRead,[ref]$stderrRead,[ref]$childPid)) { throw 'diagnostic suspended create failed' }
    $outPipe=New-Object IO.FileStream($stdoutRead,[IO.FileAccess]::Read,$false); $errPipe=New-Object IO.FileStream($stderrRead,[IO.FileAccess]::Read,$false)
    $outFile=[IO.File]::Open($stdoutPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read); $errFile=[IO.File]::Open($stderrPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $outTask=$outPipe.CopyToAsync($outFile); $errTask=$errPipe.CopyToAsync($errFile)
    if (-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,$process)) { throw 'diagnostic job assignment failed' }; $assigned=$true
    if ([Sr0OwnedJobProcess]::ResumeThread($thread,$process) -eq [uint32]::MaxValue) { throw 'diagnostic resume failed' }
    $success=$true
    return [pscustomobject]@{ Job=$job; Process=$process; Thread=$thread; StdoutRead=$stdoutRead; StderrRead=$stderrRead; ProcessId=$childPid; Assigned=$assigned; OutPipe=$outPipe; ErrPipe=$errPipe; OutFile=$outFile; ErrFile=$errFile; OutTask=$outTask; ErrTask=$errTask }
  } finally {
    if (-not $success) {
      if ($process -ne [IntPtr]::Zero) { if ($assigned) { [Sr0OwnedJobProcess]::TerminateJobObject($job,124) | Out-Null } else { [Sr0OwnedJobProcess]::TerminateProcess($process,124) | Out-Null }; [Sr0OwnedJobProcess]::WaitForSingleObject($process,15000) | Out-Null }
      Close-Owned ([pscustomobject]@{ Job=$job; Process=$process; Thread=$thread; StdoutRead=$stdoutRead; StderrRead=$stderrRead; OutPipe=$outPipe; ErrPipe=$errPipe; OutFile=$outFile; ErrFile=$errFile })
    }
  }
}

function Wait-Owned([pscustomobject]$owned,[int]$deadlineSeconds) {
  $timedOut=$false; $outputExceeded=$false; $rssExceeded=$false; $terminal=$false; $outDone=$false; $errDone=$false; $activeReadable=$false; [uint32]$active=1; [uint32]$exitCode=259; [int64]$peakRss=0; [int64]$rssSamples=0; $watch=[Diagnostics.Stopwatch]::StartNew()
  while ($true) {
    $wait=[Sr0OwnedJobProcess]::WaitForSingleObject($owned.Process,1000)
    foreach ($path in @($owned.OutFile.Name,$owned.ErrFile.Name)) { if ((Get-Item -LiteralPath $path).Length -gt $StreamCapBytes) { $outputExceeded=$true } }
    try { $p=[Diagnostics.Process]::GetProcessById([int]$owned.ProcessId); $rss=[int64]$p.WorkingSet64; $rssSamples++; if($rss -gt $peakRss){$peakRss=$rss}; $p.Dispose() } catch {}
    if ($peakRss -gt $RssCapBytes) { $rssExceeded=$true }
    if ($wait -eq [Sr0OwnedJobProcess]::WaitObject0) { $terminal=$true; break }
    if ($outputExceeded -or $rssExceeded) { break }
    if ($watch.Elapsed.TotalSeconds -ge $deadlineSeconds) { $timedOut=$true; break }
  }
  if ($timedOut -or $outputExceeded -or $rssExceeded) { [Sr0OwnedJobProcess]::TerminateJobObject($owned.Job,124) | Out-Null; $wait=[Sr0OwnedJobProcess]::WaitForSingleObject($owned.Process,15000); $terminal=($wait -eq [Sr0OwnedJobProcess]::WaitObject0) }
  $outDone=$owned.OutTask.Wait(30000); $errDone=$owned.ErrTask.Wait(30000)
  foreach ($path in @($owned.OutFile.Name,$owned.ErrFile.Name)) { if ((Get-Item -LiteralPath $path).Length -gt $StreamCapBytes) { $outputExceeded=$true } }
  if (-not $outDone -or -not $errDone) { [Sr0OwnedJobProcess]::TerminateJobObject($owned.Job,124) | Out-Null; [Sr0OwnedJobProcess]::WaitForSingleObject($owned.Process,15000) | Out-Null; $outDone=$owned.OutTask.Wait(5000); $errDone=$owned.ErrTask.Wait(5000) }
  foreach ($path in @($owned.OutFile.Name,$owned.ErrFile.Name)) { if ((Get-Item -LiteralPath $path).Length -gt $StreamCapBytes) { $outputExceeded=$true } }
  $activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($owned.Job,[ref]$active)
  if ($active -ne 0) { [Sr0OwnedJobProcess]::TerminateJobObject($owned.Job,124) | Out-Null; [Sr0OwnedJobProcess]::WaitForSingleObject($owned.Process,15000) | Out-Null; $outDone=$owned.OutTask.Wait(5000); $errDone=$owned.ErrTask.Wait(5000); for($q=0;$q -lt 60 -and $active -ne 0;$q++){ $activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($owned.Job,[ref]$active); if($activeReadable -and $active -eq 0){break}; [Sr0OwnedJobProcess]::WaitForSingleObject($owned.Process,250) | Out-Null } }
  $terminal=($terminal -and [Sr0OwnedJobProcess]::WaitForSingleObject($owned.Process,0) -eq [Sr0OwnedJobProcess]::WaitObject0)
  $exitReadable=[Sr0OwnedJobProcess]::GetExitCodeProcess($owned.Process,[ref]$exitCode)
  $cleanupZero=$terminal -and $outDone -and $errDone -and $activeReadable -and $active -eq 0
  [ordered]@{ processId=$owned.ProcessId; originalHandleRetained=($owned.Process -ne [IntPtr]::Zero); jobHandleRetained=($owned.Job -ne [IntPtr]::Zero); assigned=$owned.Assigned; terminal=$terminal; exitCode=$(if($exitReadable){[int64]$exitCode}else{$null}); streamsDrained=($outDone -and $errDone); activeReadable=$activeReadable; activeProcesses=$active; cleanupZero=$cleanupZero; timedOut=$timedOut; outputExceeded=$outputExceeded; rssExceeded=$rssExceeded; peakRssBytes=$peakRss; rssSamples=$rssSamples; deadlineSeconds=$deadlineSeconds; streamCapBytes=$StreamCapBytes; rssCapBytes=$RssCapBytes }
}

try {
  $lockDeadline=[DateTime]::UtcNow.AddSeconds($LockWaitSeconds); while (-not $lockHeld -and [DateTime]::UtcNow -lt $lockDeadline) { $lockHeld=Try-Acquire-Lock; if(-not $lockHeld){Start-Sleep -Seconds 1} }; if(-not $lockHeld){throw 'desktop lock did not become free within bounded wait'}
  $sessionMatch=[Sr0DiagnosticSessionV3]::CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession); if(-not $sessionMatch){$sessionAdmission='rejected-session-mismatch'; throw "wrapper session $currentSession differs from active console session $activeConsoleSession"}; $sessionAdmission='matched'
  $runArgs=@('-Base',([IO.Path]::GetFullPath($Base)),'-ControlRoot',([IO.Path]::GetFullPath($ControlRoot)),'-AnalysisRoot',([IO.Path]::GetFullPath($AnalysisRoot)),'-Instr','full','-Runs','1','-Warmup',"$Warmup",'-Measure',"$Measure",'-Rows','200','-KeyRate','10','-NoActivate','-LifecycleProof','-Tag',$Tag,'-ExpectDll',$expectedDll)
  $runOwned=Start-OwnedScript $runScript $runArgs $runStdout $runStderr $Base
  $discoveryDeadline=[DateTime]::UtcNow.AddSeconds($DiscoverySeconds)
  while ($null -eq $samplerOwned -and [DateTime]::UtcNow -lt $discoveryDeadline -and [Sr0OwnedJobProcess]::WaitForSingleObject($runOwned.Process,0) -ne [Sr0OwnedJobProcess]::WaitObject0) {
    if(Test-Path -LiteralPath $resultPath -PathType Leaf){$resultText=[IO.File]::ReadAllText($resultPath)}
    $pm=[regex]::Match($resultText,'(?m)^pid run=r1 pid=([0-9]+)'); $wm=[regex]::Match($resultText,'(?m)^window run=r1 hwnd=([0-9-]+)')
    if($pm.Success -and $wm.Success){$sessionMatch=[Sr0DiagnosticSessionV3]::CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession); if(-not $sessionMatch){$sessionAdmission='rejected-session-mismatch'; throw "wrapper session $currentSession differs from active console session $activeConsoleSession before sampler"}; $targetPid=[int]$pm.Groups[1].Value; $targetHwnd=[IntPtr]::new([int64]$wm.Groups[1].Value); $targetDiscovery='observed-r1-pid-hwnd'; $samplerArgs=@('-TargetPid',"$targetPid",'-TargetHwnd',"$($targetHwnd.ToInt64())",'-Out',$raw,'-Summary',$summary,'-DurationSeconds',"$SamplerSeconds",'-SampleMilliseconds','250'); $samplerOwned=Start-OwnedScript $samplerScript $samplerArgs $samplerStdout $samplerStderr $outFull}
    if($null -eq $samplerOwned){Start-Sleep -Milliseconds 500}
  }
  $runResult=Wait-Owned $runOwned $ChildDeadlineSeconds; if($null -ne $samplerOwned){$samplerResult=Wait-Owned $samplerOwned ([math]::Min(1200,$SamplerSeconds+90))}; $taskQuiescent=Task-Quiescent
  $releaseAllowed=$runResult.cleanupZero -and -not $runResult.outputExceeded -and -not $runResult.rssExceeded -and $taskQuiescent -and ($null -ne $samplerResult) -and $samplerResult.cleanupZero -and -not $samplerResult.outputExceeded -and -not $samplerResult.rssExceeded
} catch { $failure=$_.Exception.Message }
finally {
  if($null -ne $runOwned -and $null -eq $runResult){try{$runResult=Wait-Owned $runOwned $ChildDeadlineSeconds}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}}
  if($null -ne $samplerOwned -and $null -eq $samplerResult){try{$samplerResult=Wait-Owned $samplerOwned ([math]::Min(1200,$SamplerSeconds+90))}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}}
  if($null -ne $runOwned -and -not $taskQuiescent){$taskQuiescent=Task-Quiescent}
  if($lockHeld -and $releaseAllowed){try{Release-Lock;$lockReleased=$true}catch{$releaseError=$_.Exception.Message}}
  $status=if($sessionAdmission -eq 'rejected-session-mismatch'){'session-mismatch'}elseif($lockReleased -and $releaseAllowed){'observed'}else{'failed'}
  $obj=[ordered]@{kind='sr0-tuple12-workload-display-diagnostic-v3';status=$status;tag=$Tag;helper=$helperPath;lockOwner=$lockOwner;lockHeld=$lockHeld;lockReleased=$lockReleased;releaseAllowed=$releaseAllowed;releaseError=$releaseError;sessionAdmission=$sessionAdmission;sessionMatch=$sessionMatch;currentSession=$currentSession;activeConsoleSession=$activeConsoleSession;runScript=$runScript;runRoot=$runRoot;runResult=$runResult;samplerScript=$samplerScript;samplerResult=$samplerResult;targetPid=$targetPid;targetHwnd=$(if($null -ne $targetHwnd){$targetHwnd.ToInt64()}else{$null});targetDiscovery=$targetDiscovery;taskQuiescent=$taskQuiescent;resultWorkload=$resultPath;rawContext=$raw;contextSummary=$summary;failure=$failure;nativeConclusion='display-context-only; strict PresentMon displayed-row gate unchanged';sessionConclusion='sampler admitted only when wrapper session matches active console'}
  Close-Owned $samplerOwned; Close-Owned $runOwned
  $bytes=[Text.Encoding]::UTF8.GetBytes(($obj|ConvertTo-Json -Depth 16)+"`r`n"); $s=[IO.File]::Open($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read); try{$s.Write($bytes,0,$bytes.Length);$s.Flush($true)}finally{$s.Dispose()}; $obj|ConvertTo-Json -Depth 16|Write-Output
}
if($status -eq 'observed'){exit 0}else{exit 1}
