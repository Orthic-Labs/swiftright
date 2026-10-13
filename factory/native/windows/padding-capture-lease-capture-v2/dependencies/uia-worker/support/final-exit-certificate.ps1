# Dot-sourcing is pure. Native functions initialize only on actual sampling.
function Test-FactoryUiaFinalInteger($Value){
 return [bool]($Value -is [int] -or $Value -is [long] -or $Value -is [uint32] -or $Value -is [uint64])
}
function Test-FactoryUiaFinalTrue($Value){return [bool](($Value -is [bool]) -and $Value)}
function Test-FactoryUiaFinalHash($Value){return [bool](($Value -is [string]) -and $Value -cmatch '^[0-9a-f]{64}$')}
function Test-FactoryUiaFinalStreams($Streams){
 $rows=@($Streams)
 if($rows.Count -ne 2){return $false}
 if(@($rows|Where-Object{$_.name -ceq 'stdout'}).Count -ne 1 -or @($rows|Where-Object{$_.name -ceq 'stderr'}).Count -ne 1){return $false}
 foreach($s in $rows){
  foreach($field in @('copyCompleted','destinationClosed','sealed','taskIsCompleted')){if(-not(Test-FactoryUiaFinalTrue $s.$field)){return $false}}
  foreach($field in @('taskIsFaulted','taskIsCanceled')){if($s.$field -isnot [bool] -or $s.$field){return $false}}
  if($s.taskException -isnot [string] -or $s.taskException -cne '' -or $s.closure.deadlineMilliseconds -ne 5000){return $false}
  if($s.taskStatus -cne 'RanToCompletion' -or $s.closureTaskStatus -cne 'RanToCompletion' -or $s.hashQualification -cne 'sealed-raw'){return $false}
  foreach($field in @('flushCompleted','destinationClosed','completedWithinDeadline')){if(-not(Test-FactoryUiaFinalTrue $s.closure.$field)){return $false}}
  if($s.closure.deadlineExpired -isnot [bool] -or $s.closure.deadlineExpired -or $s.closure.error -isnot [string] -or $s.closure.error -cne ''){return $false}
  if($s.path -isnot [string] -or -not $s.path -or -not(Test-FactoryUiaFinalHash $s.sha256)){return $false}
 }
 return $true
}
function Test-FactoryUiaFinalStart($Start){
 if(-not(Test-FactoryUiaFinalInteger $Start.pid) -or $Start.pid -le 0 -or -not(Test-FactoryUiaFinalInteger $Start.retainedHandle) -or $Start.retainedHandle -le 0){return $false}
 foreach($field in @('path','startedAt','lockOwner','workerId')){if($Start.$field -isnot [string] -or -not $Start.$field){return $false}}
 foreach($field in @('workerExeHash','sourceContractHash','configHash','workerScriptHash')){if(-not(Test-FactoryUiaFinalHash $Start.$field)){return $false}}
 return $true
}
# Start is immutable identity recorded immediately after Process.Start & Handle retention.
# It must never be rebuilt from Get-Process, Process.HasExited, or a later Handle getter.
function Test-FactoryUiaFinalExitSample($Sample,$Start,$Streams){
 if(-not(Test-FactoryUiaFinalStart $Start) -or -not(Test-FactoryUiaFinalStreams $Streams)){return $false}
 if($Sample.phase -cne 'raw-closure-final' -or -not(Test-FactoryUiaFinalInteger $Sample.waitMilliseconds) -or $Sample.waitMilliseconds -ne 0){return $false}
 foreach($field in @('retainedHandle','handlePid','kernelBefore','kernelAfter','exitCode')){if(-not(Test-FactoryUiaFinalInteger $Sample.$field)){return $false}}
 if($Sample.retainedHandle -ne $Start.retainedHandle -or $Sample.handlePid -ne $Start.pid -or $Sample.kernelBefore -ne 0 -or $Sample.kernelAfter -ne 0 -or $Sample.exitCode -eq 259 -or $Sample.exitCode -lt 0 -or $Sample.exitCode -gt 4294967295){return $false}
 if(-not(Test-FactoryUiaFinalTrue $Sample.getExitCodeSucceeded) -or $Sample.errors -isnot [Array] -or @($Sample.errors).Count -ne 0){return $false}
 return $true
}
function Initialize-FactoryUiaFinalExitNative {
 if(-not ('FactoryUiaFinalExitNativeV1' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FactoryUiaFinalExitNativeV1 {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h,uint ms);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern uint GetProcessId(IntPtr h);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h,out uint code);
}
'@
 }
}
function Get-FactoryUiaFinalExitSample([IntPtr]$OriginalRetainedHandle,$Start){
 if(-not ('FactoryUiaFinalExitNativeV1' -as [type])){throw 'Initialize native declarations before Process.Start'}
 if(-not(Test-FactoryUiaFinalStart $Start) -or $OriginalRetainedHandle.ToInt64() -ne $Start.retainedHandle){throw 'Original retained start identity required'}
 $sample=[ordered]@{phase='raw-closure-final';at=[DateTimeOffset]::UtcNow.ToString('o');waitMilliseconds=0;retainedHandle=$OriginalRetainedHandle.ToInt64();handlePid=$null;kernelBefore=$null;kernelAfter=$null;getExitCodeSucceeded=$false;exitCode=$null;errors=@()}
 try{
  $sample.kernelBefore=[FactoryUiaFinalExitNativeV1]::WaitForSingleObject($OriginalRetainedHandle,0)
  $sample.handlePid=[FactoryUiaFinalExitNativeV1]::GetProcessId($OriginalRetainedHandle)
  [uint32]$code=259
  $sample.getExitCodeSucceeded=[FactoryUiaFinalExitNativeV1]::GetExitCodeProcess($OriginalRetainedHandle,[ref]$code)
  $sample.exitCode=$code
  $sample.kernelAfter=[FactoryUiaFinalExitNativeV1]::WaitForSingleObject($OriginalRetainedHandle,0)
 }catch{$sample.errors+=([string]$_)}
 return $sample
}
# Pure constructor also used by controls. Actual callers use measured Sample only.
function New-FactoryUiaFinalExitCertificate($Sample,$Start,$Streams){
 if(-not(Test-FactoryUiaFinalExitSample $Sample $Start $Streams)){throw 'Final original-handle exit or sealed raw proof absent'}
 return [ordered]@{kind='factory-uia-final-exit-certificate-v1';scope='owner-release-only';qualification='failed-or-successful-snapshot-only';start=$Start;sample=$Sample;rawStreams=@($Streams)}
}
function Get-FactoryUiaFinalBytesHash([byte[]]$Bytes){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
# Reader(ref)->byte[]; context-scoped root supplies actual archived reads, not booleans.
# Expected carries original coordinator identity & hash-pinned terminal worker receipt.
function Test-FactoryUiaFinalReleaseProof($Certificate,$Expected,[scriptblock]$Reader){
 try{
  if($null -eq $Reader -or $Certificate.kind -cne 'factory-uia-final-exit-certificate-v1' -or $Certificate.scope -cne 'owner-release-only' -or $Certificate.qualification -cne 'failed-or-successful-snapshot-only'){return $false}
  if(-not(Test-FactoryUiaFinalStart $Expected) -or -not(Test-FactoryUiaFinalExitSample $Certificate.sample $Certificate.start $Certificate.rawStreams)){return $false}
  foreach($field in @('pid','retainedHandle','path','startedAt','lockOwner','workerId','workerExeHash','sourceContractHash','configHash','workerScriptHash')){if($Certificate.start.$field -cne $Expected.$field){return $false}}
  if($Expected.workerReceiptRef -isnot [string] -or -not $Expected.workerReceiptRef -or -not(Test-FactoryUiaFinalHash $Expected.workerReceiptHash)){return $false}
  $bytes=& $Reader $Expected.workerReceiptRef
  if($bytes -isnot [byte[]] -or (Get-FactoryUiaFinalBytesHash $bytes) -cne $Expected.workerReceiptHash){return $false}
  $worker=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
  if($worker.kind -cne 'factory-uia-terminal-worker-v1' -or -not(Test-FactoryUiaFinalTrue $worker.terminalResultConfirmed)){return $false}
  foreach($field in @('pid','retainedHandle','path','startedAt','lockOwner','workerId','workerExeHash','sourceContractHash','configHash','workerScriptHash')){if($worker.start.$field -cne $Expected.$field){return $false}}
  if(-not(Test-FactoryUiaFinalStart $worker.start)){return $false}
  foreach($pair in @(@('workerExeRef','workerExeHash'),@('sourceContractRef','sourceContractHash'),@('configRef','configHash'),@('workerScriptRef','workerScriptHash'))){
   $ref=$Expected.($pair[0]);$hash=$Expected.($pair[1])
   if($ref -isnot [string] -or -not $ref){return $false}
   $bound=& $Reader $ref
   if($bound -isnot [byte[]] -or (Get-FactoryUiaFinalBytesHash $bound) -cne $hash){return $false}
  }
  # Explicit coordinator source refs, never derived from receipt path strings.
  if($Expected.sourceBindings -isnot [Array] -or @($Expected.sourceBindings).Count -eq 0){return $false}
  foreach($binding in $Expected.sourceBindings){
   if($binding.ref -isnot [string] -or -not $binding.ref -or -not(Test-FactoryUiaFinalHash $binding.sha256)){return $false}
   $source=& $Reader $binding.ref
   if($source -isnot [byte[]] -or (Get-FactoryUiaFinalBytesHash $source) -cne $binding.sha256){return $false}
  }
  $contractBytes=& $Reader $Expected.sourceContractRef
  $contract=[Text.Encoding]::UTF8.GetString($contractBytes)|ConvertFrom-Json
  if(@($contract.sourceBindings).Count -ne @($Expected.sourceBindings).Count){return $false}
  foreach($b in $contract.sourceBindings){$matches=@($Expected.sourceBindings|Where-Object{$_.path -ceq $b.path -and $_.sha256 -ceq $b.sha256});if($matches.Count -ne 1){return $false}}
  $configBytes=& $Reader $Expected.configRef
  $config=[Text.Encoding]::UTF8.GetString($configBytes)|ConvertFrom-Json
  if(($config.sourceBindings|ConvertTo-Json -Depth 12 -Compress) -cne ($contract.sourceBindings|ConvertTo-Json -Depth 12 -Compress)){return $false}
  if($config.kind -cne 'factory-uia-snapshot-worker-config-v1' -or $config.outputRoot -cne $Expected.workerId -or $config.target.lockOwner -cne $Expected.lockOwner){return $false}
  if($worker.originalOutcomeRef -isnot [string] -or -not $worker.originalOutcomeRef -or -not(Test-FactoryUiaFinalHash $worker.originalOutcomeHash)){return $false}
  $outcomeBytes=& $Reader $worker.originalOutcomeRef
  if($outcomeBytes -isnot [byte[]] -or (Get-FactoryUiaFinalBytesHash $outcomeBytes) -cne $worker.originalOutcomeHash){return $false}
  $outcome=[Text.Encoding]::UTF8.GetString($outcomeBytes)|ConvertFrom-Json
  if($outcome.kind -cne 'factory-uia-snapshot-worker-exit-v1'){return $false}
  foreach($field in @('pid','path','startedAt','retainedHandle')){if($outcome.ownedIdentity.$field -cne $Expected.$field){return $false}}
  if($outcome.workerExeSha256 -cne $Expected.workerExeHash -or $outcome.sourceContractSha256 -cne $Expected.sourceContractHash -or $outcome.configSha256 -cne $Expected.configHash -or $outcome.target.lockOwner -cne $Expected.lockOwner){return $false}
  # Worker binds exact certificate bytes; coordinator binds recorded immutable compile/start context.
  if($worker.finalCertificateRef -isnot [string] -or -not $worker.finalCertificateRef -or -not(Test-FactoryUiaFinalHash $worker.finalCertificateHash)){return $false}
  $certBytes=& $Reader $worker.finalCertificateRef
  if($certBytes -isnot [byte[]] -or (Get-FactoryUiaFinalBytesHash $certBytes) -cne $worker.finalCertificateHash){return $false}
  $parsed=[Text.Encoding]::UTF8.GetString($certBytes)|ConvertFrom-Json
  if(($parsed|ConvertTo-Json -Depth 16 -Compress) -cne ($Certificate|ConvertTo-Json -Depth 16 -Compress)){return $false}
  foreach($s in $Certificate.rawStreams){
   $raw=& $Reader $s.path
   if($raw -isnot [byte[]] -or (Get-FactoryUiaFinalBytesHash $raw) -cne $s.sha256){return $false}
  }
  return $true
 }catch{return $false}
}
# Release implementation remains coordinator's existing exact-owner CAS, not this helper.
# Original failed snapshot outcome is hash-bound, never changed into successful capture.
function Invoke-FactoryUiaFinalCertifiedRelease($Certificate,$Expected,[scriptblock]$Reader,[scriptblock]$Release){
 if(-not(Test-FactoryUiaFinalReleaseProof $Certificate $Expected $Reader)){throw 'Final owner release proof absent'}
 & $Release $Expected.lockOwner
}
# Coordinator supplies complete predeclared owned-worker slots; absence is failure.
# This checks worker scope only; coordinator additionally verifies EVERY renderer certificate.
function Test-FactoryAllUiaWorkerReleaseProofs($ExpectedWorkerRoots,$OwnedWorkers,[scriptblock]$Reader){
 try{
  if($ExpectedWorkerRoots -isnot [Array] -or $OwnedWorkers -isnot [Array] -or @($ExpectedWorkerRoots).Count -ne @($OwnedWorkers).Count){return $false}
  if(@($ExpectedWorkerRoots|Select-Object -Unique).Count -ne @($ExpectedWorkerRoots).Count){return $false}
  foreach($root in $ExpectedWorkerRoots){
   if($root -isnot [string] -or -not $root){return $false}
   $matches=@($OwnedWorkers|Where-Object{$_.expected.workerId -ceq $root})
   if($matches.Count -ne 1 -or -not(Test-FactoryUiaFinalReleaseProof $matches[0].certificate $matches[0].expected $Reader)){return $false}
  }
  return $true
 }catch{return $false}
}
