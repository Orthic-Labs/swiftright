# Source-bound task wrapper: attach current interactive PowerShell to 1GiB job before frozen task can spawn WorkloadWin or sampler.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FrozenTaskPath,
  [Parameter(Mandatory)][string]$HelperPath,
  [Parameter(Mandatory)][string]$MemoryReceiptPath,
  [string]$Base = 'D:\Claude\sr0b-workload',
  [string]$ControlRoot = '',
  [string]$RunRoot = 'D:\Claude\sr0b-workload\runs\manual',
  [string]$ResultFile = 'D:\Claude\sr0b-workload\runs\manual\result-workload.txt',
  [int]$Runs = 3,
  [int]$Warmup = 10,
  [int]$Measure = 60,
  [string]$Instr = 'full',
  [Alias('RateHz')][double]$KeyRate = 10,
  [int]$Rows = 200,
  [double]$KeyTailS = 0.5,
  [switch]$NoResources,
  [string]$PaintPhaseMs = '',
  [switch]$MemDeep,
  [string]$RunPrefix = 'r',
  [ValidateSet('char','all')][string]$KeyMode = 'char',
  [int]$ForegroundSeconds = 8,
  [switch]$LifecycleProof,
  [switch]$NoActivate
)
$ErrorActionPreference = 'Stop'
foreach($p in @($FrozenTaskPath,$HelperPath)){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ throw "required pinned source missing: $p" } }
$helperFull=[IO.Path]::GetFullPath($HelperPath); $frozenFull=[IO.Path]::GetFullPath($FrozenTaskPath)
Add-Type -Path $helperFull
$job=$null; $taskError=$null; $started=[DateTimeOffset]::UtcNow
try {
  # Current task process enters job before invoking frozen task; every WorkloadWin/sampler descendant inherits membership.
  $job=[Sr0OwnedJobProcess]::CreateJob()
  if($job -eq [IntPtr]::Zero){ throw 'CreateJobObject failed' }
  if(-not [Sr0OwnedJobProcess]::ConfigureJobWithFlags($job,[Sr0OwnedJobProcess]::JobObjectLimitJobMemory,1073741824)){ throw '1GiB job configuration failed' }
  [uint32]$flags=0
  if(-not [Sr0OwnedJobProcess]::ReadJobFlags($job,[ref]$flags) -or $flags -ne [Sr0OwnedJobProcess]::JobObjectLimitJobMemory){ throw "job flags mismatch: $flags" }
  if(-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,(Get-Process -Id $PID).Handle)){ throw 'current task assignment failed' }
  [uint32]$active=0
  if(-not [Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active) -or $active -ne 1){ throw "pre-child active count mismatch: $active" }
  & $frozenFull -Base $Base -ControlRoot $ControlRoot -RunRoot $RunRoot -ResultFile $ResultFile -Runs $Runs -Warmup $Warmup -Measure $Measure -Instr $Instr -KeyRate $KeyRate -Rows $Rows -KeyTailS $KeyTailS -NoResources:$NoResources -PaintPhaseMs $PaintPhaseMs -MemDeep:$MemDeep -RunPrefix $RunPrefix -KeyMode $KeyMode -ForegroundSeconds $ForegroundSeconds -LifecycleProof:$LifecycleProof -NoActivate:$NoActivate
  if(-not (Test-Path -LiteralPath $ResultFile -PathType Leaf) -or -not (Select-String -LiteralPath $ResultFile -Pattern '^finished=' -Quiet)){ throw 'frozen task did not emit finished receipt' }
} catch { $taskError=$_.Exception.Message }
$proof=$null
try {
  [uint32]$active=0; $activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active)
  $flagsFinal=0; $flagsReadable=[Sr0OwnedJobProcess]::ReadJobFlags($job,[ref]$flagsFinal)
  $proof=[ordered]@{activeReadable=$activeReadable;activeProcesses=$active;flagsReadable=$flagsReadable;flags=$flagsFinal}
  if(-not $activeReadable -or $active -ne 1){ if(-not $taskError){$taskError='child process remains in memory job'} }
  if(-not $flagsReadable -or $flagsFinal -ne [Sr0OwnedJobProcess]::JobObjectLimitJobMemory){ if(-not $taskError){$taskError='final memory flags mismatch'} }
} catch { if(-not $taskError){$taskError=$_.Exception.Message} }
$receipt=[ordered]@{
  kind='pilot-next-task-memory-receipt-v1'; candidate='swiftui.shapes.rectangle-fill.pilot-next'; status=if($null -eq $taskError){'completed'}else{'failed'}
  jobMemoryLimitBytes=1073741824; limitFlags='0x200'; killOnJobClose=$false; parentPid=$PID; frozenTaskPath=$frozenFull; helperPath=$helperFull
  startedAt=$started.ToString('o'); endedAt=[DateTimeOffset]::UtcNow.ToString('o'); proof=$proof; error=if($taskError){$taskError}else{''}
}
$receiptParent=Split-Path -Parent ([IO.Path]::GetFullPath($MemoryReceiptPath)); if(-not(Test-Path -LiteralPath $receiptParent)){[IO.Directory]::CreateDirectory($receiptParent)|Out-Null}
$receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $MemoryReceiptPath -Encoding UTF8
if($null -ne $job){[Sr0OwnedJobProcess]::CloseHandle($job)|Out-Null}
if($taskError){throw $taskError}
exit 0
