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

function Assert-LeaseIssuedMetadata([string]$Path,[string]$Hash,[string]$RunRoot,[int]$Count,[string]$CompileHash,[string]$ExeHash,[string]$SerializerHash){
 if($Hash -cnotmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant() -cne $Hash){throw 'Issued metadata raw hash mismatch'}
 $m=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json
 if($m.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $m.runRoot -cne $RunRoot -or $m.expectedCount -isnot [int] -and $m.expectedCount -isnot [long] -or $m.expectedCount -ne $Count -or $m.frozenTupleBound -isnot [bool] -or $m.frozenTupleBound -or $m.compile.sha256 -cne ('sha256:'+$CompileHash) -or $m.exe.sha256 -cne ('sha256:'+$ExeHash) -or $m.serializerControlSha256 -cne $SerializerHash -or @($m.hostArguments).Count -ne 1 -or $m.hostArguments[0] -cne '--factory-capture-lease-seconds=40'){throw 'Issued metadata admitted context mismatch'}
 $builder='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis'
 $planPath=Join-Path $builder 'package\plan.json';$compiledPath=Join-Path $builder 'package\build-capture-lease-r1\observation.json'
 $plan=Get-Content -Raw -LiteralPath $planPath|ConvertFrom-Json;$compiled=Get-Content -Raw -LiteralPath $compiledPath|ConvertFrom-Json
 if($m.sourceHash -cne $plan.sourceHash -or $m.case.id -cne $plan.case.id -or $m.case.hash -cne $plan.case.hash -or $m.historicalTemplateTupleClosed -isnot [bool] -or $m.historicalTemplateTupleClosed -or $m.qualification -cne 'sourceBoundCandidate-observation-only'){throw 'Issued metadata source/template boundary mismatch'}
 $tuplePath=Join-Path (Split-Path -Parent $Path) 'candidate-tuple.json';$candidatePath=Join-Path (Split-Path -Parent $Path) 'candidate-binding.json';$contextPath=Join-Path $PSScriptRoot 'candidate-context.json';$canonicalPath='D:\Claude\swiftright\factory\native\windows\canonical-inputs-v1\manifest.json';$sourceBindingPath=Join-Path $builder 'metadata\source-binding.json'
 foreach($pair in @(@('plan',$planPath),@('compile',$compiledPath),@('exe',$compiled.exePath),@('renderer',$plan.rendererPath),@('recipe',(Join-Path $builder 'package\witness.manifest.json')),@('sourceBoundCandidateTuple',$candidatePath),@('candidateTuple',$tuplePath),@('candidateContext',$contextPath))){
  $ref=$m.($pair[0]);$required=$pair[1]
  if($ref.path -cne $required -or $ref.sha256 -cne ('sha256:'+(Get-FileHash -LiteralPath $required).Hash.ToLowerInvariant()) -or $ref.bytes -isnot [int] -and $ref.bytes -isnot [long] -or $ref.bytes -ne (Get-Item -LiteralPath $required).Length){throw 'Issued metadata exact raw reference mismatch'}
 }
 $tuple=Get-Content -Raw -LiteralPath $tuplePath|ConvertFrom-Json;$candidate=Get-Content -Raw -LiteralPath $candidatePath|ConvertFrom-Json
 if($tuple.kind -cne 'factory-source-bound-candidate-canonical-tuple-v1' -or $tuple.version -ne 1 -or $tuple.frozenTupleBound -ne $false -or $tuple.case.id -cne $plan.case.id -or $tuple.case.hash -cne $plan.case.hash){throw 'Candidate tuple wrapper/case boundary mismatch'}
 if($tuple.tuple.runtimeCommit -cne $plan.runtimeSourceCommit -or $tuple.tuple.rendererHash -cne ('sha256:'+$plan.rendererSha256) -or $tuple.tuple.hostHashes.windows -cne ('sha256:'+$ExeHash) -or $tuple.tuple.hostHashes.macos -notmatch '^sha256:[0-9a-f]{64}$' -or [string]::IsNullOrWhiteSpace($tuple.tuple.sdk) -or [string]::IsNullOrWhiteSpace($tuple.tuple.macosBuild) -or @($tuple.tuple.toolchains.psobject.Properties).Count -lt 1 -or $tuple.tuple.factoryVersion -ne '0.1-working-observation' -or $tuple.tuple.acceptanceConfigHash -notmatch '^sha256:[0-9a-f]{64}$'){throw 'Candidate tuple actual plan/exe/context join missing'}
 if($tuple.sourceInputs.canonicalInputs.path -cne $canonicalPath -or $tuple.sourceInputs.canonicalInputs.sha256 -cne ('sha256:'+(Get-FileHash -LiteralPath $canonicalPath).Hash.ToLowerInvariant()) -or $tuple.sourceInputs.sourceBinding.path -cne $sourceBindingPath -or $tuple.sourceInputs.sourceBinding.sha256 -cne ('sha256:'+(Get-FileHash -LiteralPath $sourceBindingPath).Hash.ToLowerInvariant())){throw 'Candidate tuple source inputs raw joins missing'}
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
