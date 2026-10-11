$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'final-exit-certificate.ps1')
# Synthetic only: no process/window/native/lock operations. No native Add-Type reached.
function New-ControlFixture {
 $start=[ordered]@{pid=123;retainedHandle=456;path='synthetic/FactoryProbe.exe';startedAt='2026-10-11T00:00:00.0000000Z';lockOwner='synthetic-owner';workerId='synthetic-worker';compileReceiptHash='';exeHash=''}
 $map=@{'compile'=([Text.Encoding]::UTF8.GetBytes('synthetic compile'));'exe'=([Text.Encoding]::UTF8.GetBytes('synthetic exe'));'stdout'=([Text.Encoding]::UTF8.GetBytes('synthetic stdout'));'stderr'=([byte[]]@())}
 $start.compileReceiptHash=Get-FactoryFinalBytesHash $map.compile;$start.exeHash=Get-FactoryFinalBytesHash $map.exe
 $rows=@()
 foreach($name in @('stdout','stderr')){
  $rows+=([ordered]@{name=$name;path=$name;sha256=(Get-FactoryFinalBytesHash $map[$name]);copyCompleted=$true;destinationClosed=$true;sealed=$true;hashQualification='sealed-raw';taskStatus='RanToCompletion';taskIsCompleted=$true;taskIsFaulted=$false;taskIsCanceled=$false;closureTaskStatus='RanToCompletion';closure=[ordered]@{flushCompleted=$true;destinationClosed=$true;completedWithinDeadline=$true;deadlineExpired=$false;error=''}})
 }
 $sample=[ordered]@{phase='raw-closure-final';waitMilliseconds=0;retainedHandle=456;handlePid=123;kernelBefore=0;kernelAfter=0;getExitCodeSucceeded=$true;exitCode=0;errors=@()}
 $certificate=New-FactoryFinalExitCertificate $sample $start $rows
 $expected=($start|ConvertTo-Json|ConvertFrom-Json)
 $expected|Add-Member compileReceiptRef 'compile';$expected|Add-Member exeRef 'exe'
 $certBytes=[Text.Encoding]::UTF8.GetBytes(($certificate|ConvertTo-Json -Depth 16 -Compress));$map.certificate=$certBytes
 $worker=[ordered]@{kind='factory-terminal-worker-v1';synthetic=$true;terminalResultConfirmed=$true;start=$start;finalCertificateRef='certificate';finalCertificateHash=(Get-FactoryFinalBytesHash $certBytes)}
 $map.worker=[Text.Encoding]::UTF8.GetBytes(($worker|ConvertTo-Json -Depth 16 -Compress))
 $expected|Add-Member workerReceiptRef 'worker';$expected|Add-Member workerReceiptHash (Get-FactoryFinalBytesHash $map.worker)
 return @{certificate=$certificate;expected=$expected;map=$map;reader={param($ref) if(-not $map.ContainsKey($ref)){throw 'Unknown fixture ref'};return ,$map[$ref]}.GetNewClosure()}
}
function Rebind-ControlFixture($f){
 # Coherent rehash prevents tests passing only because stale outer hashes reject.
 $f.map.certificate=[Text.Encoding]::UTF8.GetBytes(($f.certificate|ConvertTo-Json -Depth 16 -Compress))
 $worker=[Text.Encoding]::UTF8.GetString($f.map.worker)|ConvertFrom-Json
 $worker.finalCertificateHash=Get-FactoryFinalBytesHash $f.map.certificate
 $f.map.worker=[Text.Encoding]::UTF8.GetBytes(($worker|ConvertTo-Json -Depth 16 -Compress))
 $f.expected.workerReceiptHash=Get-FactoryFinalBytesHash $f.map.worker
}
$results=@()
function Assert-Control($name,[scriptblock]$mutate,$wanted){
 $f=New-ControlFixture
 if($null -ne $mutate){& $mutate $f;Rebind-ControlFixture $f}
 $actual=Test-FactoryFinalReleaseProof $f.certificate $f.expected $f.reader
 if($actual -ne $wanted){throw ('Control failed: '+$name)}
 $script:results+=@{name=$name;expected=$wanted;actual=$actual;synthetic=$true}
}
Assert-Control 'same-original-handle-zero' $null $true
Assert-Control 'qualification-drift' {param($f) $f.certificate.qualification='qualified-native'} $false
Assert-Control 'missing-kernel' {param($f) $f.certificate.sample.kernelBefore=$null} $false
Assert-Control 'HasExited-only' {param($f) $f.certificate.sample.kernelBefore=258;$f.certificate.sample.kernelAfter=258;$f.certificate.sample.hasExited=$true} $false
Assert-Control 'wrong-handle-pid' {param($f) $f.certificate.sample.handlePid=124} $false
Assert-Control 'new-handle' {param($f) $f.certificate.sample.retainedHandle=457} $false
Assert-Control 'raw-open' {param($f) $f.certificate.rawStreams[0].destinationClosed=$false} $false
Assert-Control 'foreign-owner' {param($f) $f.certificate.start.lockOwner='foreign'} $false
Assert-Control 'one-stream' {param($f) $f.certificate.rawStreams=@($f.certificate.rawStreams[0])} $false
Assert-Control 'duplicate-stream' {param($f) $f.certificate.rawStreams[1].name='stdout'} $false
Assert-Control 'typed-true' {param($f) $f.certificate.rawStreams[0].sealed='true'} $false
Assert-Control 'bool-wait' {param($f) $f.certificate.sample.kernelBefore=$false} $false
Assert-Control 'still-active' {param($f) $f.certificate.sample.exitCode=259} $false
Assert-Control 'exit-query-failed' {param($f) $f.certificate.sample.getExitCodeSucceeded=$false} $false
Assert-Control 'raw-byte-drift' {param($f) $f.map.stdout=[Text.Encoding]::UTF8.GetBytes('changed')} $false
Assert-Control 'compile-byte-drift' {param($f) $f.map.compile=[Text.Encoding]::UTF8.GetBytes('changed')} $false
Assert-Control 'exe-byte-drift' {param($f) $f.map.exe=[Text.Encoding]::UTF8.GetBytes('changed')} $false
Assert-Control 'terminal-worker-false' {param($f) $w=[Text.Encoding]::UTF8.GetString($f.map.worker)|ConvertFrom-Json;$w.terminalResultConfirmed=$false;$f.map.worker=[Text.Encoding]::UTF8.GetBytes(($w|ConvertTo-Json -Depth 16 -Compress))} $false
Assert-Control 'missing-ref' {param($f) $f.expected.workerReceiptRef='missing'} $false
# Original deadline & cleanup remain failed even when separate final release proof succeeds.
$f=New-ControlFixture
$outcome=[ordered]@{primaryError='Owned renderer child deadline';cleanup=[ordered]@{confirmedOwnedExit=$false;kernelWaitResult=258};qualification='hold';nativeParity='hold'}
$before=$outcome|ConvertTo-Json -Depth 8 -Compress
$released=[Collections.Generic.List[string]]::new()
Invoke-FactoryFinalCertifiedRelease $f.certificate $f.expected $f.reader {param($owner) $released.Add($owner)}
if($released.Count -ne 1 -or $released[0] -cne 'synthetic-owner' -or ($outcome|ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'Failure outcome changed or exact owner not released'}
$results+=@{name='deadline-preserved-release';expected=$true;actual=$true;synthetic=$true}
# Failed proof never invokes callback.
$f=New-ControlFixture;$f.certificate.sample.kernelAfter=258;Rebind-ControlFixture $f
try{Invoke-FactoryFinalCertifiedRelease $f.certificate $f.expected $f.reader {throw 'CALLBACK_REACHED'};throw 'Bad proof accepted'}catch{if([string]$_ -match 'CALLBACK_REACHED|Bad proof accepted'){throw}}
$results+=@{name='failed-proof-no-release';expected=$true;actual=$true;synthetic=$true}
@{kind='factory-final-exit-certificate-pure-controls-v1';synthetic=$true;nativeLaunches=0;lockWrites=0;controls=$results}|ConvertTo-Json -Depth 12
