# Source-only controls; root may execute after staging. No native/window actions here.
param([Parameter(Mandatory=$true)][string]$WorkerPath,[Parameter(Mandatory=$true)][string]$InvokerPath,[string]$SchemaPath=(Join-Path $PSScriptRoot 'schema.ps1'))
$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)){throw 'Explicit producer schema.ps1 required; overlay default is not admitted'}
$worker=Get-Content -Raw -LiteralPath $WorkerPath;$invoker=Get-Content -Raw -LiteralPath $InvokerPath;$schema=Get-Content -Raw -LiteralPath $SchemaPath
foreach($marker in @('Invoke-UiaFromHandleBounded','CurrentThread.GetApartmentState','FromHandle($Hwnd)','requires dedicated MTA worker','before-from-handle-mta','after-from-handle-mta','workerApartment=$c.apartment',"deadline='parent-15s'")){if($worker -notmatch [regex]::Escape($marker)){throw ('MTA worker marker missing: '+$marker)}}
foreach($marker in @("workerApartment='MTA'",'-MTA','parentApartment=$apartment','worker-contract.json','worker-exit-v2')){if($invoker -notmatch [regex]::Escape($marker)){throw ('MTA invoker marker missing: '+$marker)}}
if($worker -match 'Task\[object\]|Task\.Run|Start-NewThread'){throw 'MTA worker must use dedicated process thread'}
if($invoker -match '-\$apartment|workerApartment=\$apartment'){throw 'Invoker must request fixed MTA worker'}
if($invoker -match 'AddSeconds\((?:1[6-9]|[2-9][0-9])\)'){throw 'worker deadline expanded'}
if($worker -match 'TimeoutMilliseconds|timeoutMilliseconds'){throw 'worker claims independent timeout'}
foreach($marker in @('factory-uia-snapshot-worker-exit-v2','parentApartment -cnotin @(''STA'',''MTA'')','workerApartment -cne ''MTA''','worker natural kernel0 exit required')){if($schema -notmatch [regex]::Escape($marker)){throw ('v2 schema marker missing: '+$marker)}}
$schemaRoot=Split-Path -Parent $SchemaPath
$schemaSupport=Join-Path $schemaRoot 'support'
foreach($support in @((Join-Path $schemaSupport 'cleanup.ps1'),(Join-Path $schemaSupport 'stream-seal.ps1'))){if(-not (Test-Path -LiteralPath $support -PathType Leaf)){throw ('Producer schema support missing: '+$support)};. $support}
. $SchemaPath
$hash='a'*64
$target=[pscustomobject]@{pid=101;hwnd=202;path='D:\owned\FactoryProbe.exe';startedAt='2026-10-12T00:00:00.0000000Z';lockOwner='mta-controls'}
$stream=[pscustomobject]@{name='stdout';copyCompleted=$true;destinationClosed=$true;sealed=$true;hashQualification='sealed-raw';taskStatus='RanToCompletion';taskIsCompleted=$true;taskIsFaulted=$false;taskIsCanceled=$false;taskException='';closureTaskStatus='RanToCompletion';closure=[pscustomobject]@{destinationClosed=$true;completedWithinDeadline=$true;flushCompleted=$true;deadlineExpired=$false;error=''}}
$streamErr=$stream|ConvertTo-Json -Depth 20|ConvertFrom-Json;$streamErr.name='stderr'
$proof=[pscustomobject]@{kind='factory-uia-snapshot-worker-exit-v2';status='completed-natural-uiasnapshot';target=$target;ownedIdentity=[pscustomobject]@{pid=303;path='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';startedAt=$target.startedAt;retainedHandle=404};primaryError='';parentApartment='STA';workerApartment='MTA';configSha256=$hash;sourceContractSha256=$hash;workerExeSha256=$hash;exitCode=0;timedOut=$false;preCleanupKernelWaitResult=0;cleanup=[pscustomobject]@{confirmedOwnedExit=$true;kernelExitSignaled=$true;kernelWaitResult=0;exitCertification='retained-kernel-handle';status='already-signaled';killAttempted=$false;error=''};streamErrors=@();rawStreams=@($stream,$streamErr);stdoutSha256=$hash;stderrSha256=$hash;uiaSha256=$hash}
function Copy-MtaFixture($Value){$Value|ConvertTo-Json -Depth 40|ConvertFrom-Json}
try { Assert-UiaSnapshotWorkerProof $proof $target $hash $hash $hash } catch { throw ('Production schema positive fixture rejected: '+[string]$_) }
$schemaFaults=@('missing-parent-apartment','wrong-worker-apartment','legacy-proof-kind')
foreach($fault in $schemaFaults){
 $copy=Copy-MtaFixture $proof
 switch($fault){
  'missing-parent-apartment' {$copy.parentApartment=$null}
  'wrong-worker-apartment' {$copy.workerApartment='STA'}
  'legacy-proof-kind' {$copy.kind='factory-uia-snapshot-worker-exit-v1'}
 }
 $rejected=$false;try { Assert-UiaSnapshotWorkerProof $copy $target $hash $hash $hash } catch {$rejected=$true}
 if(-not $rejected){throw ('Production schema accepted fault: '+$fault)}
}
[ordered]@{kind='factory-uia-fromhandle-mta-controls-v5';status='SOURCE_CONTROLS_PASS';workerApartment='MTA';parentApartment='observed-STA-or-MTA';parentWorkerDeadlineSeconds=15;schemaPositive='production Assert-UiaSnapshotWorkerProof accepted exact v2 fixture';schemaFaultsRejected=$schemaFaults;nativeActions=0;compilerActions=0}|ConvertTo-Json -Depth 6
