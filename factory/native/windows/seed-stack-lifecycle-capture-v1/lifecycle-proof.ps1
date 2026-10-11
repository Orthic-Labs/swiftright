# Factory diagnostic authority is separate from immutable Mac host/repetition proof.
function Test-LifecycleIntegerEqual($Value,[long]$Expected) {
 if($Value -isnot [int] -and $Value -isnot [long]){return $false}
 return ([long]$Value -eq $Expected)
}
function Assert-LifecyclePlanObject([string]$Package,$Plan,[string]$PlanHash,[string]$MainHash,[string]$AdapterHash) {
 if($Package -cne 'D:\Claude\swiftright\factory\native\windows\seed-stack-lifecycle-host-v1\package' -or $PlanHash -cne '82f29632a9a2937fa313ba52eee5b2a4dbc1b23b1a24ebbced923107cbe3cbcd'){throw 'Exact diagnostic package/plan required'}
 if($MainHash -cne '05411ce0741ce48868d3591fe1429415ca81746c2b1633f1456e5e265d309e1e' -or $AdapterHash -cne '468a869590d1c647e9e8506dfbb1d59ef53fbb8c0b15fb5ece5af64de3a6b834'){throw 'Diagnostic lifecycle observer/adapter bytes drift'}
 if($Plan.diagnosticScope -cne 'factory-stack-host-lifecycle-v1' -or $Plan.sourceHash -cne 'sha256:fe91bed344011c7464a18c1ae5ee757a113f6eda6f7f4e0c4cb0258a258d8c35' -or $Plan.hostMode -cne 'renderer' -or $Plan.case.id -cne 'swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258'){throw 'Diagnostic scope/source/case mismatch'}
 foreach($flag in @('executionEligible','frozenTupleBound')){if($Plan.$flag -isnot [bool] -or $Plan.$flag){throw 'Diagnostic authority cannot qualify parity'}}
 $lineage=$Plan.diagnosticLineage
 foreach($flag in @('witnessUnchanged','quitThresholdUnchanged','runtimeBridgeCompilerBindingsUnchanged')){if($lineage.$flag -isnot [bool] -or -not $lineage.$flag){throw 'Diagnostic lineage boolean mismatch'}}
 if($lineage.parentPlanSha256 -cne 'sha256:4cc752eee6d227bf2fcbff60e2822f8199f233a904e1a8087f5a3ddd65f19f9b' -or $lineage.parentMainSha256 -cne 'sha256:b2e6fde07c21274a7e74c8b47a9c3e11545215f2a0cd280ba6d0f19c86667e6c' -or $lineage.adapterSha256 -cne ('sha256:'+$AdapterHash)){throw 'Diagnostic immutable parent/adapter lineage mismatch'}
 $mainBindings=@($Plan.sourceBindings|Where-Object{$_.path -ceq 'Sources/FactoryProbe/main.swift'})
 if($mainBindings.Count -ne 1 -or $mainBindings[0].sha256 -cne ('sha256:'+$MainHash)){throw 'Diagnostic marker source binding mismatch'}
}
function Assert-LifecycleHostSource([string]$Package,$Plan,[string]$PlanHash) {
 $actualPlanHash=(Get-FileHash -LiteralPath (Join-Path $Package 'plan.json')).Hash.ToLowerInvariant()
 if($actualPlanHash -cne $PlanHash){throw 'Diagnostic plan file bytes drift'}
 $mainHash=(Get-FileHash -LiteralPath (Join-Path $Package 'Sources\FactoryProbe\main.swift')).Hash.ToLowerInvariant()
 $adapterHash=(Get-FileHash -LiteralPath (Join-Path (Split-Path $Package -Parent) 'adapt-host.py')).Hash.ToLowerInvariant()
 Assert-LifecyclePlanObject $Package $Plan $PlanHash $mainHash $adapterHash
 $parent='D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\stack-overlay\package'
 $parentPlan=Get-Content -Raw -LiteralPath (Join-Path $parent 'plan.json')|ConvertFrom-Json
 if((Get-FileHash -LiteralPath (Join-Path $parent 'Sources\FactoryProbe\main.swift')).Hash.ToLowerInvariant() -cne 'b2e6fde07c21274a7e74c8b47a9c3e11545215f2a0cd280ba6d0f19c86667e6c'){throw 'Immutable parent host drift'}
 $macHelper=Join-Path $PSScriptRoot 'mac-proof.ps1'
 if((Get-FileHash -LiteralPath $macHelper).Hash.ToLowerInvariant() -cne 'e02cfbaf71df028f385baae9eec65eabc07e691c91509b17ca42b19b345835ef'){throw 'Mac proof helper drift'}
 . $macHelper
 # Original Mac proof applies only to original parent; diagnostic host is never relabelled as that Mac witness.
 Assert-SeedMacProof $parent $parentPlan '4cc752eee6d227bf2fcbff60e2822f8199f233a904e1a8087f5a3ddd65f19f9b'
 if((Get-FileHash -LiteralPath (Join-Path $Package 'Sources\FactoryProbe\Witness.swift')).Hash.ToLowerInvariant() -cne $Plan.sourceHash.Replace('sha256:','')){throw 'Diagnostic witness bytes drift'}
}
function Assert-LifecycleCompileObject([string]$Package,$Plan,[string]$PlanHash,$Compiled,[string]$ExeHash) {
 if($Compiled.kind -cne 'factory-lifecycle-diagnostic-compile-only-owned-handle-v1' -or $Compiled.diagnosticScope -cne 'factory-stack-host-lifecycle-v1'){throw 'Fresh diagnostic compiler identity required'}
 if(-not (Test-LifecycleIntegerEqual $Compiled.exitCode 0) -or -not (Test-LifecycleIntegerEqual $Compiled.exeSubsystem 2)){throw 'Diagnostic compiler terminal/PE status required'}
 foreach($flag in @('ownedExited','streamDrainComplete')){if($Compiled.$flag -isnot [bool] -or -not $Compiled.$flag){throw 'Diagnostic compiler exit/streams incomplete'}}
 foreach($flag in @('timedOut','nativeWindowOpened','frozenTupleBound')){if($Compiled.$flag -isnot [bool] -or $Compiled.$flag){throw 'Diagnostic compiler timeout/scope invalid'}}
 foreach($field in @('error','cleanupError')){if($null -ne $Compiled.$field -and ($Compiled.$field -isnot [string] -or $Compiled.$field -cne '')){throw 'Diagnostic compiler errors present'}}
 foreach($field in @('sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','rendererSha256','compilerHash')){if($Compiled.$field -isnot [string] -or $Compiled.$field -cne $Plan.$field){throw ('Diagnostic compiler binding '+$field)}}
 if($Compiled.planSha256 -cne $PlanHash -or $Compiled.exeSha256 -cne $ExeHash -or $ExeHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Diagnostic compiled plan/executable mismatch'}
 foreach($field in @('parentPlanSha256','parentMainSha256','adapterSha256')){if($Compiled.diagnosticLineage.$field -cne $Plan.diagnosticLineage.$field){throw 'Diagnostic compiler parent/adapter lineage mismatch'}}
 foreach($flag in @('witnessUnchanged','quitThresholdUnchanged','runtimeBridgeCompilerBindingsUnchanged')){if($Compiled.diagnosticLineage.$flag -isnot [bool] -or -not $Compiled.diagnosticLineage.$flag){throw 'Diagnostic compiler lineage authority mismatch'}}
 $exePath=[IO.Path]::GetFullPath($Compiled.exePath)
 if(-not $exePath.StartsWith($Package+'\build-lifecycle-v1-r1\scratch\',[StringComparison]::OrdinalIgnoreCase)){throw 'Diagnostic executable escaped fresh compiler output'}
}
function Assert-LifecycleWindowsCompile([string]$Package,$Plan,[string]$PlanHash,[string]$CompileReceiptHash,[string]$ExeHash) {
 if($CompileReceiptHash -cnotmatch '^[0-9a-f]{64}$' -or $ExeHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Fresh measured diagnostic receipt/executable pins required'}
 $receipt=Join-Path $Package 'build-lifecycle-v1-r1\observation.json'
 if((Get-FileHash -LiteralPath $receipt).Hash.ToLowerInvariant() -cne $CompileReceiptHash){throw 'Diagnostic compile receipt bytes drift'}
 $compiled=Get-Content -Raw -LiteralPath $receipt|ConvertFrom-Json
 Assert-LifecycleCompileObject $Package $Plan $PlanHash $compiled $ExeHash
 if((Get-FileHash -LiteralPath $compiled.exePath).Hash.ToLowerInvariant() -cne $ExeHash){throw 'Diagnostic produced executable bytes drift'}
}
