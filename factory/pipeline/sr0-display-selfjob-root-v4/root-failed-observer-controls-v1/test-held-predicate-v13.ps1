[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$FailureRoot,
  [Parameter(Mandatory)][string]$ObserverPath,
  [Parameter(Mandatory)][string]$SourcePinsPath,
  [Parameter(Mandatory)][string]$ControlRoot,
  [int64]$MaxJsonBytes = 2097152
)
$ErrorActionPreference='Stop'
if($MaxJsonBytes -lt 1 -or $MaxJsonBytes -gt 2097152){throw 'bounded read limit rejected'}
function Require-BoundedFile([string]$Path){$i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $i.Length -gt $MaxJsonBytes){throw "bounded/reparse input rejected: $Path"};return $i}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-BoundedJson([string]$Path){$i=Require-BoundedFile $Path;return ([IO.File]::ReadAllText($i.FullName)|ConvertFrom-Json)}
function Test-HeldPredicateV13([object]$launcher,[object]$collector,[object]$coordinator,[string]$ExpectedTaskName){
  $reasons=[System.Collections.Generic.List[string]]::new()
  if($null -eq $launcher -or $null -eq $collector -or $null -eq $coordinator){[void]$reasons.Add('receipt-missing');return [ordered]@{accepted=$false;reasons=@($reasons)}}
  if([string]$launcher.kind -cne 'sr0-display-launcher-v8-status'){[void]$reasons.Add('launcher-kind')}
  if([string]$collector.kind -cne 'sr0-display-collector-v8-drain-pidjoin'){[void]$reasons.Add('collector-kind')}
  if([string]$coordinator.kind -cne 'sr0-display-coordinator-v5'){[void]$reasons.Add('coordinator-kind')}
  foreach($r in @($launcher,$collector,$coordinator)){if([string]$r.taskName -cne $ExpectedTaskName){[void]$reasons.Add('task-name')}}
  if([string]$launcher.status -cne 'held'){[void]$reasons.Add('launcher-status')}
  if([string]$collector.status -cne 'failed'){[void]$reasons.Add('collector-status')}
  if([string]$coordinator.status -cne 'held'){[void]$reasons.Add('coordinator-status')}
  if([string]$collector.failure -notmatch '(?i)workload exit row count mismatch'){[void]$reasons.Add('collector-failure-kind')}
  foreach($n in @('parentOriginalHandleRetained','parentOriginalHandleAcquired','workloadHandleAcquired','workloadTerminal','workloadExitIdentity','activeSelfOnly')){if(-not [bool]$collector.$n){[void]$reasons.Add("collector-$n")}}
  if([int64]$collector.activeAfter -ne 1 -or [int64]$collector.workloadExit -ne 0){[void]$reasons.Add('collector-terminal-state')}
  foreach($n in @('coordinatorHandleAcquired','coordinatorTerminal','coordinatorExitIdentity','collectorHandleAcquired','collectorTerminal','collectorExitIdentity','childReceiptsRead','aggregateDescendantsQuiesced','aggregateCleanupSelfOnly')){if(-not [bool]$launcher.$n){[void]$reasons.Add("launcher-$n")}}
  if([int64]$launcher.aggregateActiveAfter -ne 1){[void]$reasons.Add('launcher-active-count')}
  if(-not [bool]$coordinator.parentKernelTerminal){[void]$reasons.Add('parent-kernel-terminal')}
  if([int64]$coordinator.parentExitRaw -ne 1 -or [int64]$coordinator.parentExitSigned -ne 1 -or [int64]$coordinator.parentExitDotnet -ne 1){[void]$reasons.Add('parent-exit-identity')}
  [ordered]@{accepted=($reasons.Count -eq 0);reasons=@($reasons)}
}
$pins=Read-BoundedJson $SourcePinsPath
$observer=Require-BoundedFile $ObserverPath
if((Hash $observer.FullName) -cne ([string]$pins.observerSha256).ToLowerInvariant()){throw 'observer source hash mismatch'}
$observerText=[IO.File]::ReadAllText($observer.FullName)
foreach($needle in @('function Test-FailedQuiescentReceipts','earlyFailureObserved','nativeQualificationClaim','DeadlineSeconds')){if($observerText -notmatch [regex]::Escape($needle)){throw "observer source token missing: $needle"}}
if(Test-Path -LiteralPath $ControlRoot){throw "fresh control root required: $ControlRoot"}
[IO.Directory]::CreateDirectory($ControlRoot)|Out-Null
$names=[ordered]@{collector='collector.json';coordinator='coordinator.json';launcher='launcher.json'};$receipts=[ordered]@{}
foreach($name in $names.Keys){$path=Join-Path $FailureRoot $names[$name];$item=Require-BoundedFile $path;$expected=[string]$pins.receiptSha256.$name;if((Hash $item.FullName) -cne $expected.ToLowerInvariant()){throw "archived $name hash mismatch"};$receipts[$name]=Read-BoundedJson $item.FullName}
$base=Test-HeldPredicateV13 $receipts.launcher $receipts.collector $receipts.coordinator ([string]$pins.taskName)
if(-not $base.accepted){throw "actual held failure rejected: $($base.reasons -join ',')"}
$mutations=@(
  @{name='missing-original-retained-handle';apply={param($r)$r.collector.parentOriginalHandleRetained=$false}},
  @{name='active-two';apply={param($r)$r.launcher.aggregateActiveAfter=2}},
  @{name='kernel-exit-mismatch';apply={param($r)$r.coordinator.parentExitSigned=0}},
  @{name='wrong-status';apply={param($r)$r.collector.status='passed'}},
  @{name='missing-parent-kernel-proof';apply={param($r)$r.coordinator.parentKernelTerminal=$false}}
)
$rows=[System.Collections.Generic.List[object]]::new()
foreach($mutation in $mutations){$copy=[ordered]@{collector=(Read-BoundedJson (Join-Path $FailureRoot $names.collector));coordinator=(Read-BoundedJson (Join-Path $FailureRoot $names.coordinator));launcher=(Read-BoundedJson (Join-Path $FailureRoot $names.launcher))};& $mutation.apply $copy;$dir=Join-Path $ControlRoot $mutation.name;[IO.Directory]::CreateDirectory($dir)|Out-Null;foreach($name in $names.Keys){$copy[$name]|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $dir $names[$name]) -Encoding UTF8};$v=Test-HeldPredicateV13 $copy.launcher $copy.collector $copy.coordinator ([string]$pins.taskName);if($v.accepted){throw "held predicate fault accepted: $($mutation.name)"};$rows.Add([ordered]@{name=$mutation.name;status='rejected';reasons=@($v.reasons)})}
[ordered]@{kind='sr0-display-failed-observer-held-predicate-controls-v13';status='passed-source-controls';actual=$base;faults=@($rows);qualificationClaim=$false;lockReleaseEligibility=$false}|ConvertTo-Json -Depth 16
