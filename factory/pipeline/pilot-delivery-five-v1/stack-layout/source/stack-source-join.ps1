# Source-only measured-host join for stack-overlay lifecycle Count1.
$ErrorActionPreference='Stop'
$StackPlanHash='9e385e4e50b46c109103cf28b9d8e93be01298fed6c35f2426a1d6a3cdaacef1'
$StackReceiptHash='99a0332b765518e97a8200ef25612fa5c31671037eccdf5504a1fcec091dcae8'
$StackExeHash='abf82f6f133f1d4dd9a48b3075f9af5fe4632db2b9fdc9763114661196bf6c2c'
$StackSourceHash='fe91bed344011c7464a18c1ae5ee757a113f6eda6f7f4e0c4cb0258a258d8c35'
$StackRendererHash='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
$StackRuntimeCommit='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
$StackRuntimeTreeHash='c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'
$StackCompilerHash='1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'
$StackReceiptRelative='root-build-r1\actual\observation.json'
$StackRendererPath='D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll'
$StackPackagePath='D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle\package'

function Assert-StackLifecycleSource([string]$Package,[string]$CompileReceiptHash,[string]$ExeHash) {
 $packagePath=[IO.Path]::GetFullPath($Package)
 if($packagePath -cne $StackPackagePath){throw 'Exact canonical stack package required'}
 if($CompileReceiptHash -cne $StackReceiptHash -or $ExeHash -cne $StackExeHash){throw 'Measured next-build receipt/exe join required'}
 $planPath=Join-Path $packagePath 'plan.json'
 if((Get-FileHash $planPath).Hash.ToLowerInvariant() -cne $StackPlanHash){throw 'Stack plan drift'}
 $plan=Get-Content -Raw $planPath|ConvertFrom-Json
 if($plan.kind -cne 'windows-stack-lifecycle-canonical-input-source-plan' -or $plan.diagnosticScope -cne 'factory-stack-host-lifecycle-next-v1' -or $plan.sourceHash -ne ('sha256:'+$StackSourceHash) -or $plan.rendererSha256 -ne $StackRendererHash -or $plan.runtimeSourceCommit -ne $StackRuntimeCommit -or $plan.runtimeSourceTreeHash -ne ('sha256:'+$StackRuntimeTreeHash) -or $plan.compilerHash -ne $StackCompilerHash -or $plan.executionEligible -ne $false -or $plan.frozenTupleBound -ne $false){throw 'Stack plan identity/scope drift'}
 if($plan.rendererPath -cne $StackRendererPath -or (Get-FileHash $plan.rendererPath).Hash.ToLowerInvariant() -cne $StackRendererHash){throw 'Stack renderer join drift'}
 $receiptPath=Join-Path $packagePath $StackReceiptRelative
 if((Get-FileHash $receiptPath).Hash.ToLowerInvariant() -cne $StackReceiptHash){throw 'Stack compile receipt bytes drift'}
 $receipt=Get-Content -Raw $receiptPath|ConvertFrom-Json
 foreach($pair in @(@('planSha256',$StackPlanHash),@('sourceHash','sha256:'+$StackSourceHash),@('rendererSha256',$StackRendererHash),@('runtimeSourceCommit',$StackRuntimeCommit),@('runtimeSourceTreeHash','sha256:'+$StackRuntimeTreeHash),@('compilerHash',$StackCompilerHash),@('exeSha256',$StackExeHash))){if([string]$receipt.($pair[0]) -cne [string]$pair[1]){throw ('Stack receipt join drift: '+$pair[0])}}
 if($receipt.kind -cne 'factory-stack-lifecycle-compile-only-owned-handle-v1' -or $receipt.exitCode -ne 0 -or $receipt.timedOut -or -not $receipt.ownedExited -or -not $receipt.streamDrainComplete -or $receipt.nativeWindowOpened -or $receipt.frozenTupleBound){throw 'Stack compile proof incomplete'}
 $exePath=[IO.Path]::GetFullPath($receipt.exePath)
 if(-not $exePath.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $exePath).Hash.ToLowerInvariant() -ne $StackExeHash){throw 'Stack executable join drift'}
 foreach($binding in @($plan.sourceBindings)){$p=[IO.Path]::GetFullPath((Join-Path $packagePath $binding.path));if(-not $p.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $p).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw ('Stack source binding drift: '+$binding.path)}}
 foreach($name in @('runtime-source-receipt.json','runtime-source-tree.json')){if(-not(Test-Path -LiteralPath (Join-Path $packagePath $name) -PathType Leaf)){throw ('Stack runtime proof missing: '+$name)}}
 if((Get-FileHash (Join-Path $packagePath 'runtime-source-tree.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceTreeFileHash.Replace('sha256:','')){throw 'Stack runtime tree proof drift'}
 if((Get-FileHash (Join-Path $packagePath 'runtime-source-receipt.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'Stack runtime receipt proof drift'}
 [ordered]@{planHash=$StackPlanHash;receiptHash=$StackReceiptHash;exeHash=$StackExeHash;sourceHash=$StackSourceHash;rendererHash=$StackRendererHash;runtimeCommit=$StackRuntimeCommit;runtimeTreeHash=$StackRuntimeTreeHash;compilerHash=$StackCompilerHash;caseID=$plan.case.id;diagnosticScope=$plan.diagnosticScope;nativeParity='hold';frozenTupleBound=$false}
}
