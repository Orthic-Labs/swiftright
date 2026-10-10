# Immutable postshape/fontstorage release binaries, serial paired timing; no compiler invocation.
param([Parameter(Mandatory=$true)][string]$Config,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$ReservationRoot,[ValidateRange(1,5)][int]$Rounds=3,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$run=[IO.Path]::GetFullPath($RunRoot)
if($run -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\' -or (Test-Path $run)){throw 'Fresh owned timing archive required'}
$timingConfig=Get-Content $Config -Raw|ConvertFrom-Json
if(@($timingConfig.hosts).Count -ne 2 -or @($timingConfig.hosts.label|Select-Object -Unique).Count -ne 2){throw 'Two distinct labelled binaries required'}
$expectedCommits=@('bbceb5a14cab2be125af68f8e84014a29f3277a7','37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b')
$expectedLabels=@('postshape','fontstorage')
function Binding-Hash($bindings) {
 $items=@();foreach($b in @($bindings)){
  if($b.path -notmatch '^[A-Za-z0-9_./-]+$' -or $b.path -match '(^|/)\.\.(/|$)' -or $b.sha256 -notmatch '^sha256:[a-f0-9]{64}$'){throw 'Canonical source binding invalid'}
  $items+= [ordered]@{path=[string]$b.path;sha256=[string]$b.sha256}
 }
 if(-not $items.Count -or @($items.path|Select-Object -Unique).Count -ne $items.Count){throw 'Nonempty unique source bindings required'}
 $json=ConvertTo-Json -InputObject ([object[]]$items) -Depth 5 -Compress
 $sha=[Security.Cryptography.SHA256]::Create();try{return 'sha256:'+([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}
}
$ready=Get-Content (Join-Path $ReservationRoot 'lock-ready.json') -Raw|ConvertFrom-Json
function Check-Lock {if((Get-Content 'D:\Claude\desktop.lock' -Raw).Trim() -ne $ready.owner){throw 'Reservation lost'};if(([DateTimeOffset]$ready.leaseDeadline) -lt [DateTimeOffset]::UtcNow.AddMinutes(2)){throw 'Reservation lease insufficient'}}
$hosts=@();$performanceHash=$null;$hostIndex=0
foreach($h in $timingConfig.hosts){
 $root=[IO.Path]::GetFullPath($h.runtimeRoot);$binary=[IO.Path]::GetFullPath($h.binary)
 if($root -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\' -or -not $binary.StartsWith((Split-Path $root)+'\',[StringComparison]::OrdinalIgnoreCase) -or $binary -notmatch '\\Release-windows-x86_64\\SwiftRightRuntimeTests-test-runner.exe$'){throw 'Owned release test runner required'}
 $receiptPath=Join-Path (Split-Path $root) 'runtime-source-receipt.json';$receipt=Get-Content $receiptPath -Raw|ConvertFrom-Json
 if($receipt.synthetic -or $receipt.sourceCommit -notmatch '^[a-f0-9]{40}$'){throw 'Actual committed runtime snapshot required'}
 if($h.label -cne $expectedLabels[$hostIndex] -or $h.sourceCommit -cne $expectedCommits[$hostIndex] -or $receipt.sourceCommit -cne $expectedCommits[$hostIndex]){throw 'Exact postshape/fontstorage pins required'}
 if($h.sourceReceiptHash -cne ('sha256:'+(Get-FileHash $receiptPath).Hash.ToLowerInvariant())){throw 'Archived source receipt hash differs'}
 if((Binding-Hash $receipt.sourceBindings) -cne $receipt.sourceTreeHash -or (Binding-Hash $receipt.completeSnapshotBindings) -cne $receipt.completeSnapshotHash){throw 'Canonical source tree/snapshot hash differs'}
 if(1+@(Get-ChildItem (Join-Path $root 'Sources') -Recurse -File).Count -ne @($receipt.sourceBindings).Count){throw 'Runtime source coverage differs'}
 $archive=[IO.Path]::GetFullPath($h.binaryArchiveRoot)
 if($archive -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\' -or @($h.binaryBindings).Count -ne 2 -or @($h.binaryBindings.path|Select-Object -Unique).Count -ne 2){throw 'Owned exact archived test executable/DLL required'}
 foreach($b in $h.binaryBindings){
  if($b.path -cnotin @('SwiftRightRuntimeTests-test-runner.exe','SwiftRightRuntimeTests.dll') -or $b.hash -notmatch '^sha256:[a-f0-9]{64}$'){throw 'Expected archived binary binding invalid'}
  foreach($p in @((Join-Path $archive $b.path),(Join-Path (Split-Path $binary) $b.path))){if(('sha256:'+(Get-FileHash $p).Hash.ToLowerInvariant()) -cne $b.hash){throw 'Current binary differs from expected archive'}}
 }
 $compilePath=[IO.Path]::GetFullPath($h.compileEvidencePath)
 if($compilePath -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\' -or ('sha256:'+(Get-FileHash $compilePath).Hash.ToLowerInvariant()) -cne $h.compileEvidenceHash){throw 'Actual archived compile evidence required'}
 $compiled=Get-Content $compilePath -Raw|ConvertFrom-Json
 if($compiled.kind -eq 'factory-windows-headless-runtime'){
  if($compiled.sourceCommit -cne $receipt.sourceCommit -or $compiled.sourceTreeHash -cne $receipt.sourceTreeHash -or $compiled.configuration -cne 'release' -or $compiled.error -or @($compiled.commands|Where-Object {$_.command -eq 'build' -and $_.exitCode -eq 0 -and -not $_.timedOut}).Count -ne 1){throw 'Headless compile context differs'}
  foreach($b in $h.binaryBindings){if(@($compiled.binaryBindings|Where-Object {(Split-Path $_.path -Leaf) -ceq $b.path -and $_.sha256 -ceq $b.hash.Replace('sha256:','')}).Count -ne 1){throw 'Binary differs from actual compile receipt'}}
 }elseif($compiled.kind -eq 'windows-owned-matched-runtime-timing'){
  if($compiled.error -or @($compiled.rows|Where-Object {$_.runtimeCommit -ceq $receipt.sourceCommit -and $_.sourceTreeHash -ceq $receipt.sourceTreeHash -and -not $_.timedOut}).Count -ne 3){throw 'Prior actual release compile/test context differs'}
 }else{throw 'Unsupported compile evidence'}
 $testHash=(Get-FileHash (Join-Path $root 'Tests\SwiftRightRuntimeTests\PerformanceTests.swift')).Hash.ToLowerInvariant()
 if($performanceHash -and $performanceHash -ne $testHash){throw 'Same unchanged performance source required'};$performanceHash=$testHash
 $bindings=@(Get-ChildItem (Split-Path $binary) -File|Where-Object {$_.Extension -in @('.exe','.dll')}|ForEach-Object{[ordered]@{path=$_.FullName;hash=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})
 $hosts+=[ordered]@{label=$h.label;root=$root;binary=$binary;runtimeCommit=$receipt.sourceCommit;sourceTreeHash=$receipt.sourceTreeHash;receiptHash=(Get-FileHash $receiptPath).Hash.ToLowerInvariant();sourceBindings=$receipt.completeSnapshotBindings;binaryBindings=$bindings;binaryArchiveRoot=$archive;expectedBinaryBindings=$h.binaryBindings;compileEvidencePath=$compilePath;compileEvidenceHash=$h.compileEvidenceHash;priorCompileReceiptBoundBinaryHashes=($compiled.kind -eq 'factory-windows-headless-runtime')}
 $hostIndex++
}
if(@($hosts.runtimeCommit|Select-Object -Unique).Count -ne 2){throw 'Distinct postshape/fontstorage commits required'}
function Check-Bindings {foreach($h in $hosts){
 if((Get-FileHash (Join-Path (Split-Path $h.root) 'runtime-source-receipt.json')).Hash.ToLowerInvariant() -cne $h.receiptHash -or ('sha256:'+(Get-FileHash $h.compileEvidencePath).Hash.ToLowerInvariant()) -cne $h.compileEvidenceHash){throw 'Archived provenance drift'}
 foreach($b in $h.sourceBindings){$p=[IO.Path]::GetFullPath((Join-Path $h.root $b.path));if(-not $p.StartsWith($h.root+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $p).Hash.ToLowerInvariant() -ne $b.sha256.Replace('sha256:','')){throw 'Immutable source drift'}}
 foreach($b in $h.binaryBindings){if((Get-FileHash $b.path).Hash.ToLowerInvariant() -ne $b.hash){throw 'Immutable release binary drift'}}
 foreach($b in $h.expectedBinaryBindings){if(('sha256:'+(Get-FileHash (Join-Path $h.binaryArchiveRoot $b.path)).Hash.ToLowerInvariant()) -cne $b.hash){throw 'Expected binary archive drift'}}
}}
Check-Lock;Check-Bindings
if($ValidateOnly){[ordered]@{kind='windows-cached-timing-readonly-preflight';validated=$true;nativeWindowOpened=$false;childLaunched=$false;configHash=(Get-FileHash $Config).Hash.ToLowerInvariant()}|ConvertTo-Json;return}
New-Item -ItemType Directory $run|Out-Null
Copy-Item $Config (Join-Path $run 'config.json')
$testFrameworkDirectories=@('C:\Users\adrds\AppData\Local\Programs\Swift\Platforms\6.4.0\Windows.platform\Developer\Library\XCTest-6.4.0\usr\bin64','C:\Users\adrds\AppData\Local\Programs\Swift\Platforms\6.4.0\Windows.platform\Developer\Library\Testing-6.4.0\usr\bin64')
$testFrameworkBindings=@(Get-ChildItem $testFrameworkDirectories -Filter '*.dll' -File|ForEach-Object{[ordered]@{path=$_.FullName;hash=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})
if($testFrameworkBindings.Count -ne 5){throw 'Expected installed Swift6.4 x64 test frameworks required'}
$knownFrameworkHashes=@{'XCTest.dll'='84111b60479bfbee6487899a36527b416a986b659a6262ef11347f859be576d6';'Testing.dll'='a7522627b6df7ad56105e5789b16402da80a62d17a6542cb3cdc670a8164d136';'_Testing_Foundation.dll'='7badcbdcfdc5d49d82cd3590f101bb1f66bf8acabc6bdfabe8f274b86acc2b97';'_Testing_WinSDK.dll'='b70c992478e192e639902d77a734294ac006f06cc477ab01988f0590c50d9dee';'_TestingInterop.dll'='4da22e9e2e87f34cb819ba8761a2f4ae8908e9bc65d3622bbb89c40a376ad839'}
foreach($b in $testFrameworkBindings){if($b.hash -cne $knownFrameworkHashes[(Split-Path $b.path -Leaf)]){throw 'Recorded Swift6.4 x64 test-framework pin differs'}}
$env:Path=($testFrameworkDirectories -join ';')+';C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$rows=@();$errorText='';$filter='SwiftRightRuntimeTests.PerformanceTests/testSingleRowEditCommitTime'
try{
 # One discarded but archived warm run per binary, followed by balanced cyclic orders.
 for($round=0;$round -le $Rounds;$round++){
  $order=if($round -eq 0 -or $round%2 -eq 1){@(0,1)}else{@(1,0)}
  foreach($i in $order){
   Check-Lock;Check-Bindings;foreach($b in $testFrameworkBindings){if((Get-FileHash $b.path).Hash.ToLowerInvariant() -cne $b.hash){throw 'Installed test framework drift'}};$h=$hosts[$i];$dir=Join-Path $run ('round-{0:D2}-{1}' -f $round,$h.label);New-Item -ItemType Directory $dir|Out-Null
   $load=@(Get-CimInstance Win32_Processor|Select-Object DeviceID,LoadPercentage)
   $info=[Diagnostics.ProcessStartInfo]::new($h.binary);$info.Arguments=$filter;$info.WorkingDirectory=Split-Path $h.binary;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
   $p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o');$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$deadline=[DateTimeOffset]::UtcNow.AddSeconds(60);$timeout=$false
   [ordered]@{pid=$p.Id;path=$h.binary;startedAt=$started}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'owned-process.json')
   try{while(-not $p.WaitForExit(100)){Check-Lock;if([DateTimeOffset]::UtcNow -ge $deadline){$timeout=$true;throw 'Owned test runner deadline'}}}
   finally{
    if(-not $p.HasExited){$owned=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($owned -and $owned.Path -eq $h.binary -and $owned.StartTime.ToUniversalTime().ToString('o') -eq $started){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null}
    $text='';if($out.Wait(5000)){$text=$out.GetAwaiter().GetResult();[IO.File]::WriteAllText((Join-Path $dir 'stdout.txt'),$text)};if($err.Wait(5000)){[IO.File]::WriteAllText((Join-Path $dir 'stderr.txt'),$err.GetAwaiter().GetResult())}
    $rows+=[ordered]@{round=$round;warmup=$round -eq 0;label=$h.label;runtimeCommit=$h.runtimeCommit;sourceTreeHash=$h.sourceTreeHash;startedAt=$started;finishedAt=[DateTime]::UtcNow.ToString('o');exitCode=$p.ExitCode;timedOut=$timeout;actualPerformanceOutputPresent=$text.Contains('PERF 200-row commit medians');requestedTestOnly=($text -match 'Executed 1 test, with' -and $text -notmatch 'Executed [2-9][0-9]* tests, with|Executed 1[0-9]+ tests, with');processorLoadBefore=$load;stdoutHash=(Get-FileHash (Join-Path $dir 'stdout.txt')).Hash.ToLowerInvariant();stderrHash=(Get-FileHash (Join-Path $dir 'stderr.txt')).Hash.ToLowerInvariant();directory=Split-Path $dir -Leaf}
   }
   if(-not $rows[-1].actualPerformanceOutputPresent -or -not $rows[-1].requestedTestOnly){throw 'Exactly requested performance test did not actually execute'}
  }
 }
}catch{$errorText=[string]$_}
finally{Check-Bindings;[ordered]@{kind='windows-serial-cached-release-current67-postshape-timing';filter=$filter;owner=$ready.owner;hosts=$hosts;testFrameworkBindings=$testFrameworkBindings;performanceTestHash=$performanceHash;rows=$rows;error=$errorText;thresholdUnchanged=$true;compileInvoked=$false;nativeWindowOpened=$false;configuration='release';finishedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 15|Set-Content -Encoding UTF8 (Join-Path $run 'timing-receipt.json')}
