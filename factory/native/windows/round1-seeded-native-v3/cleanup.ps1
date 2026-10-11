# Kernel process signal is separate from Framework HasExited/exit-code observation.
if(-not ('FactoryProcessWaitV3' -as [type])) {
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FactoryProcessWaitV3 {
 [DllImport("kernel32.dll", SetLastError=true)] public static extern UInt32 WaitForSingleObject(IntPtr handle, UInt32 milliseconds);
}
'@
}
function Invoke-FactoryOwnedCleanup($Process,[string]$Path,[string]$StartedAt,[int]$WaitMilliseconds=5000,[scriptblock]$Lookup={param($id) Get-Process -Id $id -ErrorAction Stop},[switch]$KnownStartedIdentity,[scriptblock]$KernelWait={param($handle,$ms) [FactoryProcessWaitV3]::WaitForSingleObject($handle,[uint32]$ms)}) {
 $result=[ordered]@{confirmedOwnedExit=$false;kernelExitSignaled=$false;kernelWaitResult=$null;exitCertification='retained-kernel-handle';hasExitedObserved=$null;killAttempted=$false;status='hold-cleanup';error=''}
 try {
  $retainedHandle=$Process.Handle
  if($retainedHandle -eq [IntPtr]::Zero){throw 'Stable process handle unavailable'}
  $Process.Refresh();$result.hasExitedObserved=[bool]$Process.HasExited
  if(-not $result.hasExitedObserved -and ($Process.Path -ne $Path -or $Process.StartTime.ToUniversalTime().ToString('o') -ne $StartedAt)){throw 'Retained process identity drift'}
  if($result.hasExitedObserved -and -not $KnownStartedIdentity){throw 'Exited process lacks known Start lineage'}
  $wait=[uint32](& $KernelWait $retainedHandle 0);$result.kernelWaitResult=$wait
  if($wait -eq 0){$result.confirmedOwnedExit=$true;$result.kernelExitSignaled=$true;$result.status='already-signaled';return $result}
  if($wait -ne 258){throw ('Kernel exit wait failed: '+$wait)}
  if($result.hasExitedObserved){
   $wait=[uint32](& $KernelWait $retainedHandle $WaitMilliseconds);$result.kernelWaitResult=$wait
   if($wait -ne 0){throw ('HasExited without retained kernel exit signal: '+$wait)}
   $result.confirmedOwnedExit=$true;$result.kernelExitSignaled=$true;$result.status='signaled-after-exit-observation';return $result
  }
  try{$fresh=& $Lookup $Process.Id}catch{
   $wait=[uint32](& $KernelWait $retainedHandle 0);$result.kernelWaitResult=$wait
   if($wait -eq 0){$result.confirmedOwnedExit=$true;$result.kernelExitSignaled=$true;$result.status='signaled-during-lookup';return $result}
   throw 'Owned process lookup failed without retained kernel exit signal'
  }
  if($fresh.Path -ne $Path -or $fresh.StartTime.ToUniversalTime().ToString('o') -ne $StartedAt){throw 'Owned cleanup identity drift'}
  $wait=[uint32](& $KernelWait $retainedHandle 0);$result.kernelWaitResult=$wait
  if($wait -eq 0){$result.confirmedOwnedExit=$true;$result.kernelExitSignaled=$true;$result.status='signaled-before-kill';return $result}
  if($wait -ne 258){throw ('Kernel exit wait failed: '+$wait)}
  $result.killAttempted=$true
  try{$Process.Kill()}catch{
   $wait=[uint32](& $KernelWait $retainedHandle 0);$result.kernelWaitResult=$wait
   if($wait -ne 0){throw}
   $result.status='signaled-during-kill'
  }
  $wait=[uint32](& $KernelWait $retainedHandle $WaitMilliseconds);$result.kernelWaitResult=$wait
  if($wait -ne 0){throw ('Owned cleanup kernel exit deadline/failure: '+$wait)}
  $Process.Refresh();$result.hasExitedObserved=[bool]$Process.HasExited
  $result.confirmedOwnedExit=$true;$result.kernelExitSignaled=$true
  if($result.status -eq 'hold-cleanup'){$result.status='killed-owned-handle-signaled'}
 }catch{$result.error=[string]$_}
 return $result
}

# Shared production error priority; original ErrorRecord always wins.
function Assert-FactoryCaptureOutcome($PrimaryError,$Cleanup,[object[]]$StreamErrors){
 if($null -ne $PrimaryError){throw $PrimaryError}
 if(-not $Cleanup.confirmedOwnedExit -or -not $Cleanup.kernelExitSignaled -or $Cleanup.exitCertification -cne 'retained-kernel-handle' -or @($StreamErrors).Count -ne 0){throw 'Owned cleanup/raw stream failure; inspect capture-outcome.json'}
}
# Do not free desktop while owned exit remains unconfirmed.
function Invoke-FactoryConfirmedRelease([bool]$Acquired,[bool]$ExitConfirmed,[scriptblock]$Release){
 if(-not $Acquired -or -not $ExitConfirmed){return $false}
 return [bool](& $Release)
}
# Capture's retained Start handle can certify exit after a later PID lookup loses original identity.
function Test-FactoryCaptureExitProof($Outcome,$Owned,[string]$Owner,[string]$CompileHash,[string]$ExeHash,[string]$StdoutHash,[string]$StderrHash,[string]$ExpectedPath){
 return [bool](($Outcome.cleanup.confirmedOwnedExit -is [bool]) -and $Outcome.cleanup.confirmedOwnedExit -and ($Outcome.cleanup.kernelExitSignaled -is [bool]) -and $Outcome.cleanup.kernelExitSignaled -and $Outcome.cleanup.exitCertification -ceq 'retained-kernel-handle' -and
  $Owned.pid -gt 0 -and -not [string]::IsNullOrEmpty($Owned.startedAt) -and $Owned.path -ceq $ExpectedPath -and $Outcome.ownedIdentity.pid -eq $Owned.pid -and $Outcome.ownedIdentity.path -ceq $Owned.path -and $Outcome.ownedIdentity.startedAt -ceq $Owned.startedAt -and
  $Outcome.lockOwner -ceq $Owner -and $Outcome.compileReceiptHash -ceq $CompileHash -and $Outcome.exeHash -ceq $ExeHash -and
  $Outcome.stdoutSha256 -ceq $StdoutHash -and $Outcome.stderrSha256 -ceq $StderrHash -and
  $CompileHash -cmatch '^[0-9a-f]{64}$' -and $ExeHash -cmatch '^[0-9a-f]{64}$' -and $StdoutHash -cmatch '^[0-9a-f]{64}$' -and $StderrHash -cmatch '^[0-9a-f]{64}$')
}
