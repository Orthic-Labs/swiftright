# Source-bound diagnostic profile; pure validation only.
$CircleCompiledPackagePath='D:\Claude\swiftright\.factory-work\hosts\circle\package'
function GetCircleCompiledPackage{return [IO.Path]::GetFullPath($CircleCompiledPackagePath)}
function Get-DiagnosticFull([string]$Path){[IO.Path]::GetFullPath($Path)}
function Assert-CircleNestedRunRoot([string]$OutputRoot,[string]$RunRoot){
 $out=[IO.Path]::GetFullPath($OutputRoot);$run=[IO.Path]::GetFullPath($RunRoot)
 if($out.Length -gt 3){$out=$out.TrimEnd([char]92)};if($run.Length -gt 3){$run=$run.TrimEnd([char]92)}
 if([string]::IsNullOrWhiteSpace($out) -or [string]::IsNullOrWhiteSpace($run)){throw 'Circle output/run root required'}
 if($run -ieq $out){throw 'Circle run root must be strictly nested'}
 if(-not $run.StartsWith($out+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Circle run root outside fresh output namespace'}
 return $run
}
function Get-DiagnosticItem([string]$Path,[int64]$Max=67108864){$i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $i.Length -gt $Max){throw 'Diagnostic reference is not bounded regular file'};return $i}
function Get-DiagnosticHash([string]$Path,[int64]$Max=67108864){$i=Get-DiagnosticItem $Path $Max;return (Get-FileHash -LiteralPath $i.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-DiagnosticJson([string]$Path){$i=Get-DiagnosticItem $Path 2097152;return (Get-Content -LiteralPath $i.FullName -Raw|ConvertFrom-Json)}
function Assert-DiagnosticRef([object]$Ref,[string]$Name){if($null -eq $Ref -or [string]::IsNullOrWhiteSpace([string]$Ref.path) -or [string]$Ref.sha256 -notmatch '^sha256:[0-9a-f]{64}$'){throw "$Name ref incomplete"};$p=Get-DiagnosticFull ([string]$Ref.path);$i=Get-DiagnosticItem $p;if((Get-DiagnosticHash $p) -cne $Ref.sha256.Substring(7) -or $i.Length -ne [int64]$Ref.bytes){throw "$Name ref drift"};return $p}
function Assert-CircleDiagnosticCleanup([string]$ProducerRoot,[object]$SourceInputs){
 $producer=Get-DiagnosticFull $ProducerRoot;if([string]::IsNullOrWhiteSpace([string]$SourceInputs.cleanupHelperKind) -or $SourceInputs.cleanupHelperKind -cne 'factory-child-kernel-cleanup-v3'){throw 'Circle diagnostic cleanup helper kind mismatch'}
 if([string]$SourceInputs.cleanupHelperSha256 -cne 'cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13'){throw 'Circle diagnostic cleanup helper seal mismatch'}
 $expected='cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13';$refs=@($SourceInputs.cleanupV2.renderer,$SourceInputs.cleanupV2.uia);if($refs.Count -ne 2){throw 'Circle diagnostic cleanup role count mismatch'}
 # V3 helper is intentionally bound to V6. Keep legacy V5 as the only
 # forbidden wait ABI; checking this explicitly prevents an accidental
 # V6 rejection while still rejecting donor cleanup callers.
 $exactV3ABI=@('FactoryProcessWaitV6','Invoke-FactoryOwnedCleanup','Test-FactoryKernelExitCertificate','GetExitCodeProcess','TerminateProcess','ReadIdentity','kernelExitCodeRead','retained-kernel-handle')
 $legacyV5='FactoryProcessWaitV5'
 foreach($ref in $refs){$p=Assert-DiagnosticRef $ref 'diagnostic cleanup';if(-not $p.StartsWith($producer+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Circle diagnostic cleanup escaped producer root'};if((Get-DiagnosticHash $p) -cne $expected){throw 'Circle diagnostic cleanup bytes drift'};$t=Get-Content -LiteralPath $p -Raw;$missing=@();foreach($token in $exactV3ABI){if(-not $t.Contains([string]$token)){$missing+=$token}};if($t.Contains($legacyV5)){$missing+='forbidden-'+$legacyV5};if($missing.Count -gt 0){throw ('Circle diagnostic cleanup ABI incomplete: '+($missing -join ','))}}
 $paths=@($SourceInputs.cleanupHelperPaths);if($paths.Count -ne 2 -or $paths[0] -ne $SourceInputs.cleanupV2.renderer.path -or $paths[1] -ne $SourceInputs.cleanupV2.uia.path){throw 'Circle diagnostic cleanup path closure mismatch'}
 return $true
}
function Assert-CircleDiagnosticPlanReceipt([object]$SI,[object]$Plan,[object]$Receipt,[object]$Tuple){
 if([string]$SI.caseHash -notmatch '^sha256:[0-9a-f]{64}$' -or [string]$SI.recipeHash -notmatch '^sha256:[0-9a-f]{64}$'){throw 'Circle diagnostic canonical case/recipe hash required'}
 if($Plan.kind -cne 'factory-circle-incremental-compile-plan-v1' -or [string]::IsNullOrWhiteSpace([string]$Plan.candidate) -or $Plan.candidate -cne $SI.candidate -or $Plan.phase -cne 'final' -or $Plan.executionEligible -ne $true -or $Plan.qualification -cne 'diagnostic-native-only-not-qualified'){throw 'Circle diagnostic plan identity/candidate mismatch'}
 if($Plan.case.id -cne $SI.caseID -or $Plan.case.hash -cne $SI.caseHash -or $Plan.sourceHash -cne $SI.sourceHash -or $Plan.tuple.id -cne $SI.tupleID -or $Plan.tuple.hostHashes.windows -ne $Tuple.hostHashes.windows -or $Plan.tuple.hostHashes.macos -ne $Tuple.hostHashes.macos -or $Plan.rendererSha256 -cne $SI.rendererSha256 -or $Plan.runtimeSourceCommit -cne $SI.runtimeSourceCommit){throw 'Circle diagnostic plan/source join mismatch'}
 if($Plan.compileRequest.maxParallelJobs -ne 1 -or $Plan.compileRequest.maxFrontendThreads -ne 1){throw 'Circle diagnostic compiler budget mismatch'}
 if($Receipt.kind -cne 'factory-circle-incremental-owned-compile-v1' -or $Receipt.phase -cne 'final' -or $Receipt.exitCode -ne 0 -or $Receipt.timedOut -or $Receipt.ownedExited -ne $true -or $Receipt.streamsSealed -ne $true -or $Receipt.streamDrainComplete -ne $true -or $Receipt.originalHandleRetained -ne $true -or $Receipt.jobActiveCount -ne 0 -or $Receipt.kernelWait -ne 0 -or $Receipt.memoryCapBytes -ne 1073741824 -or $Receipt.jobFlags -ne 512 -or $Receipt.maxParallelJobs -ne 1 -or $Receipt.maxFrontendThreads -ne 1 -or $Receipt.nativeActions -ne 0){throw 'Circle diagnostic compile receipt closure mismatch'}
 if($Receipt.planSha256 -cne $SI.planHash -or $Receipt.sourceHash -cne $SI.sourceHash -or $Receipt.exeSha256 -cne $SI.exeHash -or $Receipt.rendererSha256 -cne $SI.rendererSha256 -or $Receipt.runtimeSourceCommit -cne $SI.runtimeSourceCommit){throw 'Circle diagnostic receipt/source join mismatch'}
 if($Tuple.id -cne $SI.tupleID -or $Tuple.hostHashes.windows -ne $Plan.tuple.hostHashes.windows -or $Tuple.hostHashes.macos -ne $Plan.tuple.hostHashes.macos -or $Tuple.hostHashes.windows -ne ('sha256:'+$SI.exeHash) -or $Tuple.rendererHash -ne ('sha256:'+$SI.rendererSha256) -or $Tuple.runtimeCommit -ne $SI.runtimeSourceCommit){throw 'Circle diagnostic tuple closure mismatch'}
 return $true
}
function Assert-CircleDiagnosticDispatchPlan([object]$Plan,[object]$SourceInputs,[int]$Count){
 if($null -eq $Plan){throw 'Circle dispatch plan missing'}
 $dispatchProp=$Plan.PSObject.Properties.Name -contains 'dispatch'
 if($dispatchProp -and $null -ne $Plan.dispatch -and $null -ne $Plan.dispatch.first){return 'legacy-dispatch-first'}
 if($Count -ne 1){throw 'Circle diagnostic dispatch is Count1-only'}
 if($Plan.kind -cne 'factory-circle-incremental-compile-plan-v1'){throw 'Circle diagnostic dispatch plan kind mismatch'}
 if($Plan.phase -cne 'final'){throw 'Circle diagnostic dispatch phase must be final'}
 if($Plan.executionEligible -ne $true){throw 'Circle diagnostic dispatch requires executionEligible=true'}
 if($Plan.qualification -cne 'diagnostic-native-only-not-qualified'){throw 'Circle diagnostic dispatch qualification mismatch'}
 if([string]::IsNullOrWhiteSpace([string]$Plan.candidate) -or $Plan.candidate -cne $SourceInputs.candidate){throw 'Circle diagnostic dispatch candidate mismatch'}
 if($Plan.case.id -cne $SourceInputs.caseID -or $Plan.case.hash -cne $SourceInputs.caseHash){throw 'Circle diagnostic dispatch case mismatch'}
 if($Plan.tuple.id -cne $SourceInputs.tupleID){throw 'Circle diagnostic dispatch tuple mismatch'}
 if($Plan.sourceHash -cne $SourceInputs.sourceHash){throw 'Circle diagnostic dispatch source mismatch'}
 if($Plan.compileRequest.maxParallelJobs -ne 1 -or $Plan.compileRequest.maxFrontendThreads -ne 1){throw 'Circle diagnostic dispatch compiler budget mismatch'}
 return 'diagnostic-final-eligible'
}
function Assert-CircleDiagnosticSourceInputs([string]$Root,[object]$SourceInputs){
 if($SourceInputs.kind -cne 'factory-circle-source-inputs-diagnostic-v10' -or $SourceInputs.count -ne 1){throw 'Circle diagnostic source kind/count mismatch'}
 foreach($n in @('caseID','caseHash','sourceHash','tupleID','planHash','compileReceiptHash','tupleHash','bindingHash','recipeHash','exeHash','rendererSha256','rendererPath','compiledHostPackagePath','compileReceiptPath','capturePlanPath','capturePlanHash','buildPreflightPath','buildPreflightHash','runtimeSourceCommit','serializerControlSha256','serializerPath','contextRef','planRef','compileRef','tupleRef','bindingRef','recipeRef','manifestRef','receiptRef','rendererRef','exeRef','serializerRef','integrationBindingsRef','buildPreflightRef','capturePlanRef','uiaWorkerPath','uiaWorkerHash','cleanupV2','cleanupHelperKind','cleanupHelperSha256','cleanupHelperPaths')){if($null -eq $SourceInputs.$n -or [string]::IsNullOrWhiteSpace([string]$SourceInputs.$n)){throw "Circle diagnostic source field missing: $n"}}
 if([IO.Path]::GetFullPath([string]$SourceInputs.compiledHostPackagePath) -cne (GetCircleCompiledPackage)){throw 'Circle compiled host package canonical path mismatch'}
 $planPath=Assert-DiagnosticRef $SourceInputs.planRef 'diagnostic plan';$receiptPath=Assert-DiagnosticRef $SourceInputs.receiptRef 'diagnostic receipt';$tuplePath=Assert-DiagnosticRef $SourceInputs.tupleRef 'diagnostic tuple';$bindingPath=Assert-DiagnosticRef $SourceInputs.bindingRef 'diagnostic binding';$contextPath=Assert-DiagnosticRef $SourceInputs.contextRef 'diagnostic context';[void](Assert-DiagnosticRef $SourceInputs.caseRef 'diagnostic case');[void](Assert-DiagnosticRef $SourceInputs.recipeRef 'diagnostic recipe');[void](Assert-DiagnosticRef $SourceInputs.manifestRef 'diagnostic manifest');[void](Assert-DiagnosticRef $SourceInputs.rendererRef 'diagnostic renderer');[void](Assert-DiagnosticRef $SourceInputs.exeRef 'diagnostic executable');[void](Assert-DiagnosticRef $SourceInputs.serializerRef 'diagnostic serializer');[void](Assert-DiagnosticRef $SourceInputs.integrationBindingsRef 'diagnostic bindings');[void](Assert-DiagnosticRef $SourceInputs.buildPreflightRef 'diagnostic preflight');[void](Assert-DiagnosticRef $SourceInputs.capturePlanRef 'diagnostic capture plan')
 $plan=Get-DiagnosticJson $planPath;$receipt=Get-DiagnosticJson $receiptPath;$tuple=Get-DiagnosticJson $tuplePath;$binding=Get-DiagnosticJson $bindingPath;$context=Get-DiagnosticJson $contextPath
 if((Get-DiagnosticHash $planPath) -cne $SourceInputs.planHash -or (Get-DiagnosticHash $receiptPath) -cne $SourceInputs.compileReceiptHash -or (Get-DiagnosticHash $tuplePath) -cne $SourceInputs.tupleHash -or (Get-DiagnosticHash $bindingPath) -cne $SourceInputs.bindingHash){throw 'Circle diagnostic source hash join mismatch'}
 Assert-CircleDiagnosticPlanReceipt $SourceInputs $plan $receipt $tuple|Out-Null
 if($Plan.candidate -ne $SourceInputs.candidate -or $binding.kind -cne 'factory-source-bound-candidate-binding-v1' -or $binding.frozenTupleBound -ne $false -or $binding.canonicalTupleRef.sha256 -ne ('sha256:'+$SourceInputs.tupleHash)){throw 'Circle diagnostic binding closure mismatch'}
 $serializerPath=Assert-DiagnosticRef $SourceInputs.serializerRef 'diagnostic serializer';if((Get-DiagnosticHash $serializerPath) -cne ([string]$SourceInputs.serializerControlSha256).Replace('sha256:','')){throw 'Circle diagnostic serializer control drift'}
 $preflightPath=Assert-DiagnosticRef $SourceInputs.buildPreflightRef 'diagnostic preflight';if((Get-DiagnosticHash $preflightPath) -cne ([string]$SourceInputs.buildPreflightHash).Replace('sha256:','')){throw 'Circle diagnostic preflight control drift'}
 $ctxTuple=if($context.tupleID){$context.tupleID}elseif($context.tupleContext){$context.tupleContext.tupleID}else{$null};$ctxSource=if($context.sourceHash){$context.sourceHash}elseif($context.sourceBinding){$context.sourceBinding.sourceHash}else{$null};$ctxCase=if($context.caseID){$context.caseID}elseif($context.case){$context.case.id}else{$null};$ctxCaseHash=if($context.caseHash){$context.caseHash}elseif($context.case){$context.case.hash}else{$null};if($ctxTuple -cne $SourceInputs.tupleID -or $ctxSource -cne $SourceInputs.sourceHash -or $ctxCase -cne $SourceInputs.caseID -or $ctxCaseHash -cne $SourceInputs.caseHash){throw 'Circle diagnostic context closure mismatch'}
 $uia=Get-DiagnosticFull ([string]$SourceInputs.uiaWorkerPath);if($SourceInputs.uiaWorkerHash -notmatch '^[0-9a-f]{64}$' -or (Get-DiagnosticHash $uia) -cne $SourceInputs.uiaWorkerHash){throw 'Circle diagnostic UIA worker drift'}
 Assert-CircleDiagnosticCleanup $Root $SourceInputs|Out-Null
 return $true
}
