# Coordinator: bounded free-lock wait, owned interactive task, ownership-safe release.
param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$CompileReceiptHash,[Parameter(Mandatory=$true)][string]$ExeHash)
$ErrorActionPreference='Stop'
$cleanupHelper=Join-Path $PSScriptRoot 'cleanup.ps1'
if((Get-FileHash $cleanupHelper).Hash.ToLowerInvariant() -ne 'fbb0944383d460902f7bb668cfcdaa025d40ac00dd33e2b07e5495f9e81d16ed'){throw 'Cleanup helper drift'}
. $cleanupHelper
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe pins required'}
$factory='D:\Claude\swiftright\factory\native\windows\'
if($RunRoot -match '["
]' -or $Package -match '["
]'){throw 'Unsafe command path'}
if(-not [IO.Path]::GetFullPath($RunRoot).StartsWith((Join-Path $factory 'round1-seeded-native-v3\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Fresh first capture lane required'}
$packagePath=[IO.Path]::GetFullPath($Package);$runPath=[IO.Path]::GetFullPath($RunRoot)
$approvedReceiptRoutes=@{
 'D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\stack-overlay\package'='build-v2-r1\observation.json'
 'D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\custom-layout\package'='build-v2-r1\observation.json'
 'D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\padding-frame\package'='build-v2-r1\observation.json'
 'D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\preference-key\package'='build-v2-r1\observation.json'
 'D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\scroll-view\package'='build-v2-r1\observation.json'
}
if(-not $approvedReceiptRoutes.ContainsKey($packagePath)){throw 'Exact reviewed Round1 package required'}
if(-not $packagePath.StartsWith($factory,[StringComparison]::OrdinalIgnoreCase) -or -not $runPath.StartsWith($factory,[StringComparison]::OrdinalIgnoreCase)){throw 'Paths outside factory'}
$macProofHelper=Join-Path $PSScriptRoot 'mac-proof.ps1'
if((Get-FileHash -LiteralPath $macProofHelper).Hash.ToLowerInvariant() -cne 'e02cfbaf71df028f385baae9eec65eabc07e691c91509b17ca42b19b345835ef'){throw 'Seed proof helper drift'}
. $macProofHelper
$seedPlan=Get-Content -Raw (Join-Path $packagePath 'plan.json')|ConvertFrom-Json
Assert-SeedMacProof $packagePath $seedPlan ((Get-FileHash (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant())
Assert-SeedWindowsCompile $packagePath $seedPlan ((Get-FileHash (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant()) $CompileReceiptHash $ExeHash
if(Test-Path -LiteralPath $runPath){throw 'Use fresh run output'}
New-Item -ItemType Directory -Path $runPath|Out-Null
$lock='D:\Claude\desktop.lock'
$owner='alchemist-f7-'+[Guid]::NewGuid().ToString('N')+' '+[DateTimeOffset]::UtcNow.ToString('o')
$task='AlchemistF7-'+[Guid]::NewGuid().ToString('N')
$log=[Collections.Generic.List[object]]::new()
function Change-Lock([string]$expected,[string]$replacement){
 try{$stream=[IO.File]::Open($lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{return $false}
 try{
  $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,1024,$true)
  try{$state=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()}
  if($state -ne $expected){return $false}
  $data=[Text.Encoding]::UTF8.GetBytes($replacement)
  $stream.Position=0;$stream.SetLength(0);$stream.Write($data,0,$data.Length);$stream.Flush($true)
  return $true
 }finally{$stream.Dispose()}
}
$acquired=$false;$started=$false;$result='hold-desktop-busy';$errorText=''
$deadline=[DateTime]::UtcNow.AddMinutes(6)
try{
 do{
  $acquired=Change-Lock 'free' $owner
  if($acquired){break}
  $state=try{(Get-Content -Raw $lock).Trim()}catch{'unreadable'}
  $log.Add([ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');state=$state;acquired=$false})
  if([DateTime]::UtcNow -ge $deadline){break}
  Start-Sleep -Seconds 3
 }while($true)
 if($acquired){
  [ordered]@{owner=$owner;package=$packagePath;runRoot=$runPath;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $runPath 'config.json')
  $config=Join-Path $runPath 'config.json'
  $script=Join-Path $PSScriptRoot 'repeat-task.ps1'
  $actionArguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$script+'" -Config "'+$config+'"'
  $vbs=Join-Path $runPath 'hidden-task.vbs'
  $vbsText='Set sh = CreateObject("WScript.Shell")'+[Environment]::NewLine+'rc = sh.Run("powershell.exe '+$actionArguments.Replace('"','""')+'", 0, True)'+[Environment]::NewLine+'WScript.Quit rc'
  [IO.File]::WriteAllText($vbs,$vbsText,[Text.Encoding]::ASCII)
  $action=New-ScheduledTaskAction -Execute (Join-Path $env:windir 'System32\wscript.exe') -Argument ('"'+$vbs+'"')
  $principal=New-ScheduledTaskPrincipal -UserId 'adrds' -LogonType Interactive -RunLevel Highest
  $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings|Out-Null
  Start-ScheduledTask -TaskName $task;$started=$true
  $jobDeadline=[DateTime]::UtcNow.AddMinutes(10)
  $receipt=Join-Path $runPath 'task-result.json'
  do{
   if(Test-Path -LiteralPath $receipt){$result=(Get-Content -Raw $receipt|ConvertFrom-Json).status;break}
   if([DateTime]::UtcNow -ge $jobDeadline){$result='hold-native-timeout';Stop-ScheduledTask -TaskName $task;break}
   Start-Sleep -Seconds 3
  }while($true)
 }
}catch{$result='hold-harness-error';$errorText=[string]$_}
finally{
 $cleanupErrors=@();$releaseAllowed=$true
 try{
 if($started){
  $info=Get-ScheduledTaskInfo -TaskName $task -ErrorAction SilentlyContinue
  $info|Select-Object LastRunTime,LastTaskResult,NextRunTime|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $runPath 'scheduled-task-receipt.json')
 }
 if($result -like 'hold-*' -and $started){
  Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  $ownedFiles=@(Get-ChildItem -LiteralPath $runPath -Filter 'owned-process.json' -Recurse -File)
  if($ownedFiles.Count -eq 0 -and (Test-Path (Join-Path $runPath 'native-01'))){$releaseAllowed=$false;$cleanupErrors+='Capture directory exists without owned identity; exit unproven'}
  foreach($file in $ownedFiles){
   $owned=Get-Content -Raw $file.FullName|ConvertFrom-Json
   $outcomePath=Join-Path $file.DirectoryName 'capture-outcome.json'
   $captureExitConfirmed=$false
   if(Test-Path -LiteralPath $outcomePath){
    try{
     $proofCompilePath=Join-Path $packagePath $approvedReceiptRoutes[$packagePath]
     if((Get-FileHash $proofCompilePath).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Capture exit compile receipt drift'}
     $proofCompile=Get-Content -Raw $proofCompilePath|ConvertFrom-Json
     if($proofCompile.exeSha256 -ne $ExeHash -or -not $proofCompile.exePath.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Capture exit executable lineage drift'}
     $outcome=Get-Content -Raw $outcomePath|ConvertFrom-Json
     $stdoutHash=(Get-FileHash (Join-Path $file.DirectoryName 'host.stdout.txt')).Hash.ToLowerInvariant()
     $stderrHash=(Get-FileHash (Join-Path $file.DirectoryName 'host.stderr.txt')).Hash.ToLowerInvariant()
     $captureExitConfirmed=Test-FactoryCaptureExitProof $outcome $owned $owner $CompileReceiptHash $ExeHash $stdoutHash $stderrHash $proofCompile.exePath
     if($captureExitConfirmed){[ordered]@{status='capture-retained-kernel-handle-exit-proof';outcomeHash=(Get-FileHash $outcomePath).Hash.ToLowerInvariant();confirmedOwnedExit=$true}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $file.DirectoryName 'coordinator-cleanup.json')}
    }catch{$cleanupErrors+=('Capture exit proof rejected: '+[string]$_)}
   }
   if($captureExitConfirmed){continue}
   $process=$null;$absent=$false
   try{$process=Get-Process -Id $owned.pid -ErrorAction Stop}catch{
    if($_.FullyQualifiedErrorId -like 'NoProcessFoundForGivenId*'){$absent=$true}else{$releaseAllowed=$false;$cleanupErrors+=([string]$_)}
   }
   if($process){$cleanup=Invoke-FactoryOwnedCleanup $process $owned.path $owned.startedAt;if(-not $cleanup.confirmedOwnedExit){$releaseAllowed=$false;$cleanupErrors+=('Owned exit unconfirmed: '+$cleanup.error)};$cleanup|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 (Join-Path $file.DirectoryName 'coordinator-cleanup.json')}
   else{$releaseAllowed=$false;$cleanupErrors+=('Retained kernel exit certificate absent; PID lookup cannot certify original handle signal')}
  }
 }
 }catch{$releaseAllowed=$false;$cleanupErrors+=([string]$_)}finally{
 $released=Invoke-FactoryConfirmedRelease $acquired $releaseAllowed {Change-Lock $owner 'free'}
 [ordered]@{kind='windows-first-observational-dispatch';version='0.1';status=$result;owner=$owner;lockAcquired=$acquired;lockReleased=$released;lockRetainedForUnconfirmedOwnedExit=($acquired -and -not $releaseAllowed);taskName=$task;taskRetained=$started;windowedDispatch=$started;waitObservations=$log;error=$errorText;cleanupErrors=$cleanupErrors;stageModified=$false;nativeParity='hold';frozenTupleBound=$false;closureBinding=$null}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $runPath 'dispatch.json')
}
}
