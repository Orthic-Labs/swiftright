# SR0 tuple12 workload display root launch envelope v1.
# Root schedules this exact wrapper in active interactive session. SSH/session mismatch rejects before child launch.
# v3 child owns workload lock; this envelope owns child process tree, pipes, deadline, memory cap, & quiescence proof.
# Root passes exact child/helper paths; no ambient source discovery is allowed.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][string]$AnalysisRoot,
  [Parameter(Mandatory)][string]$OutRoot,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [Parameter(Mandatory)][string]$ChildScriptPath,
  [Parameter(Mandatory)][string]$HelperPath,
  [string]$Lock = 'D:\Claude\desktop.lock',
  [string]$Tag = '',
  [ValidateRange(30,1200)][int]$ChildDeadlineSeconds = 900,
  [ValidateRange(1048576,67108864)][int64]$StreamCapBytes = 8388608
)
$ErrorActionPreference = 'Stop'
$expectedExe=$ExpectExe.ToLowerInvariant(); $expectedDll=$ExpectDll.ToLowerInvariant()
if ($expectedExe -notmatch '^[0-9a-f]{64}$' -or $expectedDll -notmatch '^[0-9a-f]{64}$') { throw 'expected artifact hash is not SHA-256' }
foreach($path in @($Base,$ControlRoot,$AnalysisRoot)){if(-not (Test-Path -LiteralPath $path -PathType Container)){throw "required directory missing: $path"}}
if(-not (Test-Path -LiteralPath $Lock -PathType Leaf)){throw "desktop lock missing: $Lock"}
if(-not $Tag){$Tag='tuple12-interactive-'+[guid]::NewGuid().ToString('N')}; if($Tag -notmatch '^[A-Za-z0-9._-]+$'){throw 'tag contains unsafe characters'}
$outFull=[IO.Path]::GetFullPath($OutRoot); if(Test-Path -LiteralPath $outFull){if(@(Get-ChildItem -LiteralPath $outFull -Force).Count -ne 0){throw 'OutRoot must be fresh'}}else{[IO.Directory]::CreateDirectory($outFull)|Out-Null}
$receipt=Join-Path $outFull 'interactive-receipt.json'; $stdoutPath=Join-Path $outFull 'v3.stdout.txt'; $stderrPath=Join-Path $outFull 'v3.stderr.txt'; $innerRoot=Join-Path $outFull 'v3-output'
$helperPath=[IO.Path]::GetFullPath($HelperPath)
$childScript=[IO.Path]::GetFullPath($ChildScriptPath)
foreach($path in @($helperPath,$childScript)){if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "pinned source missing: $path"}}
Add-Type -Path $helperPath
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class Sr0InteractiveSessionV1 {
  [DllImport("kernel32.dll", EntryPoint="ProcessIdToSessionId", SetLastError=true)] private static extern bool ProcessIdToSessionId(uint pid, out uint session);
  [DllImport("kernel32.dll", EntryPoint="WTSGetActiveConsoleSessionId")] private static extern uint WTSGetActiveConsoleSessionId();
  public static bool CurrentMatchesActive(out uint current, out uint active) { current=0; active=WTSGetActiveConsoleSessionId(); return ProcessIdToSessionId((uint)Process.GetCurrentProcess().Id,out current) && current==active; }
}
'@
$sessionMatch=$false; [uint32]$currentSession=0; [uint32]$activeConsoleSession=0; $sessionAdmission='not-checked'; $owned=$null; $result=$null; $childReceipt=$null; $childReceiptValid=$false; $failure=$null
function Close-Owned([pscustomobject]$x){if($null -eq $x){return}; foreach($s in @($x.OutPipe,$x.ErrPipe,$x.OutFile,$x.ErrFile)){if($s){try{$s.Dispose()}catch{}}}; foreach($h in @($x.Thread,$x.Process,$x.StdoutRead,$x.StderrRead,$x.Job)){if($h -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($h)|Out-Null}}}
function Start-OwnedChild([string[]]$arguments){
  $job=[IntPtr]::Zero;$memoryFlags=[uint32]0;$process=[IntPtr]::Zero;$thread=[IntPtr]::Zero;$stdoutRead=[IntPtr]::Zero;$stderrRead=[IntPtr]::Zero;$assigned=$false;$success=$false;$outPipe=$null;$errPipe=$null;$outFile=$null;$errFile=$null;$outTask=$null;$errTask=$null;[uint32]$childPid=0
  try{
    $job=[Sr0OwnedJobProcess]::CreateJob();if($job -eq [IntPtr]::Zero){throw 'interactive envelope job create failed'}
    if(-not [Sr0OwnedJobProcess]::ConfigureJobWithFlags($job,[Sr0OwnedJobProcess]::JobObjectLimitJobMemory,1073741824)){throw 'interactive envelope 1GiB job limit failed'}; if(-not [Sr0OwnedJobProcess]::ReadJobFlags($job,[ref]$memoryFlags) -or $memoryFlags -ne [Sr0OwnedJobProcess]::JobObjectLimitJobMemory){throw 'interactive envelope memory flags mismatch'}
    $tokens=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$childScript)+$arguments;$argText=($tokens|ForEach-Object{[Sr0OwnedJobProcess]::QuoteWindowsArgument([string]$_)})-join ' ';$powershell=Join-Path $PSHOME 'powershell.exe';$cmdline=[Sr0OwnedJobProcess]::BuildCommandLine($powershell,$argText)
    if(-not [Sr0OwnedJobProcess]::CreateSuspended($powershell,$cmdline,$Base,[ref]$process,[ref]$thread,[ref]$stdoutRead,[ref]$stderrRead,[ref]$childPid)){throw 'interactive envelope suspended create failed'}
    $outPipe=New-Object IO.FileStream($stdoutRead,[IO.FileAccess]::Read,$false);$errPipe=New-Object IO.FileStream($stderrRead,[IO.FileAccess]::Read,$false)
    $outFile=[IO.File]::Open($stdoutPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$errFile=[IO.File]::Open($stderrPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $outTask=$outPipe.CopyToAsync($outFile);$errTask=$errPipe.CopyToAsync($errFile)
    if(-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,$process)){throw 'interactive envelope job assignment failed'};$assigned=$true
    if([Sr0OwnedJobProcess]::ResumeThread($thread,$process) -eq [uint32]::MaxValue){throw 'interactive envelope resume failed'}
    $success=$true;return [pscustomobject]@{Job=$job;MemoryFlags=$memoryFlags;KillOnJobClose=$false;Process=$process;Thread=$thread;StdoutRead=$stdoutRead;StderrRead=$stderrRead;ProcessId=$childPid;Assigned=$assigned;OutPipe=$outPipe;ErrPipe=$errPipe;OutFile=$outFile;ErrFile=$errFile;OutTask=$outTask;ErrTask=$errTask}
  }finally{if(-not $success){if($process -ne [IntPtr]::Zero){if($assigned){[Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null}else{[Sr0OwnedJobProcess]::TerminateProcess($process,124)|Out-Null};[Sr0OwnedJobProcess]::WaitForSingleObject($process,15000)|Out-Null};Close-Owned ([pscustomobject]@{Job=$job;Process=$process;Thread=$thread;StdoutRead=$stdoutRead;StderrRead=$stderrRead;OutPipe=$outPipe;ErrPipe=$errPipe;OutFile=$outFile;ErrFile=$errFile})}}
}
function Wait-Owned([pscustomobject]$x){
  $timedOut=$false; $outputExceeded=$false; $terminal=$false; $outDone=$false; $errDone=$false; $activeReadable=$false; [uint32]$active=1; $watch=[Diagnostics.Stopwatch]::StartNew()
  while($true){
    $wait=[Sr0OwnedJobProcess]::WaitForSingleObject($x.Process,1000)
    foreach($p in @($x.OutFile.Name,$x.ErrFile.Name)){if((Get-Item -LiteralPath $p).Length -gt $StreamCapBytes){$outputExceeded=$true}}
    if($wait -eq [Sr0OwnedJobProcess]::WaitObject0){$terminal=$true;break}; if($outputExceeded){break}; if($watch.Elapsed.TotalSeconds -ge $ChildDeadlineSeconds){$timedOut=$true;break}
  }
  if($timedOut -or $outputExceeded){[Sr0OwnedJobProcess]::TerminateJobObject($x.Job,124)|Out-Null;$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($x.Process,15000);$terminal=$wait -eq [Sr0OwnedJobProcess]::WaitObject0}
  $outDone=$x.OutTask.Wait(30000); $errDone=$x.ErrTask.Wait(30000)
  foreach($p in @($x.OutFile.Name,$x.ErrFile.Name)){if((Get-Item -LiteralPath $p).Length -gt $StreamCapBytes){$outputExceeded=$true}}
  if(-not $outDone -or -not $errDone){[Sr0OwnedJobProcess]::TerminateJobObject($x.Job,124)|Out-Null;[Sr0OwnedJobProcess]::WaitForSingleObject($x.Process,15000)|Out-Null;$outDone=$x.OutTask.Wait(5000);$errDone=$x.ErrTask.Wait(5000)}
  foreach($p in @($x.OutFile.Name,$x.ErrFile.Name)){if((Get-Item -LiteralPath $p).Length -gt $StreamCapBytes){$outputExceeded=$true}}
  $activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($x.Job,[ref]$active)
  if($active -ne 0){[Sr0OwnedJobProcess]::TerminateJobObject($x.Job,124)|Out-Null;[Sr0OwnedJobProcess]::WaitForSingleObject($x.Process,15000)|Out-Null;for($q=0;$q -lt 60 -and $active -ne 0;$q++){[Sr0OwnedJobProcess]::WaitForSingleObject($x.Process,250)|Out-Null;$activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($x.Job,[ref]$active)}}
  $terminal=$terminal -and ([Sr0OwnedJobProcess]::WaitForSingleObject($x.Process,0) -eq [Sr0OwnedJobProcess]::WaitObject0); [uint32]$exitCode=259; $exitReadable=$false; if($terminal){$exitReadable=[Sr0OwnedJobProcess]::GetExitCodeProcess($x.Process,[ref]$exitCode)}; $exitAccepted=$terminal -and $exitReadable -and $exitCode -ne 259 -and $exitCode -eq 0
  $cleanupZero=$terminal -and $outDone -and $errDone -and $activeReadable -and $active -eq 0
  [ordered]@{processId=$x.ProcessId;originalHandleRetained=$true;jobHandleRetained=$true;assigned=$x.Assigned;terminal=$terminal;exitReadable=$exitReadable;exitCode=[int64]$exitCode;exitAccepted=$exitAccepted;streamsDrained=($outDone -and $errDone);activeReadable=$activeReadable;activeProcesses=$active;cleanupZero=$cleanupZero;timedOut=$timedOut;outputExceeded=$outputExceeded;streamCapBytes=$StreamCapBytes;deadlineSeconds=$ChildDeadlineSeconds}
}
try{
  $sessionMatch=[Sr0InteractiveSessionV1]::CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession);if(-not $sessionMatch){$sessionAdmission='rejected-session-mismatch';throw "interactive envelope session $currentSession differs from active console $activeConsoleSession"};$sessionAdmission='matched'
  $childArgs=@('-Base',[IO.Path]::GetFullPath($Base),'-ControlRoot',[IO.Path]::GetFullPath($ControlRoot),'-AnalysisRoot',[IO.Path]::GetFullPath($AnalysisRoot),'-OutRoot',$innerRoot,'-ExpectExe',$expectedExe,'-ExpectDll',$expectedDll,'-Lock',$Lock,'-Tag',$Tag);$owned=Start-OwnedChild $childArgs;$result=Wait-Owned $owned
  if(-not $result.cleanupZero -or -not $result.exitAccepted){throw 'interactive envelope child exit/quiescence proof failed'}
  $childReceiptPath=Join-Path $innerRoot 'diagnostic-receipt.json'; if(-not(Test-Path -LiteralPath $childReceiptPath -PathType Leaf)){throw 'v3 diagnostic receipt missing'}; $childReceiptItem=Get-Item -LiteralPath $childReceiptPath; if(($childReceiptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'v3 diagnostic receipt reparse point rejected'}; if($childReceiptItem.Length -gt 2097152){throw 'v3 diagnostic receipt exceeds 2MiB bound'}; $childReceiptBytes=[IO.File]::ReadAllBytes($childReceiptPath); if($childReceiptBytes.Length -gt 2097152){throw 'v3 diagnostic receipt read exceeds 2MiB bound'}; $childReceipt=([Text.Encoding]::UTF8.GetString($childReceiptBytes))|ConvertFrom-Json; $childReceiptValid=([string]$childReceipt.kind -ceq 'sr0-tuple12-workload-display-diagnostic-v3' -and [string]$childReceipt.status -ceq 'observed' -and [bool]$childReceipt.lockReleased -and [bool]$childReceipt.releaseAllowed -and [bool]$childReceipt.taskQuiescent -and [bool]$childReceipt.runResult.cleanupZero -and [int]$childReceipt.runResult.exitCode -eq 0 -and -not [bool]$childReceipt.runResult.timedOut -and -not [bool]$childReceipt.runResult.outputExceeded -and -not [bool]$childReceipt.runResult.rssExceeded -and [bool]$childReceipt.samplerResult.cleanupZero -and [int]$childReceipt.samplerResult.exitCode -eq 0 -and -not [bool]$childReceipt.samplerResult.timedOut -and -not [bool]$childReceipt.samplerResult.outputExceeded -and -not [bool]$childReceipt.samplerResult.rssExceeded); if(-not $childReceiptValid){throw 'v3 receipt did not prove observed lock release, zero exits, bounded output, & child quiescence'}
}catch{$failure=$_.Exception.Message}finally{
  if($null -ne $owned -and $null -eq $result){try{$result=Wait-Owned $owned}catch{$failure=if($failure){$failure}else{$_.Exception.Message};$result=[ordered]@{cleanupZero=$false;cleanupError=$_.Exception.Message;terminal=$false;streamsDrained=$false;activeReadable=$false;activeProcesses=$null;exitReadable=$false;exitCode=$null;exitAccepted=$false}}}
  $status=if($sessionAdmission -eq 'rejected-session-mismatch'){'session-mismatch'}elseif($null -ne $result -and $null -eq $failure -and $result.cleanupZero -and $result.exitAccepted -and $childReceiptValid -and -not $result.outputExceeded){'completed'}else{'failed'}
  $receiptObject=[ordered]@{kind='sr0-tuple12-workload-display-root-launch-v1'; memoryLimitBytes=1073741824; memoryLimitFlags=0x200; killOnJobClose=$false; helper=$helperPath; childScript=$childScript;status=$status;tag=$Tag;sessionAdmission=$sessionAdmission;sessionMatch=$sessionMatch;currentSession=$currentSession;activeConsoleSession=$activeConsoleSession;childResult=$result;childReceipt=$childReceipt;childReceiptValid=$childReceiptValid;childStdout=$stdoutPath;childStderr=$stderrPath;lockProtocol='delegated-to-v3-child';failure=$failure}
  if($null -ne $owned){Close-Owned $owned};$bytes=[Text.Encoding]::UTF8.GetBytes(($receiptObject|ConvertTo-Json -Depth 16)+"`r`n");$s=[IO.File]::Open($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$s.Write($bytes,0,$bytes.Length);$s.Flush($true)}finally{$s.Dispose()};$receiptObject|ConvertTo-Json -Depth 16
}
if($status -eq 'completed'){exit 0}else{exit 1}
