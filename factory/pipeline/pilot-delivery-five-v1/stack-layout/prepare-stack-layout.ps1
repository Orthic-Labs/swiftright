# Source-only preflight. Emits exact Count1 entry; does no process/native/lock action.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$RunRoot,
 [Parameter(Mandatory=$true)][string]$LockOwner,
 [Parameter(Mandatory=$true)][string]$PlanOutput
)
$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\'
$package='D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle\package'
$packet='D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\stack-layout'
if($RunRoot -match '["\r\n]' -or $LockOwner -match '["\r\n]' -or $PlanOutput -match '["\r\n]'){throw 'Quoted/newline argument rejected'}
$run=[IO.Path]::GetFullPath($RunRoot);$planOut=[IO.Path]::GetFullPath($PlanOutput)
if(-not $run.StartsWith($packet+'\native\',[StringComparison]::OrdinalIgnoreCase)){throw 'RunRoot must be fresh stack-layout native descendant'}
if(-not $planOut.StartsWith($packet+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'PlanOutput must remain under stack-layout'}
if(Test-Path -LiteralPath $planOut){throw 'Fresh source plan required'}
. (Join-Path $packet 'source\stack-source-join.ps1')
$join=Assert-StackLifecycleSource $package $StackReceiptHash $StackExeHash
$files=[ordered]@{}
foreach($rel in @('source\capture-stack-lifecycle-count1.ps1','source\stack-source-join.ps1','helpers\cleanup-v3.ps1','helpers\stream-seal.ps1','helpers\owned-close.ps1','helpers\pixels-background.ps1','helpers\host-inputs.ps1')){
 $p=Join-Path $packet $rel
 if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('Packet source missing: '+$rel)}
 $files[$rel]=[ordered]@{sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $p).Length}
}
$uiaWorkerFiles=@('source\uia-worker-mta-v1\README.md','source\uia-worker-mta-v1\worker-contract.json','source\uia-worker-mta-v1\worker.ps1','source\uia-worker-mta-v1\invoke-stack-uia-worker.ps1','source\uia-worker-mta-v1\read-uia.ps1','source\uia-worker-mta-v1\schema.ps1','source\uia-worker-mta-v1\root-rss-supervisor.ps1','source\uia-worker-mta-v1\support\final-exit-certificate.ps1','source\uia-worker-mta-v1\test-stack-uia-mta-controls.ps1')
foreach($rel in $uiaWorkerFiles){
 $p=Join-Path $packet $rel
 if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('Packet source missing: '+$rel)}
 $files[$rel]=[ordered]@{sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $p).Length}
}
$workerContract=Get-Content -Raw (Join-Path $packet 'source\uia-worker-mta-v1\worker-contract.json')|ConvertFrom-Json
if($workerContract.kind -cne 'factory-stack-uia-fromhandle-mta-worker-contract-v1' -or $workerContract.workerApartment -cne 'MTA' -or $workerContract.workerDeadlineSeconds -ne 15 -or $workerContract.streamDeadlineSeconds -ne 5 -or $workerContract.destinationClosureSeconds -ne 5 -or $workerContract.releaseABI -cne 'FactoryProcessWaitV6'){throw 'Stack MTA worker contract drift'}
if($files['helpers\cleanup-v3.ps1'].sha256 -cne 'cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13'){throw 'Approved V6 cleanup helper drift'}
if($files['helpers\stream-seal.ps1'].sha256 -cne '4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'){throw 'Stream helper drift'}
if($files['helpers\owned-close.ps1'].sha256 -cne 'd0898e1a2ebdefce64fbf5b16cbc3b9f72578e2f0efb649ee001c182f7aaec7c'){throw 'Owned-close helper drift'}
$entry='powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $packet 'source\capture-stack-lifecycle-count1.ps1')+'" -Package "'+$package+'" -LockOwner "'+$LockOwner+'" -RunRoot "'+$run+'" -CompileReceiptHash '+$StackReceiptHash+' -ExeHash '+$StackExeHash
$doc=[ordered]@{kind='factory-pilot-delivery-five-stack-layout-source-plan-v1';status='SOURCE_READY';caseID=$join.caseID;diagnosticScope=$join.diagnosticScope;package=$package;plan=[ordered]@{path=(Join-Path $package 'plan.json');sha256=$StackPlanHash};compileReceipt=[ordered]@{path=(Join-Path $package $StackReceiptRelative);sha256=$StackReceiptHash};exe=[ordered]@{path='D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle\package\build-lifecycle-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe';sha256=$StackExeHash};renderer=[ordered]@{path=$StackRendererPath;sha256=$StackRendererHash};runtime=[ordered]@{commit=$StackRuntimeCommit;treeHash=$StackRuntimeTreeHash};entry=$entry;runRoot=$run;count=1;nativeActions=0;compilerActions=0;lockActions=0;nativeParity='hold';frozenTupleBound=$false;closePolicy=[ordered]@{childSeconds=15;streamSeconds=5;destinationClosureSeconds=5;retainedKernelHandle=$true;waitABI='FactoryProcessWaitV6'};files=$files}
$planOutDir=Split-Path -Parent $planOut;New-Item -ItemType Directory -Path $planOutDir -Force|Out-Null;$doc|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $planOut -Encoding UTF8
$doc|ConvertTo-Json -Depth 12
