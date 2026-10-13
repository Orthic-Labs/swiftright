# SR0 displayed-workload self-job envelope v1.
# Root schedules this file as one interactive task.  Current task joins its own
# 1 GiB kill-on-close job before frozen workload host starts; descendants
# WorkloadWin, renderer, & display sampler inherit membership.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][string]$FrozenTaskPath,
  [Parameter(Mandatory)][string]$HelperPath,
  [Parameter(Mandatory)][string]$RunRoot,
  [Parameter(Mandatory)][string]$ResultFile,
  [Parameter(Mandatory)][string]$MemoryReceiptPath,
  [string]$Lock = 'D:\Claude\desktop.lock',
  [string]$Tag = 'sr0-display-selfjob-v1',
  [ValidateRange(1,20)][int]$Runs = 1,
  [ValidateRange(1,120)][int]$Warmup = 10,
  [ValidateRange(1,300)][int]$Measure = 60,
  [int]$Rows = 200,
  [double]$KeyRate = 10,
  [switch]$NoResources,
  [switch]$NoActivate
)
$ErrorActionPreference = 'Stop'
foreach($path in @($Base,$ControlRoot,$FrozenTaskPath,$HelperPath)){if(-not((Test-Path -LiteralPath $path -PathType Leaf) -or (Test-Path -LiteralPath $path -PathType Container))){throw "required source missing: $path"}}
$baseFull=[IO.Path]::GetFullPath($Base);$controlFull=[IO.Path]::GetFullPath($ControlRoot);$frozenFull=[IO.Path]::GetFullPath($FrozenTaskPath);$helperFull=[IO.Path]::GetFullPath($HelperPath);$runFull=[IO.Path]::GetFullPath($RunRoot);$resultFull=[IO.Path]::GetFullPath($ResultFile);$memoryFull=[IO.Path]::GetFullPath($MemoryReceiptPath);$lockFull=[IO.Path]::GetFullPath($Lock)
if(-not(Test-Path -LiteralPath $lockFull -PathType Leaf)){throw "desktop lock missing: $lockFull"}
if($Tag -notmatch '^[A-Za-z0-9._-]+$'){throw 'unsafe tag'}
if(Test-Path -LiteralPath $memoryFull){throw 'memory receipt must be fresh'}
[IO.Directory]::CreateDirectory($runFull)|Out-Null
$resultParent=Split-Path -Parent $resultFull;if(-not(Test-Path -LiteralPath $resultParent)){[IO.Directory]::CreateDirectory($resultParent)|Out-Null}
Add-Type -Path $helperFull
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class Sr0DisplaySelfJobSessionV1 {
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
$job=[IntPtr]::Zero;$lockOwner="SR0-DISPLAY-SELFJOB-$Tag";$lockHeld=$false;$releaseAllowed=$false;$lockReleased=$false;$failure=$null;$sessionMatch=$false;[uint32]$currentSession=0;[uint32]$activeConsoleSession=0;$proof=$null;$activeBefore=$null;$activeAfter=$null;$flags=$null;$activeReadableBefore=$false;$activeReadableAfter=$false;$status='failed';$started=[DateTimeOffset]::UtcNow
try{
  $sessionMatch=[Sr0DisplaySelfJobSessionV1]::MatchesActive([ref]$currentSession,[ref]$activeConsoleSession);if(-not $sessionMatch){throw "interactive session mismatch current=$currentSession active=$activeConsoleSession"}
  $job=[Sr0OwnedJobProcess]::CreateJob();if($job -eq [IntPtr]::Zero){throw 'self-job creation failed'}
  if(-not [Sr0OwnedJobProcess]::ConfigureJob($job,1073741824)){throw 'self-job 1GiB configuration failed'}
  [uint32]$flagsValue=0;$flagsReadable=[Sr0OwnedJobProcess]::ReadJobFlags($job,[ref]$flagsValue);$flags=$flagsValue;if(-not $flagsReadable -or $flagsValue -ne ([Sr0OwnedJobProcess]::JobObjectLimitKillOnJobClose -bor [Sr0OwnedJobProcess]::JobObjectLimitJobMemory)){throw "self-job flags mismatch: $flagsValue"}
  if(-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,(Get-Process -Id $PID).Handle)){throw 'self-job current process assignment failed'}
  [uint32]$activeValue=0;$activeReadableBefore=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$activeValue);$activeBefore=$activeValue;if(-not $activeReadableBefore -or $activeValue -ne 1){throw "self-job pre-workload active count mismatch: $activeValue"}
  $lockDeadline=[DateTime]::UtcNow.AddSeconds(60);while(-not $lockHeld -and [DateTime]::UtcNow -lt $lockDeadline){$lockHeld=Acquire-Lock $lockOwner;if(-not $lockHeld){Start-Sleep -Seconds 1}};if(-not $lockHeld){throw 'desktop lock did not become free'}
  & $frozenFull -Base $baseFull -ControlRoot $controlFull -RunRoot $runFull -ResultFile $resultFull -Runs $Runs -Warmup $Warmup -Measure $Measure -Instr 'full' -Rows $Rows -KeyRate $KeyRate -LifecycleProof -NoActivate:$NoActivate -NoResources:$NoResources
  $receiptText=Read-Bounded $resultFull
  $proof=[ordered]@{finished=($receiptText -match '(?m)^finished=');workerTerminal=($receiptText -match '(?m)^worker_terminal=1');displaySamplerTerminal=($receiptText -match '(?m)^sampler_terminal=1' -or $NoResources);taskQuiescent=($receiptText -match '(?m)^task_quiescent=1');rendererTimeout=($receiptText -match '(?m)timeout-killed|worker-terminal-proof-missing|stream-drain-timeout');receiptPath=$resultFull}
  $proof.allRunsValid=($receiptText -match "(?m)^finished=.*runs_valid=$Runs of $Runs$")
  $releaseAllowed=[bool]($proof.finished -and $proof.allRunsValid -and $proof.workerTerminal -and $proof.displaySamplerTerminal -and $proof.taskQuiescent -and -not $proof.rendererTimeout)
  [uint32]$activeValue=0;$activeReadableAfter=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$activeValue);$activeAfter=$activeValue;if(-not $activeReadableAfter -or $activeValue -ne 1){$releaseAllowed=$false;throw "self-job post-workload active count mismatch: $activeValue"}
  if(-not $releaseAllowed){throw 'renderer/display worker terminal or lock cleanup proof missing'}
  Release-Lock $lockOwner;$lockReleased=$true;$status='completed'
}catch{$failure=$_.Exception.Message}
finally{
  if($null -ne $job -and $null -eq $activeAfter){try{[uint32]$activeFinal=0;$activeReadableAfter=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$activeFinal);$activeAfter=$activeFinal}catch{}}
  if($lockHeld -and $releaseAllowed -and -not $lockReleased){try{Release-Lock $lockOwner;$lockReleased=$true}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}}
  $status=if($sessionMatch -and $lockReleased -and $releaseAllowed -and $null -eq $failure){'completed'}else{'failed'}
  $receipt=[ordered]@{kind='sr0-display-selfjob-v1';status=$status;tag=$Tag;sessionMatch=$sessionMatch;currentSession=$currentSession;activeConsoleSession=$activeConsoleSession;helper=$helperFull;frozenTask=$frozenFull;jobMemoryLimitBytes=1073741824;limitFlags=$flags;killOnJobClose=$true;activeReadableBefore=$activeReadableBefore;activeBefore=$activeBefore;activeReadableAfter=$activeReadableAfter;activeAfter=$activeAfter;lockOwner=$lockOwner;lockHeld=$lockHeld;releaseAllowed=$releaseAllowed;lockReleased=$lockReleased;workloadProof=$proof;displayEvidenceStatus=if($proof -and $proof.workerTerminal -and $proof.displaySamplerTerminal){'observed-worker-terminal'}else{'held'};occlusionAdmission='separate-presentmon-displayed-row-gate';failure=$failure;startedAt=$started.ToString('o');endedAt=[DateTimeOffset]::UtcNow.ToString('o')}
  $parent=Split-Path -Parent $memoryFull;if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$receipt|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $memoryFull -Encoding UTF8
  if($job -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($job)|Out-Null}
}
if($status -eq 'completed'){exit 0}else{exit 1}
