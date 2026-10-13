param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'support\cleanup.ps1')
. (Join-Path $PSScriptRoot 'support\stream-seal.ps1')
. (Join-Path $PSScriptRoot 'schema.ps1')
$results=@()
function Copy-Fixture($x){$x|ConvertTo-Json -Depth 80|ConvertFrom-Json}
function Pass([string]$Name,[scriptblock]$Run){& $Run|Out-Null;$script:results+=@([ordered]@{name=$Name;passed=$true})}
function Reject([string]$Name,[scriptblock]$Run){$rejected=$false;try{& $Run|Out-Null}catch{$rejected=$true};if(-not $rejected){throw ('Fault accepted: '+$Name)};$script:results+=@([ordered]@{name=$Name;passed=$true})}
$target=[pscustomobject]@{pid=101;hwnd=202;path='D:\owned\probe.exe';startedAt='2026-10-11T00:00:00.0000000Z';lockOwner='owned-case'}
$observed=[pscustomobject]@{pid=101;hwnd=202;windowPid=101;path=$target.path;startedAt=$target.startedAt;hasExited=$false;foregroundPid=303;foregroundHwnd=404;workerPid=505;lockOwner=$target.lockOwner}
Pass 'target-valid' {Assert-UiaSnapshotTargetObject $target $observed}
foreach($field in @('pid','hwnd','windowPid','path','startedAt','lockOwner')){ $copy=Copy-Fixture $observed;if($copy.$field -is [string]){$copy.$field='foreign'}else{$copy.$field=999};Reject ('target-'+$field) {Assert-UiaSnapshotTargetObject $target $copy} }
$copy=Copy-Fixture $observed;$copy.hwnd='202';Reject 'stale-hwnd-numeric-string' {Assert-UiaSnapshotTargetObject $target $copy}
$copy=Copy-Fixture $observed;$copy.hasExited=$true;Reject 'exited-target' {Assert-UiaSnapshotTargetObject $target $copy}
foreach($fg in @(101,505)){$copy=Copy-Fixture $observed;$copy.foregroundPid=$fg;Reject ('foreground-'+$fg) {Assert-UiaSnapshotTargetObject $target $copy}}
$node=[pscustomobject]@{name='owned';automationId='id';controlType='ControlType.Window';enabled=$true;patterns=@('Pattern.Invoke');offscreen=$false;bounds=@(0,0,320.0,240.0);children=@()}
Pass 'scalar-schema-valid' {Assert-UiaSnapshotScalarObject $node}
$copy=Copy-Fixture $node;$copy|Add-Member liveObject ([pscustomobject]@{});Reject 'schema-extra-live-property' {Assert-UiaSnapshotScalarObject $copy}
$copy=Copy-Fixture $node;$copy.enabled='true';Reject 'schema-boolean-string' {Assert-UiaSnapshotScalarObject $copy}
$copy=Copy-Fixture $node;$copy.name=[pscustomobject]@{Current='live'};Reject 'schema-live-name' {Assert-UiaSnapshotScalarObject $copy}
$copy=Copy-Fixture $node;$copy.patterns=@([pscustomobject]@{});Reject 'schema-live-pattern' {Assert-UiaSnapshotScalarObject $copy}
$copy=Copy-Fixture $node;$copy.bounds[0]=[double]::NaN;Reject 'schema-nan-bound' {Assert-UiaSnapshotScalarObject $copy}
$copy=Copy-Fixture $node;$copy.bounds=@(0,0,1);Reject 'schema-short-bounds' {Assert-UiaSnapshotScalarObject $copy}
$copy=Copy-Fixture $node;$copy.children=@(1..1001|ForEach-Object{$node});Reject 'schema-child-bound' {Assert-UiaSnapshotScalarObject $copy}
Reject 'schema-depth-bound' {Assert-UiaSnapshotScalarObject $node 41}
$h='a'*64
$stream=[pscustomobject]@{name='stdout';copyCompleted=$true;destinationClosed=$true;sealed=$true;hashQualification='sealed-raw';taskStatus='RanToCompletion';taskIsCompleted=$true;taskIsFaulted=$false;taskIsCanceled=$false;taskException='';closureTaskStatus='RanToCompletion';closure=[pscustomobject]@{destinationClosed=$true;completedWithinDeadline=$true;flushCompleted=$true;deadlineExpired=$false;error=''}}
$stderr=Copy-Fixture $stream;$stderr.name='stderr'
$proof=[pscustomobject]@{kind='factory-uia-snapshot-worker-exit-v1';status='completed-natural-uiasnapshot';target=$target;ownedIdentity=[pscustomobject]@{pid=505;path='D:\Windows\powershell.exe';startedAt=$target.startedAt;retainedHandle=808};primaryError='';apartment='STA';workerExeSha256=$h;sourceContractSha256=$h;configSha256=$h;exitCode=0;timedOut=$false;preCleanupKernelWaitResult=0;cleanup=[pscustomobject]@{confirmedOwnedExit=$true;kernelExitSignaled=$true;kernelWaitResult=0;exitCertification='retained-kernel-handle';status='already-signaled';killAttempted=$false;error=''};streamErrors=@();rawStreams=@($stream,$stderr);stdoutSha256=$h;stderrSha256=$h;uiaSha256=$h}
Pass 'worker-natural-proof-valid' {Assert-UiaSnapshotWorkerProof $proof $target $h $h $h}
foreach($v in @(258,'0',$null)){$copy=Copy-Fixture $proof;$copy.preCleanupKernelWaitResult=$v;Reject ('worker-precleanup-kernel-'+[string]$v) {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h};$copy=Copy-Fixture $proof;$copy.cleanup.kernelWaitResult=$v;Reject ('worker-cleanup-kernel-'+[string]$v) {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}}
$copy=Copy-Fixture $proof;$copy.cleanup.killAttempted=$true;Reject 'worker-killed' {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}
$copy=Copy-Fixture $proof;$copy.cleanup.status='signaled-after-exit-observation';Reject 'worker-nonnatural-terminal-status' {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}
foreach($field in @('sealed','destinationClosed','copyCompleted','taskIsCompleted')){$copy=Copy-Fixture $proof;$copy.rawStreams[0].$field=$false;Reject ('raw-unsealed-'+$field) {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}}
$copy=Copy-Fixture $proof;$copy.rawStreams[0].taskStatus='WaitingForActivation';Reject 'raw-pending-worker-fault' {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}
$copy=Copy-Fixture $proof;$copy.rawStreams[0].closure.flushCompleted=$false;Reject 'raw-flush-fault' {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}
$copy=Copy-Fixture $proof;$copy.rawStreams=@($copy.rawStreams[0]);Reject 'raw-missing-stderr' {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}
$copy=Copy-Fixture $proof;$copy.target.hwnd=999;Reject 'worker-stale-hwnd-proof' {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}
$copy=Copy-Fixture $proof;$copy.target.lockOwner='foreign';Reject 'worker-foreign-lock-owner' {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}
$copy=Copy-Fixture $proof;$copy.stdoutSha256='b'*64;Reject 'worker-raw-bytehash-mismatch' {Assert-UiaSnapshotWorkerProof $copy $target $h $h $h}
$contract=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'worker-contract.json')|ConvertFrom-Json
Pass 'exact-read-uia-source' {if((Get-FileHash (Join-Path $PSScriptRoot 'read-uia.ps1')).Hash.ToLowerInvariant() -cne $contract.readUiaSha256){throw 'Original traversal drift'}}
Pass 'contract-source-hashes' {foreach($b in $contract.sourceBindings){if((Get-FileHash (Join-Path $PSScriptRoot $b.path)).Hash.ToLowerInvariant() -cne $b.sha256){throw 'Contract source drift'}}}
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh controls output required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
Write-FactoryDiagnosticJson (Join-Path $OutputRoot 'pure-controls.json') ([ordered]@{kind='factory-uia-snapshot-worker-pure-controls-v1';status='passed';checks=$results;nativeWindowOpened=$false;workerLaunched=$false})
