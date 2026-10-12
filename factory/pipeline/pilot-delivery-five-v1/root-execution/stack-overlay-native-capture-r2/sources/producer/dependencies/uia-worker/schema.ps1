# Scalar-only UIA snapshot validation; this file loads no UIA assembly/element type.
function Test-UiaSnapshotInteger($Value){return [bool]($Value -is [int] -or $Value -is [long])}
function Assert-UiaSnapshotTargetObject($Expected,$Observed) {
 if(-not(Test-UiaSnapshotInteger $Expected.pid) -or $Expected.pid -le 0 -or -not(Test-UiaSnapshotInteger $Expected.hwnd) -or $Expected.hwnd -le 0){throw 'Typed owned target PID/HWND required'}
 foreach($n in @('pid','windowPid','hwnd','foregroundPid','foregroundHwnd','workerPid')){if(-not(Test-UiaSnapshotInteger $Observed.$n)){throw 'Typed observed target identity required'}}
 if($Expected.path -isnot [string] -or $Expected.startedAt -isnot [string] -or $Expected.lockOwner -isnot [string]){throw 'Typed target path/start/lock required'}
 if([string]::IsNullOrEmpty($Expected.path) -or [string]::IsNullOrEmpty($Expected.startedAt) -or [string]::IsNullOrEmpty($Expected.lockOwner)){throw 'Exact target path/start/lock required'}
 if($Observed.hasExited -isnot [bool] -or $Observed.hasExited -or $Observed.path -cne $Expected.path -or $Observed.startedAt -cne $Expected.startedAt -or $Observed.pid -ne $Expected.pid -or $Observed.windowPid -ne $Expected.pid -or $Observed.hwnd -ne $Expected.hwnd){throw 'Owned target identity/HWND drift'}
 if($Observed.foregroundPid -eq $Expected.pid -or $Observed.foregroundPid -eq $Observed.workerPid -or $Observed.foregroundHwnd -eq $Expected.hwnd){throw 'Owned target/worker foreground'}
 if($Observed.lockOwner -cne $Expected.lockOwner){throw 'Desktop lock ownership drift'}
}
function Assert-UiaSnapshotScalarObject($Node,[int]$Depth=0) {
 if($Depth -gt 40){throw 'UIA depth bound exceeded'}
 $names=@($Node.PSObject.Properties.Name);$expected=@('name','automationId','controlType','enabled','patterns','offscreen','bounds','children')
 if($names.Count -ne 8 -or @($names|Where-Object{$expected -cnotcontains $_}).Count){throw 'Exact UIA record properties required'}
 foreach($name in @('name','automationId','controlType')){if($Node.$name -isnot [string]){throw 'UIA string scalar required'}}
 foreach($name in @('enabled','offscreen')){if($Node.$name -isnot [bool]){throw 'UIA boolean scalar required'}}
 if($Node.patterns -isnot [array] -or $Node.bounds -isnot [array] -or $Node.children -isnot [array]){throw 'UIA arrays required'}
 foreach($pattern in $Node.patterns){if($pattern -isnot [string]){throw 'UIA pattern string scalar required'}}
 if($Node.bounds.Count -ne 4){throw 'UIA four bounds scalars required'}
 foreach($bound in $Node.bounds){if($bound -isnot [int] -and $bound -isnot [long] -and $bound -isnot [double] -and $bound -isnot [decimal]){throw 'UIA numeric bound required'};if([double]::IsNaN([double]$bound) -or [double]::IsInfinity([double]$bound)){throw 'UIA finite bound required'}}
 if($Node.children.Count -gt 1000){throw 'UIA child bound exceeded'}
 foreach($child in $Node.children){Assert-UiaSnapshotScalarObject $child ($Depth+1)}
}
function Assert-UiaSnapshotWorkerProof($Proof,$Expected,[string]$StdoutHash,[string]$StderrHash,[string]$UiaHash) {
 if($Proof.kind -cne 'factory-uia-snapshot-worker-exit-v2' -or $Proof.status -cne 'completed-natural-uiasnapshot' -or $Proof.target.pid -ne $Expected.pid -or $Proof.target.hwnd -ne $Expected.hwnd -or $Proof.target.path -cne $Expected.path -or $Proof.target.startedAt -cne $Expected.startedAt -or $Proof.target.lockOwner -cne $Expected.lockOwner){throw 'Worker target/proof authority mismatch'}
 if($Proof.primaryError -cne '' -or -not(Test-UiaSnapshotInteger $Proof.ownedIdentity.pid) -or $Proof.ownedIdentity.pid -le 0 -or -not(Test-UiaSnapshotInteger $Proof.ownedIdentity.retainedHandle) -or $Proof.ownedIdentity.retainedHandle -le 0 -or [string]::IsNullOrEmpty($Proof.ownedIdentity.path) -or [string]::IsNullOrEmpty($Proof.ownedIdentity.startedAt) -or $Proof.parentApartment -cnotin @('STA','MTA') -or $Proof.workerApartment -cne 'MTA'){throw 'Owned worker identity/source authority required'}
 foreach($h in @($Proof.configSha256,$Proof.sourceContractSha256,$Proof.workerExeSha256)){if($h -cnotmatch '^[0-9a-f]{64}$'){throw 'Worker config/source/exe SHA required'}}
 if(-not(Test-UiaSnapshotInteger $Proof.exitCode) -or $Proof.exitCode -ne 0 -or $Proof.timedOut -isnot [bool] -or $Proof.timedOut -or $Proof.preCleanupKernelWaitResult -isnot [int] -or $Proof.preCleanupKernelWaitResult -ne 0){throw 'Worker natural kernel0 exit required'}
 if(-not(Test-FactoryKernelExitCertificate $Proof.cleanup) -or $Proof.cleanup.killAttempted -isnot [bool] -or $Proof.cleanup.killAttempted -or $Proof.cleanup.status -cne 'already-signaled' -or $Proof.cleanup.error -cne '' -or @($Proof.streamErrors).Count){throw 'Worker cleanup natural exit/raw error'}
 $streams=@($Proof.rawStreams);if($streams.Count -ne 2 -or @($streams|Where-Object{$_.name -ceq 'stdout'}).Count -ne 1 -or @($streams|Where-Object{$_.name -ceq 'stderr'}).Count -ne 1){throw 'Worker exact two raw streams required'}
 foreach($s in $streams){
  if(-not(Test-FactoryRawDestinationClosed $s) -or $s.copyCompleted -isnot [bool] -or -not $s.copyCompleted -or $s.sealed -isnot [bool] -or -not $s.sealed -or $s.hashQualification -cne 'sealed-raw' -or $s.taskStatus -cne 'RanToCompletion' -or $s.taskIsCompleted -isnot [bool] -or -not $s.taskIsCompleted -or $s.taskIsFaulted -isnot [bool] -or $s.taskIsFaulted -or $s.taskIsCanceled -isnot [bool] -or $s.taskIsCanceled -or $s.taskException -cne '' -or $s.closure.flushCompleted -isnot [bool] -or -not $s.closure.flushCompleted -or $s.closure.deadlineExpired -isnot [bool] -or $s.closure.deadlineExpired -or $s.closure.error -cne ''){throw 'Worker raw unsealed/faulted'}
 }
 foreach($h in @($StdoutHash,$StderrHash,$UiaHash)){if($h -cnotmatch '^[0-9a-f]{64}$'){throw 'Worker measured output SHA required'}}
 if($Proof.stdoutSha256 -cne $StdoutHash -or $Proof.stderrSha256 -cne $StderrHash -or $Proof.uiaSha256 -cne $UiaHash){throw 'Worker output bytes mismatch'}
}
