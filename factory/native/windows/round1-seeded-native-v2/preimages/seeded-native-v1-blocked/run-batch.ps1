# Exactly1 or20 fresh independent observational dispatches; no retries or compilation.
param([Parameter(Mandatory=$true)][ValidateSet('stack-overlay','custom-layout','padding-frame','preference-key','scroll-view')][string]$Case,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$CompileReceiptHash,[Parameter(Mandatory=$true)][string]$ExeHash,[ValidateSet(1,20)][int]$Count=20)
$ErrorActionPreference='Stop'
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$'){throw 'Actual measured receipt/exe pins required'}
$root=[IO.Path]::GetFullPath($RunRoot)
if(-not $root.StartsWith('D:\Claude\swiftright\factory\native\windows\round1-seeded-native-v1\',[StringComparison]::OrdinalIgnoreCase) -or $root -match '["\r\n]'){throw 'Fresh owned repeatability namespace required'}
if(Test-Path -LiteralPath $root){throw 'Namespace already exists; no reuse/retry'}
$contractPath=Join-Path $PSScriptRoot 'contract.json'
if((Get-FileHash $contractPath).Hash.ToLowerInvariant() -ne '6239a677e91a6dfb81f605526951c91da761ba2cda55a6931bcb39c2deb358da'){throw 'Contract drift'}
$c=Get-Content -Raw $contractPath|ConvertFrom-Json
$hostRow=@($c.hosts|Where-Object{$_.label -ceq $Case})
if($hostRow.Count -ne 1){throw 'Exact host contract required'}
$h=$hostRow[0]
$namespaceHelper=Join-Path $PSScriptRoot 'namespace.ps1'
if((Get-FileHash $namespaceHelper).Hash.ToLowerInvariant() -ne '04f2066a2f8fb510fa47dac69c2835577bbd3c9c1fc08891f1485d231c970dd1'){throw 'Namespace guard drift'}
. $namespaceHelper
function Assert-ReplayInputs {
 . (Join-Path $PSScriptRoot 'mac-proof.ps1')
 $macPlan=Get-Content -Raw (Join-Path $h.package 'plan.json')|ConvertFrom-Json
 Assert-SeedMacProof $h.package $macPlan $h.planHash
 if((Get-FileHash $namespaceHelper).Hash.ToLowerInvariant() -ne '04f2066a2f8fb510fa47dac69c2835577bbd3c9c1fc08891f1485d231c970dd1'){throw 'Namespace helper drift'}
 if((Get-FileHash $contractPath).Hash.ToLowerInvariant() -ne '6239a677e91a6dfb81f605526951c91da761ba2cda55a6931bcb39c2deb358da'){throw 'Contract drift'}
 foreach($b in $h.bindings){if((Get-FileHash -LiteralPath $b.path).Hash.ToLowerInvariant() -ne $b.sha256){throw 'Consumed driver/helper drift'}}
 $planPath=Join-Path $h.package 'plan.json'
 if((Get-FileHash $planPath).Hash.ToLowerInvariant() -ne $h.planHash){throw 'Exact host plan drift'}
 $plan=Get-Content -Raw $planPath|ConvertFrom-Json
 . $h.helper
 Assert-HostCompilerInputs $h.package $plan.sourceBindings
 $receiptPath=Join-Path $h.package $h.receiptRelative
 if((Get-FileHash $receiptPath).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Actual compile receipt drift'}
 $receipt=Get-Content -Raw $receiptPath|ConvertFrom-Json
 if($receipt.exitCode -ne 0 -or $receipt.timedOut -or -not $receipt.ownedExited -or $receipt.planSha256 -ne $h.planHash -or $receipt.sourceHash -ne $plan.sourceHash -or $receipt.exeSha256 -ne $ExeHash -or $receipt.runtimeSourceCommit -ne $plan.runtimeSourceCommit -or $receipt.runtimeSourceTreeHash -ne $plan.runtimeSourceTreeHash -or $receipt.rendererSha256 -ne $plan.rendererSha256){throw 'Compile lineage mismatch'}
 $exe=[IO.Path]::GetFullPath($receipt.exePath)
 if(-not $exe.StartsWith($h.package+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $exe).Hash.ToLowerInvariant() -ne $ExeHash){throw 'Actual executable binding drift'}
}
Assert-ReplayInputs
New-Item -ItemType Directory -Path $root|Out-Null
$replays=Join-Path $root 'replays';New-Item -ItemType Directory -Path $replays|Out-Null
$expected=@();$rows=@();$attempted=0;$status='hold-batch-error';$errorText='';$deadline=[DateTime]::UtcNow.AddMinutes(30)
try{
 for($i=1;$i -le $Count;$i++){
  if([DateTime]::UtcNow.AddMinutes(17) -gt $deadline){throw 'Batch deadline; no further dispatch'}
  Assert-ReplayInputs
  Assert-RepeatNamespace $replays $expected
  $name='run-'+$i.ToString('000');$out=Join-Path $replays $name
  $attempted++
  & $h.driver -Package $h.package -RunRoot $out -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash
  $expected+= $name
  Assert-RepeatNamespace $replays $expected
  $dispatchPath=Join-Path $out 'dispatch.json';$dispatch=Get-Content -Raw $dispatchPath|ConvertFrom-Json
  $rows+= [ordered]@{index=$i;run=$name;status=$dispatch.status;dispatchHash=(Get-FileHash $dispatchPath).Hash.ToLowerInvariant()}
  if($dispatch.status -ne 'captured-single-observational-uia-printwindow' -or -not $dispatch.lockAcquired -or -not $dispatch.lockReleased){throw 'First failed dispatch/lock abort; no retries'}
  Assert-ReplayInputs
 }
 $status='completed-'+$Count+'-observational'
}catch{$errorText=[string]$_}
finally{
 [ordered]@{kind='round1-repeatability-batch';case=$Case;status=$status;requested=$Count;attempted=$attempted;contractHash='6239a677e91a6dfb81f605526951c91da761ba2cda55a6931bcb39c2deb358da';compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;rows=$rows;error=$errorText;retry=$false;nativeParity='hold';frozenTupleBound=$false;closureBinding=$null}|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $root 'batch.json')
}
if($status -ne ('completed-'+$Count+'-observational')){throw 'Batch aborted; inspect immutable raw attempts'}
