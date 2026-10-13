# Pure report-only predicate for r13 capture-held terminal evidence v14.
# It never qualifies display output, releases locks, or mutates receipts.
function Test-CaptureHeldTerminalV13 {
  param([object]$Launcher,[object]$Collector,[object]$Coordinator)
  if($null -eq $Launcher -or $null -eq $Collector -or $null -eq $Coordinator){return $false}
  function HasProp([object]$Object,[string]$Name){if($null -eq $Object){return $false};$propertyNames=@($Object.PSObject.Properties|ForEach-Object{$_.Name});return ($propertyNames -contains $Name)}
  function TrueField([object]$Object,[string]$Name){$present=HasProp $Object $Name;if(-not $present){return $false};$value=$Object.PSObject.Properties[$Name].Value;return ([bool]$value)}
  function FalseOrAbsent([object]$Object,[string]$Name){$present=HasProp $Object $Name;if(-not $present){return $true};$value=$Object.PSObject.Properties[$Name].Value;return (-not [bool]$value)}
  function NullOrAbsent([object]$Object,[string]$Name){$present=HasProp $Object $Name;if(-not $present){return $true};return ($null -eq $Object.PSObject.Properties[$Name].Value)}
  function NoClaim([object]$Object){return (-not (TrueField $Object 'qualificationClaim')) -and (-not (TrueField $Object 'nativeQualificationClaim'))}
  $csv=$Collector.presentMonCsvEvidence;$proof=$Collector.workloadProof
  $errors=@($Coordinator.errors|ForEach-Object{[string]$_})
  return (
    ([string]$Launcher.kind -ceq 'sr0-display-launcher-v8-status') -and
    ([string]$Launcher.status -ceq 'held') -and (TrueField $Launcher 'childReceiptsRead') -and
    (TrueField $Launcher 'aggregateDescendantsQuiesced') -and ([int64]$Launcher.aggregateActiveAfter -eq 1) -and
    (TrueField $Launcher 'collectorTerminal') -and (TrueField $Launcher 'collectorExitIdentity') -and
    (TrueField $Launcher 'coordinatorTerminal') -and (TrueField $Launcher 'coordinatorExitIdentity') -and (NoClaim $Launcher) -and
    ([string]$Collector.kind -ceq 'sr0-display-collector-v8-drain-pidjoin') -and
    ([string]$Collector.status -ceq 'qualification-held') -and (TrueField $Collector 'captureComplete') -and
    (TrueField $Collector 'qualificationHeld') -and ([string]$Collector.qualificationHoldReason -ceq 'strict-display-parser-pending') -and
    (NoClaim $Collector) -and (TrueField $Collector 'parentOriginalHandleAcquired') -and (TrueField $Collector 'parentOriginalHandleRetained') -and
    (TrueField $Collector 'activeSelfOnly') -and ([int64]$Collector.activeAfter -eq 1) -and
    (TrueField $Collector 'presentMonTerminal') -and (TrueField $Collector 'presentMonExitIdentity') -and
    (TrueField $Collector 'presentMonNaturalExit') -and (FalseOrAbsent $Collector 'presentMonForcedStopAttempted') -and
    (TrueField $Collector 'presentMonStreamsSealed') -and (TrueField $Collector 'presentMonExpectedStopValidated') -and
    (TrueField $Collector 'workloadHandleAcquired') -and (TrueField $Collector 'workloadTerminal') -and (TrueField $Collector 'workloadExitIdentity') -and
    (TrueField $Collector 'releaseAllowed') -and (TrueField $Collector 'lockReleased') -and
    ($null -ne $csv) -and (TrueField $csv 'valid') -and ([int64]$csv.dataRows -gt 0) -and ([int64]$csv.workloadRows -gt 0) -and
    (TrueField $csv 'qpcValid') -and ([int64]$csv.targetPid -gt 0) -and
    (TrueField $proof 'streamsDrained') -and (TrueField $proof 'taskQuiescent') -and (TrueField $proof 'ownershipTerminal') -and
    (TrueField $proof 'allRunsValid') -and (NullOrAbsent $Collector 'failure') -and
    ([string]$Coordinator.kind -ceq 'sr0-display-coordinator-v5') -and ([string]$Coordinator.status -ceq 'held') -and
    (TrueField $Coordinator 'parentKernelTerminal') -and ([int64]$Coordinator.parentExitRaw -eq 0) -and
    ([int64]$Coordinator.parentExitSigned -eq 0) -and ([int64]$Coordinator.parentExitDotnet -eq 0) -and
    (FalseOrAbsent $Coordinator 'parentCertificatePresent') -and (FalseOrAbsent $Coordinator 'lockOwnerObserved') -and
    ($errors -contains 'final-kind') -and (NoClaim $Coordinator)
  )
}
