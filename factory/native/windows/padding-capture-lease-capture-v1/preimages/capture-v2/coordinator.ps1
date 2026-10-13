# Headless coordinator; exclusive desktop CAS & hidden interactive dispatch only.
param(
 [Parameter(Mandatory=$true)][string]$CompileReceiptHash,
 [Parameter(Mandatory=$true)][string]$ExeHash,
 [Parameter(Mandatory=$true)][string]$SerializerControlSha256,
 [ValidateSet(1)][int]$Count=1
)
$ErrorActionPreference='Stop'
if($CompileReceiptHash -cnotmatch '^[0-9a-f]{64}$' -or $ExeHash -cnotmatch '^[0-9a-f]{64}$' -or $SerializerControlSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Measured lowercase SHA256 compile/executable/serializer control pins required'}
$here=[IO.Path]::GetFullPath($PSScriptRoot)
$expectedHere='D:\Claude\swiftright\factory\native\windows\padding-window-diagnosis-capture-v2'
if($here -cne $expectedHere){throw 'Exact capture coordinator lane required'}
$plan=Get-Content -Raw (Join-Path $here 'capture-plan.json')|ConvertFrom-Json
if($CompileReceiptHash -cne $plan.admittedCompileReceiptSha256 -or $ExeHash -cne $plan.admittedExeSha256){throw 'Exact canonical diagnosis compile/exe required'}
$runRoot=$plan.dispatch.first.runRoot
$controlRoot=Join-Path $here 'coordinator-single-r1'
if($runRoot -cne (Join-Path $here 'actual-single-r1')){throw 'Exact prospective output namespace required'}
if(Test-Path -LiteralPath $runRoot){throw 'Fresh capture output required'}
if(Test-Path -LiteralPath $controlRoot){throw 'Fresh coordinator output required; retries disabled'}
$cleanupHelper=Join-Path $here 'support\cleanup.ps1';$sealHelper=Join-Path $here 'support\stream-seal.ps1'
function Assert-ControlHelpers {
 if((Get-FileHash -LiteralPath $cleanupHelper).Hash.ToLowerInvariant() -cne 'a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7'){throw 'Cleanup helper drift'}
 if((Get-FileHash -LiteralPath $sealHelper).Hash.ToLowerInvariant() -cne '4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'){throw 'Stream helper drift'}
}
Assert-ControlHelpers
if((Get-FileHash -LiteralPath (Join-Path $here 'integration-bindings.json')).Hash.ToLowerInvariant() -cne 'c144a0260b9fa89bc9e4d528f52568636c6704ff4fea378c75d4a0c21d526740'){throw 'Integration binding manifest drift'}
. (Join-Path $here 'support\integration.ps1')
Assert-FactoryIntegrationSources $here
. (Join-Path $here 'support\final-exit-certificate.ps1')
. $cleanupHelper
. $sealHelper
$receiptPath=Join-Path $plan.compiledHostPackagePath 'build-diagnosis-r1\observation.json'
if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -cne $CompileReceiptHash){throw 'Compile receipt drift'}
$compiled=Get-Content -Raw $receiptPath|ConvertFrom-Json
$exe=[IO.Path]::GetFullPath($compiled.exePath)
if(-not $exe.StartsWith($plan.compiledHostPackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or $compiled.exeSha256 -cne $ExeHash -or (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -cne $ExeHash){throw 'Executable lineage drift'}
$buildPreflightPath=$plan.launchPreflightPath
if(-not (Test-Path -LiteralPath $buildPreflightPath -PathType Leaf)){throw 'Reviewed build preflight missing'}
if((Get-FileHash -LiteralPath $buildPreflightPath).Hash.ToLowerInvariant() -ne $plan.launchPreflightSha256.Replace('sha256:','')){throw 'Reviewed build preflight drift'}
& $buildPreflightPath -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256 | Out-Null
New-Item -ItemType Directory -Path $controlRoot|Out-Null
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
 $config=Join-Path $controlRoot 'config.json'
 [ordered]@{owner=$owner;count=$Count;runRoot=$runRoot;controlRoot=$controlRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256}|ConvertTo-Json|Set-Content -Encoding UTF8 $config
 $arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $here 'interactive-task.ps1')+'" -Config "'+$config+'"'
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
   if($taskResult.owner -cne $owner -or $taskResult.count -ne $Count -or $taskResult.runRoot -cne $runRoot -or $taskResult.compileReceiptHash -cne $CompileReceiptHash -or $taskResult.exeHash -cne $ExeHash -or $taskResult.serializerControlSha256 -cne $SerializerControlSha256 -or $taskResult.status -cnotin @('completed-source-bound-observation','hold-harness-error')){throw 'Interactive result lineage mismatch'}
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
  # Prevent later starts, then confirm task quiescence before inspecting whole batch.
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
  if($dirs.Count -gt $Count -or ($status -ceq 'completed-source-bound-observation' -and $dirs.Count -ne $Count)){throw 'Whole batch child cardinality mismatch'}
  foreach($dir in $dirs){
   if($dir.Name -cnotmatch '^native-(0[1-9]|1[0-9]|20)$' -or [int]$dir.Name.Substring(7) -gt $Count){throw 'Unexpected batch child directory'}
   $ownedPath=Join-Path $dir.FullName 'owned-process.json';$outcomePath=Join-Path $dir.FullName 'capture-outcome.json'
   if(-not(Test-Path -LiteralPath $ownedPath -PathType Leaf) -or -not(Test-Path -LiteralPath $outcomePath -PathType Leaf)){throw 'Child directory lacks original retained-handle exit proof'}
   $owned=Get-Content -Raw $ownedPath|ConvertFrom-Json;$outcome=Get-Content -Raw $outcomePath|ConvertFrom-Json
   $stdout=@($outcome.rawStreams|Where-Object{$_.name -ceq 'stdout'});$stderr=@($outcome.rawStreams|Where-Object{$_.name -ceq 'stderr'})
   if(@($outcome.rawStreams).Count -ne 2 -or $stdout.Count -ne 1 -or $stderr.Count -ne 1){throw 'Exact child raw stream closure states required'}
   $stdoutHash=Get-FactoryRawHash (Join-Path $dir.FullName 'host.stdout.txt') $stdout[0]
   $stderrHash=Get-FactoryRawHash (Join-Path $dir.FullName 'host.stderr.txt') $stderr[0]
   if($stdoutHash.qualification -eq 'unqualified' -or $stderrHash.qualification -eq 'unqualified'){throw 'Child raw destination hashes unqualified'}
   $originalProof=Test-FactoryCaptureExitProof $outcome $owned $owner $CompileReceiptHash $ExeHash $stdoutHash.sha256 $stderrHash.sha256 $exe
   if(-not $originalProof){
    Assert-FactoryIntegrationSources $here
    $startPath=Join-Path $dir.FullName 'final-start.json';$workerPath=Join-Path $dir.FullName 'terminal-worker.json';$certPath=Join-Path $dir.FullName 'final-exit-certificate.json'
    $expected=Get-Content -Raw -LiteralPath $startPath|ConvertFrom-Json
    if(-not(Test-FactoryFinalStart $expected) -or $expected.pid -ne $owned.pid -or $expected.path -cne $exe -or $expected.startedAt -cne $owned.startedAt -or $expected.lockOwner -cne $owner -or $expected.workerId -cne $dir.FullName -or $expected.compileReceiptHash -cne $CompileReceiptHash -or $expected.exeHash -cne $ExeHash){throw 'Final start original lineage mismatch'}
    $expected|Add-Member workerReceiptRef $workerPath
    $expected|Add-Member workerReceiptHash ((Get-FileHash -LiteralPath $workerPath).Hash.ToLowerInvariant())
    $expected|Add-Member compileReceiptRef $receiptPath
    $expected|Add-Member exeRef $exe
    $certificate=Get-Content -Raw -LiteralPath $certPath|ConvertFrom-Json
    foreach($raw in @($certificate.rawStreams)){
     $requiredPath=Join-Path $dir.FullName ('host.'+$raw.name+'.txt')
     $requiredHash=if($raw.name -ceq 'stdout'){$stdoutHash.sha256}elseif($raw.name -ceq 'stderr'){$stderrHash.sha256}else{throw 'Unknown final stream'}
     if($raw.path -cne $requiredPath -or $raw.sha256 -cne $requiredHash){throw 'Final raw stream/outcome byte join mismatch'}
    }
    $terminal=Get-Content -Raw -LiteralPath $workerPath|ConvertFrom-Json
    if($terminal.finalCertificateRef -cne $certPath -or $terminal.originalOutcomeRef -cne $outcomePath -or $terminal.originalOutcomeHash -cne (Get-FileHash -LiteralPath $outcomePath).Hash.ToLowerInvariant()){throw 'Final certificate/outcome exact reference mismatch'}
    $allowedRefs=@($workerPath,$certPath,$receiptPath,$exe,(Join-Path $dir.FullName 'host.stdout.txt'),(Join-Path $dir.FullName 'host.stderr.txt'))
    $reader={param($ref) if($allowedRefs -cnotcontains $ref){throw 'Final proof read outside exact closure'};return ,([IO.File]::ReadAllBytes($ref))}
    if(-not(Test-FactoryFinalReleaseProof $certificate $expected $reader)){throw 'Final original-handle release proof absent'}
   }

  }
  $releaseAllowed=$true
 }catch{$cleanupErrors+=([string]$_);$releaseAllowed=$false}
 $released=Invoke-FactoryConfirmedRelease $acquired $releaseAllowed {Change-Lock $owner 'free'}
 if($acquired -and -not $released){$cleanupErrors+='Desktop lock retained: release ownership or cleanup proof unconfirmed'}
 [ordered]@{kind='padding-window-diagnosis-interactive-coordinator';status=$status;count=$Count;owner=$owner;runRoot=$runRoot;controlRoot=$controlRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;lockAcquired=$acquired;lockReleased=$released;wholeBatchExitConfirmed=$releaseAllowed;taskName=$taskName;taskRegistered=$registered;taskStarted=$started;terminalResultConfirmed=$terminalResultConfirmed;error=if($null -ne $primaryError){[string]$primaryError}else{''};errorId=if($null -ne $primaryError){$primaryError.FullyQualifiedErrorId}else{''};interactiveError=if($null -ne $taskResult){$taskResult.error}else{''};interactiveErrorId=if($null -ne $taskResult){$taskResult.errorId}else{''};cleanupErrors=$cleanupErrors;qualification='hold';nativeParity='hold';frozenTupleBound=$false}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $controlRoot 'coordinator.json')
}
if($null -ne $primaryError){throw $primaryError}
if(-not $released){throw 'Coordinator cleanup/release incomplete; inspect coordinator.json'}
