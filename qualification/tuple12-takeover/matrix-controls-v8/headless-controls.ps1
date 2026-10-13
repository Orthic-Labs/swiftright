# Matrix v8 owned-job controls. Root runs on Dell after parser review.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$OutRoot,
  [ValidateRange(1,30)][int]$TimeoutSeconds = 5
)
$ErrorActionPreference = 'Stop'
function Write-CreateNew([string]$Path,[string]$Text) {
  if (Test-Path -LiteralPath $Path) { throw "output exists: $Path" }
  $s = [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try { $b=[Text.Encoding]::UTF8.GetBytes($Text);$s.Write($b,0,$b.Length);$s.Flush($true) } finally { $s.Dispose() }
}
if (Test-Path -LiteralPath $OutRoot) { throw "output namespace exists: $OutRoot" }
[IO.Directory]::CreateDirectory($OutRoot) | Out-Null
$helperPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\workload-incremental-v6\shared\Sr0OwnedJobProcess.cs'))
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw "helper missing: $helperPath" }
Add-Type -Path $helperPath

function Invoke-OwnedChild([string]$Name,[string]$ChildArgs,[int]$DeadlineSeconds,[bool]$ExpectTimeout) {
  $root=Join-Path $OutRoot $Name;[IO.Directory]::CreateDirectory($root)|Out-Null
  $stdout=Join-Path $root 'stdout.bin';$stderr=Join-Path $root 'stderr.bin'
  $job=[IntPtr]::Zero;$process=[IntPtr]::Zero;$thread=[IntPtr]::Zero;$stdoutRead=[IntPtr]::Zero;$stderrRead=[IntPtr]::Zero;$assigned=$false;$terminal=$false;$cleanupZero=$false
  $outPipe=$null;$errPipe=$null;$outFile=$null;$errFile=$null;$outTask=$null;$errTask=$null;$activeReadable=$false;[uint32]$active=1
  try {
    $job=[Sr0OwnedJobProcess]::CreateJob()
    if (-not [Sr0OwnedJobProcess]::ConfigureJob($job,1073741824)) { throw 'job memory configuration failed' }
    $powershell=Join-Path $PSHOME 'powershell.exe';$commandArgs=[Sr0OwnedJobProcess]::QuoteWindowsArgument('-NoProfile')+' '+[Sr0OwnedJobProcess]::QuoteWindowsArgument('-NonInteractive')+' '+[Sr0OwnedJobProcess]::QuoteWindowsArgument('-Command')+' '+[Sr0OwnedJobProcess]::QuoteWindowsArgument($ChildArgs);$cmd=[Sr0OwnedJobProcess]::BuildCommandLine($powershell,$commandArgs);[uint32]$childPid=0
    if (-not [Sr0OwnedJobProcess]::CreateSuspended($powershell,$cmd,$root,[ref]$process,[ref]$thread,[ref]$stdoutRead,[ref]$stderrRead,[ref]$childPid)) { throw 'suspended child create failed' }
    $outPipe=New-Object IO.FileStream($stdoutRead,[IO.FileAccess]::Read,$false);$errPipe=New-Object IO.FileStream($stderrRead,[IO.FileAccess]::Read,$false);$outFile=[IO.File]::Open($stdout,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$errFile=[IO.File]::Open($stderr,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$outTask=$outPipe.CopyToAsync($outFile);$errTask=$errPipe.CopyToAsync($errFile)
    if (-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,$process)) { throw 'job assignment failed' };$assigned=$true
    if ([Sr0OwnedJobProcess]::ResumeThread($thread,$process) -eq [uint32]::MaxValue) { throw 'resume failed' }
    $watch=[Diagnostics.Stopwatch]::StartNew();$timedOut=$false
    while($true){$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($process,1000);if($wait -eq [Sr0OwnedJobProcess]::WaitObject0){$terminal=$true;break};if($watch.Elapsed.TotalSeconds -ge $DeadlineSeconds){$timedOut=$true;break}}
    if($timedOut){[Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null;$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($process,5000);$terminal=($wait -eq [Sr0OwnedJobProcess]::WaitObject0)}
    $outDone=$outTask.Wait(5000);$errDone=$errTask.Wait(5000);$activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active)
    if($active -ne 0){[Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null;$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($process,5000);$terminal=($wait -eq [Sr0OwnedJobProcess]::WaitObject0);$activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active)}
    $cleanupZero=$terminal -and $outDone -and $errDone -and $activeReadable -and $active -eq 0
    if($ExpectTimeout){if(-not $timedOut -or -not $cleanupZero){throw 'timeout cleanup proof failed'}}else{if($timedOut -or -not $cleanupZero){throw 'positive cleanup proof failed'}}
    return [ordered]@{name=$Name;terminal=$terminal;timedOut=$timedOut;streamsDrained=($outDone -and $errDone);activeReadable=$activeReadable;activeProcesses=$active;cleanupZero=$cleanupZero;originalHandleRetained=$true}
  } finally {
    if(-not $cleanupZero -and $process -ne [IntPtr]::Zero){if($assigned){[Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null}else{[Sr0OwnedJobProcess]::TerminateProcess($process,124)|Out-Null};[Sr0OwnedJobProcess]::WaitForSingleObject($process,5000)|Out-Null}
    if($outPipe){$outPipe.Dispose()};if($errPipe){$errPipe.Dispose()};if($outFile){$outFile.Dispose()};if($errFile){$errFile.Dispose()};if($thread -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($thread)|Out-Null};if($process -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($process)|Out-Null};if($stdoutRead -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($stdoutRead)|Out-Null};if($stderrRead -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($stderrRead)|Out-Null};if($job -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($job)|Out-Null}
  }
}
$receipt=[ordered]@{kind='sr0-tuple12-matrix-headless-controls-v2';status='passed';results=@((Invoke-OwnedChild 'positive' 'Write-Output matrix-v8-positive' 5 $false),(Invoke-OwnedChild 'timeout-fault' 'Start-Sleep -Seconds 30' $TimeoutSeconds $true));gui=$false;desktopLock=$false;nativeInput=$false;deletion=$false;jobMemoryBytes=1073741824;sharedHelper=$helperPath}
Write-CreateNew (Join-Path $OutRoot 'controls.json') (($receipt|ConvertTo-Json -Depth 8)+"`r`n");Write-Output (($receipt|ConvertTo-Json -Depth 8))
