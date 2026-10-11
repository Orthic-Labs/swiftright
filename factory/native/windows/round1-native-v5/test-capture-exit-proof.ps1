# Actual production proof gates. No processes/windows; coherent wrong proofs reject.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path $OutputRoot){throw 'Fresh output required'}
. (Join-Path $PSScriptRoot 'cleanup.ps1')
New-Item -ItemType Directory $OutputRoot|Out-Null
$hash='a'*64;$owned=@{pid=7;path='D:\fixture\host.exe';startedAt='2026-10-11T00:00:00Z'};$results=@()
foreach($mode in @('normal','pid','path','start','owner','compile','exe','stdout','stderr','unconfirmed','numeric-confirmed','expected-path')){
 $outcome=@{cleanup=@{confirmedOwnedExit=$true};ownedIdentity=@{pid=7;path=$owned.path;startedAt=$owned.startedAt};lockOwner='owner timestamp';compileReceiptHash=$hash;exeHash=$hash;stdoutSha256=$hash;stderrSha256=$hash};$expectedPath=$owned.path
 switch($mode){
 'pid'{$outcome.ownedIdentity.pid=8};'path'{$outcome.ownedIdentity.path='wrong'};'start'{$outcome.ownedIdentity.startedAt='wrong'}
 'owner'{$outcome.lockOwner='foreign'};'compile'{$outcome.compileReceiptHash='b'*64};'exe'{$outcome.exeHash='b'*64};'stdout'{$outcome.stdoutSha256='b'*64};'stderr'{$outcome.stderrSha256='b'*64}
 'unconfirmed'{$outcome.cleanup.confirmedOwnedExit=$false};'numeric-confirmed'{$outcome.cleanup.confirmedOwnedExit=1};'expected-path'{$expectedPath='other.exe'}
 }
 $value=Test-FactoryCaptureExitProof $outcome $owned 'owner timestamp' $hash $hash $hash $hash $expectedPath
 if($value -ne ($mode -eq 'normal')){throw ('Exit proof gate failed '+$mode)}
 $results+=[ordered]@{mode=$mode;accepted=$value}
}
$results|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
