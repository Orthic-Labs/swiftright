# Allocates logical identities only. Call BEFORE native Process.Start; no host/clock measurement claims.
param([Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$OutputPath,[Parameter(Mandatory=$true)][string]$CompileReceiptSha256,[Parameter(Mandatory=$true)][string]$ExeSha256,[Parameter(Mandatory=$true)][string]$SerializerControlSha256)
$ErrorActionPreference='Stop'
$builder=Split-Path -Parent $PSScriptRoot
$preflight=Join-Path $builder 'preflight.ps1'
if((Get-FileHash -LiteralPath $preflight).Hash.ToLowerInvariant() -cne '37ed4ec43f7b3e27db423d1b5564155ec58b0d5c61b021fa602a5919ebd15c6b'){throw 'Exact lease launch preflight required'}
if(Test-Path -LiteralPath $OutputPath){throw 'Issued metadata already exists'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture must remain unlaunched/fresh when metadata issued'}
$allowedRoot='D:\Claude\swiftright\factory\native\windows\'
foreach($path in @($RunRoot,$OutputPath)){if(-not ([IO.Path]::GetFullPath($path)).StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase) -or $path -match '["\r\n]'){throw 'Exact factory output lane required'}}
& $preflight -Phase Launch -CompileReceiptSha256 $CompileReceiptSha256 -ExeSha256 $ExeSha256 -SerializerControlSha256 $SerializerControlSha256 | Out-Null
if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'source-binding.json')).Hash.ToLowerInvariant() -cne '21fe0b64c8d9d5886fb4c2470274959793b5c7a53d31039d862947b20a8dd4c4' -or (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'canonical-inputs-manifest.json')).Hash.ToLowerInvariant() -cne '208689e04f06a0e397ccd611bb8aca3828e0cf7ec15fd7df0a4dab8436389efa'){throw 'Prospective source-bound tuple reference drift'}
$package=Join-Path $builder 'package';$planPath=Join-Path $package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json
if(@($plan.hostArguments).Count -ne 1 -or $plan.hostArguments[0] -cne '--factory-capture-lease-seconds=40' -or $plan.captureLease.selectedSeconds -ne 40){throw 'Exact bounded diagnostic lease required'}
$receiptPath=Join-Path $package 'build-capture-lease-r1\observation.json';$receipt=Get-Content -Raw $receiptPath|ConvertFrom-Json
$bindingPath=Join-Path $PSScriptRoot 'source-binding.json'
$runID=[Guid]::NewGuid().ToString('N');$captureID=[Guid]::NewGuid().ToString('N');$imageID=[Guid]::NewGuid().ToString('N');$at=[DateTimeOffset]::UtcNow.ToString('o')
function Raw-Ref([string]$Path){return [ordered]@{path=$Path;sha256='sha256:'+(Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $Path).Length}}
$issued=[ordered]@{kind='factory-prelaunch-capture-metadata-v2';version=2;createdAt=$at;runID=$runID;runRoot=[IO.Path]::GetFullPath($RunRoot);expectedCount=1;case=$plan.case;historicalTemplateTupleClosed=$false;recipe=Raw-Ref (Join-Path $package 'witness.manifest.json');plan=Raw-Ref $planPath;sourceHash=$plan.sourceHash;compile=Raw-Ref $receiptPath;exe=Raw-Ref $receipt.exePath;renderer=Raw-Ref $plan.rendererPath;sourceBoundCandidateTuple=Raw-Ref $bindingPath;producedRuntimeModules=$receipt.runtimeModules;serializerControlSha256=$SerializerControlSha256;frozenTupleBound=$false;hostArguments=@($plan.hostArguments);captures=@([ordered]@{run=1;captureID=$captureID;imageID=$imageID;provenance=[ordered]@{sourceHash=$plan.sourceHash;createdAt=$at;producer='padding-capture-lease-build-v1/metadata/issue-before-launch.ps1'};plannedHostIdentity='owned-renderer/'+$runID;plannedClockIdentity='parent-monotonic-clock/'+$runID;measuredHostIdentity=$null;measuredClockIdentity=$null;measurementStatus='pending-actual-launch-joins'});qualification='sourceBoundCandidate-observation-only'}
if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -cne $CompileReceiptSha256 -or (Get-FileHash -LiteralPath $receipt.exePath).Hash.ToLowerInvariant() -cne $ExeSha256){throw 'Prelaunch compile/exe changed'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture launched before metadata allocation finished'}
$json=$issued|ConvertTo-Json -Depth 20
$bytes=[Text.Encoding]::UTF8.GetBytes($json)
$file=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
[ordered]@{kind='factory-issued-metadata-ref-v1';path=$OutputPath;sha256=(Get-FileHash -LiteralPath $OutputPath).Hash.ToLowerInvariant();bytes=$bytes.Length;runID=$runID;nativeActions=0}|ConvertTo-Json
