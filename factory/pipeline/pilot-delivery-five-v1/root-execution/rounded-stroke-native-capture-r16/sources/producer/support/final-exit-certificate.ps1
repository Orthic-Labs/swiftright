# Dot-sourcing is pure. Native functions initialize only on actual sampling.
function Test-FactoryFinalInteger($Value){
 return [bool]($Value -is [int] -or $Value -is [long] -or $Value -is [uint32] -or $Value -is [uint64])
}
function Test-FactoryFinalTrue($Value){return [bool](($Value -is [bool]) -and $Value)}
function Test-FactoryFinalHash($Value){return [bool](($Value -is [string]) -and $Value -cmatch '^[0-9a-f]{64}$')}
function Test-FactoryFinalStreams($Streams){
 $rows=@($Streams)
 if($rows.Count -ne 2){return $false}
 if(@($rows|Where-Object{$_.name -ceq 'stdout'}).Count -ne 1 -or @($rows|Where-Object{$_.name -ceq 'stderr'}).Count -ne 1){return $false}
 foreach($s in $rows){
  foreach($field in @('copyCompleted','destinationClosed','sealed','taskIsCompleted')){if(-not(Test-FactoryFinalTrue $s.$field)){return $false}}
  foreach($field in @('taskIsFaulted','taskIsCanceled')){if($s.$field -isnot [bool] -or $s.$field){return $false}}
  if($s.taskStatus -cne 'RanToCompletion' -or $s.closureTaskStatus -cne 'RanToCompletion' -or $s.hashQualification -cne 'sealed-raw'){return $false}
  foreach($field in @('flushCompleted','destinationClosed','completedWithinDeadline')){if(-not(Test-FactoryFinalTrue $s.closure.$field)){return $false}}
  if($s.closure.deadlineExpired -isnot [bool] -or $s.closure.deadlineExpired -or $s.closure.error -isnot [string] -or $s.closure.error -cne ''){return $false}
  if($s.path -isnot [string] -or -not $s.path -or -not(Test-FactoryFinalHash $s.sha256)){return $false}
 }
 return $true
}
function Test-FactoryFinalStart($Start){
 if(-not(Test-FactoryFinalInteger $Start.pid) -or $Start.pid -le 0 -or -not(Test-FactoryFinalInteger $Start.retainedHandle) -or $Start.retainedHandle -le 0){return $false}
 foreach($field in @('path','startedAt','lockOwner','workerId')){if($Start.$field -isnot [string] -or -not $Start.$field){return $false}}
 foreach($field in @('compileReceiptHash','exeHash')){if(-not(Test-FactoryFinalHash $Start.$field)){return $false}}
 return $true
}
# Start is immutable identity recorded immediately after Process.Start & Handle retention.
# It must never be rebuilt from Get-Process, Process.HasExited, or a later Handle getter.
function Test-FactoryFinalExitSample($Sample,$Start,$Streams){
 if(-not(Test-FactoryFinalStart $Start) -or -not(Test-FactoryFinalStreams $Streams)){return $false}
 if($Sample.phase -cne 'raw-closure-final' -or -not(Test-FactoryFinalInteger $Sample.waitMilliseconds) -or $Sample.waitMilliseconds -ne 0){return $false}
 foreach($field in @('retainedHandle','handlePid','kernelBefore','kernelAfter','exitCode')){if(-not(Test-FactoryFinalInteger $Sample.$field)){return $false}}
 if($Sample.retainedHandle -ne $Start.retainedHandle -or $Sample.handlePid -ne $Start.pid -or $Sample.kernelBefore -ne 0 -or $Sample.kernelAfter -ne 0 -or $Sample.exitCode -eq 259 -or $Sample.exitCode -lt 0 -or $Sample.exitCode -gt 4294967295){return $false}
 if(-not(Test-FactoryFinalTrue $Sample.getExitCodeSucceeded) -or $Sample.errors -isnot [Array] -or @($Sample.errors).Count -ne 0){return $false}
 return $true
}
function Initialize-FactoryFinalExitNative {
 if(-not ('FactoryFinalExitNativeV1' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FactoryFinalExitNativeV1 {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h,uint ms);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern uint GetProcessId(IntPtr h);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h,out uint code);
}
'@
 }
}
function Get-FactoryFinalExitSample([IntPtr]$OriginalRetainedHandle,$Start){
 if(-not ('FactoryFinalExitNativeV1' -as [type])){throw 'Initialize native declarations before Process.Start'}
 if(-not(Test-FactoryFinalStart $Start) -or $OriginalRetainedHandle.ToInt64() -ne $Start.retainedHandle){throw 'Original retained start identity required'}
 $sample=[ordered]@{phase='raw-closure-final';at=[DateTimeOffset]::UtcNow.ToString('o');waitMilliseconds=0;retainedHandle=$OriginalRetainedHandle.ToInt64();handlePid=$null;kernelBefore=$null;kernelAfter=$null;getExitCodeSucceeded=$false;exitCode=$null;errors=@()}
 try{
  $sample.kernelBefore=[FactoryFinalExitNativeV1]::WaitForSingleObject($OriginalRetainedHandle,0)
  $sample.handlePid=[FactoryFinalExitNativeV1]::GetProcessId($OriginalRetainedHandle)
  [uint32]$code=259
  $sample.getExitCodeSucceeded=[FactoryFinalExitNativeV1]::GetExitCodeProcess($OriginalRetainedHandle,[ref]$code)
  $sample.exitCode=$code
  $sample.kernelAfter=[FactoryFinalExitNativeV1]::WaitForSingleObject($OriginalRetainedHandle,0)
 }catch{$sample.errors+=([string]$_)}
 return $sample
}
# Pure constructor also used by controls. Actual callers use measured Sample only.
function New-FactoryFinalExitCertificate($Sample,$Start,$Streams){
 if(-not(Test-FactoryFinalExitSample $Sample $Start $Streams)){throw 'Final original-handle exit or sealed raw proof absent'}
 return [ordered]@{kind='factory-final-exit-certificate-v1';scope='owner-release-only';qualification='failed-or-successful-observation-only';start=$Start;sample=$Sample;rawStreams=@($Streams)}
}
function Get-FactoryFinalBytesHash([byte[]]$Bytes){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
# Reader(ref)->byte[]; context-scoped root supplies actual archived reads, not booleans.
# Expected carries original coordinator identity & hash-pinned terminal worker receipt.
function Test-FactoryFinalReleaseProof($Certificate,$Expected,[scriptblock]$Reader){
 try{
  if($null -eq $Reader -or $Certificate.kind -cne 'factory-final-exit-certificate-v1' -or $Certificate.scope -cne 'owner-release-only' -or $Certificate.qualification -cne 'failed-or-successful-observation-only'){return $false}
  if(-not(Test-FactoryFinalStart $Expected) -or -not(Test-FactoryFinalExitSample $Certificate.sample $Certificate.start $Certificate.rawStreams)){return $false}
  foreach($field in @('pid','retainedHandle','path','startedAt','lockOwner','workerId','compileReceiptHash','exeHash')){if($Certificate.start.$field -cne $Expected.$field){return $false}}
  if($Expected.workerReceiptRef -isnot [string] -or -not $Expected.workerReceiptRef -or -not(Test-FactoryFinalHash $Expected.workerReceiptHash)){return $false}
  $bytes=& $Reader $Expected.workerReceiptRef
  if($bytes -isnot [byte[]] -or (Get-FactoryFinalBytesHash $bytes) -cne $Expected.workerReceiptHash){return $false}
  $worker=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
  if($worker.kind -cne 'factory-terminal-worker-v1' -or -not(Test-FactoryFinalTrue $worker.terminalResultConfirmed)){return $false}
  foreach($field in @('pid','retainedHandle','path','startedAt','lockOwner','workerId','compileReceiptHash','exeHash')){if($worker.start.$field -cne $Expected.$field){return $false}}
  if(-not(Test-FactoryFinalStart $worker.start)){return $false}
  foreach($pair in @(@('compileReceiptRef','compileReceiptHash'),@('exeRef','exeHash'))){
   $ref=$Expected.($pair[0]);$hash=$Expected.($pair[1])
   if($ref -isnot [string] -or -not $ref){return $false}
   $bound=& $Reader $ref
   if($bound -isnot [byte[]] -or (Get-FactoryFinalBytesHash $bound) -cne $hash){return $false}
  }
  # Worker binds exact certificate bytes; coordinator binds recorded immutable compile/start context.
  if($worker.finalCertificateRef -isnot [string] -or -not $worker.finalCertificateRef -or -not(Test-FactoryFinalHash $worker.finalCertificateHash)){return $false}
  $certBytes=& $Reader $worker.finalCertificateRef
  if($certBytes -isnot [byte[]] -or (Get-FactoryFinalBytesHash $certBytes) -cne $worker.finalCertificateHash){return $false}
  $parsed=[Text.Encoding]::UTF8.GetString($certBytes)|ConvertFrom-Json
  if(($parsed|ConvertTo-Json -Depth 16 -Compress) -cne ($Certificate|ConvertTo-Json -Depth 16 -Compress)){return $false}
  foreach($s in $Certificate.rawStreams){
   $raw=& $Reader $s.path
   if($raw -isnot [byte[]] -or (Get-FactoryFinalBytesHash $raw) -cne $s.sha256){return $false}
  }
  return $true
 }catch{return $false}
}
# Release implementation remains coordinator's existing exact-owner CAS, not this helper.
# Original outcome & cleanup are neither arguments nor mutated; this cannot make capture pass.
function Invoke-FactoryFinalCertifiedRelease($Certificate,$Expected,[scriptblock]$Reader,[scriptblock]$Release){
 if(-not(Test-FactoryFinalReleaseProof $Certificate $Expected $Reader)){throw 'Final owner release proof absent'}
 & $Release $Expected.lockOwner
}
