function Test-FactoryCombinedReleaseAuthority($RendererProof,$WorkerProof){
 return [bool]($RendererProof -is [bool] -and $RendererProof -and $WorkerProof -is [bool] -and $WorkerProof)
}
# Release requires BOTH renderer & every predeclared UIA slot. No process lookup or status promotion.
function Assert-RootCircleAllOwnedRelease([string]$Directory,[string]$Owner,[string]$CompilePath,[string]$CompileHash,[string]$Exe,[string]$ExeHash,[string]$SourceHash,[string]$ProducerRoot,[object]$SourceInputs){
 Assert-FactoryIntegrationSources $ProducerRoot $SourceInputs
 $owned=Get-Content -Raw -LiteralPath (Join-Path $Directory 'owned-process.json')|ConvertFrom-Json
 $outcomePath=Join-Path $Directory 'capture-outcome.json';$outcome=Get-Content -Raw -LiteralPath $outcomePath|ConvertFrom-Json
 if($outcome.lockOwner -cne $Owner -or $outcome.sourceHash -cne $SourceHash -or $outcome.compileReceiptHash -cne $CompileHash -or $outcome.exeHash -cne $ExeHash){throw 'Renderer original outcome lineage mismatch'}
 $workerPath=Join-Path $Directory 'terminal-worker.json';$certPath=Join-Path $Directory 'final-exit-certificate.json'
 $expected=Get-Content -Raw -LiteralPath (Join-Path $Directory 'final-start.json')|ConvertFrom-Json
 if(-not(Test-FactoryFinalStart $expected) -or $expected.pid -ne $owned.pid -or $expected.path -cne $Exe -or $expected.startedAt -cne $owned.startedAt -or $expected.lockOwner -cne $Owner -or $expected.workerId -cne $Directory -or $expected.compileReceiptHash -cne $CompileHash -or $expected.exeHash -cne $ExeHash){throw 'Renderer final start original lineage mismatch'}
 $expected|Add-Member workerReceiptRef $workerPath;$expected|Add-Member workerReceiptHash ((Get-FileHash -LiteralPath $workerPath).Hash.ToLowerInvariant());$expected|Add-Member compileReceiptRef $CompilePath;$expected|Add-Member exeRef $Exe
 $certificate=Get-Content -Raw -LiteralPath $certPath|ConvertFrom-Json
 $terminal=Get-Content -Raw -LiteralPath $workerPath|ConvertFrom-Json
 if($terminal.finalCertificateRef -cne $certPath -or $terminal.originalOutcomeRef -cne $outcomePath -or $terminal.originalOutcomeHash -cne (Get-FileHash -LiteralPath $outcomePath).Hash.ToLowerInvariant()){throw 'Renderer terminal/outcome reference mismatch'}
 foreach($raw in @($certificate.rawStreams)){
  $requiredPath=Join-Path $Directory ('host.'+$raw.name+'.txt');$hash=if($raw.name -ceq 'stdout'){$outcome.stdoutSha256}elseif($raw.name -ceq 'stderr'){$outcome.stderrSha256}else{throw 'Unknown renderer final stream'}
  if($raw.path -cne $requiredPath -or $raw.sha256 -cne $hash){throw 'Renderer final raw/outcome mismatch'}
 }
 $allowedRefs=@($workerPath,$certPath,$CompilePath,$Exe,(Join-Path $Directory 'host.stdout.txt'),(Join-Path $Directory 'host.stderr.txt'))
 $reader={param($ref) if($allowedRefs -cnotcontains $ref){throw 'Renderer final read outside exact closure'};return ,([IO.File]::ReadAllBytes($ref))}
 if(-not(Test-FactoryFinalReleaseProof $certificate $expected $reader)){throw 'Renderer final original handle proof absent'}
 $declaration=Get-Content -Raw -LiteralPath (Join-Path $Directory 'declared-worker-inventory.json')|ConvertFrom-Json
 $declaredRoot=Join-Path $Directory 'uia-worker'
 if($declaration.kind -cne 'factory-owned-uia-slot-inventory-v1' -or $declaration.lockOwner -cne $Owner -or $declaration.rendererDirectory -cne $Directory -or @($declaration.roots).Count -ne 1 -or $declaration.roots[0] -cne $declaredRoot -or $declaration.attempted -isnot [bool] -or $declaration.attempted){throw 'Exact prelaunch worker declaration required'}
 $root=Join-Path $Directory 'uia-worker';$inventory=Get-Content -Raw -LiteralPath (Join-Path $Directory 'owned-worker-inventory.json')|ConvertFrom-Json
 if($inventory.kind -cne 'factory-owned-uia-slot-inventory-v1' -or $inventory.lockOwner -cne $Owner -or $inventory.rendererDirectory -cne $Directory -or @($inventory.roots).Count -ne 1 -or $inventory.roots[0] -cne $root -or $inventory.attempted -isnot [bool]){throw 'Exact exhaustive worker slot inventory required'}
 $sourceRoot=Join-Path $ProducerRoot 'dependencies\uia-worker'
 $definiteNoStartPath=Join-Path $Directory 'uia-no-start.json'
 if($inventory.attempted -and (Test-Path -LiteralPath $definiteNoStartPath)){
  if($SourceInputs.PSObject.Properties.Name -notcontains 'definiteNoWorkerStartRef' -or $null -eq $SourceInputs.definiteNoWorkerStartRef -or [string]::IsNullOrWhiteSpace([string]$SourceInputs.definiteNoWorkerStartRef.path) -or [string]::IsNullOrWhiteSpace([string]$SourceInputs.definiteNoWorkerStartRef.sha256)){throw 'Definite no-worker-start source binding missing'}
  if($SourceInputs.PSObject.Properties.Name -notcontains 'integrationBindingsRef' -or $null -eq $SourceInputs.integrationBindingsRef -or [string]::IsNullOrWhiteSpace([string]$SourceInputs.integrationBindingsRef.path) -or [string]::IsNullOrWhiteSpace([string]$SourceInputs.integrationBindingsRef.sha256) -or $SourceInputs.integrationBindingsRef.bytes -le 0){throw 'Definite no-worker-start integration binding reference missing'}
  $integrationPath=[string]$SourceInputs.integrationBindingsRef.path
  if(-not [IO.Path]::IsPathRooted($integrationPath)){$integrationPath=Join-Path $ProducerRoot $integrationPath}
  $integrationItem=Get-Item -LiteralPath $integrationPath -Force -ErrorAction Stop
  if($integrationItem.PSIsContainer -or $integrationItem.LinkType -or (($integrationItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $integrationItem.Length -ne [int64]$SourceInputs.integrationBindingsRef.bytes){throw 'Integration binding bytes drift'}
  $integrationHash=(Get-FileHash -LiteralPath $integrationPath).Hash.ToLowerInvariant();$integrationExpected=(([string]$SourceInputs.integrationBindingsRef.sha256)-replace '^sha256:','').ToLowerInvariant()
  if($integrationHash -cne $integrationExpected){throw 'Integration binding hash drift'}
  $bindingDoc=Get-Content -Raw -LiteralPath $integrationPath|ConvertFrom-Json;$bindingRows=@()
  if($bindingDoc.PSObject.Properties.Name -contains 'files' -and $null -ne $bindingDoc.files){$bindingRows+=@($bindingDoc.files)}
  foreach($property in @('sourceBindings','bindings','rows')){if($bindingDoc.PSObject.Properties.Name -contains $property -and $null -ne $bindingDoc.$property){$bindingRows+=@($bindingDoc.$property)}}
  $definitePathRef=(([string]$SourceInputs.definiteNoWorkerStartRef.path)-replace '\\','/')
  if([IO.Path]::IsPathRooted($definitePathRef)){$producerPrefix=(([IO.Path]::GetFullPath($ProducerRoot))-replace '\\','/').TrimEnd('/');if($definitePathRef.StartsWith($producerPrefix+'/')){$definitePathRef=$definitePathRef.Substring($producerPrefix.Length+1)}}
  $bindingMatch=@($bindingRows|Where-Object{(([string]$_.path)-replace '\\','/') -ceq $definitePathRef -and (([string]$_.sha256)-replace '^sha256:','').ToLowerInvariant() -ceq (([string]$SourceInputs.definiteNoWorkerStartRef.sha256)-replace '^sha256:','').ToLowerInvariant()})
  if($bindingMatch.Count -ne 1){throw 'Definite no-worker-start integration binding mismatch'}
  $definitePath=[string]$SourceInputs.definiteNoWorkerStartRef.path
  if(-not [IO.Path]::IsPathRooted($definitePath)){$definitePath=Join-Path $ProducerRoot $definitePath}
  if(-not (Test-Path -LiteralPath $definitePath -PathType Leaf)){throw 'Definite no-worker-start validator missing'}
  $definiteActual=(Get-FileHash -LiteralPath $definitePath).Hash.ToLowerInvariant();$definiteExpected=(([string]$SourceInputs.definiteNoWorkerStartRef.sha256)-replace '^sha256:','').ToLowerInvariant()
  if($definiteActual -cne $definiteExpected){throw 'Definite no-worker-start validator hash drift'}
  . $definitePath
  if($SourceInputs.PSObject.Properties.Name -notcontains 'uiaWorkerPath' -or $SourceInputs.PSObject.Properties.Name -notcontains 'uiaWorkerHash' -or [string]::IsNullOrWhiteSpace([string]$SourceInputs.uiaWorkerPath) -or [string]::IsNullOrWhiteSpace([string]$SourceInputs.uiaWorkerHash)){throw 'Definite no-worker-start UIA invoker binding missing'}
  $workerInvokerPath=[string]$SourceInputs.uiaWorkerPath
  if(-not [IO.Path]::IsPathRooted($workerInvokerPath)){$workerInvokerPath=Join-Path $ProducerRoot $workerInvokerPath}
  $invokerPathRef=(([string]$SourceInputs.uiaWorkerPath)-replace '\\','/')
  if([IO.Path]::IsPathRooted($invokerPathRef)){$producerPrefix=(([IO.Path]::GetFullPath($ProducerRoot))-replace '\\','/').TrimEnd('/');if($invokerPathRef.StartsWith($producerPrefix+'/')){$invokerPathRef=$invokerPathRef.Substring($producerPrefix.Length+1)}}
  $invokerBinding=@($bindingRows|Where-Object{(([string]$_.path)-replace '\\','/') -ceq $invokerPathRef -and (([string]$_.sha256)-replace '^sha256:','').ToLowerInvariant() -ceq (([string]$SourceInputs.uiaWorkerHash)-replace '^sha256:','').ToLowerInvariant()})
  if($invokerBinding.Count -ne 1){throw 'Definite no-worker-start UIA invoker integration binding mismatch'}
  $invokerItem=Get-Item -LiteralPath $workerInvokerPath -Force -ErrorAction Stop
  if($invokerItem.PSIsContainer -or $invokerItem.LinkType -or (($invokerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $invokerItem.Length -ne [int64]$invokerBinding[0].bytes){throw 'Definite no-worker-start UIA invoker bytes drift'}
  $contractBinding=@($bindingRows|Where-Object{(([string]$_.path)-replace '\\','/') -ceq 'dependencies/uia-worker/worker-contract.json'})
  if($contractBinding.Count -ne 1){throw 'Definite no-worker-start worker contract binding missing'}
  $contractPath=Join-Path $sourceRoot 'worker-contract.json';$contractItem=Get-Item -LiteralPath $contractPath -Force -ErrorAction Stop
  if($contractItem.PSIsContainer -or $contractItem.LinkType -or (($contractItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $contractItem.Length -ne [int64]$contractBinding[0].bytes){throw 'Definite no-worker-start worker contract bytes drift'}
  $definiteResult=Assert-FactoryDefiniteNoWorkerStart -ReceiptPath $definiteNoStartPath -FailureText ([string]$outcome.primaryError) -WorkerRoot $root -WorkerSourceRoot $sourceRoot -WorkerInvokerPath $workerInvokerPath -WorkerContractPath $contractPath -ExpectedInvokerHash ([string]$SourceInputs.uiaWorkerHash) -ExpectedWorkerContractHash ([string]$contractBinding[0].sha256) -Owner $Owner
  if($null -eq $definiteResult -or $definiteResult.processStartReached -ne $false){throw 'Definite no-worker-start admission failed'}
  if(-not(Test-FactoryCombinedReleaseAuthority $true $true)){throw 'Combined renderer/definite-no-start release policy failed'}
  return
 }
 if(-not $inventory.attempted){
  $noStart=Get-Content -Raw -LiteralPath $definiteNoStartPath|ConvertFrom-Json
  if($noStart.kind -cne 'factory-uia-slot-no-start-v1' -or $noStart.root -cne $root -or $noStart.lockOwner -cne $Owner -or $noStart.rendererDirectory -cne $Directory -or $noStart.attempted -isnot [bool] -or $noStart.attempted -or $noStart.noInvocationConfirmed -isnot [bool] -or -not $noStart.noInvocationConfirmed -or (Test-Path -LiteralPath $root)){throw 'Worker no-start producer proof absent'}
  if(-not(Test-FactoryCombinedReleaseAuthority $true $true)){throw 'Combined renderer/no-start release policy failed'}
  return
 }
 $contractPath=Join-Path $sourceRoot 'worker-contract.json';$contract=Get-Content -Raw $contractPath|ConvertFrom-Json
 $start=Get-Content -Raw -LiteralPath (Join-Path $root 'final-start.json')|ConvertFrom-Json
 $workerOwned=Get-Content -Raw -LiteralPath (Join-Path $root 'owned-worker.json')|ConvertFrom-Json
 $psExe=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
 if(-not(Test-FactoryUiaFinalStart $start) -or $start.pid -ne $workerOwned.pid -or $start.retainedHandle -ne $workerOwned.retainedHandle -or $start.startedAt -cne $workerOwned.startedAt -or $start.path -cne $psExe -or $workerOwned.path -cne $psExe -or $start.lockOwner -cne $Owner -or $start.workerId -cne $root){throw 'Worker original retained start lineage mismatch'}
 $configPath=Join-Path $root 'config.json';$config=Get-Content -Raw $configPath|ConvertFrom-Json
 if($config.target.pid -ne $owned.pid -or $config.target.path -cne $Exe -or $config.target.startedAt -cne $owned.startedAt -or $config.target.lockOwner -cne $Owner){throw 'Worker target renderer lineage mismatch'}
 $attempt=Get-Content -Raw -LiteralPath (Join-Path $root 'worker-launch-attempt.json')|ConvertFrom-Json
 if($attempt.kind -cne 'factory-uia-worker-launch-attempt-v1' -or $attempt.workerId -cne $root -or $attempt.lockOwner -cne $Owner -or $attempt.configHash -cne $start.configHash -or $attempt.workerExeHash -cne $start.workerExeHash -or $attempt.sourceContractHash -cne $start.sourceContractHash){throw 'Worker attempt/start lineage mismatch'}
 $terminalPath=Join-Path $root 'terminal-worker.json';$workerCertPath=Join-Path $root 'final-exit-certificate.json';$originalPath=Join-Path $root 'worker-exit.json'
 $wt=Get-Content -Raw $terminalPath|ConvertFrom-Json
 if($wt.finalCertificateRef -cne $workerCertPath -or $wt.originalOutcomeRef -cne $originalPath){throw 'Worker exact terminal paths required'}
 $start|Add-Member workerReceiptRef $terminalPath;$start|Add-Member workerReceiptHash ((Get-FileHash $terminalPath).Hash.ToLowerInvariant())
 $start|Add-Member workerExeRef $psExe;$start|Add-Member sourceContractRef $contractPath;$start|Add-Member configRef $configPath;$start|Add-Member workerScriptRef (Join-Path $sourceRoot 'worker.ps1')
 $sourceBindings=@($contract.sourceBindings|ForEach-Object{[pscustomobject]@{path=$_.path;ref=(Join-Path $sourceRoot $_.path);sha256=$_.sha256}})
 $start|Add-Member sourceBindings $sourceBindings
 $workerCertificate=Get-Content -Raw $workerCertPath|ConvertFrom-Json
 foreach($raw in @($workerCertificate.rawStreams)){if($raw.path -cne (Join-Path $root ($raw.name+'.bin'))){throw 'Worker exact raw paths required'}}
 $workerRefs=@($terminalPath,$workerCertPath,$originalPath,$psExe,$contractPath,$configPath,(Join-Path $sourceRoot 'worker.ps1'),(Join-Path $root 'stdout.bin'),(Join-Path $root 'stderr.bin'))+@($sourceBindings|ForEach-Object{$_.ref})
 $workerReader={param($ref) if($workerRefs -cnotcontains $ref){throw 'Worker final read outside exact closure'};return ,([IO.File]::ReadAllBytes($ref))}
 $workersConfirmed=Test-FactoryAllUiaWorkerReleaseProofs @($root) @([pscustomobject]@{certificate=$workerCertificate;expected=$start}) $workerReader
 if(-not(Test-FactoryCombinedReleaseAuthority $true $workersConfirmed)){throw 'All owned worker original handle proofs required'}
}
