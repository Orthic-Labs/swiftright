[CmdletBinding()]
param([Parameter(Mandatory)][string]$FailureRoot,[Parameter(Mandatory)][string]$ControlRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'r12-failure-admission-v1.ps1')
$names = [ordered]@{ collector='collector.json'; coordinator='coordinator.json'; launcher='launcher.json' }
$actual = Test-R12OriginalFailureQuiescence -CollectorPath (Join-Path $FailureRoot $names.collector) -CoordinatorPath (Join-Path $FailureRoot $names.coordinator) -LauncherPath (Join-Path $FailureRoot $names.launcher) -TaskName 'SR0-factory-display-selfjob-v7-root-r12'
if ([string]$actual.status -ne 'early-failure-held' -or [bool]$actual.qualificationClaim) { throw 'actual r12 failure must be held without qualification' }
if (-not (Test-Path -LiteralPath $ControlRoot -PathType Container)) { [IO.Directory]::CreateDirectory($ControlRoot) | Out-Null }
# Mutations execute same production predicate; each must reject without changing raw evidence.
$base = [ordered]@{ collector=(Read-R12BoundedJson (Join-Path $FailureRoot $names.collector)); coordinator=(Read-R12BoundedJson (Join-Path $FailureRoot $names.coordinator)); launcher=(Read-R12BoundedJson (Join-Path $FailureRoot $names.launcher)) }
$mutations = @(
  @{ name='collector-row-success'; apply={ $base.collector.captureComplete=$true } },
  @{ name='collector-target-fabrication'; apply={ $base.collector.workloadTargetPid=47312 } },
  @{ name='launcher-active-two'; apply={ $base.launcher.aggregateActiveAfter=2 } },
  @{ name='parent-terminal-missing'; apply={ $base.coordinator.parentKernelTerminal=$false } },
  @{ name='launcher-quiescence-missing'; apply={ $base.launcher.aggregateDescendantsQuiesced=$false } },
  @{ name='coordinator-handle-unproven'; apply={ $base.launcher.coordinatorHandleAcquired=$false } },
  @{ name='collector-exit-identity-missing'; apply={ $base.launcher.collectorExitIdentity=$false } },
  @{ name='parent-exit-mismatch'; apply={ $base.coordinator.parentExitSigned=0 } }
)
$results = [System.Collections.Generic.List[object]]::new()
foreach ($m in $mutations) {
  & $m.apply
  $dir = Join-Path $ControlRoot $m.name
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
  foreach ($pair in @(@('collector.json',$base.collector),@('coordinator.json',$base.coordinator),@('launcher.json',$base.launcher))) { $pair[1] | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $dir $pair[0]) -Encoding UTF8 }
  $v = Test-R12OriginalFailureQuiescence -CollectorPath (Join-Path $dir 'collector.json') -CoordinatorPath (Join-Path $dir 'coordinator.json') -LauncherPath (Join-Path $dir 'launcher.json') -TaskName 'SR0-factory-display-selfjob-v7-root-r12'
  if ([string]$v.status -ne 'rejected') { throw "mutation accepted: $($m.name)" }
  $results.Add([ordered]@{name=$m.name;status=$v.status;reasons=@($v.reasons)})
  $base = [ordered]@{ collector=(Read-R12BoundedJson (Join-Path $FailureRoot $names.collector)); coordinator=(Read-R12BoundedJson (Join-Path $FailureRoot $names.coordinator)); launcher=(Read-R12BoundedJson (Join-Path $FailureRoot $names.launcher)) }
}
[ordered]@{status='controls-pass';baseline=$actual;mutations=@($results);qualificationClaim=$false} | ConvertTo-Json -Depth 16
