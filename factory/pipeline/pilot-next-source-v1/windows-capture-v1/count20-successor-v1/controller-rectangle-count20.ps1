# Source-only Count20 admission. It performs no native, GUI, lock, compiler, or remote action.
param([Parameter(Mandatory=$true)][string]$Config,[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
$configPath=[IO.Path]::GetFullPath($Config)
function Assert-RegularBounded([string]$Path,[long]$Limit){
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.LinkType -or $item.Length -gt $Limit){throw "Bounded regular file required: $Path"}
 return $item
}
function Hash-File([string]$Path,[long]$Limit){
 $item=Assert-RegularBounded $Path $Limit
 return (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-Json([string]$Path){
 Assert-RegularBounded $Path 2097152|Out-Null
 return Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
}
function Resolve-Required([string]$Value,[string]$Name){
 if([string]::IsNullOrWhiteSpace($Value)){throw "$Name required"}
 return [IO.Path]::GetFullPath($Value)
}
function Require-Hash([string]$Value,[string]$Name){
 if($Value -notmatch '^[0-9a-f]{64}$'){throw "$Name must be lowercase SHA-256"}
}
function Require-PathHash([string]$Path,[string]$Expected,[string]$Name,[long]$Limit){
 Require-Hash $Expected $Name
 if((Hash-File $Path $Limit) -cne $Expected){throw "$Name drift"}
}
function Require-True([object]$Value,[string]$Name){if($Value -ne $true){throw "$Name proof missing"}}

$config=Read-Json $configPath
if($config.kind -ne 'factory-rectangle-count20-config-v1'){throw 'Rectangle Count20 config kind mismatch'}
$configRoot=[IO.Path]::GetFullPath([string]$config.controlRoot)
if($configPath -cne (Join-Path $configRoot 'count20-config.json')){throw 'Count20 config must be inside fresh control root'}
if($config.count -ne 20){throw 'Exact Rectangle Count20 required'}

$sourceInputs=Resolve-Required ([string]$config.sourceInputsPath) 'sourceInputsPath'
$sourceInputsHash=[string]$config.sourceInputsHash
Require-PathHash $sourceInputs $sourceInputsHash 'source input manifest' 2097152
$inputs=Read-Json $sourceInputs
if($inputs.kind -ne 'factory-rectangle-source-inputs-v2' -or $inputs.count -ne 20){throw 'Rectangle Count20 source-input manifest kind/count mismatch'}
foreach($field in @('caseID','caseHash','sourceHash','tupleID','planHash','compileReceiptHash','tupleHash','bindingHash','recipeHash','exeHash','runtimeSourceCommit','rendererPath','rendererSha256','serializerControlSha256','contextRef','integrationBindingsRef','integrationBindingsHash','rendererRef','exeRef','helperManifestHash')){if([string]::IsNullOrWhiteSpace([string]$inputs.$field)){throw "source-input field missing: $field"}}
if($inputs.sourceHash -notmatch '^sha256:[0-9a-f]{64}$'){throw 'source witness hash malformed'}

$count1Proof=Resolve-Required ([string]$config.count1ProofPath) 'count1ProofPath'
Require-PathHash $count1Proof ([string]$config.count1ProofHash) 'Count1 proof' 4194304
$proof=Read-Json $count1Proof
if($proof.kind -ne 'factory-rectangle-count1-proof-v1' -or $proof.count -ne 1 -or $proof.status -ne 'completed-source-bound-observation'){throw 'Successful fresh Rectangle Count1 proof required'}
foreach($field in @('caseID','sourceHash','tupleID','planHash','compileReceiptHash','exeHash','runtimeSourceCommit','rendererSha256','serializerControlSha256')){if([string]$proof.$field -cne [string]$inputs.$field){throw "Count1 proof/source join mismatch: $field"}}
Require-True $proof.native.firstCaptureProof 'native first capture'
Require-True $proof.native.backgroundWindow 'background window'
Require-True $proof.native.retainedRendererHandle 'retained renderer handle'
Require-True $proof.native.workerTerminalProof 'worker terminal proof'
Require-True $proof.native.rendererTerminalProof 'renderer terminal proof'
Require-True $proof.native.streamsSealed 'sealed output streams'
Require-True $proof.native.jobMemoryBound '1GiB job memory bound'
Require-True $proof.native.lockReleased 'desktop lock release'
if($proof.native.activeProcessCount -ne 1 -or $proof.native.peakJobMemoryUsedBytes -gt 1073741824){throw 'Count1 job proof violates memory/active-process bound'}

$helperManifest=Resolve-Required ([string]$config.helperManifestPath) 'helperManifestPath'
Require-PathHash $helperManifest ([string]$config.helperManifestHash) 'helper manifest' 2097152
$helpers=Read-Json $helperManifest
if($helpers.kind -ne 'factory-rectangle-helper-source-manifest-v1' -or @($helpers.files).Count -lt 1){throw 'Rectangle helper source manifest incomplete'}
foreach($entry in @($helpers.files)){
 if([string]::IsNullOrWhiteSpace([string]$entry.path)){throw 'helper path missing'}
 $helperPath=Resolve-Required ([string]$entry.path) 'helper path'
 if($entry.bytes -lt 0 -or $entry.bytes -gt 67108864){throw 'helper byte bound invalid'}
 if((Get-Item -LiteralPath $helperPath -Force).Length -ne [long]$entry.bytes){throw "helper byte drift: $helperPath"}
 Require-PathHash $helperPath ([string]$entry.sha256) 'helper source' 67108864
}

foreach($pin in @(
 @{path=$config.planPath;hash=$config.planHash;name='Rectangle plan'},
 @{path=$config.compileReceiptPath;hash=$config.compileReceiptHash;name='compile receipt'},
 @{path=$config.rendererPath;hash=$config.rendererSha256;name='renderer'},
 @{path=$config.serializerControlPath;hash=$config.serializerControlSha256;name='serializer control'}
)){
 $pinPath=Resolve-Required ([string]$pin.path) $pin.name
 Require-PathHash $pinPath ([string]$pin.hash) $pin.name 67108864
}
$plan=Read-Json (Resolve-Required ([string]$config.planPath) 'planPath')
if($plan.kind -ne 'factory-rectangle-compiler-plan-v2' -or $plan.case.id -cne $inputs.caseID -or $plan.case.hash -cne $inputs.caseHash -or $plan.tuple.id -cne $inputs.tupleID -or $plan.sourceHash -cne $inputs.sourceHash -or $plan.runtimeSourceCommit -ne $inputs.runtimeSourceCommit -or $plan.rendererPath -ne $inputs.rendererPath -or $plan.rendererSha256 -ne $inputs.rendererSha256){throw 'Count20 plan identity mismatch'}

$issuedPath=Resolve-Required ([string]$config.issuedMetadataPath) 'issuedMetadataPath'
Require-PathHash $issuedPath ([string]$config.issuedMetadataHash) 'issued metadata' 2097152
$issued=Read-Json $issuedPath
if($issued.kind -ne 'factory-prelaunch-capture-metadata-v2' -or $issued.version -ne 2 -or $issued.expectedCount -ne 20 -or @($issued.captures).Count -ne 20){throw 'Issued Rectangle Count20 metadata incomplete'}
$issuedTuplePath=Resolve-Required ([string]$issued.candidateTuple.path) 'issued candidate tuple'
Require-PathHash $issuedTuplePath ([string]$inputs.tupleHash) 'issued candidate tuple' 2097152
$issuedTuple=Read-Json $issuedTuplePath
if($issued.candidateTuple.path -cne $inputs.tupleRef.path -or $issued.candidateTuple.sha256 -cne $inputs.tupleRef.sha256 -or [int64]$issued.candidateTuple.bytes -ne [int64]$inputs.tupleRef.bytes -or $issuedTuple.tuple.id -cne $inputs.tupleID){throw 'Issued candidate tuple/source join mismatch'}
$runs=@($issued.captures|ForEach-Object{$_.run})
if(($runs -join ',') -ne ((1..20) -join ',')){throw 'Issued capture order must remain 1..20'}
foreach($capture in @($issued.captures)){
 if([string]$capture.captureID -notmatch '^capture/[0-9a-f]{32}$' -or [string]$capture.imageID -notmatch '^image/[0-9a-f]{32}$'){throw 'Issued Count20 IDs must be prefixed canonical IDs'}
 if($capture.caseID -and $capture.caseID -cne $inputs.caseID){throw 'Issued case join mismatch'}
 if($capture.tupleID -and $capture.tupleID -cne $inputs.tupleID){throw 'Issued tuple join mismatch'}
 if($capture.sourceHash -and $capture.sourceHash -cne $inputs.sourceHash){throw 'Issued source join mismatch'}
}
if($issued.sourceHash -cne $inputs.sourceHash -or $issued.case.id -cne $inputs.caseID -or $issued.case.hash -cne $inputs.caseHash){throw 'Issued metadata source/case mismatch'}

$outputRoot=Resolve-Required ([string]$config.outputRoot) 'outputRoot'
$runRoot=Resolve-Required ([string]$config.runRoot) 'runRoot'
if(-not $runRoot.StartsWith($outputRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Count20 run root outside output root'}
if(Test-Path -LiteralPath $runRoot){throw 'Count20 run root must be fresh'}
$admission=[ordered]@{kind='factory-rectangle-count20-admission-v1';status='passed-source-only';count=20;count1ProofHash=$config.count1ProofHash;sourceInputsHash=$sourceInputsHash;issuedMetadataHash=$config.issuedMetadataHash;caseID=$inputs.caseID;tupleID=$inputs.tupleID;sourceHash=$inputs.sourceHash;planHash=$inputs.planHash;compileReceiptHash=$inputs.compileReceiptHash;exeHash=$inputs.exeHash;runtimeSourceCommit=$inputs.runtimeSourceCommit;rendererSha256=$inputs.rendererSha256;serializerControlSha256=$inputs.serializerControlSha256;nativeWindowActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0}
New-Item -ItemType Directory -Path $configRoot -Force|Out-Null
$admission|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $configRoot 'count20-admission.json') -Encoding UTF8
if(-not $PreflightOnly){throw 'Count20 controller only admits source; root must invoke reviewed native controller after admission'}
