# Allocates logical identities only. Call BEFORE native Process.Start; no host/clock measurement claims.
param([ValidateSet(1,20)][int]$Count=1,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$OutputPath,[Parameter(Mandatory=$true)][string]$CompileReceiptSha256,[Parameter(Mandatory=$true)][string]$ExeSha256,[Parameter(Mandatory=$true)][string]$SerializerControlSha256)
$ErrorActionPreference='Stop'
$builder='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis'
$metadataRoot=Join-Path $builder 'metadata'
$contextPath=Join-Path $PSScriptRoot 'candidate-context.json'
$canonicalPath='D:\Claude\swiftright\factory\native\windows\canonical-inputs-v1\manifest.json'
$preflight=Join-Path $builder 'preflight.ps1'
if((Get-FileHash -LiteralPath $preflight).Hash.ToLowerInvariant() -cne '37ed4ec43f7b3e27db423d1b5564155ec58b0d5c61b021fa602a5919ebd15c6b'){throw 'Exact lease launch preflight required'}
if(Test-Path -LiteralPath $OutputPath){throw 'Issued metadata already exists'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture must remain unlaunched/fresh when metadata issued'}
$allowedRoot='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3\'
$expectedRun=Join-Path $PSScriptRoot $(if($Count -eq 1){'actual-single-r1'}else{'actual-repeat-r1'})
$expectedOutput=Join-Path (Join-Path $PSScriptRoot $(if($Count -eq 1){'coordinator-single-r1'}else{'coordinator-repeat-r1'})) 'issued-metadata.json'
if([IO.Path]::GetFullPath($RunRoot) -cne $expectedRun -or [IO.Path]::GetFullPath($OutputPath) -cne $expectedOutput){throw 'Exact prelaunch issued namespace required'}
foreach($path in @($RunRoot,$OutputPath)){if(-not ([IO.Path]::GetFullPath($path)).StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase) -or $path -match '["\r\n]'){throw 'Exact factory output lane required'}}
& $preflight -Phase Launch -CompileReceiptSha256 $CompileReceiptSha256 -ExeSha256 $ExeSha256 -SerializerControlSha256 $SerializerControlSha256 | Out-Null
if((Get-FileHash -LiteralPath (Join-Path $metadataRoot 'source-binding.json')).Hash.ToLowerInvariant() -cne '21fe0b64c8d9d5886fb4c2470274959793b5c7a53d31039d862947b20a8dd4c4' -or (Get-FileHash -LiteralPath (Join-Path $metadataRoot 'canonical-inputs-manifest.json')).Hash.ToLowerInvariant() -cne '208689e04f06a0e397ccd611bb8aca3828e0cf7ec15fd7df0a4dab8436389efa' -or (Get-FileHash -LiteralPath $contextPath).Hash.ToLowerInvariant() -cne '705377b54e341e7cfc06eea4394bd7c5b9d92885e56165c0ee928a0e433c8de2'){throw 'Prospective source-bound tuple reference drift'}
$context=Get-Content -Raw -LiteralPath $contextPath|ConvertFrom-Json
if($context.kind -cne 'factory-source-bound-candidate-context-v1' -or $context.frozenTupleBound -ne $false -or $context.canonicalInputs.path -cne 'factory/native/windows/canonical-inputs-v1/manifest.json' -or $context.canonicalInputs.sha256 -cne 'sha256:208689e04f06a0e397ccd611bb8aca3828e0cf7ec15fd7df0a4dab8436389efa'){throw 'Candidate context wrapper drift'}
$package=Join-Path $builder 'package';$planPath=Join-Path $package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json
if(@($plan.hostArguments).Count -ne 1 -or $plan.hostArguments[0] -cne '--factory-capture-lease-seconds=40' -or $plan.captureLease.selectedSeconds -ne 40){throw 'Exact bounded diagnostic lease required'}
$receiptPath=Join-Path $package 'build-capture-lease-r1\observation.json';$receipt=Get-Content -Raw $receiptPath|ConvertFrom-Json
$bindingPath=Join-Path (Split-Path -Parent $OutputPath) 'candidate-binding.json'
$tuplePath=Join-Path (Split-Path -Parent $OutputPath) 'candidate-tuple.json'
$sourceBindingPath=Join-Path $metadataRoot 'source-binding.json'
$runID=[Guid]::NewGuid().ToString('N');$at=[DateTimeOffset]::UtcNow.ToString('o')
function Raw-Ref([string]$Path){return [ordered]@{path=$Path;sha256='sha256:'+(Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $Path).Length}}
$canonicalRef=Raw-Ref $canonicalPath
$repoRoot='D:\Claude\swiftright'
function Context-Ref($Row){
 $relative=[string]$Row.path; $resolved=Join-Path $repoRoot ($relative -replace '/','\')
 if(-not (Test-Path -LiteralPath $resolved -PathType Leaf)){throw ('Mac context raw ref missing: '+$relative)}
 $raw=[IO.File]::ReadAllBytes($resolved);$hash=(Get-FileHash -LiteralPath $resolved).Hash.ToLowerInvariant()
 if($hash -cne ([string]$Row.sha256).Replace('sha256:','') -or $raw.Length -ne [int64]$Row.bytes){throw ('Mac context raw ref drift: '+$relative)}
 return [ordered]@{path=$relative;sha256=('sha256:'+$hash);bytes=$raw.Length}
}
$macContextRefs=[ordered]@{}
foreach($row in @($context.macContext.sourceRefs)){$macContextRefs[('macContext_'+([IO.Path]::GetFileNameWithoutExtension($row.label) -replace '[^A-Za-z0-9]','_'))]=(Context-Ref $row)}
$tuple=[ordered]@{kind='factory-source-bound-candidate-canonical-tuple-v1';version=1;candidateID=$context.candidateID;case=$plan.case;frozenTupleBound=$false;historicalCaseTemplateTuple=$context.historicalCaseTemplateTuple;tuple=[ordered]@{id=$context.candidateID;sdk=$context.tupleContext.sdk;macosBuild=$context.tupleContext.macosBuild;toolchains=$context.tupleContext.toolchains;runtimeCommit=$plan.runtimeSourceCommit;rendererHash=('sha256:'+$plan.rendererSha256);hostHashes=[ordered]@{macos=$context.tupleContext.macosHostHash;windows=('sha256:'+$ExeSha256)};factoryVersion=$context.tupleContext.factoryVersion;acceptanceConfigHash=$context.tupleContext.acceptanceConfigHash};sourceInputs=[ordered]@{canonicalInputs=$canonicalRef;sourceBinding=(Raw-Ref $sourceBindingPath)}+$macContextRefs}
$tupleJson=$tuple|ConvertTo-Json -Depth 24
$tupleBytes=[Text.Encoding]::UTF8.GetBytes($tupleJson)
$tupleFile=[IO.File]::Open($tuplePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$tupleFile.Write($tupleBytes,0,$tupleBytes.Length);$tupleFile.Flush($true)}finally{$tupleFile.Dispose()}
$tupleRef=Raw-Ref $tuplePath
$candidate=[ordered]@{kind='factory-source-bound-candidate-binding-v1';version=1;canonicalTupleRef=$tupleRef;canonicalInputs=$canonicalRef;sourceBinding=(Raw-Ref $sourceBindingPath);frozenTupleBound=$false;runtime=[ordered]@{sourceCommit=$plan.runtimeSourceCommit;sourceTreeHash=$plan.runtimeSourceTreeHash};renderer=[ordered]@{sha256=('sha256:'+$plan.rendererSha256)}}
$candidateJson=$candidate|ConvertTo-Json -Depth 20
$candidateBytes=[Text.Encoding]::UTF8.GetBytes($candidateJson)
$candidateFile=[IO.File]::Open($bindingPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$candidateFile.Write($candidateBytes,0,$candidateBytes.Length);$candidateFile.Flush($true)}finally{$candidateFile.Dispose()}
$candidateRef=Raw-Ref $bindingPath
$issued=[ordered]@{kind='factory-prelaunch-capture-metadata-v2';version=2;createdAt=$at;runID=$runID;runRoot=[IO.Path]::GetFullPath($RunRoot);expectedCount=$Count;case=$plan.case;historicalTemplateTupleClosed=$false;recipe=Raw-Ref (Join-Path $package 'witness.manifest.json');plan=Raw-Ref $planPath;sourceHash=$plan.sourceHash;compile=Raw-Ref $receiptPath;exe=Raw-Ref $receipt.exePath;renderer=Raw-Ref $plan.rendererPath;sourceBoundCandidateTuple=$candidateRef;candidateTuple=$tupleRef;candidateContext=Raw-Ref $contextPath;producedRuntimeModules=$receipt.runtimeModules;serializerControlSha256=$SerializerControlSha256;frozenTupleBound=$false;hostArguments=@($plan.hostArguments);captures=@(for($run=1;$run -le $Count;$run++){[ordered]@{run=$run;captureID=[Guid]::NewGuid().ToString('N');imageID=[Guid]::NewGuid().ToString('N');provenance=[ordered]@{sourceHash=$plan.sourceHash;createdAt=$at;producer='padding-capture-lease-capture-v3/issue-before-launch.ps1'};plannedHostIdentity='owned-renderer/'+$runID+'/'+$run;plannedClockIdentity='parent-monotonic-clock/'+$runID+'/'+$run;measuredHostIdentity=$null;measuredClockIdentity=$null;measurementStatus='pending-actual-launch-joins'}});qualification='sourceBoundCandidate-observation-only'}
if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -cne $CompileReceiptSha256 -or (Get-FileHash -LiteralPath $receipt.exePath).Hash.ToLowerInvariant() -cne $ExeSha256){throw 'Prelaunch compile/exe changed'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture launched before metadata allocation finished'}
$json=$issued|ConvertTo-Json -Depth 20
$bytes=[Text.Encoding]::UTF8.GetBytes($json)
$file=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
[ordered]@{kind='factory-issued-metadata-ref-v1';path=$OutputPath;sha256=(Get-FileHash -LiteralPath $OutputPath).Hash.ToLowerInvariant();bytes=$bytes.Length;runID=$runID;nativeActions=0}|ConvertTo-Json
