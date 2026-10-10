# Owned reservation, immutable source snapshots, headless matched timing only.
param([Parameter(Mandatory=$true)][string]$BaselineRoot,[Parameter(Mandatory=$true)][string]$CandidateRoot,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$ReservationRoot,[ValidateRange(1,5)][int]$Pairs=3)
$ErrorActionPreference='Stop'
$roots=@([IO.Path]::GetFullPath($BaselineRoot),[IO.Path]::GetFullPath($CandidateRoot))
$run=[IO.Path]::GetFullPath($RunRoot)
foreach($path in @($roots)+@($run)){if($path -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\'){throw 'Owned factory source/output required'}}
if(Test-Path -LiteralPath $run){throw 'Fresh timing archive required'}
$ready=Get-Content -Raw (Join-Path $ReservationRoot 'lock-ready.json')|ConvertFrom-Json
function Check-Lock {
 $value=(Get-Content -Raw -LiteralPath 'D:\Claude\desktop.lock').Trim()
 if($value -ne $ready.owner){throw 'Reservation lost'}
 if(([DateTimeOffset]$ready.leaseDeadline) -lt [DateTimeOffset]::UtcNow.AddMinutes(11)){throw 'Reservation lease insufficient'}
}
$receipts=@();$testHashes=@()
foreach($root in $roots){
 $receipt=Get-Content -Raw (Join-Path (Split-Path $root) 'runtime-source-receipt.json')|ConvertFrom-Json
 if($receipt.synthetic -or $receipt.sourceCommit -notmatch '^[a-f0-9]{40}$'){throw 'Exact real snapshot required'}
 $receipts+= $receipt
 $testHashes+= (Get-FileHash -LiteralPath (Join-Path $root 'Tests\SwiftRightRuntimeTests\PerformanceTests.swift')).Hash
}
if($receipts[0].sourceCommit -ne '8e47b89b3e9ae488e77ea8b5a2e4663053601c0d' -or $receipts[1].sourceCommit -eq $receipts[0].sourceCommit){throw 'Distinct original/final source commits required'}
if($testHashes[0] -ne $testHashes[1]){throw 'Matched unchanged performance test bytes required'}
function Check-Sources {
 for($i=0;$i -lt 2;$i++){
  foreach($b in $receipts[$i].completeSnapshotBindings){
   $p=[IO.Path]::GetFullPath((Join-Path $roots[$i] $b.path))
   if(-not $p.StartsWith($roots[$i]+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Source binding escape'}
   if((Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -ne $b.sha256.Replace('sha256:','')){throw 'Source drift'}
  }
 }
}
Check-Lock;Check-Sources
New-Item -ItemType Directory -Path $run|Out-Null
$swift=(Get-Command swift).Source
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$rows=@();$errorText=''
try {
 for($pair=1;$pair -le $Pairs;$pair++){
  $order=if($pair%2){@(0,1)}else{@(1,0)}
  foreach($i in $order){
   Check-Lock;Check-Sources
   $label=if($i -eq 0){'baseline'}else{'candidate'}
   $dir=Join-Path $run ('pair-{0:D2}-{1}' -f $pair,$label);New-Item -ItemType Directory -Path $dir|Out-Null
   $load=@(Get-CimInstance Win32_Processor|Select-Object DeviceID,LoadPercentage)
   $args=@('test','--package-path',$roots[$i],'--scratch-path',(Join-Path (Split-Path $roots[$i]) 'matched-test-scratch'),'-c','release','--filter','PerformanceTests.testSingleRowEditCommitTime')
   $info=[Diagnostics.ProcessStartInfo]::new($swift);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
   $info.Arguments=($args|ForEach-Object{'"'+$_+'"'}) -join ' '
   $p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o')
   $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$deadline=[DateTimeOffset]::UtcNow.AddMinutes(10);$timedOut=$false
   [ordered]@{pid=$p.Id;path=$swift;startedAt=$started}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'owned-process.json')
   try{
    while(-not $p.WaitForExit(100)){Check-Lock;if([DateTimeOffset]::UtcNow -ge $deadline){$timedOut=$true;throw 'Owned benchmark deadline'}}
    if(-not $out.Wait(5000) -or -not $err.Wait(5000)){throw 'Benchmark output deadline'}
   }finally{
    if(-not $p.HasExited){$owned=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($owned -and $owned.Path -eq $swift -and $owned.StartTime.ToUniversalTime().ToString('o') -eq $started){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null}
    if($out.IsCompleted){[IO.File]::WriteAllText((Join-Path $dir 'stdout.txt'),$out.GetAwaiter().GetResult())}
    if($err.IsCompleted){[IO.File]::WriteAllText((Join-Path $dir 'stderr.txt'),$err.GetAwaiter().GetResult())}
    $files=@();foreach($name in @('stdout.txt','stderr.txt','owned-process.json')){if(Test-Path (Join-Path $dir $name)){$files+=[ordered]@{path=$name;sha256=(Get-FileHash (Join-Path $dir $name)).Hash.ToLowerInvariant()}}}
    $rows+=[ordered]@{pair=$pair;label=$label;runtimeCommit=$receipts[$i].sourceCommit;sourceTreeHash=$receipts[$i].sourceTreeHash;startedAt=$started;finishedAt=[DateTimeOffset]::UtcNow.ToString('o');exitCode=if($p.HasExited){$p.ExitCode}else{$null};timedOut=$timedOut;processorLoadBefore=$load;files=$files;directory=(Split-Path $dir -Leaf);createNoWindow=$true}
   }
   Check-Sources
  }
 }
}catch{$errorText=[string]$_}
finally{
 [ordered]@{kind='windows-owned-matched-runtime-timing';owner=$ready.owner;baselineCommit=$receipts[0].sourceCommit;candidateCommit=$receipts[1].sourceCommit;performanceTestHash=$testHashes[0].ToLowerInvariant();swiftPath=$swift;swiftHash=(Get-FileHash $swift).Hash.ToLowerInvariant();pairsRequested=$Pairs;rows=$rows;error=$errorText;thresholdUnchanged=$true;stageModified=$false;nativeWindowOpened=$false;finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $run 'timing-receipt.json')
}
