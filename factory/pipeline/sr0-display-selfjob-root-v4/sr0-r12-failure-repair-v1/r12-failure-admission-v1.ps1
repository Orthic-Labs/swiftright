# Pure admission predicate for an already sealed SR0 r12 failure.
# It proves bounded transport quiescence only; it never grants display qualification or releases CAS.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-R12BoundedJson {
  param([Parameter(Mandatory)][string]$Path,[int64]$MaxBytes = 1048576)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse evidence: $Path" }
  if ($item.PSIsContainer -or $item.Length -gt $MaxBytes) { throw "bounded evidence rejected: $Path" }
  return ([IO.File]::ReadAllText($item.FullName) | ConvertFrom-Json)
}

function Test-R12EqualExit {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$Prefix)
  foreach ($name in @("${Prefix}ExitRaw", "${Prefix}ExitSigned", "${Prefix}ExitDotnet")) {
    if (-not ($Receipt.PSObject.Properties.Name -contains $name)) { return $false }
  }
  return ([int64]$Receipt."${Prefix}ExitRaw" -eq [int64]$Receipt."${Prefix}ExitSigned" -and
          [int64]$Receipt."${Prefix}ExitSigned" -eq [int64]$Receipt."${Prefix}ExitDotnet")
}

function Test-R12OriginalFailureQuiescence {
  param(
    [Parameter(Mandatory)][string]$CollectorPath,
    [Parameter(Mandatory)][string]$CoordinatorPath,
    [Parameter(Mandatory)][string]$LauncherPath,
    [Parameter(Mandatory)][string]$TaskName,
    [int64]$MaxJsonBytes = 1048576
  )
  $collector = Read-R12BoundedJson -Path $CollectorPath -MaxBytes $MaxJsonBytes
  $coordinator = Read-R12BoundedJson -Path $CoordinatorPath -MaxBytes $MaxJsonBytes
  $launcher = Read-R12BoundedJson -Path $LauncherPath -MaxBytes $MaxJsonBytes
  $reasons = [System.Collections.Generic.List[string]]::new()
  $collectorClaim = if ($collector.PSObject.Properties.Name -contains 'qualificationClaim') { [bool]$collector.qualificationClaim } else { $false }
  $collectorRelease = if ($collector.PSObject.Properties.Name -contains 'releaseAllowed') { [bool]$collector.releaseAllowed } else { $false }
  if ([string]$collector.kind -ne 'sr0-display-collector-v8-drain-pidjoin') { [void]$reasons.Add('collector-kind') }
  if ([string]$coordinator.kind -ne 'sr0-display-coordinator-v5') { [void]$reasons.Add('coordinator-kind') }
  if ([string]$launcher.kind -ne 'sr0-display-launcher-v8-status') { [void]$reasons.Add('launcher-kind') }
  foreach ($r in @($collector,$coordinator,$launcher)) {
    if ([string]$r.taskName -cne $TaskName) { [void]$reasons.Add('task-name') }
  }
  if ([string]$collector.status -cne 'failed') { [void]$reasons.Add('collector-not-failed') }
  if ([string]::IsNullOrWhiteSpace([string]$collector.failure)) { [void]$reasons.Add('collector-failure-missing') }
  if ([string]$collector.failure -notmatch '(?i)workload exit row count mismatch') { [void]$reasons.Add('collector-failure-kind') }
  foreach ($name in @('parentOriginalHandleRetained','parentOriginalHandleAcquired','workloadHandleAcquired','workloadTerminal','workloadExitIdentity','activeSelfOnly')) {
    if (-not [bool]$collector.$name) { [void]$reasons.Add("collector-$name") }
  }
  if ([int64]$collector.activeAfter -ne 1 -or [int64]$collector.workloadExit -ne 0) { [void]$reasons.Add('collector-terminal-state') }
  # Failure is retained as qualification-false. No result rows may be manufactured by this predicate.
  if ([bool]$collector.captureComplete -or $collectorClaim -or $collectorRelease) { [void]$reasons.Add('collector-qualification-claim') }
  if ([string]$coordinator.status -ne 'held') { [void]$reasons.Add('coordinator-not-held') }
  if ([bool]$coordinator.parentCertificatePresent) { [void]$reasons.Add('unexpected-parent-certificate') }
  if (-not [bool]$coordinator.parentKernelTerminal) { [void]$reasons.Add('parent-kernel-not-terminal') }
  if (-not (Test-R12EqualExit -Receipt $coordinator -Prefix 'parent')) { [void]$reasons.Add('parent-exit-identity') }
  if ([string]$launcher.status -ne 'held') { [void]$reasons.Add('launcher-not-held') }
  foreach ($name in @('coordinatorHandleAcquired','coordinatorTerminal','coordinatorExitIdentity','collectorHandleAcquired','collectorTerminal','collectorExitIdentity','childReceiptsRead','aggregateDescendantsQuiesced','aggregateCleanupSelfOnly')) {
    if (-not [bool]$launcher.$name) { [void]$reasons.Add($name) }
  }
  if (-not (Test-R12EqualExit -Receipt $launcher -Prefix 'coordinator')) { [void]$reasons.Add('coordinator-exit-identity') }
  if (-not (Test-R12EqualExit -Receipt $launcher -Prefix 'collector')) { [void]$reasons.Add('collector-exit-identity') }
  if ([int64]$launcher.aggregateActiveAfter -ne 1) { [void]$reasons.Add('aggregate-not-self-only-count1') }
  if ([bool]$launcher.aggregateMemoryCapExceeded) { [void]$reasons.Add('aggregate-memory-cap') }
  if ([bool]$launcher.terminationAttempted) { [void]$reasons.Add('unexpected-termination') }
  $valid = ($reasons.Count -eq 0)
  [ordered]@{
    kind = 'sr0-display-r12-failure-transport-admission-v1'
    status = if ($valid) { 'early-failure-held' } else { 'rejected' }
    taskName = $TaskName
    qualificationClaim = $false
    qualificationStatus = 'held-row-count-mismatch'
    transportQuiescent = $valid
    originalParentTerminalProof = $valid
    originalLauncherQuiescenceProof = $valid
    parentCertificatePresent = [bool]$coordinator.parentCertificatePresent
    currentAggregateActive = [int64]$launcher.aggregateActiveAfter
    lockReleaseEligibility = $false
    releaseAction = 'none'
    reasons = @($reasons)
    sourceEvidence = [ordered]@{ collector=$CollectorPath; coordinator=$CoordinatorPath; launcher=$LauncherPath }
  }
}
