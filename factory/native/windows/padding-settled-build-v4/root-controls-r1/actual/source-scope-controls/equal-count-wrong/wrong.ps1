# Source-only preflight callable immediately before any DLL/window child launch; no launch here.
param([ValidateSet('Compile','Launch')][string]$Phase='Compile',[string]$CompileReceiptSha256,[string]$ExeSha256,[string]$SerializerControlSha256)
$Package=Join-Path $PSScriptRoot 'package'
$ErrorActionPreference='Stop'
$expected=@('D:\Claude\swiftright\.factory-work\hosts\padding-settled\package')
if($expected -cnotcontains [IO.Path]::GetFullPath($Package)){throw 'Exact correction package required'}
$planPath=Join-Path $Package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json
$planHash=(Get-FileHash $planPath).Hash.ToLowerInvariant()
$approvedPlans=@{
 'padding-settled'='fe088dc1318e6ebc319c95ee169c2c91aa7e630fd19d81729389ebedb8397b20'
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
 if($SerializerControlSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Measured actual serializer control pin mandatory'}
 $serializerRoot=Join-Path $PSScriptRoot 'serializer-control-actual-r1';$serializerPath=Join-Path $serializerRoot 'control.json'
 if((Get-FileHash $serializerPath).Hash.ToLowerInvariant() -cne $SerializerControlSha256){throw 'Actual serializer control drift'}
 $serializer=Get-Content -Raw $serializerPath|ConvertFrom-Json
 if($serializer.kind -cne 'factory-serializer-control-actual-v1' -or $serializer.passed -isnot [bool] -or -not $serializer.passed -or $serializer.planSha256 -cne $planHash -or $serializer.sourceSha256 -cne 'cde9a9a3a90f52eda4134069f7c6be80ad0d7315689c8e2cdc7ae21deb0f19e1' -or $serializer.controlSha256 -cne '7b7b79a0e90c63aa696a7347e6ab975fe6dc811bce96b12a2e3548bf3ef64454'){throw 'Serializer plan/source authority mismatch'}
 $serializerExe=Join-Path $serializerRoot 'serializer-control.exe';$swiftc=Join-Path (Split-Path $plan.compilerPath -Parent) 'swiftc.exe'
 if((Get-FileHash $serializerExe).Hash.ToLowerInvariant() -cne $serializer.exeSha256 -or (Get-FileHash $swiftc).Hash.ToLowerInvariant() -cne $serializer.swiftcSha256){throw 'Serializer actual tool/exe drift'}
 $serializerArgs='"'+(Join-Path $Package 'Sources\FactoryProbe\MetricsPayload.swift')+'" "'+(Join-Path $PSScriptRoot 'serializer-control\main.swift')+'" -o "'+$serializerExe+'"'
 foreach($phase in @('compile','run')){
  $receiptPath=Join-Path $serializerRoot ($phase+'\observation.json');$expectedReceiptHash=if($phase -ceq 'compile'){$serializer.compileReceiptSha256}else{$serializer.runReceiptSha256}
  if((Get-FileHash $receiptPath).Hash.ToLowerInvariant() -cne $expectedReceiptHash){throw 'Serializer child receipt drift'}
  $child=Get-Content -Raw $receiptPath|ConvertFrom-Json
  $expectedTool=if($phase -ceq 'compile'){$swiftc}else{$serializerExe};$expectedToolHash=if($phase -ceq 'compile'){$serializer.swiftcSha256}else{$serializer.exeSha256};$expectedArgs=if($phase -ceq 'compile'){$serializerArgs}else{''}
  if($child.kind -cne 'factory-serializer-pure-child-v1' -or $child.phase -cne $phase -or $child.planSha256 -cne $planHash -or $child.toolPath -cne $expectedTool -or $child.toolSha256 -cne $expectedToolHash -or $child.argv -cne $expectedArgs -or $child.cwd -cne $serializerRoot){throw 'Serializer child actual invocation mismatch'}
  if(($child.pid -isnot [int] -and $child.pid -isnot [long]) -or $child.pid -le 0 -or ($child.exitCode -isnot [int] -and $child.exitCode -isnot [long]) -or $child.exitCode -ne 0 -or ($child.kernelWait -isnot [int] -and $child.kernelWait -isnot [long]) -or $child.kernelWait -ne 0 -or $child.timedOut -isnot [bool] -or $child.timedOut -or $child.ownedExited -isnot [bool] -or -not $child.ownedExited -or $child.streamDrainComplete -isnot [bool] -or -not $child.streamDrainComplete -or $child.error -or $child.cleanupError){throw 'Serializer child exit/stream proof failed'}
  if(@($child.rawStreams).Count -ne 2 -or @($child.rawFileHashes).Count -ne 2){throw 'Serializer requires two raw streams'}
  foreach($name in @('stdout','stderr')){
   $states=@($child.rawStreams|Where-Object{$_.name -ceq $name});$hashes=@($child.rawFileHashes|Where-Object{$_.path -ceq ('compile.'+$name+'.bin')})
   if($states.Count -ne 1 -or $hashes.Count -ne 1){throw 'Serializer stream membership'}
   $state=$states[0];$raw=Join-Path $serializerRoot ($phase+'\compile.'+$name+'.bin')
   if($state.sealed -isnot [bool] -or -not $state.sealed -or $state.destinationClosed -isnot [bool] -or -not $state.destinationClosed -or $state.taskStatus -cne 'RanToCompletion' -or $state.closureTaskStatus -cne 'RanToCompletion' -or $hashes[0].hash.qualification -cne 'sealed-raw' -or (Get-FileHash $raw).Hash.ToLowerInvariant() -cne $hashes[0].hash.sha256){throw 'Serializer terminal raw stream mismatch'}
  }
 }
 $serializerStdout=Join-Path $serializerRoot 'run\compile.stdout.bin'
 if((Get-FileHash $serializerStdout).Hash.ToLowerInvariant() -cne $serializer.stdoutSha256 -or @([IO.File]::ReadAllText($serializerStdout) -split '\r?\n'|Where-Object{$_ -ceq 'SERIALIZER_CONTROL_PASS records=5 failClosed=true nativeLaunches=0'}).Count -ne 1){throw 'Actual serializer PASS marker missing'}

 if($CompileReceiptSha256 -cnotmatch '^[0-9a-f]{64}$' -or $ExeSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Measured actual compile receipt/exe pins mandatory'}
 $build=Join-Path $Package 'build-settled-r2';$observation=Join-Path $build 'observation.json'
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
