# Source-only preflight callable immediately before any DLL/window child launch; no launch here.
param([ValidateSet('Compile','Launch')][string]$Phase='Compile',[string]$CompileReceiptSha256,[string]$ExeSha256)
$Package=Join-Path $PSScriptRoot 'package'
$ErrorActionPreference='Stop'
$expected=@('D:\Claude\swiftright\.factory-work\hosts\padding-settled\package')
if($expected -cnotcontains [IO.Path]::GetFullPath($Package)){throw 'Exact correction package required'}
$planPath=Join-Path $Package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json
$planHash=(Get-FileHash $planPath).Hash.ToLowerInvariant()
$approvedPlans=@{
 'padding-settled'='82628daf6254cef21ec023acfd35f9a030141a9a0976a1816c91d5f0d632e5cd'
}
$label=Split-Path (Split-Path $Package -Parent) -Leaf
if(-not $approvedPlans.ContainsKey($label) -or $planHash -cne $approvedPlans[$label]){throw 'Exact reviewed seeded plan required'}
$verify=Join-Path $PSScriptRoot 'shared\verify-runtime-source.ps1'
if((Get-FileHash $verify).Hash.ToLowerInvariant() -ne $plan.runtimeVerifierHash){throw 'Verifier drift'}
. $verify
$hostInputs=Join-Path $PSScriptRoot 'shared\host-inputs.ps1'
if((Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Host input guard drift'}
. $hostInputs
function Assert-Inputs {
 if((Get-FileHash $planPath).Hash.ToLowerInvariant() -ne $planHash){throw 'Plan drift'}
 if($plan.inputsRoot -cne 'D:\Claude\swiftright\.factory-work\inputs' -or $plan.rendererPath -cne 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll' -or $plan.bridgePackagePath -cne 'D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge' -or $plan.runtimeSourceCommit -ne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'){throw 'Context drift'}
 if((Get-FileHash -LiteralPath $plan.rendererPath).Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Renderer drift'}
 if((Get-FileHash (Join-Path $Package 'runtime-source-receipt.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'Runtime receipt drift'}
 if((Get-FileHash (Join-Path $Package 'runtime-source-tree.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceTreeFileHash.Replace('sha256:','')){throw 'Runtime tree archive drift'}
 Assert-FactoryRuntimeSource $plan $Package
 Assert-HostCompilerInputs $Package $plan.sourceBindings
 if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'dependencies\canonical-inputs-manifest.json')).Hash.ToLowerInvariant() -cne $plan.bridgeCanonicalManifestHash.Replace('sha256:','')){throw 'Canonical bridge source receipt drift'}
 if((Get-FileHash -LiteralPath (Join-Path $plan.bridgePackagePath 'Sources\CSwiftRight\swiftright.h')).Hash.ToLowerInvariant() -cne $plan.bridgeHeaderHash){throw 'Exact owned ABI header required'}
 $actualBridgeFiles=@((Join-Path $plan.bridgePackagePath 'Package.swift'))+@(Get-ChildItem -LiteralPath (Join-Path $plan.bridgePackagePath 'Sources') -Recurse -File|ForEach-Object{$_.FullName})
$expectedBridgeFiles=@($plan.bridgeBindings|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $_.path))})
if($actualBridgeFiles.Count -ne $expectedBridgeFiles.Count -or @($actualBridgeFiles|Where-Object{$expectedBridgeFiles -notcontains $_}).Count -ne 0){throw 'Staged bridge membership drift'}
foreach($b in $plan.bridgeBindings){
  $f=[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $b.path))
  if(-not $f.StartsWith($plan.bridgePackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $f).Hash.ToLowerInvariant() -ne $b.sha256){throw 'Bridge input drift'}
 }
 if((Get-FileHash $plan.compilerPath).Hash.ToLowerInvariant() -ne $plan.compilerHash){throw 'Compiler drift'}
 $moduleContext=@{'module-origin-receipt.json'=$plan.runtimeModuleOrigin.receiptHash;'module-origin-accepted-replay.json'=$plan.runtimeModuleOrigin.acceptedReplayHash;'module-origin-independent-review.json'=$plan.runtimeModuleOrigin.independentReviewHash}
 foreach($name in $moduleContext.Keys){if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot ('dependencies\'+$name))).Hash.ToLowerInvariant() -cne $moduleContext[$name].Replace('sha256:','')){throw 'Archived module-origin context drift'}}
 $origin=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'dependencies\module-origin-receipt.json')|ConvertFrom-Json
 if($origin.sourceCommit -cne $plan.runtimeSourceCommit -or $origin.sourceTreeHash -cne $plan.runtimeSourceTreeHash -or $origin.status -cne 'success'){throw 'Module-origin source identity drift'}
}
Assert-Inputs
if($Phase -ceq 'Launch'){
 if($CompileReceiptSha256 -cnotmatch '^[0-9a-f]{64}$' -or $ExeSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Measured actual compile receipt/exe pins mandatory'}
 $build=Join-Path $Package 'build-settled-r1';$observation=Join-Path $build 'observation.json'
 if((Get-FileHash -LiteralPath $observation).Hash.ToLowerInvariant() -cne $CompileReceiptSha256){throw 'Actual compile receipt drift'}
 $record=Get-Content -Raw -LiteralPath $observation|ConvertFrom-Json
 $dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
 $expectedArgv='build --package-path "'+$Package+'" --scratch-path "'+$plan.compileRequest.scratchPath+'" -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+$dep+'" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
 if($record.kind -cne 'factory-padding-settled-compile-only-owned-handle-v1' -or $record.argv -cne $expectedArgv){throw 'Exact production compiler kind/release/GUI argv required'}

 if($record.planSha256 -cne $planHash -or $record.sourceHash -cne $plan.sourceHash -or $record.runtimeSourceCommit -cne $plan.runtimeSourceCommit -or $record.runtimeSourceTreeHash -cne $plan.runtimeSourceTreeHash -or $record.rendererSha256 -cne $plan.rendererSha256 -or $record.compilerPath -cne $plan.compilerPath -or $record.compilerHash -cne $plan.compilerHash -or $record.cwd -cne $Package -or $record.target -cne 'windows-x86_64' -or $record.configuration -cne 'release'){throw 'Compile/source/tool/context mismatch'}
 if(($record.exitCode -isnot [int] -and $record.exitCode -isnot [long]) -or $record.exitCode -ne 0 -or ($record.kernelWait -isnot [int] -and $record.kernelWait -isnot [long]) -or $record.kernelWait -ne 0 -or $record.timedOut -isnot [bool] -or $record.timedOut -or $record.ownedExited -isnot [bool] -or -not $record.ownedExited -or $record.streamDrainComplete -isnot [bool] -or -not $record.streamDrainComplete -or $record.error -or $record.cleanupError){throw 'Unqualified compiler termination/streams'}
 if(@($record.rawStreams).Count -ne 2 -or @($record.rawStreams|Where-Object{$_.name -ceq 'stdout'}).Count -ne 1 -or @($record.rawStreams|Where-Object{$_.name -ceq 'stderr'}).Count -ne 1){throw 'Exactly two compile streams required'}
 foreach($state in $record.rawStreams){if($state.sealed -isnot [bool] -or -not $state.sealed -or $state.destinationClosed -isnot [bool] -or -not $state.destinationClosed -or $state.taskStatus -cne 'RanToCompletion' -or $state.closureTaskStatus -cne 'RanToCompletion'){throw 'Compile streams not terminal'}}
 $exe=Join-Path $build 'FactoryProbe.exe';$produced=Join-Path $plan.compileRequest.scratchPath 'out\Products\Release-windows-x86_64\FactoryProbe.exe'
 if($record.exePath -cne $produced -or $record.exeSha256 -cne $ExeSha256 -or $record.exeSubsystem -ne 2 -or $record.exeMachine -ne 34404 -or (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -cne $ExeSha256 -or (Get-FileHash -LiteralPath $produced).Hash.ToLowerInvariant() -cne $ExeSha256){throw 'Actual produced GUI exe binding mismatch'}
 Assert-Inputs # Last pre-child renderer/source byte check; caller must invoke immediately before Process.Start.
}
[ordered]@{kind='padding-owned-input-preflight';phase=$Phase;planSha256=$planHash;rendererPath=$plan.rendererPath;rendererSha256=$plan.rendererSha256;compileReceiptSha256=$CompileReceiptSha256;exeSha256=$ExeSha256;nativeActions=0;nativeParity='hold'}|ConvertTo-Json -Depth 8
