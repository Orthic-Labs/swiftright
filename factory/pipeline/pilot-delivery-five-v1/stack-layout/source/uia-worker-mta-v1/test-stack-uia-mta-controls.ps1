# Pure source controls. No process, UIA, native window, compiler, or lock action.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
$sourceRoot=$PSScriptRoot
. (Join-Path $sourceRoot '..\..\helpers\cleanup-v3.ps1')
. (Join-Path $sourceRoot '..\..\helpers\stream-seal.ps1')
. (Join-Path $sourceRoot 'schema.ps1')
. (Join-Path $sourceRoot 'support\final-exit-certificate.ps1')
$contract=Get-Content -Raw (Join-Path $sourceRoot 'worker-contract.json')|ConvertFrom-Json
if($contract.releaseABI -cne 'FactoryProcessWaitV6' -or $contract.workerApartment -cne 'MTA' -or $contract.workerDeadlineSeconds -ne 15 -or $contract.streamDeadlineSeconds -ne 5 -or $contract.destinationClosureSeconds -ne 5){throw 'Stack worker contract timing/release drift'}
foreach($marker in @('Invoke-UiaFromHandleBounded','FromHandle($Hwnd)','requires dedicated MTA worker','before-from-handle-mta','after-from-handle-mta')){if((Get-Content -Raw (Join-Path $sourceRoot 'worker.ps1')) -notmatch [regex]::Escape($marker)){throw ('MTA worker marker missing: '+$marker)}}
foreach($marker in @('workerApartment=''MTA''','-MTA','FactoryProcessWaitV6','rootRSSSupervisor')){if((Get-Content -Raw (Join-Path $sourceRoot 'invoke-stack-uia-worker.ps1')) -notmatch [regex]::Escape($marker)){throw ('MTA invoker marker missing: '+$marker)}}
foreach($binding in $contract.sourceBindings){$path=Join-Path $sourceRoot $binding.path;if((Get-FileHash $path).Hash.ToLowerInvariant() -cne $binding.sha256 -or (Get-Item $path).Length -ne $binding.bytes){throw ('MTA contract source drift: '+$binding.path)}}
$h='a'*64
$target=[pscustomobject]@{pid=101;hwnd=202;path='D:\owned\FactoryProbe.exe';startedAt='2026-10-12T00:00:00.0000000Z';lockOwner='stack-mta-controls'}
$stream=[pscustomobject]@{name='stdout';copyCompleted=$true;destinationClosed=$true;sealed=$true;hashQualification='sealed-raw';taskStatus='RanToCompletion';taskIsCompleted=$true;taskIsFaulted=$false;taskIsCanceled=$false;taskException='';closureTaskStatus='RanToCompletion';closure=[pscustomobject]@{destinationClosed=$true;completedWithinDeadline=$true;flushCompleted=$true;deadlineExpired=$false;error=''}}
$stderr=$stream|ConvertTo-Json -Depth 12|ConvertFrom-Json;$stderr.name='stderr'
$proof=[pscustomobject]@{kind='factory-uia-snapshot-worker-exit-v2';status='completed-natural-uiasnapshot';target=$target;ownedIdentity=[pscustomobject]@{pid=303;path='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';startedAt=$target.startedAt;retainedHandle=404};primaryError='';parentApartment='STA';workerApartment='MTA';configSha256=$h;sourceContractSha256=$h;workerExeSha256=$h;exitCode=0;timedOut=$false;preCleanupKernelWaitResult=0;cleanup=[pscustomobject]@{confirmedOwnedExit=$true;kernelExitSignaled=$true;kernelWaitResult=0;exitCertification='retained-kernel-handle';status='already-signaled';killAttempted=$false;error=''};streamErrors=@();rawStreams=@($stream,$stderr);stdoutSha256=$h;stderrSha256=$h;uiaSha256=$h}
Assert-UiaSnapshotWorkerProof $proof $target $h $h $h
function Copy-Fixture($x){$x|ConvertTo-Json -Depth 40|ConvertFrom-Json}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};if(-not $rejected){throw ('Fault accepted: '+$Name)};return $Name}
$faults=@()
$bad=Copy-Fixture $proof;$bad.ownedIdentity.retainedHandle=0;$faults+=Reject 'handle-identity' {Assert-UiaSnapshotWorkerProof $bad $target $h $h $h}
$bad=Copy-Fixture $proof;$bad.preCleanupKernelWaitResult=258;$faults+=Reject 'false-kernel-exit' {Assert-UiaSnapshotWorkerProof $bad $target $h $h $h}
$bad=Copy-Fixture $proof;$bad.cleanup.kernelWaitResult=258;$faults+=Reject 'false-cleanup-kernel-exit' {Assert-UiaSnapshotWorkerProof $bad $target $h $h $h}
$config=[pscustomobject]@{kind='factory-uia-snapshot-worker-config-v2';outputRoot='D:\worker';target=$target;apartment='MTA';parentApartment='STA'}
$expected=[pscustomobject]@{workerId='D:\worker';lockOwner=$target.lockOwner}
if(-not (Test-FactoryUiaWorkerConfigAdmission $config $expected)){throw 'Positive worker config rejected'}
$badConfig=Copy-Fixture $config;$badConfig.apartment='STA';if(Test-FactoryUiaWorkerConfigAdmission $badConfig $expected){throw 'Wrong config apartment accepted'};$faults+='wrong-config'
$row=$contract.sourceBindings[0];$bytes=[IO.File]::ReadAllBytes((Join-Path $sourceRoot $row.path));$mutated=[byte[]]$bytes.Clone();$mutated[0]=[byte](($mutated[0]+1)%256);if((Get-FactoryUiaFinalBytesHash $mutated) -eq $row.sha256){throw 'Source-contract mutation fixture unexpectedly matched'};$faults+='source-contract'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh controls output required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
[ordered]@{kind='factory-stack-uia-mta-pure-controls-v1';status='SOURCE_CONTROLS_PASS';nativeActions=0;compilerActions=0;faultsRejected=$faults;workerApartment='MTA';releaseABI='FactoryProcessWaitV6';acquisitionSeconds=15;streamDrainSeconds=5;destinationClosureSeconds=5}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'pure-controls.json')
