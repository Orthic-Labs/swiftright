# Headless coordinator; exclusive desktop CAS & hidden interactive dispatch only.
param(
 [Parameter(Mandatory=$true)][string]$CompileReceiptHash,
 [Parameter(Mandatory=$true)][string]$ExeHash,
 [ValidateSet(1,20)][int]$Count=1
)
$ErrorActionPreference='Stop'
if($CompileReceiptHash -cnotmatch '^[0-9a-f]{64}$' -or $ExeHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Measured lowercase SHA256 pins required'}
$here=[IO.Path]::GetFullPath($PSScriptRoot)
$expectedHere='D:\Claude\swiftright\factory\native\windows\padding-settled-capture-v3'
if($here -cne $expectedHere){throw 'Exact capture coordinator lane required'}
$plan=Get-Content -Raw (Join-Path $here 'capture-plan.json')|ConvertFrom-Json
$runRoot=if($Count -eq 1){$plan.dispatch.first.runRoot}else{$plan.dispatch.repeat.runRoot}
$controlRoot=Join-Path $here $(if($Count -eq 1){'coordinator-single-r1'}else{'coordinator-repeat-r1'})
if($runRoot -cne (Join-Path $here $(if($Count -eq 1){'actual-single-r1'}else{'actual-repeat-r1'}))){throw 'Exact prospective output namespace required'}
if(Test-Path -LiteralPath $runRoot){throw 'Fresh capture output required'}
if(Test-Path -LiteralPath $controlRoot){throw 'Fresh coordinator output required; retries disabled'}
$cleanupHelper=Join-Path $here 'support\cleanup.ps1';$sealHelper=Join-Path $here 'support\stream-seal.ps1'
function Assert-ControlHelpers {
 if((Get-FileHash -LiteralPath $cleanupHelper).Hash.ToLowerInvariant() -cne 'a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7'){throw 'Cleanup helper drift'}
 if((Get-FileHash -LiteralPath $sealHelper).Hash.ToLowerInvariant() -cne '4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'){throw 'Stream helper drift'}
}
Assert-ControlHelpers
. $cleanupHelper
. $sealHelper
$receiptPath=Join-Path $plan.compiledHostPackagePath 'build-settled-r2\observation.json'
if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -cne $CompileReceiptHash){throw 'Compile receipt drift'}
$compiled=Get-Content -Raw $receiptPath|ConvertFrom-Json
$exe=[IO.Path]::GetFullPath($compiled.exePath)
if(-not $exe.StartsWith($plan.compiledHostPackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or $compiled.exeSha256 -cne $ExeHash -or (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -cne $ExeHash){throw 'Executable lineage drift'}
New-Item -ItemType Directory -Path $controlRoot|Out-Null
$lock='D:\Claude\desktop.lock'
$owner='padding-settled-'+[Guid]::NewGuid().ToString('N')+' '+[DateTimeOffset]::UtcNow.ToString('o')
$taskName='PaddingSettled-'+[Guid]::NewGuid().ToString('N')
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
 [ordered]@{owner=$owner;count=$Count;runRoot=$runRoot;controlRoot=$controlRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash}|ConvertTo-Json|Set-Content -Encoding UTF8 $config
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
   if($taskResult.owner -cne $owner -or $taskResult.count -ne $Count -or $taskResult.runRoot -cne $runRoot -or $taskResult.compileReceiptHash -cne $CompileReceiptHash -or $taskResult.exeHash -cne $ExeHash -or $taskResult.status -cnotin @('completed-source-bound-observation','hold-harness-error')){throw 'Interactive result lineage mismatch'}
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
   if(-not(Test-FactoryCaptureExitProof $outcome $owned $owner $CompileReceiptHash $ExeHash $stdoutHash.sha256 $stderrHash.sha256 $exe)){throw 'Original child kernel handle/stream/owner lineage unconfirmed'}
  }
  $releaseAllowed=$true
 }catch{$cleanupErrors+=([string]$_);$releaseAllowed=$false}
 $released=Invoke-FactoryConfirmedRelease $acquired $releaseAllowed {Change-Lock $owner 'free'}
 if($acquired -and -not $released){$cleanupErrors+='Desktop lock retained: release ownership or cleanup proof unconfirmed'}
 [ordered]@{kind='padding-settled-interactive-coordinator';status=$status;count=$Count;owner=$owner;runRoot=$runRoot;controlRoot=$controlRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;lockAcquired=$acquired;lockReleased=$released;wholeBatchExitConfirmed=$releaseAllowed;taskName=$taskName;taskRegistered=$registered;taskStarted=$started;terminalResultConfirmed=$terminalResultConfirmed;error=if($null -ne $primaryError){[string]$primaryError}else{''};errorId=if($null -ne $primaryError){$primaryError.FullyQualifiedErrorId}else{''};interactiveError=if($null -ne $taskResult){$taskResult.error}else{''};interactiveErrorId=if($null -ne $taskResult){$taskResult.errorId}else{''};cleanupErrors=$cleanupErrors;qualification='hold';nativeParity='hold';frozenTupleBound=$false}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $controlRoot 'coordinator.json')
}
if($null -ne $primaryError){throw $primaryError}
if(-not $released){throw 'Coordinator cleanup/release incomplete; inspect coordinator.json'}
