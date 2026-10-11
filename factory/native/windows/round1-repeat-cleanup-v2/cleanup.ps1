# Retained Process handle + fresh identity gate. Never kill by PID alone.
function Invoke-FactoryOwnedCleanup($Process,[string]$Path,[string]$StartedAt,[int]$WaitMilliseconds=5000,[scriptblock]$Lookup={param($id) Get-Process -Id $id -ErrorAction Stop},[switch]$KnownStartedIdentity) {
 $result=[ordered]@{confirmedOwnedExit=$false;killAttempted=$false;status='hold-cleanup';error=''}
 try {
  # Materialize stable OS handle before identity lookup/Kill; same object retains it.
  $retainedHandle=$Process.Handle
  if($retainedHandle -eq [IntPtr]::Zero){throw 'Stable process handle unavailable'}
  $Process.Refresh()
  if(-not $Process.HasExited -and ($Process.Path -ne $Path -or $Process.StartTime.ToUniversalTime().ToString('o') -ne $StartedAt)){throw 'Retained process identity drift'}
  if($Process.HasExited -and -not $KnownStartedIdentity){throw 'Exited process lacks known Start lineage'}
  if($Process.HasExited){$result.confirmedOwnedExit=$true;$result.status='already-exited';return $result}
  try{$fresh=& $Lookup $Process.Id}catch{
   $Process.Refresh()
   if($Process.HasExited){$result.confirmedOwnedExit=$true;$result.status='exit-during-lookup';return $result}
   throw 'Owned process lookup failed without confirmed retained-handle exit'
  }
  if($fresh.Path -ne $Path -or $fresh.StartTime.ToUniversalTime().ToString('o') -ne $StartedAt){throw 'Owned cleanup identity drift'}
  $Process.Refresh()
  if($Process.HasExited){$result.confirmedOwnedExit=$true;$result.status='exit-before-kill';return $result}
  $result.killAttempted=$true
  try{$Process.Kill()}catch{
   $Process.Refresh()
   if(-not $Process.HasExited){throw}
   $result.status='exit-during-kill'
  }
  if(-not $Process.WaitForExit($WaitMilliseconds)){throw 'Owned cleanup wait deadline'}
  $Process.Refresh()
  if(-not $Process.HasExited){throw 'Owned cleanup exit unconfirmed'}
  $result.confirmedOwnedExit=$true
  if($result.status -eq 'hold-cleanup'){$result.status='killed-owned-handle'}
 }catch{$result.error=[string]$_}
 return $result
}

# Shared production error priority; original ErrorRecord always wins.
function Assert-FactoryCaptureOutcome($PrimaryError,$Cleanup,[object[]]$StreamErrors){
 if($null -ne $PrimaryError){throw $PrimaryError}
 if(-not $Cleanup.confirmedOwnedExit -or @($StreamErrors).Count -ne 0){throw 'Owned cleanup/raw stream failure; inspect capture-outcome.json'}
}
# Do not free desktop while owned exit remains unconfirmed.
function Invoke-FactoryConfirmedRelease([bool]$Acquired,[bool]$ExitConfirmed,[scriptblock]$Release){
 if(-not $Acquired -or -not $ExitConfirmed){return $false}
 return [bool](& $Release)
}
