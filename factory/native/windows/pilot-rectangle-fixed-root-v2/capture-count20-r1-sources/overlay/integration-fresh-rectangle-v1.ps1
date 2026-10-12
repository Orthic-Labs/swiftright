# Generic Rectangle integration guard. It accepts measured source references only.
function Get-RectangleFull([string]$Path){[IO.Path]::GetFullPath($Path)}
function Get-RectangleHash([string]$Path){
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.LinkType -or $item.Length -gt 67108864){throw 'Integration reference must be bounded regular file'}
 return (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-RectangleJson([string]$Path){$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if($item.PSIsContainer -or $item.LinkType -or $item.Length -gt 2097152){throw 'Integration JSON must be bounded regular file'};return (Get-Content -Raw -LiteralPath $item.FullName|ConvertFrom-Json)}
function Assert-RectangleRef($Ref,[string]$Name){
 if($null -eq $Ref -or [string]::IsNullOrWhiteSpace([string]$Ref.path) -or [string]$Ref.sha256 -notmatch '^sha256:[0-9a-f]{64}$'){throw "$Name reference incomplete"}
 $path=Get-RectangleFull ([string]$Ref.path)
 if((Get-RectangleHash $path) -cne $Ref.sha256.Substring(7) -or (Get-Item -LiteralPath $path).Length -ne [int64]$Ref.bytes){throw "$Name reference drift"}
 return $path
}
function Assert-RectangleContextIdentity($Context,[object]$SourceInputs,[object]$Tuple){
 $tupleID=if($Context.PSObject.Properties.Name -contains 'tupleID'){$Context.tupleID}elseif($Context.tupleContext -and $Context.tupleContext.PSObject.Properties.Name -contains 'tupleID'){$Context.tupleContext.tupleID}else{$null}
 $sourceHash=if($Context.PSObject.Properties.Name -contains 'sourceHash'){$Context.sourceHash}elseif($Context.sourceBinding -and $Context.sourceBinding.PSObject.Properties.Name -contains 'sourceHash'){$Context.sourceBinding.sourceHash}else{$null}
 $caseID=if($Context.PSObject.Properties.Name -contains 'caseID'){$Context.caseID}elseif($Context.case -and $Context.case.PSObject.Properties.Name -contains 'id'){$Context.case.id}elseif($Context.sourceBinding -and $Context.sourceBinding.PSObject.Properties.Name -contains 'caseID'){$Context.sourceBinding.caseID}else{$null}
 $caseHash=if($Context.PSObject.Properties.Name -contains 'caseHash'){$Context.caseHash}elseif($Context.case -and $Context.case.PSObject.Properties.Name -contains 'hash'){$Context.case.hash}elseif($Context.sourceBinding -and $Context.sourceBinding.PSObject.Properties.Name -contains 'caseHash'){$Context.sourceBinding.caseHash}else{$null}
 $macHash=if($Context.PSObject.Properties.Name -contains 'macHostHash'){$Context.macHostHash}elseif($Context.PSObject.Properties.Name -contains 'macosHostHash'){$Context.macosHostHash}elseif($Context.tupleContext -and $Context.tupleContext.PSObject.Properties.Name -contains 'macosHostHash'){$Context.tupleContext.macosHostHash}else{$null}
 $winHash=if($Context.PSObject.Properties.Name -contains 'windowsHostHash'){$Context.windowsHostHash}elseif($Context.tupleContext -and $Context.tupleContext.PSObject.Properties.Name -contains 'windowsHostHash'){$Context.tupleContext.windowsHostHash}else{$null}
 if([string]::IsNullOrWhiteSpace([string]$tupleID) -or [string]::IsNullOrWhiteSpace([string]$sourceHash) -or [string]::IsNullOrWhiteSpace([string]$caseID) -or [string]::IsNullOrWhiteSpace([string]$caseHash) -or [string]::IsNullOrWhiteSpace([string]$macHash) -or [string]::IsNullOrWhiteSpace([string]$winHash)){throw 'Rectangle context identity incomplete'}
 if($tupleID -cne $SourceInputs.tupleID -or $sourceHash -cne $SourceInputs.sourceHash -or $caseID -cne $SourceInputs.caseID -or $caseHash -cne $SourceInputs.caseHash -or $macHash -cne $Tuple.tuple.hostHashes.macos -or $winHash -ne $Tuple.tuple.hostHashes.windows){throw 'Rectangle context closure mismatch'}
 if($Context.tupleContext -and $Context.tupleContext.runtimeCommit -and $Context.tupleContext.runtimeCommit -cne $SourceInputs.runtimeSourceCommit){throw 'Rectangle context runtime mismatch'}
 if($Context.tupleContext -and $Context.tupleContext.rendererHash -and $Context.tupleContext.rendererHash -ne ('sha256:'+$SourceInputs.rendererSha256)){throw 'Rectangle context renderer mismatch'}
 return $true
}
function Assert-FactoryIntegrationSources([string]$Root,[object]$SourceInputs){
 if(($SourceInputs.kind -eq 'factory-rectangle-source-inputs-v1' -and $SourceInputs.count -ne 1) -or ($SourceInputs.kind -eq 'factory-rectangle-source-inputs-v2' -and $SourceInputs.count -ne 20) -or $SourceInputs.kind -notin @('factory-rectangle-source-inputs-v1','factory-rectangle-source-inputs-v2')){throw 'Rectangle source input kind/count mismatch'}
 foreach($field in @('caseID','caseHash','sourceHash','tupleID','planHash','compileReceiptHash','tupleHash','bindingHash','recipeHash','exeHash','runtimeSourceCommit','rendererPath','rendererSha256','serializerControlSha256','contextRef','integrationBindingsRef','integrationBindingsHash','rendererRef','exeRef')){if([string]::IsNullOrWhiteSpace([string]$SourceInputs.$field)){throw "Rectangle source field missing: $field"}}
 $planPath=Assert-RectangleRef $SourceInputs.planRef 'plan'
 $receiptPath=Assert-RectangleRef $SourceInputs.compileRef 'compile receipt'
 $tuplePath=Assert-RectangleRef $SourceInputs.tupleRef 'tuple'
 $bindingPath=Assert-RectangleRef $SourceInputs.bindingRef 'candidate binding'
 $recipePath=Assert-RectangleRef $SourceInputs.recipeRef 'recipe'
 $serializerPath=Assert-RectangleRef $SourceInputs.serializerRef 'serializer'
 $integrationBindingsPath=Assert-RectangleRef $SourceInputs.integrationBindingsRef 'integration bindings'
 $exePath=Assert-RectangleRef $SourceInputs.exeRef 'executable'
 $rendererPath=Assert-RectangleRef $SourceInputs.rendererRef 'renderer'
 $contextPath=Assert-RectangleRef $SourceInputs.contextRef 'context'
 if($SourceInputs.planRef.sha256 -cne ('sha256:'+$SourceInputs.planHash) -or $SourceInputs.compileRef.sha256 -cne ('sha256:'+$SourceInputs.compileReceiptHash) -or $SourceInputs.tupleRef.sha256 -cne ('sha256:'+$SourceInputs.tupleHash) -or $SourceInputs.bindingRef.sha256 -cne ('sha256:'+$SourceInputs.bindingHash) -or $SourceInputs.recipeRef.sha256 -cne ('sha256:'+$SourceInputs.recipeHash) -or $SourceInputs.exeRef.sha256 -cne ('sha256:'+$SourceInputs.exeHash) -or $SourceInputs.serializerRef.sha256 -cne ('sha256:'+$SourceInputs.serializerControlSha256) -or $SourceInputs.rendererRef.sha256 -cne ('sha256:'+$SourceInputs.rendererSha256) -or $SourceInputs.integrationBindingsRef.sha256 -cne ('sha256:'+$SourceInputs.integrationBindingsHash)){throw 'Rectangle source reference/hash join mismatch'}
 $plan=Get-RectangleJson $planPath
 $receipt=Get-RectangleJson $receiptPath
 $tuple=Get-RectangleJson $tuplePath
 $binding=Get-RectangleJson $bindingPath
 if($plan.kind -ne 'factory-rectangle-compiler-plan-v2' -or $plan.case.id -cne $SourceInputs.caseID -or $plan.case.hash -cne $SourceInputs.caseHash -or $plan.sourceHash -cne $SourceInputs.sourceHash -or $plan.tuple.id -cne $SourceInputs.tupleID -or $plan.runtimeSourceCommit -ne $SourceInputs.runtimeSourceCommit -or $plan.rendererPath -ne $SourceInputs.rendererPath -or $plan.rendererSha256 -ne $SourceInputs.rendererSha256){throw 'Rectangle plan/source/tuple join mismatch'}
 if($receipt.kind -ne 'factory-rectangle-owned-compile-v1' -or $receipt.exitCode -ne 0 -or $receipt.streamsSealed -ne $true -or $receipt.streamDrainComplete -ne $true -or $receipt.originalHandleRetained -ne $true -or $receipt.jobActiveCount -ne 0 -or $receipt.kernelWait -ne 0 -or $receipt.ownedExited -ne $true -or $receipt.sourceHash -ne $SourceInputs.sourceHash -or $receipt.planSha256 -ne $SourceInputs.planHash -or $receipt.exeSha256 -ne $SourceInputs.exeHash -or $receipt.rendererSha256 -ne $SourceInputs.rendererSha256 -or $receipt.runtimeSourceCommit -ne $SourceInputs.runtimeSourceCommit){throw 'Rectangle compile receipt closure mismatch'}
 if($tuple.kind -ne 'factory-source-bound-candidate-canonical-tuple-v1' -or $tuple.frozenTupleBound -ne $false -or $tuple.case.id -cne $SourceInputs.caseID -or $tuple.case.hash -cne $SourceInputs.caseHash -or $tuple.tuple.id -cne $SourceInputs.tupleID -or $tuple.tuple.hostHashes.windows -ne ('sha256:'+$SourceInputs.exeHash) -or $tuple.tuple.runtimeCommit -ne $SourceInputs.runtimeSourceCommit -or $tuple.tuple.rendererHash -ne ('sha256:'+$SourceInputs.rendererSha256)){throw 'Rectangle tuple closure mismatch'}
 if($binding.kind -ne 'factory-source-bound-candidate-binding-v1' -or $binding.frozenTupleBound -ne $false -or $binding.canonicalTupleRef.sha256 -ne ('sha256:'+(Get-RectangleHash $tuplePath))){throw 'Rectangle binding closure mismatch'}
 $context=Get-RectangleJson $contextPath
 Assert-RectangleContextIdentity $context $SourceInputs $tuple|Out-Null
 if($plan.recipeRef -and ($plan.recipeRef.path -ne $SourceInputs.recipeRef.path -or $plan.recipeRef.sha256 -ne $SourceInputs.recipeRef.sha256 -or [int64]$plan.recipeRef.bytes -ne [int64]$SourceInputs.recipeRef.bytes)){throw 'Rectangle recipe reference mismatch'}
 if($binding.canonicalTupleRef.path -and ($binding.canonicalTupleRef.path -ne $SourceInputs.tupleRef.path -or $binding.canonicalTupleRef.sha256 -ne $SourceInputs.tupleRef.sha256 -or [int64]$binding.canonicalTupleRef.bytes -ne [int64]$SourceInputs.tupleRef.bytes)){throw 'Rectangle binding tuple reference mismatch'}
 $bindings=Get-RectangleJson $integrationBindingsPath
 if(@($bindings.files).Count -lt 23){throw 'Rectangle integration binding manifest incomplete'}
 $bindingNames=@{};foreach($entry in @($bindings.files)){if([string]::IsNullOrWhiteSpace([string]$entry.path) -or [IO.Path]::IsPathRooted([string]$entry.path) -or [string]$entry.path -match '(^|[\\/])\.\.([\\/]|$)' -or $entry.sha256 -notmatch '^[0-9a-f]{64}$' -or $entry.bytes -lt 0){throw 'Rectangle integration binding row invalid'};$candidate=[IO.Path]::GetFullPath((Join-Path $Root ([string]$entry.path)));if(-not $candidate.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase) -or $bindingNames.ContainsKey($candidate)){throw 'Rectangle integration binding path invalid'};if((Get-Item -LiteralPath $candidate -Force).Length -ne [int64]$entry.bytes -or (Get-RectangleHash $candidate) -cne [string]$entry.sha256){throw 'Rectangle integration binding drift'};$bindingNames[$candidate]=$true}
 if($SourceInputs.captures){$rows=@($SourceInputs.captures);if($rows.Count -ne $SourceInputs.count -or @($rows.captureID|Select-Object -Unique).Count -ne $rows.Count -or @($rows.imageID|Select-Object -Unique).Count -ne $rows.Count){throw 'Rectangle capture identity cardinality mismatch'};foreach($row in $rows){if([string]$row.captureID -notmatch '^capture/[0-9a-f]{32}$' -or [string]$row.imageID -notmatch '^image/[0-9a-f]{32}$'){throw 'Rectangle capture identity format mismatch'}}}
 [void]$serializerPath
 return $true
}
function Assert-FactorySnapshotReceipt($Proof,$Target,[string]$StdoutHash,[string]$StderrHash,[string]$UiaHash){Assert-UiaSnapshotWorkerProof $Proof $Target $StdoutHash $StderrHash $UiaHash}
function Assert-FactorySnapshotReady($Result,$Target){
 $root=Split-Path -Parent $Result.workerReceiptPath
 if($Result.workerReceiptPath -cne (Join-Path $root 'worker-exit.json') -or $Result.snapshotPath -cne (Join-Path $root 'uia.json')){throw 'Exact worker receipt/snapshot paths required'}
 if((Get-FileHash -LiteralPath $Result.workerReceiptPath).Hash.ToLowerInvariant() -cne $Result.workerReceiptSha256){throw 'Worker receipt bytes drift'}
 $proof=Get-Content -Raw -LiteralPath $Result.workerReceiptPath|ConvertFrom-Json
 $stdoutHash=(Get-FileHash -LiteralPath (Join-Path $root 'stdout.bin')).Hash.ToLowerInvariant();$stderrHash=(Get-FileHash -LiteralPath (Join-Path $root 'stderr.bin')).Hash.ToLowerInvariant();$uiaHash=(Get-FileHash -LiteralPath $Result.snapshotPath).Hash.ToLowerInvariant()
 if($uiaHash -cne $Result.snapshotSha256){throw 'Worker snapshot bytes drift'}
 Invoke-FactorySnapshotReceiptAction $proof $Target $stdoutHash $stderrHash $uiaHash {}
 Assert-UiaSnapshotScalarObject (Get-Content -Raw -LiteralPath $Result.snapshotPath|ConvertFrom-Json)
}
function Invoke-FactorySnapshotReceiptAction($Proof,$Target,[string]$StdoutHash,[string]$StderrHash,[string]$UiaHash,[scriptblock]$Action){Assert-FactorySnapshotReceipt $Proof $Target $StdoutHash $StderrHash $UiaHash;& $Action}
function Assert-CandidatePhaseAdmission($Phase){if($Phase.phase -cne 'close-pending' -or $Phase.nativeWindowActions -ne 0 -or $Phase.compilerActions -ne 0){throw 'candidate-guard:phase'};return $true}
function Assert-LeaseIssuedMetadata([string]$Path,[string]$Hash,[string]$RunRoot,[int]$Count,[string]$CompileHash,[string]$ExeHash,[string]$SerializerHash,[string]$ProducerRoot,[object]$SourceInputs){
 if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Rectangle issued metadata missing'}
 if((Get-RectangleHash $Path) -cne $Hash){throw 'Rectangle issued metadata hash drift'}
 $issued=Get-RectangleJson $Path
 if($issued.kind -ne 'factory-prelaunch-capture-metadata-v2' -or $issued.version -ne 2 -or $issued.expectedCount -ne $Count -or $issued.runRoot -cne ([IO.Path]::GetFullPath($RunRoot))){throw 'Rectangle issued metadata envelope mismatch'}
 $contextPath=Assert-RectangleRef $SourceInputs.contextRef 'context'
 $context=Get-RectangleJson $contextPath
 $issuedTuple=Get-RectangleJson (Assert-RectangleRef $SourceInputs.tupleRef 'tuple')
 Assert-RectangleContextIdentity $context $SourceInputs $issuedTuple|Out-Null
 if($issued.case.id -cne $SourceInputs.caseID -or $issued.case.hash -cne $SourceInputs.caseHash -or $issued.sourceHash -cne $SourceInputs.sourceHash -or $issued.frozenTupleBound -ne $false -or ($issued.candidateContext|ConvertTo-Json -Compress) -cne ($SourceInputs.contextRef|ConvertTo-Json -Compress)){throw 'Rectangle issued metadata context mismatch'}
 if($issued.compile.sha256 -ne ('sha256:'+$CompileHash) -or $issued.exe.sha256 -ne ('sha256:'+$ExeHash) -or $issued.serializerControlSha256 -ne $SerializerHash){throw 'Rectangle issued metadata build join mismatch'}
 foreach($ref in @(@{name='plan';value=$issued.plan},@{name='compile';value=$issued.compile},@{name='exe';value=$issued.exe},@{name='renderer';value=$issued.renderer},@{name='tuple';value=$issued.candidateTuple},@{name='binding';value=$issued.sourceBoundCandidateTuple},@{name='recipe';value=$issued.recipe})){
  [void](Assert-RectangleRef $ref.value $ref.name)
 }
 foreach($join in @(@{name='plan';issued=$issued.plan;source=$SourceInputs.planRef},@{name='compile';issued=$issued.compile;source=$SourceInputs.compileRef},@{name='exe';issued=$issued.exe;source=$SourceInputs.exeRef},@{name='tuple';issued=$issued.candidateTuple;source=$SourceInputs.tupleRef},@{name='binding';issued=$issued.sourceBoundCandidateTuple;source=$SourceInputs.bindingRef},@{name='recipe';issued=$issued.recipe;source=$SourceInputs.recipeRef},@{name='renderer';issued=$issued.renderer;source=$SourceInputs.rendererRef})){if($null -eq $join.source -or $join.issued.path -cne $join.source.path -or $join.issued.sha256 -cne $join.source.sha256 -or [int64]$join.issued.bytes -ne [int64]$join.source.bytes){throw ('Rectangle issued '+$join.name+' reference mismatch')}}
 $rows=@($issued.captures);if($rows.Count -ne $Count){throw 'Rectangle issued capture count mismatch'}
 $seen=@{};for($i=0;$i -lt $rows.Count;$i++){$row=$rows[$i];if($row.run -ne ($i+1) -or [string]$row.captureID -notmatch '^capture/[0-9a-f]{32}$' -or [string]$row.imageID -notmatch '^image/[0-9a-f]{32}$' -or $seen.ContainsKey([string]$row.captureID) -or $seen.ContainsKey([string]$row.imageID)){throw 'Rectangle issued capture identity mismatch'};$seen[[string]$row.captureID]=$true;$seen[[string]$row.imageID]=$true;if($row.provenance.sourceHash -cne $SourceInputs.sourceHash){throw 'Rectangle issued capture source join mismatch'}}
 return $issued
}
