# Actual production proof gates. No processes/windows; coherent wrong proofs reject.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path $OutputRoot){throw 'Fresh output required'}
. (Join-Path $PSScriptRoot 'cleanup.ps1')
. (Join-Path $PSScriptRoot 'stream-seal.ps1')
New-Item -ItemType Directory $OutputRoot|Out-Null
$hash='a'*64;$owned=@{pid=7;path='D:\fixture\host.exe';startedAt='2026-10-11T00:00:00Z'};$results=@()
foreach($mode in @('normal','pid','path','start','owner','compile','exe','stdout','stderr','unconfirmed','numeric-confirmed','expected-path','kernel-unsignaled','kernel-numeric','wrong-certification','wait258','waitmissing','waitstring','waitbool','waitfloat','statusmissing','statuswrong','raw-state-missing','raw-state-duplicate','raw-destination-open','raw-destination-numeric','raw-close-incomplete','raw-close-worker-pending')){
 $outcome=@{cleanup=@{confirmedOwnedExit=$true;kernelExitSignaled=$true;kernelWaitResult=0;status='already-signaled';exitCertification='retained-kernel-handle'};ownedIdentity=@{pid=7;path=$owned.path;startedAt=$owned.startedAt};lockOwner='owner timestamp';compileReceiptHash=$hash;exeHash=$hash;stdoutSha256=$hash;stderrSha256=$hash};$outcome.rawStreams=@(@{name='stdout';destinationClosed=$true;closure=@{destinationClosed=$true;completedWithinDeadline=$true};closureTaskStatus='RanToCompletion'},@{name='stderr';destinationClosed=$true;closure=@{destinationClosed=$true;completedWithinDeadline=$true};closureTaskStatus='RanToCompletion'});$expectedPath=$owned.path
 switch($mode){
 'raw-state-missing'{$outcome.Remove('rawStreams')};'raw-state-duplicate'{$outcome.rawStreams[1].name='stdout'};'raw-destination-open'{$outcome.rawStreams[0].destinationClosed=$false};'raw-destination-numeric'{$outcome.rawStreams[0].destinationClosed=1};'raw-close-incomplete'{$outcome.rawStreams[0].closure.destinationClosed=$false};'raw-close-worker-pending'{$outcome.rawStreams[0].closureTaskStatus='WaitingForActivation'}
 'wait258'{$outcome.cleanup.kernelWaitResult=258};'waitmissing'{$outcome.cleanup.Remove('kernelWaitResult')};'waitstring'{$outcome.cleanup.kernelWaitResult='0'};'waitbool'{$outcome.cleanup.kernelWaitResult=$false};'waitfloat'{$outcome.cleanup.kernelWaitResult=[double]0};'statusmissing'{$outcome.cleanup.Remove('status')};'statuswrong'{$outcome.cleanup.status='hold-cleanup'}
 'pid'{$outcome.ownedIdentity.pid=8};'path'{$outcome.ownedIdentity.path='wrong'};'start'{$outcome.ownedIdentity.startedAt='wrong'}
 'owner'{$outcome.lockOwner='foreign'};'compile'{$outcome.compileReceiptHash='b'*64};'exe'{$outcome.exeHash='b'*64};'stdout'{$outcome.stdoutSha256='b'*64};'stderr'{$outcome.stderrSha256='b'*64}
 'kernel-unsignaled'{$outcome.cleanup.kernelExitSignaled=$false};'kernel-numeric'{$outcome.cleanup.kernelExitSignaled=1};'wrong-certification'{$outcome.cleanup.exitCertification='HasExited-only'};'unconfirmed'{$outcome.cleanup.confirmedOwnedExit=$false};'numeric-confirmed'{$outcome.cleanup.confirmedOwnedExit=1};'expected-path'{$expectedPath='other.exe'}
 }
 $value=Test-FactoryCaptureExitProof $outcome $owned 'owner timestamp' $hash $hash $hash $hash $expectedPath
 if($value -ne ($mode -eq 'normal')){throw ('Exit proof gate failed '+$mode)}
 $outcomeAccepted=$true;try{Assert-FactoryCaptureOutcome $null $outcome.cleanup @()}catch{$outcomeAccepted=$false}
 if($mode -in @('wait258','waitmissing','waitstring','waitbool','waitfloat','statusmissing','statuswrong','kernel-unsignaled','kernel-numeric','wrong-certification','unconfirmed','numeric-confirmed') -and $outcomeAccepted){throw ('Capture outcome accepted incoherent kernel proof '+$mode)}
 if($mode -eq 'normal' -and -not $outcomeAccepted){throw 'Coherent normal kernel proof rejected'}
 $results+=[ordered]@{mode=$mode;accepted=$value;captureOutcomeAccepted=$outcomeAccepted}
}
$results|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
