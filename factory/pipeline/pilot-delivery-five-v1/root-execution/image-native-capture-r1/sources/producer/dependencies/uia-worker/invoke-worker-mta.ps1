# Parent entry loads no UIA assembly/type. Reuses retained-handle & raw-stream framework.
function Invoke-FactoryUiaSnapshotWorker($Target,[string]$OutputRoot,[Parameter(Mandatory=$true)][scriptblock]$Guard,[string]$SourceRoot) {
 $ErrorActionPreference='Stop'
 if([string]::IsNullOrWhiteSpace($SourceRoot)){$sourceRoot=$PSScriptRoot}else{$sourceRoot=[IO.Path]::GetFullPath($SourceRoot)}
 $root=[IO.Path]::GetFullPath($OutputRoot)
 if(-not $root.StartsWith('D:\Claude\swiftright\.factory-work\hosts\image-star-observation\captures\count1-r1\native\',[StringComparison]::OrdinalIgnoreCase) -or $root -match '["\r\n]' -or (Test-Path -LiteralPath $root)){throw 'Fresh safe factory worker output required'}
 $manifest=Get-Content -Raw -LiteralPath (Join-Path $sourceRoot 'worker-contract.json')|ConvertFrom-Json
 foreach($b in $manifest.sourceBindings){if((Get-FileHash -LiteralPath (Join-Path $sourceRoot $b.path)).Hash.ToLowerInvariant() -cne $b.sha256){throw 'UIA worker/helper source drift'}}
 . (Join-Path $sourceRoot 'support\cleanup.ps1')
 . (Join-Path $sourceRoot 'support\stream-seal.ps1')
 . (Join-Path $sourceRoot 'schema.ps1')
 . (Join-Path $sourceRoot 'support\final-exit-certificate.ps1')
 Initialize-FactoryUiaFinalExitNative
 & $Guard | Out-Null
 New-Item -ItemType Directory -Path $root|Out-Null
 $apartment=[Threading.Thread]::CurrentThread.GetApartmentState().ToString()
 if($apartment -cnotin @('STA','MTA')){throw 'Observed parent apartment required'}
 $workerApartment='MTA'
 $config=[ordered]@{kind='factory-uia-snapshot-worker-config-v2';target=$Target;outputRoot=$root;parentApartment=$apartment;apartment=$workerApartment;sourceBindings=$manifest.sourceBindings}
 $configPath=Join-Path $root 'config.json';Write-FactoryDiagnosticJson $configPath $config
 $configHash=(Get-FileHash -LiteralPath $configPath).Hash.ToLowerInvariant()
 $exe=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $exeHash=(Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()
 $script=Join-Path $sourceRoot 'worker.ps1'
 $arguments='-NoProfile -NonInteractive -WindowStyle Hidden -MTA -ExecutionPolicy Bypass -File "'+$script+'" -Config "'+$configPath+'" -ConfigHash '+$configHash
 $si=[Diagnostics.ProcessStartInfo]::new($exe,$arguments);$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true;$si.WorkingDirectory=$root
 $proof=[ordered]@{kind='factory-uia-snapshot-worker-exit-v2';status='failed';target=$Target;ownedIdentity=$null;workerExeSha256=$exeHash;sourceContractSha256=(Get-FileHash (Join-Path $sourceRoot 'worker-contract.json')).Hash.ToLowerInvariant();configSha256=$configHash;parentApartment=$apartment;workerApartment=$workerApartment;startedAt=[DateTimeOffset]::UtcNow.ToString('o');exitCode=$null;timedOut=$false;preCleanupKernelWaitResult=$null;cleanup=$null;rawStreams=@();streamErrors=@();stdoutSha256=$null;stderrSha256=$null;uiaSha256=$null;primaryError='';nativeWindowsOpened=$false;rendererLoaded=$false}
 $p=$null;$streams=@();$primaryError=$null;$startedAt=$null;$finalStart=$null;$finalReleaseError='';$finalSample=$null
 try{
  foreach($name in @('stdout','stderr')){$file=[IO.File]::Open((Join-Path $root ($name+'.bin')),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$streams+=@([pscustomobject]@{name=$name;file=$file;source=$null;task=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false;closure=$null;closeTask=$null})}
  Write-FactoryDiagnosticJson (Join-Path $root 'worker-launch-attempt.json') ([ordered]@{kind='factory-uia-worker-launch-attempt-v1';workerId=$root;lockOwner=$Target.lockOwner;target=$Target;configHash=$configHash;workerExeHash=$exeHash;sourceContractHash=$proof.sourceContractSha256;at=[DateTimeOffset]::UtcNow.ToString('o')})
  $p=[Diagnostics.Process]::Start($si)
  $handle=$p.Handle
  # Bind stream readers immediately after retaining process handle. A worker may
  # exit before process identity can observe it; raw streams still need
  # draining into sealed receipts for truthful failure evidence.
  $streams[0].source=$p.StandardOutput.BaseStream;$streams[1].source=$p.StandardError.BaseStream
  foreach($s in $streams){$s.task=$s.source.CopyToAsync($s.file)}
  $workerPid=$p.Id
  $identityError=''
  try{$startedAt=$p.StartTime.ToUniversalTime().ToString('o')}catch{$startedAt=$null;$identityError=[string]$_}
  $proof.identityStatus=if([string]::IsNullOrEmpty($identityError)){'measured-before-use'}else{'fast-exit-before-start-time'}
  $proof.identityError=$identityError
  $proof.ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$startedAt;retainedHandle=$handle.ToInt64()}
  Write-FactoryDiagnosticJson (Join-Path $root 'owned-worker.json') $proof.ownedIdentity
  $finalStart=[ordered]@{pid=$p.Id;retainedHandle=$handle.ToInt64();path=$exe;startedAt=$startedAt;lockOwner=$Target.lockOwner;workerId=$root;workerExeHash=$exeHash;sourceContractHash=$proof.sourceContractSha256;configHash=$configHash;workerScriptHash=(Get-FileHash -LiteralPath $script).Hash.ToLowerInvariant()}
  Write-FactoryDiagnosticJson (Join-Path $root 'final-start.json') $finalStart
  if(-not [string]::IsNullOrEmpty($identityError)){throw ('Worker exited before retained identity measurement: '+$identityError)}
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  while(-not $p.WaitForExit(100)){& $Guard | Out-Null;if([DateTime]::UtcNow -gt $deadline){$proof.timedOut=$true;throw 'UIA worker acquisition/exit deadline'}}
  $proof.preCleanupKernelWaitResult=[int][FactoryProcessWaitV5]::WaitForSingleObject($handle,0)
  if($proof.preCleanupKernelWaitResult -ne 0){throw 'UIA worker retained kernel not signalled'}
  $proof.exitCode=$p.ExitCode
  if($proof.exitCode -ne 0){throw 'UIA worker returned error'}
 }catch{$primaryError=$_;$proof.primaryError=[string]$_}
 finally{
  if($null -ne $p){
   try{$proof.cleanup=Invoke-FactoryOwnedCleanup $p $exe $startedAt -KnownStartedIdentity}
   catch{
    $cleanupError=[string]$_
    $proof.cleanup=[ordered]@{status='cleanup-helper-error';confirmedOwnedExit=$false;killAttempted=$false;kernelWaitResult=$null;error=$cleanupError}
    $proof.streamErrors+=('cleanup: '+$cleanupError)
   }
  }
  # Durable failure receipt precedes stream/destination or owned-handle disposal.
  $cleanupCertificate=$false
  try{$cleanupCertificate=Test-FactoryKernelExitCertificate $proof.cleanup}catch{$proof.streamErrors+=('cleanup certificate: '+[string]$_)}
  if($null -ne $primaryError -or -not $cleanupCertificate){try{Write-FactoryDiagnosticJson (Join-Path $root 'worker-exit-failure.json') $proof}catch{$proof.streamErrors+=('failure receipt: '+[string]$_)}}
  foreach($s in $streams){
   try{if($null -eq $s.task -or -not $s.task.Wait(5000)){throw 'Worker raw completion deadline'};$s.task.GetAwaiter().GetResult();$s.copyCompleted=$true}catch{$proof.streamErrors+=($s.name+': '+[string]$_);try{Write-FactoryDiagnosticJson (Join-Path $root ($s.name+'.raw-failure.json')) (Get-FactoryRawStreamState $s)}catch{$proof.streamErrors+=('raw receipt: '+[string]$_)}}
   try{Close-FactoryRawStreamDestination $s}catch{$proof.streamErrors+=($s.name+' closure: '+[string]$_)}
  }
  $proof.rawStreams=@($streams|ForEach-Object{Get-FactoryRawStreamState $_})
  foreach($s in $proof.rawStreams){$h=Get-FactoryRawHash (Join-Path $root ($s.name+'.bin')) $s;$proof[($s.name+'Sha256')]=$h.sha256;if($h.qualification -cne 'sealed-raw'){$proof.streamErrors+=($s.name+' hash unqualified')}}
  if($null -eq $primaryError -and $proof.streamErrors.Count -eq 0 -and (Test-FactoryKernelExitCertificate $proof.cleanup) -and -not $proof.cleanup.killAttempted){
   try{
    & $Guard | Out-Null
    $uiaPath=Join-Path $root 'uia.json';$observation=Get-Content -Raw -LiteralPath (Join-Path $root 'worker-observation.json')|ConvertFrom-Json
    $proof.uiaSha256=(Get-FileHash -LiteralPath $uiaPath).Hash.ToLowerInvariant()
    if($observation.kind -cne 'factory-uia-snapshot-worker-observation-v2' -or $observation.workerApartment -cne 'MTA' -or $observation.parentApartment -cne $apartment -or $observation.target.pid -ne $Target.pid -or $observation.target.hwnd -ne $Target.hwnd -or $observation.target.path -cne $Target.path -or $observation.target.startedAt -cne $Target.startedAt -or $observation.target.lockOwner -cne $Target.lockOwner -or $observation.status -cne 'snapshot-written' -or $observation.workerPid -ne $p.Id -or $observation.configSha256 -cne $configHash -or $observation.uiaSha256 -cne $proof.uiaSha256 -or $observation.error -cne ''){throw 'Worker snapshot record lineage mismatch'}
    Assert-UiaSnapshotScalarObject (Get-Content -Raw -LiteralPath $uiaPath|ConvertFrom-Json)
    $proof.status='completed-natural-uiasnapshot'
    Assert-UiaSnapshotWorkerProof $proof $Target $proof.stdoutSha256 $proof.stderrSha256 $proof.uiaSha256
   }catch{$primaryError=$_;$proof.primaryError=[string]$_;$proof.status='failed'}
  }
  $proof.finishedAt=[DateTimeOffset]::UtcNow.ToString('o')
  try{Write-FactoryDiagnosticJson (Join-Path $root 'worker-exit.json') $proof}catch{$finalReleaseError='original outcome write: '+[string]$_}
  # Zero-wait sample uses SAME retained value after raw closure, even failed acquisition/kill.
  # It proves release only; original proof/status/errors above remain immutable.
  if($null -ne $p){
   try{
    $finalSample=Get-FactoryUiaFinalExitSample $handle $finalStart
    Write-FactoryDiagnosticJson (Join-Path $root 'final-exit-sample.json') $finalSample
    $finalStreams=@($proof.rawStreams|ForEach-Object{$state=$_|ConvertTo-Json -Depth 12|ConvertFrom-Json;$state|Add-Member -NotePropertyName path -NotePropertyValue (Join-Path $root ($state.name+'.bin'));$state|Add-Member -NotePropertyName sha256 -NotePropertyValue $proof[($state.name+'Sha256')];$state})
    $certificate=New-FactoryUiaFinalExitCertificate $finalSample $finalStart $finalStreams
    $certificatePath=Join-Path $root 'final-exit-certificate.json'
    Write-FactoryDiagnosticJson $certificatePath $certificate
    $outcomePath=Join-Path $root 'worker-exit.json'
    Write-FactoryDiagnosticJson (Join-Path $root 'terminal-worker.json') ([ordered]@{kind='factory-uia-terminal-worker-v1';terminalResultConfirmed=$true;start=$finalStart;finalCertificateRef=$certificatePath;finalCertificateHash=(Get-FileHash -LiteralPath $certificatePath).Hash.ToLowerInvariant();originalOutcomeRef=$outcomePath;originalOutcomeHash=(Get-FileHash -LiteralPath $outcomePath).Hash.ToLowerInvariant()})
   }catch{$finalReleaseError+=' final release: '+[string]$_;try{Write-FactoryDiagnosticJson (Join-Path $root 'final-release-hold.json') ([ordered]@{scope='owner-release-only';qualification='failed-or-successful-snapshot-only';start=$finalStart;sample=$finalSample;error=$finalReleaseError})}catch{# Missing durable certificate must retain coordinator lease.
   }}finally{$p.Dispose()}
  }
  if($finalReleaseError -and $null -eq $primaryError){$primaryError=$finalReleaseError}

 }
 if($null -ne $primaryError){throw $primaryError}
 Assert-UiaSnapshotWorkerProof $proof $Target $proof.stdoutSha256 $proof.stderrSha256 $proof.uiaSha256
 [pscustomobject]@{finalStartPath=(Join-Path $root 'final-start.json');finalCertificatePath=(Join-Path $root 'final-exit-certificate.json');terminalWorkerPath=(Join-Path $root 'terminal-worker.json');snapshotPath=(Join-Path $root 'uia.json');snapshotSha256=$proof.uiaSha256;workerReceiptPath=(Join-Path $root 'worker-exit.json');workerReceiptSha256=(Get-FileHash -LiteralPath (Join-Path $root 'worker-exit.json')).Hash.ToLowerInvariant();proof=$proof}
}
