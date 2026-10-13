# Prospective Count20 coordinator: consumes preissued, independently guarded metadata.
# Frozen coordinator.ps1 remains source archive; this source skips issuer only after all receipts pass.
param(
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CompileReceiptHash,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExeHash,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SerializerControlSha256,
 [Parameter(Mandatory=$true)][string]$IssuedMetadataPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IssuedMetadataHash,
 [Parameter(Mandatory=$true)][string]$GuardControlsPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$GuardControlsHash,
 [Parameter(Mandatory=$true)][string]$MacSchemaReceiptPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$MacSchemaReceiptHash,
 [Parameter(Mandatory=$true)][string]$ProducerRoot,
 [Parameter(Mandatory=$true)][string]$AdmissionRoot,
 [Parameter(Mandatory=$true)][string]$ControlRoot,
 [Parameter(Mandatory=$true)][string]$RunRoot,
 [Parameter(Mandatory=$true)][string]$OutputRoot,
 [Parameter(Mandatory=$true)][string]$FreshGuardControlsPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$FreshGuardControlsHash,
 [Parameter(Mandatory=$true)][string]$IntegrationGuardPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IntegrationGuardHash,
 [Parameter(Mandatory=$true)][string]$SchemaPath,
 [ValidateSet(20)][int]$Count=20,
 [switch]$PreflightOnly
)
$ErrorActionPreference='Stop'
if($CompileReceiptHash -cnotmatch '^[0-9a-f]{64}$' -or $ExeHash -cnotmatch '^[0-9a-f]{64}$' -or $SerializerControlSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Measured lowercase SHA256 compile/executable/serializer control pins required'}
$overlayRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$here=[IO.Path]::GetFullPath($ProducerRoot)
$admissionRoot=[IO.Path]::GetFullPath($AdmissionRoot)
$controlRoot=[IO.Path]::GetFullPath($ControlRoot)
$runRoot=[IO.Path]::GetFullPath($RunRoot)
$outputRoot=[IO.Path]::GetFullPath($OutputRoot)
if(-not(Test-Path -LiteralPath $here -PathType Container)){throw 'Producer root missing'}
if(-not(Test-Path -LiteralPath $admissionRoot -PathType Container)){throw 'Explicit admission root missing'}
if(-not(Test-Path -LiteralPath $FreshGuardControlsPath -PathType Leaf)){throw 'Fresh guard controls missing'}
$firstProofOverlay=Join-Path $overlayRoot 'first-proof-fresh-r11-v12.ps1'
$firstProofHash='910ae4369d62bdbe50510b9f35db9f09a1536563aebce216459ff6d71735c902'
if(-not(Test-Path -LiteralPath $firstProofOverlay -PathType Leaf) -or (Get-FileHash -LiteralPath $firstProofOverlay).Hash.ToLowerInvariant() -cne $firstProofHash){throw 'Versioned first-proof overlay drift'}
$plan=Get-Content -Raw (Join-Path $here 'capture-plan.json')|ConvertFrom-Json
if($CompileReceiptHash -cne $plan.actualBuild.compileReceiptSha256 -or $ExeHash -cne $plan.actualBuild.exeSha256){throw 'Exact actual lease build receipt/exe pins required'}
if($null -eq $plan.dispatch.repeat){throw 'Reviewed dispatch.repeat plan required before Count20 resume'}
if($plan.dispatch.repeat.count -ne 20){throw 'Exact Count20 repeat plan required'}
if(Test-Path -LiteralPath $runRoot){throw 'Fresh capture output required'}
if(-not(Test-Path -LiteralPath $controlRoot -PathType Container)){throw 'Preissued coordinator folder missing'}
$issuedExpected=Join-Path $controlRoot 'issued-metadata.json'
if([IO.Path]::GetFullPath($IssuedMetadataPath) -cne [IO.Path]::GetFullPath($issuedExpected)){throw 'Exact preissued metadata path required'}
if(-not(Test-Path -LiteralPath $IssuedMetadataPath -PathType Leaf)){throw 'Preissued metadata missing'}
$cleanupHelper=Join-Path $here 'support\cleanup.ps1';$sealHelper=Join-Path $here 'support\stream-seal.ps1'
function Assert-ControlHelpers {
 if((Get-FileHash -LiteralPath $cleanupHelper).Hash.ToLowerInvariant() -cne 'a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7'){throw 'Cleanup helper drift'}
 if((Get-FileHash -LiteralPath $sealHelper).Hash.ToLowerInvariant() -cne '4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'){throw 'Stream helper drift'}
}
Assert-ControlHelpers
$rootManifest=Get-Content -Raw (Join-Path $here 'root-stage-manifest.json')|ConvertFrom-Json
$bindingEntry=@($rootManifest.files|Where-Object{$_.path -eq 'factory/native/windows/padding-capture-lease-capture-v3/integration-bindings.json'})
if($bindingEntry.Count -ne 1 -or $bindingEntry[0].sha256 -ne ('sha256:'+(Get-FileHash -LiteralPath (Join-Path $here 'integration-bindings.json')).Hash.ToLowerInvariant()) -or $bindingEntry[0].bytes -ne (Get-Item -LiteralPath (Join-Path $here 'integration-bindings.json')).Length){throw 'Integration binding manifest drift'}
$guardPath=[IO.Path]::GetFullPath($IntegrationGuardPath)
if((Get-FileHash -LiteralPath $guardPath).Hash.ToLowerInvariant() -cne $IntegrationGuardHash){throw 'Prefixed integration guard drift'}
. $guardPath
Assert-FactoryIntegrationSources $here
$producerRoot=$here
$issued=Get-Content -Raw -LiteralPath $IssuedMetadataPath|ConvertFrom-Json
if($issued.sourceHash -cne 'sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b'){throw 'Fresh r11 issued source hash binding missing'}
if((Get-FileHash -LiteralPath $GuardControlsPath).Hash.ToLowerInvariant() -cne $GuardControlsHash){throw 'Guard controls receipt hash mismatch'}
$guard=Get-Content -Raw -LiteralPath $GuardControlsPath|ConvertFrom-Json
if((Get-FileHash -LiteralPath $FreshGuardControlsPath).Hash.ToLowerInvariant() -cne $FreshGuardControlsHash){throw 'Fresh guard controls receipt hash mismatch'}
$freshGuard=Get-Content -Raw -LiteralPath $FreshGuardControlsPath|ConvertFrom-Json
if($guard.kind -cne 'factory-issued-metadata-full-guard-controls-v1' -or $guard.status -cne 'passed-source-only' -or $guard.count -ne 20 -or $guard.issuedMetadataPath -cne $IssuedMetadataPath -or $guard.issuedMetadataSha256 -cne $IssuedMetadataHash -or $guard.baseline.accepted -ne $true -or $guard.nativeWindowActions -ne 0 -or $guard.compilerActions -ne 0 -or $guard.guiActions -ne 0 -or $guard.remoteActions -ne 0 -or $guard.lockActions -ne 0){throw 'Full metadata guard controls receipt lineage not admitted'}
$expectedFaultNames=@('metadata-expected-count','metadata-host-argument','metadata-source-hash','metadata-serializer-prefix','metadata-runtime-modules','tuple-case','tuple-runtime','tuple-renderer','binding-frozen','binding-canonical-input-hash','mac-context-path')
$relocated=@($guard.faultControls|Where-Object{$_.name -ceq 'admitted-baseline-relocated-resealed'})
$faults=@($guard.faultControls|Where-Object{$_.name -cne 'admitted-baseline-relocated-resealed'})
if($relocated.Count -ne 1 -or $relocated[0].accepted -ne $true -or $relocated[0].rejected -ne $false -or $relocated[0].nativeWindowActions -ne 0 -or $faults.Count -ne 11 -or @($faults|Where-Object{$_.name -notin $expectedFaultNames -or $_.rejected -ne $true -or $_.accepted -ne $false -or $_.nativeWindowActions -ne 0 -or $_.outerMetadataResealed -ne $true}).Count -ne 0 -or @($faults.name|Select-Object -Unique).Count -ne 11 -or @($faults.name|Where-Object{$_ -in $expectedFaultNames}).Count -ne 11){throw 'Full metadata guard controls cases not admitted'}
if($freshGuard.kind -cne 'factory-fresh-count20-r11-guard-controls-v1' -or $freshGuard.status -ne 'passed-source-only' -or $freshGuard.issuedMetadataPath -ne [IO.Path]::GetFullPath($IssuedMetadataPath) -or $freshGuard.issuedMetadataSha256 -ne $IssuedMetadataHash -or $freshGuard.count -ne 20 -or $freshGuard.nativeWindowActions -ne 0 -or $freshGuard.compilerActions -ne 0 -or $freshGuard.guiActions -ne 0 -or $freshGuard.remoteActions -ne 0 -or $freshGuard.lockActions -ne 0 -or @($freshGuard.faultControls).Count -lt 4 -or @($freshGuard.faultControls|Where-Object{$_.rejected -ne $true -or $_.accepted -ne $false -or $_.nativeWindowActions -ne 0}).Count -ne 0){throw 'Fresh Count20 guard receipt lineage not admitted'}
if((Get-FileHash -LiteralPath $MacSchemaReceiptPath).Hash.ToLowerInvariant() -cne $MacSchemaReceiptHash){throw 'Mac schema receipt hash mismatch'}
$schemaReceipt=Get-Content -Raw -LiteralPath $MacSchemaReceiptPath|ConvertFrom-Json
$schemaPath=[IO.Path]::GetFullPath($SchemaPath)
if(-not(Test-Path -LiteralPath $schemaPath -PathType Leaf)){throw 'Explicit common schema path missing'}
$tuplePath=(Join-Path (Split-Path -Parent $IssuedMetadataPath) 'candidate-tuple.json')
$tuple=Get-Content -Raw -LiteralPath $tuplePath|ConvertFrom-Json
$sourceBinding=$tuple.sourceInputs.sourceBinding
$expectedSchemaHash='sha256:'+(Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
if([string]::IsNullOrWhiteSpace($sourceBinding.path) -or -not(Test-Path -LiteralPath $sourceBinding.path -PathType Leaf)){throw 'Fresh source-binding record missing'}
$sourceBindingItem=Get-Item -LiteralPath $sourceBinding.path -Force
if($sourceBindingItem.LinkType -or ($sourceBindingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $sourceBindingItem.Length -gt 2097152 -or $sourceBindingItem.Length -ne $sourceBinding.bytes){throw 'Fresh source-binding file bounds/ref drift'}
if((Get-FileHash -LiteralPath $sourceBinding.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sourceBinding.sha256.Replace('sha256:','')){throw 'Fresh source-binding byte/hash drift'}
$sourceBindingDoc=Get-Content -Raw -LiteralPath $sourceBinding.path|ConvertFrom-Json
if($sourceBindingDoc.historicalTemplate.witnessHash -cne $issued.sourceHash -or $sourceBindingDoc.renderer.sha256 -cne $plan.renderer.sha256){throw 'Fresh source-binding witness/renderer join missing'}
if($schemaReceipt.kind -cne 'factory-mac-common-schema-validation-receipt-v1' -or $schemaReceipt.version -ne '0.1' -or $schemaReceipt.status -cne 'PASS_LOCAL_COMMON_SCHEMA' -or $schemaReceipt.exitCode -ne 0 -or $schemaReceipt.tupleID -ne $tuple.tuple.id -or $schemaReceipt.frozenTupleBound -ne $false -or $schemaReceipt.nativeWindowActions -ne 0 -or $schemaReceipt.rootNonce -cne $issued.runID -or $schemaReceipt.sourceHash -cne $issued.sourceHash -or $schemaReceipt.candidateTupleRef.sha256 -cne $issued.candidateTuple.sha256 -or $schemaReceipt.candidateTupleRef.bytes -ne $issued.candidateTuple.bytes -or $schemaReceipt.schemaRef.sha256 -cne $expectedSchemaHash -or $schemaReceipt.schemaRef.bytes -ne (Get-Item -LiteralPath $schemaPath).Length -or [string]::IsNullOrWhiteSpace($schemaReceipt.toolRef.path) -or $schemaReceipt.toolRef.sha256 -notmatch '^sha256:[0-9a-f]{64}$' -or $schemaReceipt.toolRef.bytes -le 0 -or $schemaReceipt.sourceRef.path -cne $sourceBinding.path -or $schemaReceipt.sourceRef.sha256 -cne $sourceBinding.sha256 -or $schemaReceipt.sourceRef.bytes -ne $sourceBinding.bytes -or [string]::IsNullOrWhiteSpace($schemaReceipt.sourceArchiveRef.path) -or $schemaReceipt.sourceArchiveRef.sha256 -notmatch '^sha256:[0-9a-f]{64}$' -or $schemaReceipt.sourceArchiveRef.bytes -le 0){throw 'Mac common schema receipt actual joins not admitted'}
. (Join-Path $here 'support\final-exit-certificate.ps1')
. $cleanupHelper
. $sealHelper
. (Join-Path $here 'dependencies\uia-worker\support\final-exit-certificate.ps1')
. (Join-Path $here 'support\all-owned-release.ps1')
$receiptPath=Join-Path $plan.compiledHostPackagePath 'build-capture-lease-r1\observation.json'
if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -cne $CompileReceiptHash){throw 'Compile receipt drift'}
$compiled=Get-Content -Raw $receiptPath|ConvertFrom-Json
if($compiled.sourceHash -notmatch '^sha256:[0-9a-f]{64}$' -or $compiled.planSha256 -notmatch '^[0-9a-f]{64}$' -or $compiled.rendererSha256 -notmatch '^[0-9a-f]{64}$' -or $compiled.sourceHash -cne $issued.sourceHash -or ('sha256:'+$compiled.planSha256) -cne $plan.sourcePlanSha256 -or ('sha256:'+$compiled.rendererSha256) -cne $plan.renderer.sha256){throw 'Fresh r11 compiled source-plan binding missing'}
$exe=[IO.Path]::GetFullPath($compiled.exePath)
if(-not $exe.StartsWith($plan.compiledHostPackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or $compiled.exeSha256 -cne $ExeHash -or (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -cne $ExeHash){throw 'Executable lineage drift'}
$buildPreflightPath=$plan.launchPreflightPath
if(-not (Test-Path -LiteralPath $buildPreflightPath -PathType Leaf)){throw 'Reviewed build preflight missing'}
if((Get-FileHash -LiteralPath $buildPreflightPath).Hash.ToLowerInvariant() -ne $plan.launchPreflightSha256.Replace('sha256:','')){throw 'Reviewed build preflight drift'}
& $buildPreflightPath -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256 | Out-Null
$FirstProofSchemaPath=Join-Path $here 'dependencies\uia-worker\schema.ps1'
if(-not(Test-Path -LiteralPath $FirstProofSchemaPath -PathType Leaf)){throw 'Pinned first-proof schema dependency missing'}
. $firstProofOverlay -UiaSchemaPath (Join-Path $here 'dependencies\uia-worker\schema.ps1')
Assert-PaddingFirstCaptureProof -CaptureRoot $here -CompiledReceiptPath $receiptPath -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256 -ExpectedRunRoot $plan.dispatch.first.runRoot -AdmissionRoot $admissionRoot
if($PreflightOnly){[ordered]@{kind='factory-native-overlay-coordinator-preflight-v10';status='passed-source-only';runRoot=$runRoot;outputRoot=$outputRoot;controlRoot=$controlRoot;issuedMetadataHash=$IssuedMetadataHash;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;nativeWindowActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $controlRoot 'coordinator-preflight.json') -Encoding UTF8;return}
$lock='D:\Claude\desktop.lock'
$owner='padding-window-diagnosis-'+[Guid]::NewGuid().ToString('N')+' '+[DateTimeOffset]::UtcNow.ToString('o')
$taskName='PaddingWindowDiagnosis-'+[Guid]::NewGuid().ToString('N')
function Change-Lock([string]$expected,[string]$replacement){
 try{$stream=[IO.File]::Open($lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{return $false}
 try{
  $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,1024,$true)
  try{$state=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()}
  if($state -cne $expected){return $false}
  $data=[Text.Encoding]::UTF8.GetBytes($replacement)
  $stream.Position=0;$stream.SetLength(0);$stream.Write($data,0,$data.Length);$stream.Flush($true)
  return $true
 }finally{$stream.Dispose()}
}
$acquired=$false;$registered=$false;$started=$false;$released=$false;$terminalResultConfirmed=$false
$status='hold-desktop-busy';$primaryError=$null;$taskResult=$null;$cleanupErrors=@();$releaseAllowed=$false
try{
 # One silent until-loop waits for free without timeout, output or contention pings.
 do{
  $acquired=Change-Lock 'free' $owner
  if(-not $acquired){Start-Sleep -Seconds 3}
 }until($acquired)
 $issuedPath=$IssuedMetadataPath
 $issuedHash=$IssuedMetadataHash
 $config=Join-Path $controlRoot 'config.json'
 if(Test-Path -LiteralPath $config){throw 'Coordinator config already exists; refusing overwrite'}
 [ordered]@{owner=$owner;count=$Count;producerRoot=$here;runRoot=$runRoot;controlRoot=$controlRoot;outputRoot=$outputRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;schemaPath=$schemaPath;issuedMetadataPath=$issuedPath;issuedMetadataHash=$issuedHash;freshGuardControlsPath=$FreshGuardControlsPath;freshGuardControlsHash=$FreshGuardControlsHash;integrationGuardPath=$guardPath;integrationGuardHash=$IntegrationGuardHash}|ConvertTo-Json|Set-Content -Encoding UTF8 $config
 $arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $overlayRoot 'interactive-task-fresh-r11-v10.ps1')+'" -Config "'+$config+'"'
 $vbs=Join-Path $controlRoot 'hidden-task.vbs'
 $vbsText='Set sh = CreateObject("WScript.Shell")'+[Environment]::NewLine+'rc = sh.Run("powershell.exe '+$arguments.Replace('"','""')+'", 0, True)'+[Environment]::NewLine+'WScript.Quit rc'
 [IO.File]::WriteAllText($vbs,$vbsText,[Text.Encoding]::ASCII)
 $action=New-ScheduledTaskAction -Execute (Join-Path $env:windir 'System32\wscript.exe') -Argument ('"'+$vbs+'"')
 $principal=New-ScheduledTaskPrincipal -UserId 'adrds' -LogonType Interactive -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings|Out-Null
 $registered=$true
 # Mark possible start before API call: failure cannot imply no interactive worker.
 $started=$true;Start-ScheduledTask -TaskName $taskName
 $taskResultPath=Join-Path $controlRoot 'task-result.json'
 $jobDeadline=[DateTime]::UtcNow.AddMinutes(10)
 do{
  if(Test-Path -LiteralPath $taskResultPath){
   $taskResult=Get-Content -Raw $taskResultPath|ConvertFrom-Json
   if($taskResult.owner -cne $owner -or $taskResult.count -ne $Count -or $taskResult.runRoot -cne $runRoot -or $taskResult.compileReceiptHash -cne $CompileReceiptHash -or $taskResult.exeHash -cne $ExeHash -or $taskResult.issuedMetadataHash -cne $issuedHash -or $taskResult.serializerControlSha256 -cne $SerializerControlSha256 -or $taskResult.status -cnotin @('completed-source-bound-observation','hold-harness-error')){throw 'Interactive result lineage mismatch'}
   $terminalResultConfirmed=$true
   $status=$taskResult.status
   if($status -cne 'completed-source-bound-observation'){throw ('Interactive capture failed: '+$taskResult.error)}
   break
  }
  if([DateTime]::UtcNow -ge $jobDeadline){$status='hold-native-timeout';throw 'Interactive capture deadline'}
  Start-Sleep -Seconds 3
 }until($false)
}catch{$primaryError=$_;if($status -cne 'hold-native-timeout' -and $acquired){$status='hold-harness-error'}}
finally{
 try{
  # Prevent later starts, then confirm task quiescence before inspecting whole repeat.
  $taskStopped=$true
  if($registered){
   Disable-ScheduledTask -TaskName $taskName|Out-Null
   if($null -ne $primaryError){Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop}
   $stopDeadline=[DateTime]::UtcNow.AddSeconds(15)
   do{
    $taskState=(Get-ScheduledTask -TaskName $taskName).State
    if($taskState -notin @('Running','Queued')){break}
    if([DateTime]::UtcNow -ge $stopDeadline){throw 'Interactive task quiescence unconfirmed'}
    Start-Sleep -Milliseconds 200
   }until($false)
   Get-ScheduledTaskInfo -TaskName $taskName|Select-Object LastRunTime,LastTaskResult,NextRunTime|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $controlRoot 'scheduled-task-receipt.json')
  }
  if($started -and -not $terminalResultConfirmed){throw 'Possible interactive worker start lacks exact terminal result; scheduler state cannot certify hidden child exit'}
  Assert-ControlHelpers
  if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -cne $CompileReceiptHash -or (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -cne $ExeHash){throw 'Cleanup compile/executable lineage drift'}
  $dirs=@();if(Test-Path -LiteralPath $runRoot){$dirs=@(Get-ChildItem -LiteralPath $runRoot -Directory|Where-Object{$_.Name -like 'native-*'})}
  if($dirs.Count -gt $Count -or ($status -ceq 'completed-source-bound-observation' -and $dirs.Count -ne $Count)){throw 'Whole repeat child cardinality mismatch'}
  if(@($taskResult.workerInventories).Count -ne $dirs.Count){throw 'Terminal task exhaustive inventory cardinality mismatch'}
  foreach($dir in $dirs){
   if($dir.Name -cnotmatch '^native-(0[1-9]|1[0-9]|20)$' -or [int]$dir.Name.Substring(7) -gt $Count){throw 'Unexpected repeat child directory'}
   $bound=@($taskResult.workerInventories|Where-Object{$_.directory -ceq $dir.FullName})
   $inventoryPath=Join-Path $dir.FullName 'owned-worker-inventory.json'
   if($bound.Count -ne 1 -or $bound[0].path -cne $inventoryPath -or $bound[0].sha256 -cne (Get-FileHash -LiteralPath $inventoryPath).Hash.ToLowerInvariant()){throw 'Terminal task worker inventory raw binding mismatch'}
   Assert-FactoryAllOwnedRelease $dir.FullName $owner $receiptPath $CompileReceiptHash $exe $ExeHash $compiled.sourceHash

  }
  $releaseAllowed=$true
 }catch{$cleanupErrors+=([string]$_);$releaseAllowed=$false}
 $released=Invoke-FactoryConfirmedRelease $acquired $releaseAllowed {Change-Lock $owner 'free'}
 if($acquired -and -not $released){$cleanupErrors+='Desktop lock retained: release ownership or cleanup proof unconfirmed'}
 [ordered]@{kind='padding-window-diagnosis-interactive-coordinator';status=$status;count=$Count;owner=$owner;runRoot=$runRoot;controlRoot=$controlRoot;admissionRoot=$admissionRoot;firstProofPath=$firstProofOverlay;firstProofHash=$firstProofHash;sourceHash=$issued.sourceHash;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;lockAcquired=$acquired;lockReleased=$released;wholeBatchExitConfirmed=$releaseAllowed;taskName=$taskName;taskRegistered=$registered;taskStarted=$started;terminalResultConfirmed=$terminalResultConfirmed;error=if($null -ne $primaryError){[string]$primaryError}else{''};errorId=if($null -ne $primaryError){$primaryError.FullyQualifiedErrorId}else{''};interactiveError=if($null -ne $taskResult){$taskResult.error}else{''};interactiveErrorId=if($null -ne $taskResult){$taskResult.errorId}else{''};cleanupErrors=$cleanupErrors;qualification='hold';nativeParity='hold';frozenTupleBound=$false}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $controlRoot 'coordinator.json')
}
if($null -ne $primaryError){throw $primaryError}
if(-not $released){throw 'Coordinator cleanup/release incomplete; inspect coordinator.json'}
