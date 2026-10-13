# Source-only issuer for fresh Circle Count1/Count20 planned identities.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet(1,20)][int]$Count,
 [Parameter(Mandatory=$true)][string]$SourceInputsPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SourceInputsHash,
 [Parameter(Mandatory=$true)][string]$OutputPath,
 [Parameter(Mandatory=$true)][string]$RunRoot,
 [Parameter(Mandatory=$true)][string]$PlanPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$PlanHash,
 [Parameter(Mandatory=$true)][string]$CompileReceiptPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CompileReceiptHash,
 [Parameter(Mandatory=$true)][string]$ExePath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExeHash,
 [Parameter(Mandatory=$true)][string]$RendererPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$RendererHash,
 [Parameter(Mandatory=$true)][string]$SerializerPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SerializerHash,
 [Parameter(Mandatory=$true)][string]$TuplePath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$TupleHash,
 [Parameter(Mandatory=$true)][string]$BindingPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$BindingHash,
 [Parameter(Mandatory=$true)][string]$RecipePath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$RecipeHash
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'final-plan-eligibility.ps1')
$CircleCanonicalRecipeHashBare='57fcd72382175df83a1fe29e4e387f1e902a37174caa44cd8fc50ebc0f411a15'
$CircleCanonicalRecipeHash='sha256:'+$CircleCanonicalRecipeHashBare
$CircleCasePrefix='swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light.'
function Ref([string]$Path,[string]$Hash){$item=Get-Item -LiteralPath $Path -Force;if($item.PSIsContainer -or $item.LinkType -or $item.Length -gt 67108864){throw 'Issuer reference not bounded regular file'};if((Get-FileHash -LiteralPath $item.FullName).Hash.ToLowerInvariant() -cne $Hash){throw ('Issuer reference drift: '+$Path)};[ordered]@{path=[IO.Path]::GetFullPath($Path);sha256=('sha256:'+$Hash);bytes=[int64]$item.Length}}
function Json([string]$Path){$item=Get-Item -LiteralPath $Path -Force;if($item.PSIsContainer -or $item.LinkType -or $item.Length -gt 2097152){throw 'Issuer JSON not bounded regular file'};return (Get-Content -Raw -LiteralPath $item.FullName|ConvertFrom-Json)}
if(Test-Path -LiteralPath $OutputPath){throw 'Issuer refuses existing metadata'}
$source=Json $SourceInputsPath
if((Get-FileHash -LiteralPath $SourceInputsPath).Hash.ToLowerInvariant() -cne $SourceInputsHash -or $source.count -ne $Count){throw 'Issuer source input drift/count mismatch'}
if($source.caseID -notlike ($CircleCasePrefix+'*') -or $source.recipeHash -cne $CircleCanonicalRecipeHashBare){throw 'Issuer Circle case/recipe canonical join mismatch'}
if($null -eq $source.runtimeProof){throw 'Issuer runtime proof block missing'}
foreach($field in @('runtimeSourceCommit','runtimeSourceTreeHash','runtimeSourceReceiptHash')){if([string]::IsNullOrWhiteSpace([string]$source.runtimeProof.$field)){throw ('Issuer runtime proof field missing: '+$field)}}
if($source.runtimeSourceCommit -cne $source.runtimeProof.runtimeSourceCommit){throw 'Issuer runtime source commit proof mismatch'}
foreach($field in @('runtimeSourceTreeRef','runtimeSourceReceiptRef','runtimeVerifierRef','hostInputsRef')){if($null -eq $source.runtimeProof.$field){throw ('Issuer runtime proof reference missing: '+$field)};[void](Ref ([string]$source.runtimeProof.$field.path) ([string]$source.runtimeProof.$field.sha256).Substring(7))}
$sourceFields=@('caseID','caseHash','sourceHash','tupleID','planHash','compileReceiptHash','tupleHash','bindingHash','recipeHash','exeHash','runtimeSourceCommit','rendererPath','rendererSha256','serializerControlSha256','contextRef','rendererRef','exeRef','integrationBindingsRef','integrationBindingsHash','uiaWorkerPath','uiaWorkerHash');foreach($field in $sourceFields){if([string]::IsNullOrWhiteSpace([string]$source.$field)){throw ('Issuer source field missing: '+$field)}}
$plan=Json $PlanPath;Assert-CircleFinalPlanAdmission $plan|Out-Null;$receipt=Json $CompileReceiptPath;$tuple=Json $TuplePath
if((Get-FileHash -LiteralPath $PlanPath).Hash.ToLowerInvariant() -cne $PlanHash -or (Get-FileHash -LiteralPath $CompileReceiptPath).Hash.ToLowerInvariant() -cne $CompileReceiptHash -or (Get-FileHash -LiteralPath $TuplePath).Hash.ToLowerInvariant() -cne $TupleHash){throw 'Issuer measured reference drift'}
if($source.planRef.sha256 -cne ('sha256:'+$PlanHash) -or $source.compileRef.sha256 -cne ('sha256:'+$CompileReceiptHash) -or $source.tupleRef.sha256 -cne ('sha256:'+$TupleHash) -or $source.bindingRef.sha256 -cne ('sha256:'+$BindingHash) -or $source.recipeRef.sha256 -cne ('sha256:'+$RecipeHash) -or $source.serializerRef.sha256 -cne ('sha256:'+$SerializerHash) -or $source.exeRef.sha256 -cne ('sha256:'+$ExeHash) -or $source.rendererRef.sha256 -cne ('sha256:'+$RendererHash) -or $source.integrationBindingsRef.sha256 -cne ('sha256:'+$source.integrationBindingsHash)){throw 'Issuer source reference/hash join mismatch'}
foreach($sourceRef in @($source.planRef,$source.compileRef,$source.tupleRef,$source.bindingRef,$source.recipeRef,$source.serializerRef,$source.exeRef,$source.rendererRef,$source.integrationBindingsRef,$source.contextRef)){[void](Ref ([string]$sourceRef.path) ([string]$sourceRef.sha256).Substring(7))}
if($plan.runtimeSourceCommit -ne $source.runtimeProof.runtimeSourceCommit -or $plan.runtimeSourceTreeHash -ne $source.runtimeProof.runtimeSourceTreeHash -or $plan.runtimeSourceReceiptHash -ne $source.runtimeProof.runtimeSourceReceiptHash){throw 'Issuer runtime proof/plan mismatch'}
if($plan.kind -ne 'factory-circle-compiler-plan-v1' -or $plan.candidate -ne 'swiftui.circle.fixed.pilot-next' -or $plan.recipe.id -ne 'swiftui.circle.fixed.recipe' -or $plan.recipe.hash -ne $CircleCanonicalRecipeHash -or $plan.case.id -ne $source.caseID -or $plan.case.hash -ne $source.caseHash -or $plan.sourceHash -ne $source.sourceHash -or $plan.tuple.id -ne $source.tupleID -or $plan.runtimeSourceCommit -ne $source.runtimeSourceCommit -or $plan.rendererPath -ne $source.rendererPath -or $plan.rendererSha256 -ne $RendererHash -or $receipt.kind -ne 'factory-circle-owned-compile-v1' -or $receipt.exitCode -ne 0 -or $receipt.streamsSealed -ne $true -or $receipt.streamDrainComplete -ne $true -or $receipt.originalHandleRetained -ne $true -or $receipt.jobActiveCount -ne 0 -or $receipt.kernelWait -ne 0 -or $receipt.ownedExited -ne $true -or $receipt.sourceHash -ne $source.sourceHash -or $receipt.planSha256 -ne $source.planHash -or $receipt.exeSha256 -ne $ExeHash -or $receipt.rendererSha256 -ne $RendererHash -or $receipt.runtimeSourceCommit -ne $source.runtimeSourceCommit -or $tuple.tuple.id -ne $source.tupleID -or $tuple.tuple.runtimeCommit -ne $source.runtimeSourceCommit -or $tuple.tuple.rendererHash -ne ('sha256:'+$RendererHash)){throw 'Issuer source/plan/receipt/tuple join mismatch'}
$at=[DateTimeOffset]::UtcNow.ToString('o');$runID=[Guid]::NewGuid().ToString('N')
function New-ID([string]$Prefix){$id=$Prefix+'/'+[Guid]::NewGuid().ToString('N');if($id -notmatch ('^'+$Prefix+'/[0-9a-f]{32}$')){throw 'Issuer canonical ID generation failed'};return $id}
$captures=@(1..$Count|ForEach-Object{[ordered]@{run=$_;captureID=(New-ID 'capture');imageID=(New-ID 'image');provenance=[ordered]@{sourceHash=$source.sourceHash;createdAt=$at;producer='factory/pipeline/pilot-next-source-v1/pilot-generic-capture-v1/circle/issue-metadata.ps1'};plannedHostIdentity='owned-renderer/'+$runID+'/'+$_;plannedClockIdentity='parent-monotonic-clock/'+$runID+'/'+$_;measuredHostIdentity=$null;measuredClockIdentity=$null;measurementStatus='pending-actual-launch-joins'}})
$metadata=[ordered]@{kind='factory-prelaunch-capture-metadata-v2';version=2;createdAt=$at;runID=$runID;runRoot=[IO.Path]::GetFullPath($RunRoot);expectedCount=$Count;case=[ordered]@{id=$source.caseID;hash=$source.caseHash};historicalTemplateTupleClosed=$false;recipe=(Ref $RecipePath $RecipeHash);plan=(Ref $PlanPath $PlanHash);sourceHash=$source.sourceHash;compile=(Ref $CompileReceiptPath $CompileReceiptHash);exe=(Ref $ExePath $ExeHash);renderer=(Ref $RendererPath $RendererHash);sourceBoundCandidateTuple=(Ref $BindingPath $BindingHash);candidateTuple=(Ref $TuplePath $TupleHash);candidateContext=$source.contextRef;producedRuntimeModules=$receipt.runtimeModules;serializerControlSha256=$SerializerHash;frozenTupleBound=$false;hostArguments=@('--factory-capture-lease-seconds=40');captures=$captures;qualification='sourceBoundCandidate-observation-only'}
$json=$metadata|ConvertTo-Json -Depth 30;$bytes=[Text.UTF8Encoding]::new($true).GetBytes($json);$stream=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
