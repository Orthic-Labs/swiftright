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
 [ValidateSet(20)][int]$Count=20
)
$ErrorActionPreference='Stop'
if($CompileReceiptHash -cnotmatch '^[0-9a-f]{64}$' -or $ExeHash -cnotmatch '^[0-9a-f]{64}$' -or $SerializerControlSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Measured lowercase SHA256 compile/executable/serializer control pins required'}
$overlayRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$here=[IO.Path]::GetFullPath((Join-Path $overlayRoot '..\..'))
$expectedHere='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3'
if($here -cne $expectedHere){throw 'Exact capture coordinator lane required'}
$plan=Get-Content -Raw (Join-Path $here 'capture-plan.json')|ConvertFrom-Json
if($CompileReceiptHash -cne $plan.actualBuild.compileReceiptSha256 -or $ExeHash -cne $plan.actualBuild.exeSha256){throw 'Exact actual lease build receipt/exe pins required'}
$controlRoot=Join-Path $here 'coordinator-repeat-r1'
if($null -eq $plan.dispatch.repeat){throw 'Reviewed dispatch.repeat plan required before Count20 resume'}
$runRoot=$plan.dispatch.repeat.runRoot
if($runRoot -cne (Join-Path $here 'actual-repeat-r1')){throw 'Exact Count20 repeat output namespace required'}
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
$guardPath=Join-Path $overlayRoot 'integration-prefixed-ids-r1.ps1'
if((Get-FileHash -LiteralPath $guardPath).Hash.ToLowerInvariant() -cne 'd4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'){throw 'Prefixed integration guard drift'}
. $guardPath
Assert-FactoryIntegrationSources $here
$producerRoot=$here
Assert-LeaseIssuedMetadata $IssuedMetadataPath $IssuedMetadataHash $runRoot $Count $CompileReceiptHash $ExeHash $SerializerControlSha256 $producerRoot | Out-Null
$issued=Get-Content -Raw -LiteralPath $IssuedMetadataPath|ConvertFrom-Json
if((Get-FileHash -LiteralPath $GuardControlsPath).Hash.ToLowerInvariant() -cne $GuardControlsHash){throw 'Guard controls receipt hash mismatch'}
$guard=Get-Content -Raw -LiteralPath $GuardControlsPath|ConvertFrom-Json
if($guard.kind -cne 'factory-issued-metadata-full-guard-controls-v1' -or $guard.status -cne 'passed-source-only' -or $guard.count -ne 20 -or $guard.issuedMetadataPath -cne $IssuedMetadataPath -or $guard.issuedMetadataSha256 -cne $IssuedMetadataHash -or $guard.baseline.accepted -ne $true -or $guard.nativeWindowActions -ne 0 -or $guard.compilerActions -ne 0 -or $guard.guiActions -ne 0 -or $guard.remoteActions -ne 0 -or $guard.lockActions -ne 0){throw 'Full metadata guard controls receipt lineage not admitted'}
$expectedFaultNames=@('metadata-expected-count','metadata-host-argument','metadata-source-hash','metadata-serializer-prefix','metadata-runtime-modules','tuple-case','tuple-runtime','tuple-renderer','binding-frozen','binding-canonical-input-hash','mac-context-path')
$relocated=@($guard.faultControls|Where-Object{$_.name -ceq 'admitted-baseline-relocated-resealed'})
$faults=@($guard.faultControls|Where-Object{$_.name -cne 'admitted-baseline-relocated-resealed'})
if($relocated.Count -ne 1 -or $relocated[0].accepted -ne $true -or $relocated[0].rejected -ne $false -or $relocated[0].nativeWindowActions -ne 0 -or $faults.Count -ne 11 -or @($faults|Where-Object{$_.name -notin $expectedFaultNames -or $_.rejected -ne $true -or $_.accepted -ne $false -or $_.nativeWindowActions -ne 0 -or $_.outerMetadataResealed -ne $true}).Count -ne 0 -or @($faults.name|Select-Object -Unique).Count -ne 11 -or @($faults.name|Where-Object{$_ -in $expectedFaultNames}).Count -ne 11){throw 'Full metadata guard controls cases not admitted'}
if((Get-FileHash -LiteralPath $MacSchemaReceiptPath).Hash.ToLowerInvariant() -cne $MacSchemaReceiptHash){throw 'Mac schema receipt hash mismatch'}
$schemaReceipt=Get-Content -Raw -LiteralPath $MacSchemaReceiptPath|ConvertFrom-Json
$schemaPath=Join-Path $here '..\settled-capture-adapter-v3\dependencies\common.schema.json'
$tuplePath=(Join-Path (Split-Path -Parent $IssuedMetadataPath) 'candidate-tuple.json')
$tuple=Get-Content -Raw -LiteralPath $tuplePath|ConvertFrom-Json
$sourceBinding=$tuple.sourceInputs.sourceBinding
$expectedSchemaHash='sha256:'+(Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($schemaReceipt.kind -cne 'factory-mac-common-schema-validation-receipt-v1' -or $schemaReceipt.version -ne '0.1' -or $schemaReceipt.status -cne 'PASS_LOCAL_COMMON_SCHEMA' -or $schemaReceipt.exitCode -ne 0 -or $schemaReceipt.tupleID -ne 'sr1-source-bound-r11-20261011' -or $schemaReceipt.frozenTupleBound -ne $false -or $schemaReceipt.nativeWindowActions -ne 0 -or $schemaReceipt.rootNonce -cne $issued.runID -or $schemaReceipt.sourceHash -cne $issued.sourceHash -or $schemaReceipt.candidateTupleRef.sha256 -cne $issued.candidateTuple.sha256 -or $schemaReceipt.candidateTupleRef.bytes -ne $issued.candidateTuple.bytes -or $schemaReceipt.schemaRef.sha256 -cne $expectedSchemaHash -or $schemaReceipt.schemaRef.bytes -ne (Get-Item -LiteralPath $schemaPath).Length -or [string]::IsNullOrWhiteSpace($schemaReceipt.toolRef.path) -or $schemaReceipt.toolRef.sha256 -notmatch '^sha256:[0-9a-f]{64}$' -or $schemaReceipt.toolRef.bytes -le 0 -or $schemaReceipt.sourceRef.path -cne $sourceBinding.path -or $schemaReceipt.sourceRef.sha256 -cne $sourceBinding.sha256 -or $schemaReceipt.sourceRef.bytes -ne $sourceBinding.bytes -or [string]::IsNullOrWhiteSpace($schemaReceipt.sourceArchiveRef.path) -or $schemaReceipt.sourceArchiveRef.sha256 -notmatch '^sha256:[0-9a-f]{64}$' -or $schemaReceipt.sourceArchiveRef.bytes -le 0){throw 'Mac common schema receipt actual joins not admitted'}
. (Join-Path $here 'support\final-exit-certificate.ps1')
. $cleanupHelper
. $sealHelper
. (Join-Path $here 'dependencies\uia-worker\support\final-exit-certificate.ps1')
. (Join-Path $here 'support\all-owned-release.ps1')
$receiptPath=Join-Path $plan.compiledHostPackagePath 'build-capture-lease-r1\observation.json'
if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -cne $CompileReceiptHash){throw 'Compile receipt drift'}
$compiled=Get-Content -Raw $receiptPath|ConvertFrom-Json
$exe=[IO.Path]::GetFullPath($compiled.exePath)
if(-not $exe.StartsWith($plan.compiledHostPackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or $compiled.exeSha256 -cne $ExeHash -or (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -cne $ExeHash){throw 'Executable lineage drift'}
$buildPreflightPath=$plan.launchPreflightPath
if(-not (Test-Path -LiteralPath $buildPreflightPath -PathType Leaf)){throw 'Reviewed build preflight missing'}
if((Get-FileHash -LiteralPath $buildPreflightPath).Hash.ToLowerInvariant() -ne $plan.launchPreflightSha256.Replace('sha256:','')){throw 'Reviewed build preflight drift'}
& $buildPreflightPath -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256 | Out-Null
. (Join-Path $here 'support\first-proof-repeat-r7.ps1')
Assert-PaddingFirstCaptureProof -CaptureRoot $here -CompiledReceiptPath $receiptPath -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256 -ExpectedRunRoot $plan.dispatch.first.runRoot
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
 [ordered]@{owner=$owner;count=$Count;runRoot=$runRoot;controlRoot=$controlRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;issuedMetadataPath=$issuedPath;issuedMetadataHash=$issuedHash}|ConvertTo-Json|Set-Content -Encoding UTF8 $config
 $arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $overlayRoot 'interactive-task-repeat-r7.ps1')+'" -Config "'+$config+'"'
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
 [ordered]@{kind='padding-window-diagnosis-interactive-coordinator';status=$status;count=$Count;owner=$owner;runRoot=$runRoot;controlRoot=$controlRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;lockAcquired=$acquired;lockReleased=$released;wholeBatchExitConfirmed=$releaseAllowed;taskName=$taskName;taskRegistered=$registered;taskStarted=$started;terminalResultConfirmed=$terminalResultConfirmed;error=if($null -ne $primaryError){[string]$primaryError}else{''};errorId=if($null -ne $primaryError){$primaryError.FullyQualifiedErrorId}else{''};interactiveError=if($null -ne $taskResult){$taskResult.error}else{''};interactiveErrorId=if($null -ne $taskResult){$taskResult.errorId}else{''};cleanupErrors=$cleanupErrors;qualification='hold';nativeParity='hold';frozenTupleBound=$false}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $controlRoot 'coordinator.json')
}
if($null -ne $primaryError){throw $primaryError}
if(-not $released){throw 'Coordinator cleanup/release incomplete; inspect coordinator.json'}
