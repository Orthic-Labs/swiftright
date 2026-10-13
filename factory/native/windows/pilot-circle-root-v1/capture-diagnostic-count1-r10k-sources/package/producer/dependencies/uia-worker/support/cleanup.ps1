# Prospective cleanup successor. Frozen r9 cleanup.ps1 remains unchanged.
# Kernel retained-handle signal is exit authority; Framework HasExited is diagnostic only.
if(-not ('FactoryProcessWaitV6' -as [type])) {
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class FactoryProcessWaitV6 {
 [StructLayout(LayoutKind.Sequential)] private struct FILETIME_NATIVE { public UInt32 Low; public UInt32 High; }
 [DllImport("kernel32.dll", SetLastError=true)] public static extern UInt32 WaitForSingleObject(IntPtr handle, UInt32 milliseconds);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern bool TerminateProcess(IntPtr handle, UInt32 code);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern UInt32 GetProcessId(IntPtr handle);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr handle, out UInt32 code);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool QueryFullProcessImageNameW(IntPtr handle, UInt32 flags, StringBuilder name, ref UInt32 size);
 [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetProcessTimes(IntPtr handle, out FILETIME_NATIVE creation, out FILETIME_NATIVE exit, out FILETIME_NATIVE kernel, out FILETIME_NATIVE user);
 public static bool ReadIdentity(IntPtr handle, out UInt32 pid, out String path, out Int64 startFileTime) {
  pid=GetProcessId(handle); path=null; startFileTime=0; if(pid==0) return false;
  var name=new StringBuilder(32768); UInt32 size=(UInt32)name.Capacity;
  if(!QueryFullProcessImageNameW(handle,0,name,ref size)) return false;
  FILETIME_NATIVE c,e,k,u; if(!GetProcessTimes(handle,out c,out e,out k,out u)) return false;
  path=name.ToString(); startFileTime=((Int64)c.High << 32) | (UInt32)c.Low; return true;
 }
}
'@
}
function Test-FactoryKernelWaitNumber($Value){
 return [bool]($Value -is [int] -or $Value -is [long] -or $Value -is [uint32] -or $Value -is [uint64])
}
function Test-FactoryKernelExitCertificate($Cleanup){
 return [bool](($Cleanup.confirmedOwnedExit -is [bool]) -and $Cleanup.confirmedOwnedExit -and ($Cleanup.kernelExitSignaled -is [bool]) -and $Cleanup.kernelExitSignaled -and (Test-FactoryKernelWaitNumber $Cleanup.kernelWaitResult) -and $Cleanup.kernelWaitResult -eq 0 -and ($Cleanup.kernelExitCodeRead -is [bool]) -and $Cleanup.kernelExitCodeRead -and (Test-FactoryKernelWaitNumber $Cleanup.kernelExitCode) -and (([uint32]$Cleanup.kernelExitCode) -ne 259) -and ($Cleanup.exitCertification -is [string]) -and $Cleanup.exitCertification -ceq 'retained-kernel-handle' -and ($Cleanup.status -is [string]) -and $Cleanup.status -cin @('already-signaled','signaled-after-exit-observation','signaled-during-lookup','signaled-before-kill','signaled-during-kill','killed-owned-handle-signaled','killed-owned-handle-after-phantom-exited'))
}
function Invoke-FactoryOwnedCleanup($Process,[string]$Path,[string]$StartedAt,[int]$WaitMilliseconds=5000,[string]$ExpectedExeHash,[scriptblock]$Lookup={param($id) Get-Process -Id $id -ErrorAction Stop},[switch]$KnownStartedIdentity,[scriptblock]$KernelWait={param($handle,$ms) [FactoryProcessWaitV6]::WaitForSingleObject($handle,[uint32]$ms)},[scriptblock]$KernelTerminate={param($handle,$code) [FactoryProcessWaitV6]::TerminateProcess($handle,[uint32]$code)},[scriptblock]$KernelPid={param($handle) [FactoryProcessWaitV6]::GetProcessId($handle)},[scriptblock]$KernelExitCode={param($handle) $code=[uint32]0;$ok=[FactoryProcessWaitV6]::GetExitCodeProcess($handle,[ref]$code);[pscustomobject]@{succeeded=$ok;code=$code}},[scriptblock]$KernelIdentity={param($handle) $ownedPid=[uint32]0;$path=$null;[long]$ft=0;$ok=[FactoryProcessWaitV6]::ReadIdentity($handle,[ref]$ownedPid,[ref]$path,[ref]$ft);[pscustomobject]@{succeeded=$ok;pid=$ownedPid;path=$path;startFileTime=$ft}},[string]$Unused='') {
 $result=[ordered]@{confirmedOwnedExit=$false;kernelExitSignaled=$false;kernelWaitResult=$null;kernelExitCode=$null;kernelExitCodeRead=$false;exitCertification='retained-kernel-handle';hasExitedObserved=$null;killAttempted=$false;status='hold-cleanup';error='';kernelHandlePid=$null;identityChecked=$false;exeHashObserved=$null;terminationReason=''}
 $retainedHandle=[IntPtr]::Zero
 try {
  $retainedHandle=$Process.Handle
  if($retainedHandle -eq [IntPtr]::Zero){throw 'Stable process handle unavailable'}
  try{$Process.Refresh();$result.hasExitedObserved=[bool]$Process.HasExited}catch{$result.hasExitedObserved=$null}
  if([string]::IsNullOrWhiteSpace($ExpectedExeHash) -or $ExpectedExeHash -cnotmatch '^[0-9a-fA-F]{64}$'){throw 'Pinned executable hash required'}
  $expectedFull=[IO.Path]::GetFullPath($Path);$expectedStart=[DateTimeOffset]::Parse($StartedAt).UtcDateTime
  $handlePid=& $KernelPid $retainedHandle;$result.kernelHandlePid=$handlePid
  if(-not(Test-FactoryKernelWaitNumber $handlePid) -or [uint32]$handlePid -ne [uint32]$Process.Id -or [uint32]$handlePid -eq 0){throw 'Retained handle PID identity mismatch'}
  $wait=& $KernelWait $retainedHandle 0;$result.kernelWaitResult=$wait
  if(-not(Test-FactoryKernelWaitNumber $wait) -or $wait -notin @(0,258)){throw ('Kernel exit wait failed: '+$wait)}
  # A terminal original handle needs no fresh image lookup. A live handle
  # must supply its own native path/start before termination is considered.
  if($wait -eq 258){
   $identity=& $KernelIdentity $retainedHandle
   if($null -eq $identity -or -not $identity.succeeded){throw 'Retained handle identity query failed'}
   $handlePid=$identity.pid;$result.kernelHandlePid=$handlePid
   if(-not(Test-FactoryKernelWaitNumber $handlePid) -or [uint32]$handlePid -ne [uint32]$Process.Id -or [uint32]$handlePid -eq 0){throw 'Retained handle PID identity mismatch'}
   if(-not [String]::Equals([string]$identity.path,$expectedFull,[StringComparison]::OrdinalIgnoreCase)){throw 'Retained process path identity drift'}
   if([DateTime]::FromFileTimeUtc([int64]$identity.startFileTime).Ticks -ne $expectedStart.Ticks){throw 'Retained process start identity drift'}
  }
  $result.identityChecked=$true
  $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 536870912){throw 'Executable identity file unsafe'}
  $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant();$result.exeHashObserved=$actual
  if($actual -cne $ExpectedExeHash.ToLowerInvariant()){throw 'Executable identity hash drift'}
  if($wait -eq 0){$exit=& $KernelExitCode $retainedHandle;if($null -eq $exit -or -not $exit.succeeded -or [uint32]$exit.code -eq 259){throw 'Kernel exit-code query failed or process remains active'};$result.kernelExitCode=[uint32]$exit.code;$result.kernelExitCodeRead=$true;$result.confirmedOwnedExit=$true;$result.kernelExitSignaled=$true;$result.status='already-signaled';$result.terminationReason='retained-kernel-handle-signaled';return $result}
  if($wait -ne 258){throw ('Kernel exit wait failed: '+$wait)}

  # HasExited is only a cached framework observation. Validate retained handle identity
  # before any termination, including when HasExited is already true.
  $wait=& $KernelWait $retainedHandle 0;$result.kernelWaitResult=$wait
  if(-not(Test-FactoryKernelWaitNumber $wait)){throw 'Non-numeric kernel wait result'}
  if($wait -eq 0){$exit=& $KernelExitCode $retainedHandle;if($null -eq $exit -or -not $exit.succeeded -or [uint32]$exit.code -eq 259){throw 'Kernel exit-code query failed or process remains active'};$result.kernelExitCode=[uint32]$exit.code;$result.kernelExitCodeRead=$true;$result.confirmedOwnedExit=$true;$result.kernelExitSignaled=$true;$result.status='signaled-before-kill';$result.terminationReason='retained-kernel-handle-signaled-after-identity';return $result}
  if($wait -ne 258){throw ('Kernel exit wait failed: '+$wait)}
  $result.killAttempted=$true
  if($result.hasExitedObserved){$result.terminationReason='phantom-framework-exited-retained-handle-termination'}else{$result.terminationReason='owned-retained-handle-termination'}
  $killResult=& $KernelTerminate $retainedHandle 1
  if($killResult -isnot [bool]){throw 'Non-boolean owned termination result'}
  if(-not $killResult){
   $wait=& $KernelWait $retainedHandle 0;$result.kernelWaitResult=$wait
   if($wait -ne 0){throw 'Owned handle termination failed'}
   $result.status='signaled-during-kill'
  }
  $wait=& $KernelWait $retainedHandle $WaitMilliseconds;$result.kernelWaitResult=$wait
  if(-not(Test-FactoryKernelWaitNumber $wait)){throw 'Non-numeric kernel wait result'}
  if($wait -ne 0){throw ('Owned cleanup kernel exit deadline/failure: '+$wait)}
  try{$Process.Refresh();$result.hasExitedObserved=[bool]$Process.HasExited}catch{$result.hasExitedObserved=$null}
  $exit=& $KernelExitCode $retainedHandle;if($null -eq $exit -or -not $exit.succeeded -or [uint32]$exit.code -eq 259){throw 'Kernel exit-code query failed or process remains active'};$result.kernelExitCode=[uint32]$exit.code;$result.kernelExitCodeRead=$true
  $result.confirmedOwnedExit=$true;$result.kernelExitSignaled=$true
  if($result.status -eq 'hold-cleanup'){
   if($result.hasExitedObserved -and $result.terminationReason -ceq 'phantom-framework-exited-retained-handle-termination'){$result.status='killed-owned-handle-after-phantom-exited'}else{$result.status='killed-owned-handle-signaled'}
  }
 }catch{$result.error=[string]$_}
 return $result
}

function Assert-FactoryCaptureOutcome($PrimaryError,$Cleanup,[object[]]$StreamErrors){
 if($null -ne $PrimaryError){throw $PrimaryError}
 if(-not(Test-FactoryKernelExitCertificate $Cleanup) -or @($StreamErrors).Count -ne 0){throw 'Owned cleanup/raw stream failure; inspect capture-outcome.json'}
}
function Invoke-FactoryConfirmedRelease([bool]$Acquired,[bool]$ExitConfirmed,[scriptblock]$Release){
 if(-not $Acquired -or -not $ExitConfirmed){return $false}
 return [bool](& $Release)
}
function Test-FactoryCaptureExitProof($Outcome,$Owned,[string]$Owner,[string]$CompileHash,[string]$ExeHash,[string]$StdoutHash,[string]$StderrHash,[string]$ExpectedPath){
 $stdoutStates=@($Outcome.rawStreams|Where-Object{$_.name -ceq 'stdout'});$stderrStates=@($Outcome.rawStreams|Where-Object{$_.name -ceq 'stderr'})
 if(@($Outcome.rawStreams).Count -ne 2 -or $stdoutStates.Count -ne 1 -or $stderrStates.Count -ne 1){return $false}
 if(-not(Test-FactoryRawDestinationClosed $stdoutStates[0]) -or -not(Test-FactoryRawDestinationClosed $stderrStates[0])){return $false}
 return [bool]((Test-FactoryKernelExitCertificate $Outcome.cleanup) -and $Owned.pid -gt 0 -and -not [string]::IsNullOrEmpty($Owned.startedAt) -and $Owned.path -ceq $ExpectedPath -and $Outcome.ownedIdentity.pid -eq $Owned.pid -and $Outcome.ownedIdentity.path -ceq $Owned.path -and $Outcome.ownedIdentity.startedAt -ceq $Owned.startedAt -and $Outcome.lockOwner -ceq $Owner -and $Outcome.compileReceiptHash -ceq $CompileHash -and $Outcome.exeHash -ceq $ExeHash -and $Outcome.stdoutSha256 -ceq $StdoutHash -and $Outcome.stderrSha256 -ceq $StderrHash -and $CompileHash -cmatch '^[0-9a-f]{64}$' -and $ExeHash -cmatch '^[0-9a-f]{64}$' -and $StdoutHash -cmatch '^[0-9a-f]{64}$' -and $StderrHash -cmatch '^[0-9a-f]{64}$')
}
