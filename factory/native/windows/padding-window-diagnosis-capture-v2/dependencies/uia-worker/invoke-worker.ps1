# Parent entry loads no UIA assembly/type. Reuses retained-handle & raw-stream framework.
function Invoke-FactoryUiaSnapshotWorker($Target,[string]$OutputRoot,[Parameter(Mandatory=$true)][scriptblock]$Guard) {
 $ErrorActionPreference='Stop'
 $sourceRoot=$PSScriptRoot
 $root=[IO.Path]::GetFullPath($OutputRoot)
 if(-not $root.StartsWith('D:\Claude\swiftright\factory\native\windows\',[StringComparison]::OrdinalIgnoreCase) -or $root -match '["\r\n]' -or (Test-Path -LiteralPath $root)){throw 'Fresh safe factory worker output required'}
 $manifest=Get-Content -Raw -LiteralPath (Join-Path $sourceRoot 'worker-contract.json')|ConvertFrom-Json
 foreach($b in $manifest.sourceBindings){if((Get-FileHash -LiteralPath (Join-Path $sourceRoot $b.path)).Hash.ToLowerInvariant() -cne $b.sha256){throw 'UIA worker/helper source drift'}}
 . (Join-Path $sourceRoot 'support\cleanup.ps1')
 . (Join-Path $sourceRoot 'support\stream-seal.ps1')
 . (Join-Path $sourceRoot 'schema.ps1')
 & $Guard | Out-Null
 New-Item -ItemType Directory -Path $root|Out-Null
 $apartment=[Threading.Thread]::CurrentThread.GetApartmentState().ToString()
 if($apartment -cnotin @('STA','MTA')){throw 'Observed parent apartment required'}
 $config=[ordered]@{kind='factory-uia-snapshot-worker-config-v1';target=$Target;outputRoot=$root;apartment=$apartment;sourceBindings=$manifest.sourceBindings}
 $configPath=Join-Path $root 'config.json';Write-FactoryDiagnosticJson $configPath $config
 $configHash=(Get-FileHash -LiteralPath $configPath).Hash.ToLowerInvariant()
 $exe=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $exeHash=(Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()
 $script=Join-Path $sourceRoot 'worker.ps1'
 $arguments='-NoProfile -NonInteractive -WindowStyle Hidden -'+$apartment+' -ExecutionPolicy Bypass -File "'+$script+'" -Config "'+$configPath+'" -ConfigHash '+$configHash
 $si=[Diagnostics.ProcessStartInfo]::new($exe,$arguments);$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true;$si.WorkingDirectory=$root
 $proof=[ordered]@{kind='factory-uia-snapshot-worker-exit-v1';status='failed';target=$Target;ownedIdentity=$null;workerExeSha256=$exeHash;sourceContractSha256=(Get-FileHash (Join-Path $sourceRoot 'worker-contract.json')).Hash.ToLowerInvariant();configSha256=$configHash;apartment=$apartment;startedAt=[DateTimeOffset]::UtcNow.ToString('o');exitCode=$null;timedOut=$false;preCleanupKernelWaitResult=$null;cleanup=$null;rawStreams=@();streamErrors=@();stdoutSha256=$null;stderrSha256=$null;uiaSha256=$null;primaryError='';nativeWindowsOpened=$false;rendererLoaded=$false}
 $p=$null;$streams=@();$primaryError=$null;$startedAt=$null
 try{
  foreach($name in @('stdout','stderr')){$file=[IO.File]::Open((Join-Path $root ($name+'.bin')),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$streams+=@([pscustomobject]@{name=$name;file=$file;source=$null;task=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false;closure=$null;closeTask=$null})}
  $p=[Diagnostics.Process]::Start($si);$handle=$p.Handle;$startedAt=$p.StartTime.ToUniversalTime().ToString('o')
  $proof.ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$startedAt;retainedHandle=$handle.ToInt64()}
  Write-FactoryDiagnosticJson (Join-Path $root 'owned-worker.json') $proof.ownedIdentity
  $streams[0].source=$p.StandardOutput.BaseStream;$streams[1].source=$p.StandardError.BaseStream
  foreach($s in $streams){$s.task=$s.source.CopyToAsync($s.file)}
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  while(-not $p.WaitForExit(100)){& $Guard | Out-Null;if([DateTime]::UtcNow -gt $deadline){$proof.timedOut=$true;throw 'UIA worker acquisition/exit deadline'}}
  $proof.preCleanupKernelWaitResult=[int][FactoryProcessWaitV5]::WaitForSingleObject($handle,0)
  if($proof.preCleanupKernelWaitResult -ne 0){throw 'UIA worker retained kernel not signalled'}
  $proof.exitCode=$p.ExitCode
  if($proof.exitCode -ne 0){throw 'UIA worker returned error'}
 }catch{$primaryError=$_;$proof.primaryError=[string]$_}
 finally{
  if($null -ne $p){$proof.cleanup=Invoke-FactoryOwnedCleanup $p $exe $startedAt -KnownStartedIdentity}
  # Durable failure receipt precedes stream/destination or owned-handle disposal.
  if($null -ne $primaryError -or -not(Test-FactoryKernelExitCertificate $proof.cleanup)){try{Write-FactoryDiagnosticJson (Join-Path $root 'worker-exit-failure.json') $proof}catch{$proof.streamErrors+=('failure receipt: '+[string]$_)}}
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
    if($observation.kind -cne 'factory-uia-snapshot-worker-observation-v1' -or $observation.apartment -cne $apartment -or $observation.target.pid -ne $Target.pid -or $observation.target.hwnd -ne $Target.hwnd -or $observation.target.path -cne $Target.path -or $observation.target.startedAt -cne $Target.startedAt -or $observation.target.lockOwner -cne $Target.lockOwner -or $observation.status -cne 'snapshot-written' -or $observation.workerPid -ne $p.Id -or $observation.configSha256 -cne $configHash -or $observation.uiaSha256 -cne $proof.uiaSha256 -or $observation.error -cne ''){throw 'Worker snapshot record lineage mismatch'}
    Assert-UiaSnapshotScalarObject (Get-Content -Raw -LiteralPath $uiaPath|ConvertFrom-Json)
    $proof.status='completed-natural-uiasnapshot'
    Assert-UiaSnapshotWorkerProof $proof $Target $proof.stdoutSha256 $proof.stderrSha256 $proof.uiaSha256
   }catch{$primaryError=$_;$proof.primaryError=[string]$_;$proof.status='failed'}
  }
  $proof.finishedAt=[DateTimeOffset]::UtcNow.ToString('o')
  Write-FactoryDiagnosticJson (Join-Path $root 'worker-exit.json') $proof
  if($null -ne $p){$p.Dispose()}
 }
 if($null -ne $primaryError){throw $primaryError}
 Assert-UiaSnapshotWorkerProof $proof $Target $proof.stdoutSha256 $proof.stderrSha256 $proof.uiaSha256
 [pscustomobject]@{snapshotPath=(Join-Path $root 'uia.json');snapshotSha256=$proof.uiaSha256;workerReceiptPath=(Join-Path $root 'worker-exit.json');workerReceiptSha256=(Get-FileHash -LiteralPath (Join-Path $root 'worker-exit.json')).Hash.ToLowerInvariant();proof=$proof}
}
