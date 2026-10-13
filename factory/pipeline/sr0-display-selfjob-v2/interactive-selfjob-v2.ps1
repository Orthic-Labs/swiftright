# SR0 displayed-workload self-job envelope v2.
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
  [Parameter(Mandatory)][string]$RunRoot,
  [Parameter(Mandatory)][string]$ResultFile,
  [Parameter(Mandatory)][string]$MemoryReceiptPath,
  [string]$Lock = 'D:\Claude\desktop.lock',
  [string]$Tag = 'sr0-display-selfjob-v2',
  [ValidateRange(1,20)][int]$Runs = 1,
  [ValidateRange(1,120)][int]$Warmup = 10,
  [ValidateRange(1,300)][int]$Measure = 60,
  [int]$Rows = 200,
  [double]$KeyRate = 10,
  [switch]$NoResources,
  [switch]$NoActivate
)
$ErrorActionPreference = 'Stop'
$shaPattern='^[0-9a-fA-F]{64}$'
if($FrozenTaskSha256 -notmatch $shaPattern -or $HelperSha256 -notmatch $shaPattern){throw 'explicit source pins must be SHA-256'}
foreach($path in @($Base,$ControlRoot)){if(-not(Test-Path -LiteralPath $path -PathType Container)){throw "required directory missing: $path"}}
foreach($path in @($FrozenTaskPath,$HelperPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "required pinned source missing: $path"}}
$baseFull=[IO.Path]::GetFullPath($Base);$controlFull=[IO.Path]::GetFullPath($ControlRoot);$frozenFull=[IO.Path]::GetFullPath($FrozenTaskPath);$helperFull=[IO.Path]::GetFullPath($HelperPath);$runFull=[IO.Path]::GetFullPath($RunRoot);$resultFull=[IO.Path]::GetFullPath($ResultFile);$memoryFull=[IO.Path]::GetFullPath($MemoryReceiptPath);$lockFull=[IO.Path]::GetFullPath($Lock)
foreach($path in @($frozenFull,$helperFull)){if(((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "pinned source reparse point rejected: $path"}}
if(-not(Test-Path -LiteralPath $lockFull -PathType Leaf)){throw "desktop lock missing: $lockFull"}
if($Tag -notmatch '^[A-Za-z0-9._-]+$'){throw 'unsafe tag'}
if(Test-Path -LiteralPath $memoryFull){throw 'memory receipt must be fresh'}
$frozenObserved=(Get-FileHash -LiteralPath $frozenFull -Algorithm SHA256).Hash.ToLowerInvariant();$helperObserved=(Get-FileHash -LiteralPath $helperFull -Algorithm SHA256).Hash.ToLowerInvariant();if($frozenObserved -cne $FrozenTaskSha256.ToLowerInvariant() -or $helperObserved -cne $HelperSha256.ToLowerInvariant()){throw 'pinned source hash mismatch'}
$frozenItem=Get-Item -LiteralPath $frozenFull;if($frozenItem.Length -gt 2097152){throw 'frozen task source exceeds 2MiB'};$frozenText=[IO.File]::ReadAllText($frozenFull);if($frozenText -notmatch '\[System\.Diagnostics\.Process\]::Start' -or $frozenText -notmatch 'WorkloadWin\.exe' -or $frozenText -notmatch '\$proc\s*=\s*\[System\.Diagnostics\.Process\]::Start' -or $frozenText -match 'Register-ScheduledTask|Start-ScheduledTask'){throw 'frozen task is not direct WorkloadWin implementation'}
[IO.Directory]::CreateDirectory($runFull)|Out-Null;$resultParent=Split-Path -Parent $resultFull;if(-not(Test-Path -LiteralPath $resultParent)){[IO.Directory]::CreateDirectory($resultParent)|Out-Null}
foreach($path in @($resultParent,(Split-Path -Parent $memoryFull))){if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "receipt parent reparse point rejected: $path"}}
Add-Type -Path $helperFull
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class Sr0DisplaySelfJobSessionV2 {
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
$job=$null;$lockOwner="SR0-DISPLAY-SELFJOB-$Tag";$lockHeld=$false;$releaseAllowed=$false;$lockReleased=$false;$failure=$null;$sessionMatch=$false;[uint32]$currentSession=0;[uint32]$activeConsoleSession=0;$proof=$null;$activeBefore=$null;$activeAfter=$null;$flags=$null;$activeReadableBefore=$false;$activeReadableAfter=$false;$status='failed';$started=[DateTimeOffset]::UtcNow
try{
  $sessionMatch=[Sr0DisplaySelfJobSessionV2]::MatchesActive([ref]$currentSession,[ref]$activeConsoleSession);if(-not $sessionMatch){throw "interactive session mismatch current=$currentSession active=$activeConsoleSession"}
  $job=[Sr0OwnedJobProcess]::CreateCurrentProcess(1073741824);$initial=$job.QueryPeakJobMemory();$flags=$initial.LimitFlags;if($initial.LimitFlags -ne [Sr0OwnedJobProcess]::JobMemoryOnlyFlags -or $initial.JobMemoryLimitBytes -ne 1073741824 -or $initial.ActiveProcessCount -ne 1){throw 'self-job initial memory proof failed'};$activeReadableBefore=$true;$activeBefore=$initial.ActiveProcessCount
  $lockDeadline=[DateTime]::UtcNow.AddSeconds(60);while(-not $lockHeld -and [DateTime]::UtcNow -lt $lockDeadline){$lockHeld=Acquire-Lock $lockOwner;if(-not $lockHeld){Start-Sleep -Seconds 1}};if(-not $lockHeld){throw 'desktop lock did not become free'}
  & $frozenFull -Base $baseFull -ControlRoot $controlFull -RunRoot $runFull -ResultFile $resultFull -Runs $Runs -Warmup $Warmup -Measure $Measure -Instr 'full' -Rows $Rows -KeyRate $KeyRate -LifecycleProof -NoActivate:$NoActivate -NoResources:$NoResources
  $receiptText=Read-Bounded $resultFull
  $proof=[ordered]@{taskReceiptFinished=($receiptText -match '(?m)^finished=');allRunsValid=($receiptText -match "(?m)^finished=.*runs_valid=$Runs of $Runs$");hostKernelHandleRetained=($receiptText -match "(?m)^pid_exit run=.* handle=(?!0)");hostKernelTerminal=([regex]::Matches($receiptText,'(?m)^pid_exit run=.* kernel_terminal=1').Count -eq $Runs);displayWorkerTerminal=($receiptText -match '(?m)^worker_terminal=1');displaySamplerTerminal=($receiptText -match '(?m)^sampler_terminal=1' -or $NoResources);taskQuiescent=($receiptText -match '(?m)^task_quiescent=1');streamFault=($receiptText -match '(?m)stream-drain-timeout|sampler-stream-drain-timeout');timeoutFault=($receiptText -match '(?m)timeout-killed|worker-terminal-proof-missing');receiptPath=$resultFull}
  $releaseAllowed=[bool]($proof.taskReceiptFinished -and $proof.allRunsValid -and $proof.hostKernelHandleRetained -and $proof.hostKernelTerminal -and $proof.displayWorkerTerminal -and $proof.displaySamplerTerminal -and $proof.taskQuiescent -and -not $proof.streamFault -and -not $proof.timeoutFault)
  $final=$job.WaitForOnlyCurrent(30000);[Sr0OwnedJobProcess]::RequireOnlyCurrent($final);$activeReadableAfter=$true;$activeAfter=$final.ActiveProcessCount;if($final.ActiveProcessCount -ne 1){$releaseAllowed=$false;throw "self-job post-workload active count mismatch: $($final.ActiveProcessCount)"}
  if(-not $releaseAllowed){throw 'renderer/display worker or retained host terminal proof missing'}
  Release-Lock $lockOwner;$lockReleased=$true;$status='completed'
}catch{$failure=$_.Exception.Message}
finally{
  if($null -ne $job -and $null -eq $activeAfter){try{$final=$job.QueryPeakJobMemory();$activeReadableAfter=$true;$activeAfter=$final.ActiveProcessCount}catch{}}
  if($lockHeld -and $releaseAllowed -and -not $lockReleased){try{Release-Lock $lockOwner;$lockReleased=$true}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}}
  $status=if($sessionMatch -and $lockReleased -and $releaseAllowed -and $null -eq $failure){'completed'}else{'failed'}
  $receipt=[ordered]@{kind='sr0-display-selfjob-v2';status=$status;tag=$Tag;sessionMatch=$sessionMatch;currentSession=$currentSession;activeConsoleSession=$activeConsoleSession;helper=$helperFull;helperSha256=$helperObserved;frozenTask=$frozenFull;frozenTaskSha256=$frozenObserved;jobMemoryLimitBytes=1073741824;limitFlags=$flags;killOnJobClose=$false;activeReadableBefore=$activeReadableBefore;activeBefore=$activeBefore;activeReadableAfter=$activeReadableAfter;activeAfter=$activeAfter;lockOwner=$lockOwner;lockHeld=$lockHeld;releaseAllowed=$releaseAllowed;lockReleased=$lockReleased;workloadProof=$proof;displayEvidenceStatus=if($proof -and $proof.hostKernelTerminal -and $proof.displayWorkerTerminal){'observed-worker-terminal'}else{'held'};occlusionAdmission='separate-presentmon-displayed-row-gate';failure=$failure;startedAt=$started.ToString('o');endedAt=[DateTimeOffset]::UtcNow.ToString('o')}
  $parent=Split-Path -Parent $memoryFull;if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$receipt|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $memoryFull -Encoding UTF8
  if($null -ne $job){$job.Dispose()}
}
if($status -eq 'completed'){exit 0}else{exit 1}
