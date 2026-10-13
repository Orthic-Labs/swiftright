# Fresh Count20 r11 issuer. Source-only metadata allocation; no lock, GUI, compiler, native, or remote action.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$FreshCasePath,
 [Parameter(Mandatory=$true)][string]$FreshTuplePath,
 [Parameter(Mandatory=$true)][string]$FreshManifestPath,
 [Parameter(Mandatory=$true)][string]$EquivalencePath,
 [Parameter(Mandatory=$true)][string]$ActualPlanPath,
 [Parameter(Mandatory=$true)][string]$ActualReceiptPath,
 [Parameter(Mandatory=$true)][string]$ExecutablePath,
 [Parameter(Mandatory=$true)][string]$RendererPath,
 [Parameter(Mandatory=$true)][string]$CanonicalInputsPath,
 [Parameter(Mandatory=$true)][string]$SourceBindingPath,
 [Parameter(Mandatory=$true)][string]$NamespaceRoot,
 [Parameter(Mandatory=$true)][string]$RunRoot,
 [Parameter(Mandatory=$true)][string]$OutputPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CompileReceiptSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExeSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$PlanSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SerializerControlSha256,
 [ValidateSet(20)][int]$Count=20
)
$ErrorActionPreference='Stop'
$expectedCaseHash='sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de'
$expectedCaseID='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9'
$expectedTupleID='sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011'
$expectedMacHost='sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be977'
$expectedV4='aa8f39419292d2170b9036f6ee648bf8b71f9ca9ddcf6205d1a03ea0b2f2f34d'
function Full([string]$p){return [IO.Path]::GetFullPath($p)}
function Hash([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Ref([string]$p){$i=Get-Item -LiteralPath $p;return [ordered]@{path=(Full $p);sha256=('sha256:'+(Hash $p));bytes=[int64]$i.Length}}
function Require([string]$p,[string]$hash,[string]$label){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "$label missing"};if((Hash $p) -cne $hash.Replace('sha256:','').ToLowerInvariant()){throw "$label hash drift"}}
function Under([string]$p,[string]$root){$full=Full $p;$base=(Full $root).TrimEnd('\')+'\';if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'Fresh namespace containment failed'};return $full}
Require $FreshCasePath $expectedCaseHash 'Fresh case'
Require $FreshTuplePath 'bf5978000391687733885d3e49465e79e7727f374488cb359595a085113422c0' 'Fresh tuple packet'
Require $FreshManifestPath 'e39db8b6d3844c6de9811eb5783564b49eb8556bc3cc854e79c3a36c61f8e9e0' 'Fresh manifest'
Require $EquivalencePath $expectedV4 'v4 equivalence receipt'
if(Test-Path -LiteralPath $RunRoot){throw 'Fresh run namespace already exists'}
if(Test-Path -LiteralPath $OutputPath){throw 'Issued metadata already exists'}
$run=Under $RunRoot $NamespaceRoot;$out=Under $OutputPath $NamespaceRoot
$case=Get-Content -Raw -LiteralPath $FreshCasePath|ConvertFrom-Json
$packet=Get-Content -Raw -LiteralPath $FreshTuplePath|ConvertFrom-Json
$manifest=Get-Content -Raw -LiteralPath $FreshManifestPath|ConvertFrom-Json
$eq=Get-Content -Raw -LiteralPath $EquivalencePath|ConvertFrom-Json
if($case.id -cne $expectedCaseID -or $packet.candidateID -cne $expectedTupleID -or $packet.case.id -cne $expectedCaseID -or $packet.case.hash -cne $expectedCaseHash -or $manifest.case.id -cne $expectedCaseID -or $manifest.case.hash -cne $expectedCaseHash){throw 'Fresh case/tuple/manifest join mismatch'}
if($eq.status -cne 'reuse-admitted-source-equivalent-v4' -or $eq.candidateOnly -ne $true -or $eq.equivalence.semanticInputsEqual -ne $true -or $eq.requirements.freshMetadata -ne $true -or $eq.requirements.freshCaptureIDs -ne $true -or $eq.requirements.historicalDonorRelabel -ne $false){throw 'v4 source-equivalence receipt not admitted'}
Require $ActualPlanPath $PlanSha256 'Actual plan'
Require $ActualReceiptPath $CompileReceiptSha256 'Actual producer receipt'
Require $ExecutablePath $ExeSha256 'Actual executable'
if(-not(Test-Path -LiteralPath $RendererPath -PathType Leaf)){throw 'Actual renderer missing'}
foreach($p in @($CanonicalInputsPath,$SourceBindingPath)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw 'Source closure input missing'}}
$plan=Get-Content -Raw -LiteralPath $ActualPlanPath|ConvertFrom-Json
$receipt=Get-Content -Raw -LiteralPath $ActualReceiptPath|ConvertFrom-Json
if($receipt.exitCode -ne 0 -or $receipt.timedOut -eq $true -or $receipt.error){throw 'Actual compile closure failed'}
if($manifest.sourceHash -ne $receipt.sourceHash){throw 'Fresh source hash does not join actual receipt'}
if($packet.tuple.hostHashes.macos -ne $expectedMacHost -or $packet.tuple.hostHashes.windows -ne ('sha256:'+$ExeSha256)){throw 'Fresh host tuple mismatch'}
if($packet.tuple.runtimeCommit -ne $plan.runtimeSourceCommit -or $packet.tuple.rendererHash -ne ('sha256:'+$plan.rendererSha256)){throw 'Fresh tuple runtime/renderer mismatch'}
$parent=Split-Path -Parent $out
[IO.Directory]::CreateDirectory($parent)|Out-Null
$tuplePath=Join-Path $parent 'candidate-tuple.json';$bindingPath=Join-Path $parent 'candidate-binding.json';$contextPath=Join-Path $parent 'candidate-context.json'
$tuple=[ordered]@{kind='factory-source-bound-candidate-canonical-tuple-v1';version=1;candidateID=$expectedTupleID;case=[ordered]@{id=$expectedCaseID;hash=$expectedCaseHash};frozenTupleBound=$false;historicalCaseTemplateTuple=$packet.baseCase;tuple=$packet.tuple;sourceInputs=[ordered]@{canonicalInputs=(Ref $CanonicalInputsPath);sourceBinding=(Ref $SourceBindingPath);freshManifest=(Ref $FreshManifestPath);freshCase=(Ref $FreshCasePath);sourceEquivalenceV4=(Ref $EquivalencePath)}}
$tuple | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $tuplePath -Encoding UTF8
$binding=[ordered]@{kind='factory-source-bound-candidate-binding-v1';version=1;canonicalTupleRef=(Ref $tuplePath);canonicalInputs=(Ref $CanonicalInputsPath);sourceBinding=(Ref $SourceBindingPath);frozenTupleBound=$false;runtime=[ordered]@{sourceCommit=$plan.runtimeSourceCommit;sourceTreeHash=$plan.runtimeSourceTreeHash};renderer=[ordered]@{sha256=('sha256:'+$plan.rendererSha256)}}
$binding | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $bindingPath -Encoding UTF8
$context=[ordered]@{kind='factory-source-bound-fresh-r11-context-v1';version=1;candidateID=$expectedTupleID;case=[ordered]@{id=$expectedCaseID;hash=$expectedCaseHash};freshCase=(Ref $FreshCasePath);freshManifest=(Ref $FreshManifestPath);freshTuplePacket=(Ref $FreshTuplePath);sourceEquivalenceV4=(Ref $EquivalencePath);canonicalInputs=(Ref $CanonicalInputsPath);sourceBinding=(Ref $SourceBindingPath);frozenTupleBound=$false}
$context | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $contextPath -Encoding UTF8
$at=[DateTimeOffset]::UtcNow.ToString('o');$runID=[Guid]::NewGuid().ToString('N')
function New-ID([string]$prefix){$v=$prefix+'/'+[Guid]::NewGuid().ToString('N');if($v -notmatch ('^'+$prefix+'/[0-9a-f]{32}$')){throw 'Canonical ID generation failed'};return $v}
$captures=@(1..$Count|ForEach-Object{[ordered]@{run=$_;captureID=(New-ID 'capture');imageID=(New-ID 'image');provenance=[ordered]@{sourceHash=$manifest.sourceHash;createdAt=$at;producer='factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v13/issue-count20-fresh-r11-v5.ps1'};plannedHostIdentity='owned-renderer/'+$runID+'/'+$_;plannedClockIdentity='parent-monotonic-clock/'+$runID+'/'+$_;measuredHostIdentity=$null;measuredClockIdentity=$null;measurementStatus='pending-actual-launch-joins'}})
if($captures.Count -ne $Count -or @($captures.captureID|Select-Object -Unique).Count -ne $Count -or @($captures.imageID|Select-Object -Unique).Count -ne $Count){throw 'Capture allocation cardinality/uniqueness failed'}
$meta=[ordered]@{kind='factory-prelaunch-capture-metadata-v2';version=2;createdAt=$at;runID=$runID;runRoot=$run;expectedCount=$Count;case=[ordered]@{id=$expectedCaseID;hash=$expectedCaseHash};historicalTemplateTupleClosed=$false;recipe=(Ref $FreshManifestPath);plan=(Ref $ActualPlanPath);sourceHash=$manifest.sourceHash;compile=(Ref $ActualReceiptPath);exe=(Ref $ExecutablePath);renderer=(Ref $RendererPath);sourceBoundCandidateTuple=(Ref $bindingPath);candidateTuple=(Ref $tuplePath);candidateContext=(Ref $contextPath);producedRuntimeModules=$receipt.runtimeModules;serializerControlSha256=$SerializerControlSha256;frozenTupleBound=$false;hostArguments=@('--factory-capture-lease-seconds=40');captures=$captures;qualification='sourceBoundCandidate-observation-only';sourceEquivalenceV4=(Ref $EquivalencePath)}
$json=$meta|ConvertTo-Json -Depth 30
[IO.Directory]::CreateDirectory($out)|Out-Null
[IO.File]::WriteAllText($OutputPath,$json,[Text.Encoding]::UTF8)
[ordered]@{kind='factory-fresh-count20-r11-issued-metadata-v1';status='source-bound-candidate-observation-only';path=(Full $OutputPath);sha256=(Hash $OutputPath);bytes=(Get-Item $OutputPath).Length;runID=$runID;count=$Count;nativeActions=0;lockActions=0;compilerActions=0;remoteActions=0}|ConvertTo-Json
