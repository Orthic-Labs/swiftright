# SR0 displayed-workload self-job envelope v3.
# Uses reviewed v15 helper: JOB_OBJECT_LIMIT_JOB_MEMORY only (0x200), no
# kill-on-close, so closing job handle cannot kill current interactive task.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][string]$FrozenTaskPath,
  [Parameter(Mandatory)][string]$HelperPath,
  [Parameter(Mandatory)][string]$FrozenTaskSha256,
  [Parameter(Mandatory)][string]$HelperSha256,
  [Parameter(Mandatory)][string]$ParserPath,
  [Parameter(Mandatory)][string]$ParserSha256,
  [Parameter(Mandatory)][string]$RunRoot,
  [Parameter(Mandatory)][string]$ResultFile,
  [Parameter(Mandatory)][string]$MemoryReceiptPath,
  [Parameter(Mandatory)][string]$StartReceiptPath,
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$TaskName,
  [string]$Lock = 'D:\Claude\desktop.lock',
  [string]$Tag = 'sr0-display-selfjob-v4',
  [ValidateRange(1,20)][int]$Runs = 1,
  [ValidateRange(1,120)][int]$Warmup = 10,
  [ValidateRange(1,300)][int]$Measure = 60,
  [int]$Rows = 200,
  [double]$KeyRate = 10,
  [switch]$NoResources,
  [Parameter(Mandatory)][switch]$NoActivate
)
$ErrorActionPreference = 'Stop'
$shaPattern='^[0-9a-fA-F]{64}$'
if($FrozenTaskSha256 -notmatch $shaPattern -or $HelperSha256 -notmatch $shaPattern -or $ParserSha256 -notmatch $shaPattern){throw 'explicit source pins must be SHA-256'}
foreach($path in @($Base,$ControlRoot)){if(-not(Test-Path -LiteralPath $path -PathType Container)){throw "required directory missing: $path"}}
foreach($path in @($FrozenTaskPath,$HelperPath,$ParserPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "required pinned source missing: $path"}}
$baseFull=[IO.Path]::GetFullPath($Base);$controlFull=[IO.Path]::GetFullPath($ControlRoot);$frozenFull=[IO.Path]::GetFullPath($FrozenTaskPath);$helperFull=[IO.Path]::GetFullPath($HelperPath);$parserFull=[IO.Path]::GetFullPath($ParserPath);$runFull=[IO.Path]::GetFullPath($RunRoot);$resultFull=[IO.Path]::GetFullPath($ResultFile);$memoryFull=[IO.Path]::GetFullPath($MemoryReceiptPath);$startFull=[IO.Path]::GetFullPath($StartReceiptPath);$lockFull=[IO.Path]::GetFullPath($Lock)
foreach($path in @($frozenFull,$helperFull,$parserFull)){if(((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "pinned source reparse point rejected: $path"}}
if(-not(Test-Path -LiteralPath $lockFull -PathType Leaf)){throw "desktop lock missing: $lockFull"}
if($Tag -notmatch '^[A-Za-z0-9._-]+$'){throw 'unsafe tag'}
if(Test-Path -LiteralPath $memoryFull -or Test-Path -LiteralPath $startFull){throw 'memory/start receipt must be fresh'}
$frozenObserved=(Get-FileHash -LiteralPath $frozenFull -Algorithm SHA256).Hash.ToLowerInvariant();$helperObserved=(Get-FileHash -LiteralPath $helperFull -Algorithm SHA256).Hash.ToLowerInvariant();$parserObserved=(Get-FileHash -LiteralPath $parserFull -Algorithm SHA256).Hash.ToLowerInvariant();if($frozenObserved -cne $FrozenTaskSha256.ToLowerInvariant() -or $helperObserved -cne $HelperSha256.ToLowerInvariant() -or $parserObserved -cne $ParserSha256.ToLowerInvariant()){throw 'pinned source hash mismatch'}
$frozenItem=Get-Item -LiteralPath $frozenFull;if($frozenItem.Length -gt 2097152){throw 'frozen task source exceeds 2MiB'};$frozenText=[IO.File]::ReadAllText($frozenFull);$requiredFrozenTokens=@('System.Diagnostics.ProcessStartInfo','[System.Diagnostics.Process]::Start','WorkloadWin.exe','pid_exit run=','handle=$workerHandle','kernel_terminal=','kernel_exit_raw=','kernel_exit=','dotnet_exit=','resources run=','sampler_kernel_terminal=','sampler_kernel_exit_raw=','sampler_kernel_exit=','sampler_dotnet_exit=','stdout_drained=','stderr_drained=','stream_drains run=','worker_stdout=1','worker_stderr=1','finished=$(Get-Date -Format o) runs_valid=$okRuns of $Runs','worker_terminal=','sampler_terminal=','task_quiescent=');foreach($token in $requiredFrozenTokens){if($frozenText.IndexOf($token,[StringComparison]::Ordinal)-lt 0){throw "frozen task receipt contract missing: $token"}};$scheduledToken='Register-'+'ScheduledTask';$startScheduledToken='Start-'+'ScheduledTask';if($frozenText -notmatch '\[System\.Diagnostics\.Process\]::Start' -or $frozenText -notmatch 'WorkloadWin\.exe' -or $frozenText -notmatch '\$proc\s*=\s*\[System\.Diagnostics\.Process\]::Start' -or $frozenText.IndexOf($scheduledToken,[StringComparison]::Ordinal)-ge 0 -or $frozenText.IndexOf($startScheduledToken,[StringComparison]::Ordinal)-ge 0){throw 'frozen task is not direct WorkloadWin implementation'}
[IO.Directory]::CreateDirectory($runFull)|Out-Null;$resultParent=Split-Path -Parent $resultFull;$memoryParent=Split-Path -Parent $memoryFull;$startParent=Split-Path -Parent $startFull;foreach($parent in @($resultParent,$memoryParent,$startParent)){if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}}
foreach($path in @($resultParent,(Split-Path -Parent $memoryFull),(Split-Path -Parent $startFull))){if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "receipt parent reparse point rejected: $path"}}
Add-Type -Path $helperFull
. $parserFull
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class Sr0DisplaySelfJobSessionV4 {
  [DllImport("kernel32.dll", EntryPoint="ProcessIdToSessionId", SetLastError=true)] static extern bool ProcessIdToSessionId(uint pid, out uint session);
  [DllImport("kernel32.dll", EntryPoint="WTSGetActiveConsoleSessionId")] static extern uint WTSGetActiveConsoleSessionId();
  public static bool MatchesActive(out uint current, out uint active) { current=0; active=WTSGetActiveConsoleSessionId(); return ProcessIdToSessionId((uint)Process.GetCurrentProcess().Id,out current) && current==active; }
}
'@
function Lock-Text([IO.FileStream]$stream){$stream.Position=0;$bytes=New-Object byte[] ([int]$stream.Length);if($bytes.Length){[void]$stream.Read($bytes,0,$bytes.Length)};[Text.Encoding]::UTF8.GetString($bytes).Trim()}
function Lock-Free([string]$text){if($text -eq 'free'){return $true};try{$obj=$text|ConvertFrom-Json;foreach($field in @('state','status','value')){if($obj.PSObject.Properties.Name -contains $field -and [string]$obj.$field -eq 'free'){return $true}}}catch{};return $false}
function Acquire-Lock([string]$owner){try{$stream=[IO.File]::Open($lockFull,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{if(-not (Lock-Free (Lock-Text $stream))){return $false};$bytes=[Text.Encoding]::UTF8.GetBytes("$owner`r`n");$stream.SetLength(0);$stream.Position=0;$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true);return $true}finally{$stream.Dispose()}}catch [IO.IOException]{return $false}}
function Release-Lock([string]$owner){$stream=[IO.File]::Open($lockFull,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{if((Lock-Text $stream) -cne $owner){throw 'desktop lock ownership changed; preserving lock'};$bytes=[Text.Encoding]::UTF8.GetBytes("free`r`n");$stream.SetLength(0);$stream.Position=0;$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}
function Read-Bounded([string]$path){$item=Get-Item -LiteralPath $path -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt 2097152){throw 'workload receipt missing, reparse, or exceeds 2MiB'};return [IO.File]::ReadAllText($path)}
function Count-ReceiptLines([string]$text,[string]$pattern){return @([regex]::Matches($text,$pattern)).Count}
function Write-CreateNew([string]$Path,[string]$Text){$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$bytes=[Text.Encoding]::UTF8.GetBytes($Text);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}
$runsPattern='[A-Za-z0-9._-]+'
$job=$null;$parentProcess=$null;$parentHandle=[IntPtr]::Zero;$parentPid=$null;$parentPath=$null;$parentStartUtc=$null;$schedulerDisabled=$false;$schedulerDisableError=$null;$job=$null;$lockOwner="SR0-DISPLAY-SELFJOB-$Tag";$lockHeld=$false;$releaseAllowed=$false;$lockReleased=$false;$failure=$null;$qualificationFailure=$null;$sessionMatch=$false;[uint32]$currentSession=0;[uint32]$activeConsoleSession=0;$proof=$null;$activeBefore=$null;$activeAfter=$null;$peakBefore=$null;$peakAfter=$null;$flags=$null;$activeReadableBefore=$false;$activeReadableAfter=$false;$activeSelfOnly=$false;$status='failed';$started=[DateTimeOffset]::UtcNow
try{
  $parentProcess=[Diagnostics.Process]::GetCurrentProcess();$parentPid=$parentProcess.Id;$parentPath=$parentProcess.MainModule.FileName;$parentStartUtc=$parentProcess.StartTime.ToUniversalTime().ToString('o');$parentHandle=$parentProcess.Handle
  $sessionMatch=[Sr0DisplaySelfJobSessionV4]::MatchesActive([ref]$currentSession,[ref]$activeConsoleSession);if(-not $sessionMatch){throw "interactive session mismatch current=$currentSession active=$activeConsoleSession"}
  $job=[Sr0OwnedJobProcess]::CreateCurrentProcess(1073741824);$initial=$job.QueryPeakJobMemory();$peakBefore=$initial.PeakJobMemoryUsedBytes;$flags=$initial.LimitFlags;if($initial.LimitFlags -ne [Sr0OwnedJobProcess]::JobMemoryOnlyFlags -or $initial.JobMemoryLimitBytes -ne 1073741824 -or $initial.ActiveProcessCount -ne 1){throw 'self-job initial memory proof failed'};$activeReadableBefore=$true;$activeBefore=$initial.ActiveProcessCount
  $startReceipt=[ordered]@{kind='sr0-display-selfjob-v4-start';status='admitted';taskName=$TaskName;pid=$parentPid;path=$parentPath;startTimeUtc=$parentStartUtc;session=$currentSession;activeConsoleSession=$activeConsoleSession;originalHandle=$parentHandle.ToInt64();originalHandleRetained=($parentHandle -ne [IntPtr]::Zero);jobMemoryLimitBytes=$initial.JobMemoryLimitBytes;limitFlags=$initial.LimitFlags;activeProcessCount=$initial.ActiveProcessCount;peakJobMemoryUsedBytes=$initial.PeakJobMemoryUsedBytes;noActivate=[bool]$NoActivate;startedAt=$started.ToString('o')};Write-CreateNew $startFull (($startReceipt|ConvertTo-Json -Depth 12)+"`r`n")
  $lockDeadline=[DateTime]::UtcNow.AddSeconds(60);while(-not $lockHeld -and [DateTime]::UtcNow -lt $lockDeadline){$lockHeld=Acquire-Lock $lockOwner;if(-not $lockHeld){Start-Sleep -Seconds 1}};if(-not $lockHeld){throw 'desktop lock did not become free'}
  & $frozenFull -Base $baseFull -ControlRoot $controlFull -RunRoot $runFull -ResultFile $resultFull -Runs $Runs -Warmup $Warmup -Measure $Measure -Instr 'full' -Rows $Rows -KeyRate $KeyRate -LifecycleProof -NoActivate:$NoActivate -NoResources:$NoResources
  $proof=Parse-WorkloadReceipt -Path $resultFull -Runs $Runs -NoResources:$NoResources
  $final=$job.WaitForOnlyCurrent(30000);[Sr0OwnedJobProcess]::RequireOnlyCurrent($final);$peakAfter=$final.PeakJobMemoryUsedBytes;$activeReadableAfter=$true;$activeAfter=$final.ActiveProcessCount;$activeSelfOnly=($final.ActiveProcessCount -eq 1)
  $releaseAllowed=[bool]($proof.ownershipTerminal -and $proof.taskQuiescent -and $activeSelfOnly)
  $qualificationFailure=if($proof.qualificationPass){$null}else{'receipt qualification failed after cleanup proof'}
  if(-not $releaseAllowed){throw 'owned children, streams, or active-self proof missing'}
  Release-Lock $lockOwner;$lockReleased=$true;$status=if($proof.qualificationPass){'completed'}else{'qualification-failed'}
}catch{$failure=$_.Exception.Message}
finally{
  if($null -ne $job -and $null -eq $activeAfter){try{$final=$job.QueryPeakJobMemory();$peakAfter=$final.PeakJobMemoryUsedBytes;$activeReadableAfter=$true;$activeAfter=$final.ActiveProcessCount}catch{}}
  if($lockHeld -and $releaseAllowed -and -not $lockReleased){try{Release-Lock $lockOwner;$lockReleased=$true}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}}
  if($lockReleased){try{Disable-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null;$schedulerDisabled=$true}catch{$schedulerDisableError=$_.Exception.Message;if(-not $failure){$failure=$schedulerDisableError}}}
  $status=if($sessionMatch -and $lockReleased -and $releaseAllowed -and $null -eq $failure){if($proof -and $proof.qualificationPass){'completed'}else{'qualification-failed'}}else{'failed'}
  $receipt=[ordered]@{kind='sr0-display-selfjob-v4';status=$status;tag=$Tag;taskName=$TaskName;parentPid=$parentPid;parentPath=$parentPath;parentStartTimeUtc=$parentStartUtc;parentSession=$currentSession;parentOriginalHandle=$parentHandle.ToInt64();parentOriginalHandleRetained=($null -ne $parentProcess -and $parentHandle -ne [IntPtr]::Zero);startReceipt=$startFull;schedulerDisabled=$schedulerDisabled;schedulerDisableError=$schedulerDisableError;sessionMatch=$sessionMatch;currentSession=$currentSession;activeConsoleSession=$activeConsoleSession;helper=$helperFull;helperSha256=$helperObserved;parser=$parserFull;parserSha256=$parserObserved;frozenTask=$frozenFull;frozenTaskSha256=$frozenObserved;jobMemoryLimitBytes=1073741824;peakJobMemoryBeforeBytes=$peakBefore;peakJobMemoryAfterBytes=$peakAfter;limitFlags=$flags;killOnJobClose=$false;activeReadableBefore=$activeReadableBefore;activeBefore=$activeBefore;activeReadableAfter=$activeReadableAfter;activeAfter=$activeAfter;activeSelfOnly=$activeSelfOnly;lockOwner=$lockOwner;lockHeld=$lockHeld;releaseAllowed=$releaseAllowed;lockReleased=$lockReleased;workloadProof=$proof;qualificationFailure=$qualificationFailure;displayEvidenceStatus=if($proof -and $proof.workerTerminal){'observed-worker-terminal'}else{'held'};occlusionAdmission='separate-presentmon-displayed-row-gate';failure=$failure;startedAt=$started.ToString('o');endedAt=[DateTimeOffset]::UtcNow.ToString('o')}
  $parent=Split-Path -Parent $memoryFull;if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$receipt|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $memoryFull -Encoding UTF8
  if($null -ne $job){$job.Dispose()}
}
if($status -eq 'completed'){exit 0}else{exit 1}
