# Pure binding & ordering gates; parent never loads UIAutomation.
function Assert-FactoryIntegrationSources([string]$Root){
 $bindings=Get-Content -Raw -LiteralPath (Join-Path $Root 'integration-bindings.json')|ConvertFrom-Json
 foreach($b in $bindings.files){
  $path=[IO.Path]::GetFullPath((Join-Path $Root $b.path))
  if(-not $path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $b.sha256){throw 'Integration source binding drift'}
 }
}
function Assert-FactorySnapshotReceipt($Proof,$Target,[string]$StdoutHash,[string]$StderrHash,[string]$UiaHash){
 Assert-UiaSnapshotWorkerProof $Proof $Target $StdoutHash $StderrHash $UiaHash
}
function Assert-FactorySnapshotReady($Result,$Target){
 $root=Split-Path -Parent $Result.workerReceiptPath
 if($Result.workerReceiptPath -cne (Join-Path $root 'worker-exit.json') -or $Result.snapshotPath -cne (Join-Path $root 'uia.json')){throw 'Exact worker receipt/snapshot paths required'}
 if((Get-FileHash -LiteralPath $Result.workerReceiptPath).Hash.ToLowerInvariant() -cne $Result.workerReceiptSha256){throw 'Worker receipt bytes drift'}
 $proof=Get-Content -Raw -LiteralPath $Result.workerReceiptPath|ConvertFrom-Json
 $stdoutHash=(Get-FileHash -LiteralPath (Join-Path $root 'stdout.bin')).Hash.ToLowerInvariant()
 $stderrHash=(Get-FileHash -LiteralPath (Join-Path $root 'stderr.bin')).Hash.ToLowerInvariant()
 $uiaHash=(Get-FileHash -LiteralPath $Result.snapshotPath).Hash.ToLowerInvariant()
 if($uiaHash -cne $Result.snapshotSha256){throw 'Worker snapshot bytes drift'}
 Invoke-FactorySnapshotReceiptAction $proof $Target $stdoutHash $stderrHash $uiaHash {}
 Assert-UiaSnapshotScalarObject (Get-Content -Raw -LiteralPath $Result.snapshotPath|ConvertFrom-Json)
}

function Invoke-FactorySnapshotReceiptAction($Proof,$Target,[string]$StdoutHash,[string]$StderrHash,[string]$UiaHash,[scriptblock]$Action){
 Assert-FactorySnapshotReceipt $Proof $Target $StdoutHash $StderrHash $UiaHash
 & $Action
}

function Assert-CandidateMetadataAdmission($Metadata,$Plan,[string]$CompileHash,[string]$ExeHash,$Tuple,$Candidate,$Context,[string]$TupleHash,[int]$Count,[scriptblock]$NativeWindowAction){
 if($Metadata.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $Metadata.version -ne 2 -or $Metadata.expectedCount -ne $Count -or $Metadata.frozenTupleBound -ne $false -or $Metadata.historicalTemplateTupleClosed -ne $false){throw 'candidate-guard:metadata'}
 if($Tuple.kind -cne 'factory-source-bound-candidate-canonical-tuple-v1' -or $Tuple.version -ne 1 -or $Tuple.frozenTupleBound -ne $false){throw 'candidate-guard:tuple-kind'}
 if($Tuple.case.id -cne $Plan.case.id -or $Tuple.case.hash -cne $Plan.case.hash){throw 'candidate-guard:case'}
 if($Tuple.tuple.id -cne $Context.candidateID -or $Context.candidateID -cne 'sr1-source-bound-r11-20261011'){throw 'candidate-guard:candidate-id'}
 if($Tuple.tuple.runtimeCommit -cne $Plan.runtimeSourceCommit -or $Candidate.runtime.sourceCommit -cne $Plan.runtimeSourceCommit){throw 'candidate-guard:runtime'}
 if($Tuple.tuple.rendererHash -cne ('sha256:'+$Plan.rendererSha256) -or $Candidate.renderer.sha256 -cne ('sha256:'+$Plan.rendererSha256)){throw 'candidate-guard:renderer'}
 if($Tuple.tuple.hostHashes.windows -cne ('sha256:'+$ExeHash) -or $Tuple.tuple.hostHashes.macos -cne 'sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777' -or $Tuple.tuple.acceptanceConfigHash -cne 'sha256:c12eaec44a65627e6f546925664482736bfede7665ab593024c5fcd401998245'){throw 'candidate-guard:host-envelope'}
 if($Candidate.kind -cne 'factory-source-bound-candidate-binding-v1' -or $Candidate.version -ne 1 -or $Candidate.frozenTupleBound -ne $false -or $Candidate.canonicalTupleRef.sha256 -cne $TupleHash -or $Metadata.candidateTuple.sha256 -cne $TupleHash){throw 'candidate-guard:tuple-ref'}
 if($null -eq $Tuple.sourceInputs.canonicalInputs -or $null -eq $Tuple.sourceInputs.sourceBinding -or @($Tuple.sourceInputs.psobject.Properties).Count -lt 3){throw 'candidate-guard:source-inputs'}
 if($NativeWindowAction){& $NativeWindowAction}
 return $true
}
function Assert-CandidatePhaseAdmission($Phase){
 if($Phase.phase -cne 'close-pending' -or $Phase.nativeWindowActions -ne 0 -or $Phase.compilerActions -ne 0){throw 'candidate-guard:phase'}
 return $true
}
function Assert-LeaseIssuedMetadata([string]$Path,[string]$Hash,[string]$RunRoot,[int]$Count,[string]$CompileHash,[string]$ExeHash,[string]$SerializerHash,[Parameter(Mandatory=$true)][string]$ProducerRoot){
 if($Hash -cnotmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant() -cne $Hash){throw 'Issued metadata raw hash mismatch'}
 $m=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json
 if($m.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $m.runRoot -cne $RunRoot -or $m.expectedCount -isnot [int] -and $m.expectedCount -isnot [long] -or $m.expectedCount -ne $Count -or $m.frozenTupleBound -isnot [bool] -or $m.frozenTupleBound -or $m.compile.sha256 -cne ('sha256:'+$CompileHash) -or $m.exe.sha256 -cne ('sha256:'+$ExeHash) -or $m.serializerControlSha256 -cne $SerializerHash -or @($m.hostArguments).Count -ne 1 -or $m.hostArguments[0] -cne '--factory-capture-lease-seconds=40'){throw 'Issued metadata admitted context mismatch'}
 $planPath=[IO.Path]::GetFullPath([string]$m.plan.path);$compiledPath=[IO.Path]::GetFullPath([string]$m.compile.path)
 $plan=Get-Content -Raw -LiteralPath $planPath|ConvertFrom-Json;$compiled=Get-Content -Raw -LiteralPath $compiledPath|ConvertFrom-Json
 if($m.sourceHash -cne $plan.sourceHash -or $m.case.id -cne $plan.case.id -or $m.case.hash -cne $plan.case.hash -or $m.historicalTemplateTupleClosed -isnot [bool] -or $m.historicalTemplateTupleClosed -or $m.qualification -cne 'sourceBoundCandidate-observation-only'){throw 'Issued metadata source/template boundary mismatch'}
 $tuplePath=Join-Path (Split-Path -Parent $Path) 'candidate-tuple.json';$candidatePath=Join-Path (Split-Path -Parent $Path) 'candidate-binding.json';$contextPath=[IO.Path]::GetFullPath([string]$m.candidateContext.path);$canonicalPath=$null;$sourceBindingPath=$null
 foreach($pair in @(@('plan',$planPath),@('compile',$compiledPath),@('exe',$compiled.exePath),@('renderer',$plan.rendererPath),@('recipe',$m.recipe.path),@('sourceBoundCandidateTuple',$candidatePath),@('candidateTuple',$tuplePath),@('candidateContext',$contextPath))){
  $ref=$m.($pair[0]);$required=$pair[1]
  if($ref.path -cne $required -or $ref.sha256 -cne ('sha256:'+(Get-FileHash -LiteralPath $required).Hash.ToLowerInvariant()) -or $ref.bytes -isnot [int] -and $ref.bytes -isnot [long] -or $ref.bytes -ne (Get-Item -LiteralPath $required).Length){throw 'Issued metadata exact raw reference mismatch'}
 }
 $tuple=Get-Content -Raw -LiteralPath $tuplePath|ConvertFrom-Json;$candidate=Get-Content -Raw -LiteralPath $candidatePath|ConvertFrom-Json;$context=Get-Content -Raw -LiteralPath $contextPath|ConvertFrom-Json;$canonicalPath=[IO.Path]::GetFullPath([string]$tuple.sourceInputs.canonicalInputs.path);$sourceBindingPath=[IO.Path]::GetFullPath([string]$tuple.sourceInputs.sourceBinding.path)
 Assert-CandidateMetadataAdmission $m $plan $CompileHash $ExeHash $tuple $candidate $context ('sha256:'+(Get-FileHash -LiteralPath $tuplePath).Hash.ToLowerInvariant()) $Count $null
 if($tuple.kind -cne 'factory-source-bound-candidate-canonical-tuple-v1' -or $tuple.version -ne 1 -or $tuple.frozenTupleBound -ne $false -or $tuple.case.id -cne $plan.case.id -or $tuple.case.hash -cne $plan.case.hash){throw 'Candidate tuple wrapper/case boundary mismatch'}
 if($tuple.tuple.runtimeCommit -cne $plan.runtimeSourceCommit -or $tuple.tuple.rendererHash -cne ('sha256:'+$plan.rendererSha256) -or $tuple.tuple.hostHashes.windows -cne ('sha256:'+$ExeHash) -or $tuple.tuple.hostHashes.macos -cne 'sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777' -or [string]::IsNullOrWhiteSpace($tuple.tuple.sdk) -or [string]::IsNullOrWhiteSpace($tuple.tuple.macosBuild) -or @($tuple.tuple.toolchains.psobject.Properties).Count -lt 1 -or $tuple.tuple.factoryVersion -ne '0.1-working-observation' -or $tuple.tuple.acceptanceConfigHash -ne 'sha256:c12eaec44a65627e6f546925664482736bfede7665ab593024c5fcd401998245'){throw 'Candidate tuple actual plan/exe/context join missing'}
 if($tuple.sourceInputs.canonicalInputs.path -cne $canonicalPath -or $tuple.sourceInputs.canonicalInputs.sha256 -cne ('sha256:'+(Get-FileHash -LiteralPath $canonicalPath).Hash.ToLowerInvariant()) -or $tuple.sourceInputs.sourceBinding.path -cne $sourceBindingPath -or $tuple.sourceInputs.sourceBinding.sha256 -cne ('sha256:'+(Get-FileHash -LiteralPath $sourceBindingPath).Hash.ToLowerInvariant())){throw 'Candidate tuple source inputs raw joins missing'}
 $repoRoot=[IO.Path]::GetFullPath($ProducerRoot);$context=Get-Content -Raw -LiteralPath $contextPath|ConvertFrom-Json
 foreach($row in @($context.macContext.sourceRefs)){ $key='macContext_'+(([IO.Path]::GetFileNameWithoutExtension($row.label)) -replace '[^A-Za-z0-9]','_');$ref=$tuple.sourceInputs.$key; if($null -eq $ref -or $ref.path -cne $row.path){throw ('Mac context source ref missing: '+$key)}; $refPath=[string]$ref.path;$resolved=if([IO.Path]::IsPathRooted($refPath)){[IO.Path]::GetFullPath($refPath)}else{[IO.Path]::GetFullPath((Join-Path $repoRoot ($refPath -replace '/','\')))};if(-not(Test-Path -LiteralPath $resolved -PathType Leaf) -or (Get-Item -LiteralPath $resolved).Length -ne $ref.bytes -or (Get-FileHash -LiteralPath $resolved).Hash.ToLowerInvariant() -cne $ref.sha256.Replace('sha256:','') -or $ref.sha256 -cne $row.sha256){throw ('Mac context raw join drift: '+$key)} }
 if($candidate.kind -cne 'factory-source-bound-candidate-binding-v1' -or $candidate.frozenTupleBound -ne $false -or $candidate.canonicalTupleRef.path -cne $tuplePath -or $candidate.canonicalTupleRef.sha256 -cne ('sha256:'+(Get-FileHash -LiteralPath $tuplePath).Hash.ToLowerInvariant()) -or $candidate.canonicalInputs.sha256 -cne ('sha256:'+(Get-FileHash -LiteralPath $canonicalPath).Hash.ToLowerInvariant()) -or $candidate.sourceBinding.sha256 -cne ('sha256:'+(Get-FileHash -LiteralPath $sourceBindingPath).Hash.ToLowerInvariant()) -or $candidate.runtime.sourceCommit -cne $plan.runtimeSourceCommit -or $candidate.renderer.sha256 -cne ('sha256:'+$plan.rendererSha256)){throw 'Candidate binding raw/source joins missing'}
 if(($m.producedRuntimeModules|ConvertTo-Json -Depth 16 -Compress) -cne ($compiled.runtimeModules|ConvertTo-Json -Depth 16 -Compress)){throw 'Issued actual runtime module metadata mismatch'}
 $rows=@($m.captures)
 if($rows.Count -ne $Count -or @($rows.captureID|Select-Object -Unique).Count -ne $Count -or @($rows.imageID|Select-Object -Unique).Count -ne $Count){throw 'Unique preallocated capture identities required'}
 for($i=1;$i -le $Count;$i++){
  $r=@($rows|Where-Object{$_.run -is [int] -or $_.run -is [long]}|Where-Object{$_.run -eq $i})
  if($r.Count -ne 1 -or $r[0].captureID -isnot [string] -or $r[0].captureID -cnotmatch '^[0-9a-f]{32}$' -or $r[0].imageID -isnot [string] -or $r[0].imageID -cnotmatch '^[0-9a-f]{32}$' -or $null -ne $r[0].measuredHostIdentity -or $null -ne $r[0].measuredClockIdentity -or $r[0].measurementStatus -cne 'pending-actual-launch-joins'){throw 'Planned identities must await measured launch joins'}
 }
 return $m
}

function Test-FactoryParentOrdering($Order){
 if($Order.kind -cne 'factory-isolated-uia-parent-ordering-v1' -or $Order.clockDomain -cne 'parent-process-local-stopwatch' -or $Order.crossProcessClockQualified -isnot [bool] -or $Order.crossProcessClockQualified){return $false}
 foreach($field in @('parentProcessID','frequency','workerVerifiedTicks','pixelsStartTicks','pixelsEndTicks','ownedCloseStartTicks')){if($Order.$field -isnot [int] -and $Order.$field -isnot [long] -or $Order.$field -le 0){return $false}}
 return [bool]($Order.workerVerifiedTicks -le $Order.pixelsStartTicks -and $Order.pixelsStartTicks -le $Order.pixelsEndTicks -and $Order.pixelsEndTicks -le $Order.ownedCloseStartTicks)
}
# v5 fresh Count20 overlay: retain frozen UIA/order/release helpers, replace candidate-specific guards.
$frozenCandidateAdmission=(Get-Item Function:\Assert-CandidateMetadataAdmission).ScriptBlock
$frozenLeaseAdmission=(Get-Item Function:\Assert-LeaseIssuedMetadata).ScriptBlock
function Fresh-Full([string]$p){[IO.Path]::GetFullPath($p)}
function Fresh-Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Fresh-Require([string]$p,[string]$hash,[string]$label){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ($label+' missing')};if((Fresh-Hash $p) -cne $hash.Replace('sha256:','').ToLowerInvariant()){throw ($label+' raw hash drift')}}
function Fresh-RefCheck($ref,[string]$label){if($null -eq $ref -or [string]::IsNullOrWhiteSpace($ref.path)){throw ($label+' ref missing')};Fresh-Require $ref.path $ref.sha256 $label;if([int64]$ref.bytes -ne [int64](Get-Item -LiteralPath $ref.path).Length){throw ($label+' byte count drift')}}
function Assert-CandidateMetadataAdmission($Metadata,$Plan,[string]$CompileHash,[string]$ExeHash,$Tuple,$Candidate,$Context,[string]$TupleHash,[int]$Count,[scriptblock]$NativeWindowAction){
 if($Count -eq 1 -or $Context.candidateID -eq 'sr1-source-bound-r11-20261011'){return & $frozenCandidateAdmission @PSBoundParameters}
 if($Count -ne 20){throw 'fresh candidate count mismatch'}
 if($Metadata.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $Metadata.version -ne 2 -or $Metadata.expectedCount -ne 20 -or $Metadata.frozenTupleBound -ne $false -or $Metadata.historicalTemplateTupleClosed -ne $false){throw 'fresh candidate metadata mismatch'}
 if($Tuple.kind -cne 'factory-source-bound-candidate-canonical-tuple-v1' -or $Tuple.version -ne 1 -or $Tuple.frozenTupleBound -ne $false -or $Tuple.candidateID -notmatch '^sr1-source-bound-r11-mac20-host-[0-9a-f]{12}-20261011$' -or $Context.candidateID -cne $Tuple.candidateID){throw 'fresh candidate tuple identity mismatch'}
 if($Tuple.case.id -notmatch '\.r11\.h[0-9a-f]{12}$' -or $Tuple.case.hash -notmatch '^sha256:[0-9a-f]{64}$' -or $Tuple.case.id -cne $Metadata.case.id -or $Tuple.case.hash -cne $Metadata.case.hash){throw 'fresh candidate case mismatch'}
 if($Tuple.tuple.hostHashes.windows -cne ('sha256:'+$ExeHash) -or $Tuple.tuple.hostHashes.macos -cne 'sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777' -or $Tuple.tuple.id -cne $Tuple.candidateID){throw 'fresh host envelope mismatch'}
 if($Candidate.kind -cne 'factory-source-bound-candidate-binding-v1' -or $Candidate.version -ne 1 -or $Candidate.frozenTupleBound -ne $false -or $Candidate.canonicalTupleRef.sha256 -ne $TupleHash -or $Metadata.candidateTuple.sha256 -ne $TupleHash){throw 'fresh tuple reference mismatch'}
 if($null -eq $Tuple.sourceInputs.canonicalInputs -or $null -eq $Tuple.sourceInputs.sourceBinding -or $null -eq $Tuple.sourceInputs.freshManifest -or $null -eq $Tuple.sourceInputs.freshCase -or $null -eq $Tuple.sourceInputs.sourceEquivalenceV4){throw 'fresh source input refs missing'}
 if($NativeWindowAction){& $NativeWindowAction};return $true
}
function Assert-LeaseIssuedMetadata([string]$Path,[string]$Hash,[string]$RunRoot,[int]$Count,[string]$CompileHash,[string]$ExeHash,[string]$SerializerHash,[Parameter(Mandatory=$true)][string]$ProducerRoot){
 if($Count -eq 1){return & $frozenLeaseAdmission @PSBoundParameters}
 if($Count -ne 20){throw 'fresh lease count mismatch'}
 Fresh-Require $Path $Hash 'Fresh issued metadata';$m=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json
 if($m.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $m.version -ne 2 -or $m.expectedCount -ne 20 -or $m.runRoot -cne $RunRoot -or $m.frozenTupleBound -ne $false -or $m.historicalTemplateTupleClosed -ne $false -or $m.case.id -notmatch '\.r11\.h[0-9a-f]{12}$' -or $m.case.hash -notmatch '^sha256:[0-9a-f]{64}$' -or $m.compile.sha256 -cne ('sha256:'+$CompileHash) -or $m.exe.sha256 -cne ('sha256:'+$ExeHash) -or $m.serializerControlSha256 -cne $SerializerHash -or @($m.hostArguments).Count -ne 1 -or $m.hostArguments[0] -cne '--factory-capture-lease-seconds=40'){throw 'Fresh issued metadata context mismatch'}
 foreach($x in @(@('recipe',$m.recipe),@('plan',$m.plan),@('compile',$m.compile),@('exe',$m.exe),@('renderer',$m.renderer),@('candidateTuple',$m.candidateTuple),@('sourceBoundCandidateTuple',$m.sourceBoundCandidateTuple),@('candidateContext',$m.candidateContext))){Fresh-RefCheck $x[1] $x[0]}
 $plan=Get-Content -Raw -LiteralPath $m.plan.path|ConvertFrom-Json;$receipt=Get-Content -Raw -LiteralPath $m.compile.path|ConvertFrom-Json;$tuple=Get-Content -Raw -LiteralPath $m.candidateTuple.path|ConvertFrom-Json;$candidate=Get-Content -Raw -LiteralPath $m.sourceBoundCandidateTuple.path|ConvertFrom-Json;$context=Get-Content -Raw -LiteralPath $m.candidateContext.path|ConvertFrom-Json
 if($receipt.exitCode -ne 0 -or $receipt.timedOut -eq $true -or $receipt.exeSha256 -ne $ExeHash -or $m.sourceHash -ne $receipt.sourceHash){throw 'Donor compiler receipt closure mismatch'}
 if($context.kind -cne 'factory-source-bound-fresh-r11-context-v1' -or $context.candidateID -cne $tuple.candidateID -or $context.case.id -cne $m.case.id -or $context.frozenTupleBound -ne $false){throw 'Fresh context wrapper mismatch'}
 foreach($r in @($context.freshCase,$context.freshManifest,$context.freshTuplePacket,$context.sourceEquivalenceV4)){Fresh-RefCheck $r 'Fresh context source'}
 $case=Get-Content -Raw -LiteralPath $context.freshCase.path|ConvertFrom-Json;$manifest=Get-Content -Raw -LiteralPath $context.freshManifest.path|ConvertFrom-Json;$eq=Get-Content -Raw -LiteralPath $context.sourceEquivalenceV4.path|ConvertFrom-Json
 if($case.id -cne $m.case.id -or $manifest.case.id -cne $m.case.id -or $manifest.case.hash -cne $m.case.hash -or $eq.status -cne 'reuse-admitted-source-equivalent-v4' -or $eq.candidateOnly -ne $true -or $eq.requirements.freshMetadata -ne $true -or $eq.requirements.freshCaptureIDs -ne $true -or $eq.requirements.historicalDonorRelabel -ne $false){throw 'Fresh case/manifest/equivalence mismatch'}
 if($tuple.tuple.runtimeCommit -ne $plan.runtimeSourceCommit -or $tuple.tuple.rendererHash -ne ('sha256:'+$plan.rendererSha256) -or $candidate.runtime.sourceCommit -ne $plan.runtimeSourceCommit -or $candidate.renderer.sha256 -ne ('sha256:'+$plan.rendererSha256)){throw 'Fresh runtime/renderer closure mismatch'}
 Assert-CandidateMetadataAdmission $m $plan $CompileHash $ExeHash $tuple $candidate $context ('sha256:'+(Fresh-Hash $m.candidateTuple.path)) $Count $null
 $rows=@($m.captures);if($rows.Count -ne 20 -or @($rows.captureID|Select-Object -Unique).Count -ne 20 -or @($rows.imageID|Select-Object -Unique).Count -ne 20){throw 'Fresh capture cardinality mismatch'}
 foreach($r in $rows){if($r.captureID -notmatch '^capture/[0-9a-f]{32}$' -or $r.imageID -notmatch '^image/[0-9a-f]{32}$' -or $r.measurementStatus -cne 'pending-actual-launch-joins'){throw 'Fresh prefixed capture identity mismatch'}}
 return $m
}
function Assert-FactoryIntegrationSources([string]$Root){
 $rootFull=[IO.Path]::GetFullPath($Root);$bindings=Get-Content -Raw -LiteralPath (Join-Path $rootFull 'integration-bindings.json')|ConvertFrom-Json
 foreach($b in $bindings.files){$path=[IO.Path]::GetFullPath((Join-Path $rootFull $b.path));if(-not $path.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $b.sha256){throw 'Fresh integration source binding drift'}}
}

# v6 donor/fresh closure: exact measured receipt fields, fresh refs, run-index joins.
$V6DonorPlanHash='ee83748cd42326e57676e47d8fec777bd8466706ba2c72a01eb9b5b71292de10'
$V6DonorReceiptHash='1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf'
$V6DonorSourceHash='b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b'
$V6DonorRuntimeCommit='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
$V6DonorRuntimeTreeHash='c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'
$V6DonorCompilerHash='1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'
$V6DonorRendererHash='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
$V6DonorExeHash='3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a'
$V6FreshCaseRawHash='f9a8e685f55c8063fde159bfb58926c637cd740fc8c6edb71de702933b7e3878'
$V6FreshCaseSemanticHash='037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de'
$V6FreshTuplePacketHash='bf5978000391687733885d3e49465e79e7727f374488cb359595a085113422c0'
$V6FreshManifestRawHash='e39db8b6d3844c6de9811eb5783564b49eb8556bc3cc854e79c3a36c61f8e9e0'
$V6FreshWitnessRawHash='e0cf14d63685c6f53721ff13ed9cba86c164beea0b13655bb64a9587f546c3f2'
$V6EquivalenceHash='aa8f39419292d2170b9036f6ee648bf8b71f9ca9ddcf6205d1a03ea0b2f2f34d'
$V6MacHostHash='13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777'
$V6TupleID='sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011'
$V6CaseID='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9'
$V6DonorCaseID='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258'
$V6DonorCaseHash='84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d'

function Assert-V6DonorReceipt($Receipt,$Plan,[string]$ExeHash,[string]$SourceHash){
 if($Receipt.kind -cne 'factory-padding-capture-lease-compile-only-owned-handle-v1' -or $Receipt.planSha256 -cne $V6DonorPlanHash -or $Receipt.sourceHash -cne ('sha256:'+$V6DonorSourceHash) -or $Receipt.runtimeSourceCommit -cne $V6DonorRuntimeCommit -or $Receipt.runtimeSourceTreeHash -cne ('sha256:'+$V6DonorRuntimeTreeHash) -or $Receipt.compilerHash -cne $V6DonorCompilerHash -or $Receipt.rendererSha256 -cne $V6DonorRendererHash){throw 'Donor compiler receipt source/runtime/compiler closure mismatch'}
 if($Receipt.exitCode -ne 0 -or $Receipt.timedOut -ne $false -or $Receipt.ownedExited -ne $true -or $Receipt.streamDrainComplete -ne $true -or $Receipt.nativeWindowOpened -ne $false -or $Receipt.exeSha256 -cne $V6DonorExeHash -or $Receipt.exeSha256 -cne $ExeHash -or $Receipt.sourceHash -cne $SourceHash){throw 'Donor compiler receipt outcome mismatch'}
 if($Plan.kind -cne 'windows-padding-capture-lease-source-plan' -or $Plan.executionEligible -ne $false -or $Plan.hostMode -cne 'renderer' -or $Plan.case.id -cne $V6DonorCaseID -or $Plan.case.hash -cne ('sha256:'+$V6DonorCaseHash) -or $Plan.sourceHash -cne ('sha256:'+$V6DonorSourceHash) -or $Plan.runtimeSourceCommit -cne $V6DonorRuntimeCommit -or $Plan.runtimeSourceTreeHash -ne ('sha256:'+$V6DonorRuntimeTreeHash) -or $Plan.compilerHash -cne $V6DonorCompilerHash -or $Plan.rendererSha256 -cne $V6DonorRendererHash){throw 'Donor plan closure mismatch'}
 if($Receipt.runtimeModules -isnot [array] -and $Receipt.runtimeModules -isnot [System.Collections.IEnumerable]){throw 'Donor runtime module closure missing'}
}
function Assert-V6FreshDocument($Case,$Manifest,$Tuple,$Equivalence){
 if($Case.kind -cne 'case' -or $Case.id -cne $V6CaseID -or $Case.provenance.sourceHash -cne ('sha256:fa97b8398b00bae018a187f80d8058a0955b340caa4cc6a4b34bb9eac9410bc6')){throw 'Fresh case identity/source mismatch'}
 if($Manifest.kind -cne 'generated-probe' -or $Manifest.case.id -cne $V6CaseID -or $Manifest.case.hash -cne ('sha256:'+$V6FreshCaseSemanticHash) -or $Manifest.sourceHash -cne ('sha256:'+$V6DonorSourceHash)){throw 'Fresh manifest identity/source mismatch'}
 if($Tuple.schema -cne 'factory-macos-r11-host-bound-candidate-tuple-v1' -or $Tuple.status -cne 'source-ready-native-pending' -or $Tuple.candidateID -cne $V6TupleID -or $Tuple.case.id -cne $V6CaseID -or $Tuple.case.hash -cne ('sha256:'+$V6FreshCaseSemanticHash) -or $Tuple.tuple.id -cne $V6TupleID -or $Tuple.tuple.hostHashes.macos -cne ('sha256:'+$V6MacHostHash) -or $Tuple.tuple.hostHashes.windows -cne ('sha256:'+$V6DonorExeHash) -or $Tuple.expectedTemplateMacHostHash -cne ('sha256:'+$V6MacHostHash) -or $Tuple.hostBuild.bytes -ne 9079 -or $Tuple.hostBuild.sha256 -ne 'sha256:ab38be841b62900958a63f9b7f83867e35420fe2410511303dfd9279393f6769'){throw 'Fresh tuple identity/host closure mismatch'}
 if($Equivalence.schema -cne 'factory-windows-r11-replay-admission-v4-equivalence' -or $Equivalence.status -cne 'reuse-admitted-source-equivalent-v4' -or $Equivalence.candidateOnly -ne $true -or $Equivalence.requirements.freshMetadata -ne $true -or $Equivalence.requirements.freshCaptureIDs -ne $true -or $Equivalence.requirements.historicalDonorRelabel -ne $false -or $Equivalence.actualReceipt.sha256 -ne ('sha256:'+$V6DonorReceiptHash) -or $Equivalence.actualReceipt.bytes -ne 17795){throw 'Fresh equivalence receipt boundary mismatch'}
 if($Equivalence.equivalence.freshManifest.sha256 -ne ('sha256:'+$V6FreshWitnessRawHash) -or $Equivalence.equivalence.freshManifest.bytes -ne 2406 -or $Equivalence.equivalence.compiledManifest.sha256 -ne 'sha256:0210e1c0ac73ac48528c3303d42f85f9506e99e3eef816e031f20138f705c629' -or $Equivalence.equivalence.compiledManifest.bytes -ne 1878){throw 'Fresh/donor witness closure mismatch'}
}
function Assert-CandidateMetadataAdmission($Metadata,$Plan,[string]$CompileHash,[string]$ExeHash,$Tuple,$Candidate,$Context,[string]$TupleHash,[int]$Count,[scriptblock]$NativeWindowAction){
 if($Count -eq 1 -or $Context.candidateID -eq 'sr1-source-bound-r11-20261011'){return & $frozenCandidateAdmission @PSBoundParameters}
 if($Count -ne 20){throw 'fresh candidate count mismatch'}
 if($Metadata.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $Metadata.version -ne 2 -or $Metadata.expectedCount -ne 20 -or $Metadata.frozenTupleBound -ne $false -or $Metadata.historicalTemplateTupleClosed -ne $false){throw 'fresh candidate metadata mismatch'}
 if($Tuple.kind -cne 'factory-source-bound-candidate-canonical-tuple-v1' -or $Tuple.version -ne 1 -or $Tuple.frozenTupleBound -ne $false -or $Tuple.candidateID -cne $V6TupleID -or $Context.candidateID -cne $V6TupleID){throw 'fresh candidate tuple identity mismatch'}
 if($Tuple.case.id -cne $V6CaseID -or $Tuple.case.hash -cne ('sha256:'+$V6FreshCaseSemanticHash) -or $Metadata.case.id -cne $V6CaseID -or $Metadata.case.hash -cne ('sha256:'+$V6FreshCaseSemanticHash)){throw 'fresh candidate case mismatch'}
 if($Tuple.tuple.hostHashes.windows -cne ('sha256:'+$V6DonorExeHash) -or $Tuple.tuple.hostHashes.macos -cne ('sha256:'+$V6MacHostHash) -or $Tuple.tuple.rendererHash -cne ('sha256:'+$V6DonorRendererHash) -or $Tuple.tuple.runtimeCommit -cne $V6DonorRuntimeCommit -or $Tuple.tuple.acceptanceConfigHash -cne 'sha256:c12eaec44a65627e6f546925664482736bfede7665ab593024c5fcd401998245'){throw 'fresh host/runtime envelope mismatch'}
 if($Candidate.kind -cne 'factory-source-bound-candidate-binding-v1' -or $Candidate.version -ne 1 -or $Candidate.frozenTupleBound -ne $false -or $Candidate.canonicalTupleRef.sha256 -cne $TupleHash -or $Metadata.candidateTuple.sha256 -cne $TupleHash){throw 'fresh tuple reference mismatch'}
 if($Candidate.canonicalInputs.sha256 -cne $Tuple.sourceInputs.canonicalInputs.sha256 -or $Candidate.sourceBinding.sha256 -cne $Tuple.sourceInputs.sourceBinding.sha256){throw 'fresh candidate binding source-input hash mismatch'}
 foreach($ref in @($Tuple.sourceInputs.canonicalInputs,$Tuple.sourceInputs.sourceBinding,$Tuple.sourceInputs.freshManifest,$Tuple.sourceInputs.freshCase,$Tuple.sourceInputs.sourceEquivalenceV4)){Fresh-RefCheck $ref 'fresh tuple source input'}
 foreach($join in @(@('freshManifest',$Context.freshManifest),@('freshCase',$Context.freshCase),@('sourceEquivalenceV4',$Context.sourceEquivalenceV4))){$tupleRef=$Tuple.sourceInputs.($join[0]);$contextRef=$join[1];if($null -eq $tupleRef -or $null -eq $contextRef -or $tupleRef.path -cne $contextRef.path -or $tupleRef.sha256 -cne $contextRef.sha256 -or [int64]$tupleRef.bytes -ne [int64]$contextRef.bytes){throw ('Mac context source ref mismatch: '+$join[0])}}
 if($NativeWindowAction){& $NativeWindowAction};return $true
}
function Assert-LeaseIssuedMetadata([string]$Path,[string]$Hash,[string]$RunRoot,[int]$Count,[string]$CompileHash,[string]$ExeHash,[string]$SerializerHash,[Parameter(Mandatory=$true)][string]$ProducerRoot){
 if($Count -eq 1){return & $frozenLeaseAdmission @PSBoundParameters}
 if($Count -ne 20){throw 'fresh lease count mismatch'}
 Fresh-Require $Path $Hash 'Fresh issued metadata';$m=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json
 if($m.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $m.version -ne 2 -or $m.expectedCount -ne 20 -or $m.runRoot -cne $RunRoot -or $m.frozenTupleBound -ne $false -or $m.historicalTemplateTupleClosed -ne $false -or $m.case.id -cne $V6CaseID -or $m.case.hash -cne ('sha256:'+$V6FreshCaseSemanticHash) -or $m.sourceHash -cne ('sha256:'+$V6DonorSourceHash) -or $m.compile.sha256 -cne ('sha256:'+$V6DonorReceiptHash) -or $m.exe.sha256 -cne ('sha256:'+$V6DonorExeHash) -or $CompileHash -cne $V6DonorReceiptHash -or $ExeHash -cne $V6DonorExeHash -or $m.serializerControlSha256 -cne $SerializerHash -or @($m.hostArguments).Count -ne 1 -or $m.hostArguments[0] -cne '--factory-capture-lease-seconds=40'){throw 'Fresh issued metadata context mismatch'}
 foreach($x in @(@('recipe',$m.recipe),@('plan',$m.plan),@('compile',$m.compile),@('exe',$m.exe),@('renderer',$m.renderer),@('candidateTuple',$m.candidateTuple),@('sourceBoundCandidateTuple',$m.sourceBoundCandidateTuple),@('candidateContext',$m.candidateContext))){Fresh-RefCheck $x[1] $x[0]}
 if((Fresh-Hash $m.plan.path) -cne $V6DonorPlanHash -or (Fresh-Hash $m.compile.path) -cne $V6DonorReceiptHash -or (Fresh-Hash $m.exe.path) -cne $V6DonorExeHash){throw 'Actual donor closure hash mismatch'}
 $plan=Get-Content -Raw -LiteralPath $m.plan.path|ConvertFrom-Json;$receipt=Get-Content -Raw -LiteralPath $m.compile.path|ConvertFrom-Json;$tuple=Get-Content -Raw -LiteralPath $m.candidateTuple.path|ConvertFrom-Json;$candidate=Get-Content -Raw -LiteralPath $m.sourceBoundCandidateTuple.path|ConvertFrom-Json;$context=Get-Content -Raw -LiteralPath $m.candidateContext.path|ConvertFrom-Json
 Assert-V6DonorReceipt $receipt $plan $ExeHash ('sha256:'+$V6DonorSourceHash)
 if($receipt.exePath -and $receipt.exePath -cne $m.exe.path){throw 'Donor executable path mismatch'}
 if($m.recipe.sha256 -ne ('sha256:'+$V6FreshManifestRawHash)){throw 'Fresh recipe raw hash mismatch'}
 foreach($r in @($context.freshCase,$context.freshManifest,$context.freshTuplePacket,$context.sourceEquivalenceV4)){Fresh-RefCheck $r 'fresh context source'}
 if((Fresh-Hash $context.freshCase.path) -ne $V6FreshCaseRawHash -or (Fresh-Hash $context.freshTuplePacket.path) -ne $V6FreshTuplePacketHash -or (Fresh-Hash $context.sourceEquivalenceV4.path) -ne $V6EquivalenceHash){throw 'Fresh source packet raw hash mismatch'}
 $case=Get-Content -Raw -LiteralPath $context.freshCase.path|ConvertFrom-Json;$manifest=Get-Content -Raw -LiteralPath $context.freshManifest.path|ConvertFrom-Json;$packet=Get-Content -Raw -LiteralPath $context.freshTuplePacket.path|ConvertFrom-Json;$eq=Get-Content -Raw -LiteralPath $context.sourceEquivalenceV4.path|ConvertFrom-Json
 Assert-V6FreshDocument $case $manifest $packet $eq
 if($context.kind -cne 'factory-source-bound-fresh-r11-context-v1' -or $context.candidateID -cne $V6TupleID -or $context.case.id -cne $V6CaseID -or $context.case.hash -cne ('sha256:'+$V6FreshCaseSemanticHash) -or $context.frozenTupleBound -ne $false){throw 'Fresh context wrapper mismatch'}
 if($tuple.tuple.runtimeCommit -ne $V6DonorRuntimeCommit -or $tuple.tuple.rendererHash -ne ('sha256:'+$V6DonorRendererHash) -or $tuple.tuple.hostHashes.windows -ne ('sha256:'+$V6DonorExeHash) -or $tuple.tuple.hostHashes.macos -ne ('sha256:'+$V6MacHostHash)){throw 'Fresh runtime/renderer/host closure mismatch'}
 if(($m.producedRuntimeModules|ConvertTo-Json -Depth 32 -Compress) -cne ($receipt.runtimeModules|ConvertTo-Json -Depth 32 -Compress)){throw 'Issued actual runtime module metadata mismatch'}
 Assert-CandidateMetadataAdmission $m $plan $CompileHash $ExeHash $tuple $candidate $context ('sha256:'+(Fresh-Hash $m.candidateTuple.path)) $Count $null
 $rows=@($m.captures);if($rows.Count -ne 20 -or @($rows.captureID|Select-Object -Unique).Count -ne 20 -or @($rows.imageID|Select-Object -Unique).Count -ne 20){throw 'Fresh capture cardinality mismatch'}
 for($i=1;$i -le 20;$i++){ $r=@($rows|Where-Object{$_.run -eq $i});if($r.Count -ne 1 -or $r[0].captureID -notmatch '^capture/[0-9a-f]{32}$' -or $r[0].imageID -notmatch '^image/[0-9a-f]{32}$' -or $r[0].measurementStatus -cne 'pending-actual-launch-joins'){throw ('Fresh capture run index/identity mismatch: '+$i)} }
 return $m
}
function Assert-FactoryIntegrationSources([string]$Root){
 $rootFull=[IO.Path]::GetFullPath($Root);$bindings=Get-Content -Raw -LiteralPath (Join-Path $rootFull 'integration-bindings.json')|ConvertFrom-Json
 foreach($b in $bindings.files){$path=[IO.Path]::GetFullPath((Join-Path $rootFull $b.path));if(-not $path.StartsWith($rootFull+'\',[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $b.sha256){throw 'Fresh integration source binding drift'}}
}
