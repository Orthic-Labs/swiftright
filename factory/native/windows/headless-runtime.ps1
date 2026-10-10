# Owned exact source snapshot only. Noninteractive headless build/tests; no lock/UI/stage writes.
param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$Receipt,[Parameter(Mandatory=$true)][string]$RunRoot,[switch]$BuildOnly,[string]$ReservationRoot)
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath($SourceRoot);$run=[IO.Path]::GetFullPath($RunRoot)
foreach($p in @($source,$run,[IO.Path]::GetFullPath($Receipt))){if($p -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\'){throw 'Owned new factory root required'}}
if(Test-Path -LiteralPath $run){throw 'Fresh headless output required'}
$snapshot=Get-Content -Raw $Receipt|ConvertFrom-Json
if($snapshot.synthetic -or $snapshot.sourceCommit -notmatch '^[a-f0-9]{40}$'){throw 'Actual exact source snapshot required'}
function Check-Snapshot {
 foreach($b in $snapshot.completeSnapshotBindings){
  $path=[IO.Path]::GetFullPath((Join-Path $source $b.path))
  if(-not $path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Snapshot binding escape'}
  if((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ne $b.sha256.Replace('sha256:','')){throw 'Snapshot source drift'}
 }
}
$reservation=$null
if($ReservationRoot){$reservation=Get-Content -Raw (Join-Path $ReservationRoot 'lock-ready.json')|ConvertFrom-Json}
function Check-Reservation {
 if($reservation){
  if((Get-Content -Raw -LiteralPath 'D:\Claude\desktop.lock').Trim() -ne $reservation.owner){throw 'Owned reservation lost'}
  if(([DateTimeOffset]$reservation.leaseDeadline) -lt [DateTimeOffset]::UtcNow.AddMinutes(11)){throw 'Owned reservation lease insufficient'}
 }
}
Check-Reservation
Check-Snapshot
New-Item -ItemType Directory -Path $run|Out-Null
$swift=(Get-Command swift).Source
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$rows=@();$errorText=''
try{
 $verbs=if($BuildOnly){@('build')}else{@('build','test')}
 foreach($verb in $verbs){
  Check-Reservation
  Check-Snapshot
  $arguments=@($verb,'--package-path',$source,'--scratch-path',(Join-Path $run 'scratch'),'-c','release')
  $info=[Diagnostics.ProcessStartInfo]::new($swift);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $info.Arguments=($arguments|ForEach-Object{'"'+$_+'"'}) -join ' '
  $p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o')
  $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
  [ordered]@{pid=$p.Id;path=$swift;startedAt=$started}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $run ($verb+'.owned-process.json'))
  $timedOut=$false
  try{
   $deadline=[DateTimeOffset]::UtcNow.AddMinutes(10)
   while(-not $p.WaitForExit(100)){
    Check-Reservation
    if([DateTimeOffset]::UtcNow -lt $deadline){continue}
    $timedOut=$true;$current=Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if($current -and $current.Path -eq $swift -and $current.StartTime.ToUniversalTime().ToString('o') -eq $started){& taskkill /PID $p.Id /T /F|Out-Null}
    $p.WaitForExit(5000)|Out-Null
    break
   }
   if(-not $out.Wait(5000) -or -not $err.Wait(5000)){throw 'Owned headless output deadline'}
   $stdout=Join-Path $run ($verb+'.stdout.txt');$stderr=Join-Path $run ($verb+'.stderr.txt')
   [IO.File]::WriteAllText($stdout,$out.GetAwaiter().GetResult());[IO.File]::WriteAllText($stderr,$err.GetAwaiter().GetResult())
   $rows += [ordered]@{command=$verb;exitCode=$p.ExitCode;timedOut=$timedOut;stdoutHash=(Get-FileHash -LiteralPath $stdout).Hash.ToLowerInvariant();stderrHash=(Get-FileHash -LiteralPath $stderr).Hash.ToLowerInvariant();createNoWindow=$true}
  }finally{
   if(-not $p.HasExited){$current=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($current -and $current.Path -eq $swift -and $current.StartTime.ToUniversalTime().ToString('o') -eq $started){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null}
   if(-not @($rows|Where-Object {$_.command -eq $verb}).Count){
    $out.Wait(5000)|Out-Null;$err.Wait(5000)|Out-Null
    $stdout=Join-Path $run ($verb+'.stdout.txt');$stderr=Join-Path $run ($verb+'.stderr.txt')
    if($out.IsCompleted){[IO.File]::WriteAllText($stdout,$out.GetAwaiter().GetResult())}
    if($err.IsCompleted){[IO.File]::WriteAllText($stderr,$err.GetAwaiter().GetResult())}
    $rows += [ordered]@{command=$verb;exitCode=if($p.HasExited){$p.ExitCode}else{$null};timedOut=$timedOut;stdoutHash=if(Test-Path $stdout){(Get-FileHash $stdout).Hash.ToLowerInvariant()}else{$null};stderrHash=if(Test-Path $stderr){(Get-FileHash $stderr).Hash.ToLowerInvariant()}else{$null};createNoWindow=$true;aborted=$true}
   }
  }
  Check-Snapshot
 }
}catch{$errorText=[string]$_}
finally{
 $products=Join-Path $run 'scratch\out\Products\Release-windows-x86_64'
 $binaryBindings=@();if(Test-Path $products){$binaryBindings=@(Get-ChildItem $products -File|Where-Object {$_.Extension -in @('.exe','.dll')}|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})}
 [ordered]@{kind='factory-windows-headless-runtime';sourceCommit=$snapshot.sourceCommit;sourceTreeHash=$snapshot.sourceTreeHash;completeSnapshotHash=$snapshot.completeSnapshotHash;snapshotArchiveHash=$snapshot.snapshotArchiveHash;commands=$rows;binaryBindings=$binaryBindings;error=$errorText;finishedAt=[DateTimeOffset]::UtcNow.ToString('o');swiftPath=$swift;swiftHash=(Get-FileHash $swift).Hash.ToLowerInvariant();stageModified=$false;desktopLockAcquired=$false;desktopReservationOwner=if($reservation){$reservation.owner}else{$null};configuration='release';nativeWindowOpened=$false;nativeReplayCount=0}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $run 'headless-receipt.json')
}
