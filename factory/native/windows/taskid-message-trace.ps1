# Three fresh diagnostic test binaries; exactly nine serial isolated TaskID processes.
param([Parameter(Mandatory=$true)][string]$Config,[Parameter(Mandatory=$true)][string]$RunRoot,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$run=[IO.Path]::GetFullPath($RunRoot)
if($run -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\' -or (Test-Path $run)){throw 'Fresh owned timing archive required'}
$timingConfig=Get-Content $Config -Raw|ConvertFrom-Json
if(@($timingConfig.hosts).Count -ne 3 -or @($timingConfig.hosts.label|Select-Object -Unique).Count -ne 3){throw 'Three diagnostic variants required'}
$expectedCommits=@('8e47b89b3e9ae488e77ea8b5a2e4663053601c0d','bbceb5a14cab2be125af68f8e84014a29f3277a7','37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b')
$expectedLabels=@('baseline','postshape','fontstorage')
$expectedReceipts=@('sha256:2c80c056793927e655f75264a77a9e541f033ba2900bc14cecd80bbaec79d3ee','sha256:8864e4c7cb27d61083a6d453a45fe0446e0bc96701d292b475b6e3e6226f1ad7','sha256:c90002dcbb26d0a36c3c887dc53e1e45cb4501556b43e15866d397da76cacf83')
function Binding-Hash($bindings) {
 $items=@();foreach($b in @($bindings)){
  if($b.path -notmatch '^[A-Za-z0-9_./-]+$' -or $b.path -match '(^|/)\.\.(/|$)' -or $b.sha256 -notmatch '^sha256:[a-f0-9]{64}$'){throw 'Canonical source binding invalid'}
  $items+= [ordered]@{path=[string]$b.path;sha256=[string]$b.sha256}
 }
 if(-not $items.Count -or @($items.path|Select-Object -Unique).Count -ne $items.Count){throw 'Nonempty unique source bindings required'}
 $json=ConvertTo-Json -InputObject ([object[]]$items) -Depth 5 -Compress
 $sha=[Security.Cryptography.SHA256]::Create();try{return 'sha256:'+([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}
}
$ready=$null
function Check-Lock {} # No GUI/input/desktop dependency; headless diagnostics may continue after lease.
$hosts=@();$performanceHash=$null;$hostIndex=0
foreach($h in $timingConfig.hosts){
 $root=[IO.Path]::GetFullPath($h.runtimeRoot);$binary=[IO.Path]::GetFullPath($h.binary)
 if($root -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\' -or -not $binary.StartsWith((Split-Path $root)+'\',[StringComparison]::OrdinalIgnoreCase) -or $binary -notmatch '\\Release-windows-x86_64\\SwiftRightRuntimeTests-test-runner.exe$'){throw 'Owned release test runner required'}
 $receiptPath=Join-Path (Split-Path $root) 'runtime-source-receipt.json';$receipt=Get-Content $receiptPath -Raw|ConvertFrom-Json
 if($receipt.synthetic -or -not $receipt.diagnosticOnly -or $receipt.kind -cne 'factory-diagnostic-runtime-source' -or $receipt.diagnosticTaskSourceHash -cne 'sha256:bc720665b481a84ed717a6a8a20af721d8bfee7e29bcf984881e6dd4b6bed7c7' -or $h.sourceReceiptHash -cne $expectedReceipts[$hostIndex]){throw 'Exact diagnostic source receipt required'}
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
 if(-not $compiled.diagnosticOnly -or $compiled.sourceCommit -cne $receipt.sourceCommit -or $compiled.sourceTreeHash -cne $receipt.sourceTreeHash -or $compiled.diagnosticCompleteSnapshotHash -cne $receipt.completeSnapshotHash -or $compiled.diagnosticSourceReceiptHash -cne $h.sourceReceiptHash -or $compiled.exitCode -ne 0 -or $compiled.timedOut -or $compiled.testRunnerExecuted -or (-not $compiled.arguments.Contains('build --build-tests') -or -not $compiled.arguments.Contains('-Xswiftc -enable-testing'))){throw 'Diagnostic build receipt differs'}
 foreach($b in $h.binaryBindings){if(@($compiled.binaryBindings|Where-Object {(Split-Path $_.path -Leaf) -ceq $b.path -and $_.sha256 -ceq $b.hash.Replace('sha256:','')}).Count -ne 1){throw 'Diagnostic binary differs from build receipt'}}
 $testHash=(Get-FileHash (Join-Path $root 'Tests\SwiftRightRuntimeTests\PerformanceTests.swift')).Hash.ToLowerInvariant()
 if($performanceHash -and $performanceHash -ne $testHash){throw 'Same unchanged performance source required'};$performanceHash=$testHash
 $bindings=@(Get-ChildItem (Split-Path $binary) -File|Where-Object {$_.Extension -in @('.exe','.dll')}|ForEach-Object{[ordered]@{path=$_.FullName;hash=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})
 $hosts+=[ordered]@{label=$h.label;root=$root;binary=$binary;runtimeCommit=$receipt.sourceCommit;sourceTreeHash=$receipt.sourceTreeHash;receiptHash=(Get-FileHash $receiptPath).Hash.ToLowerInvariant();sourceBindings=$receipt.completeSnapshotBindings;binaryBindings=$bindings;binaryArchiveRoot=$archive;expectedBinaryBindings=$h.binaryBindings;compileEvidencePath=$compilePath;compileEvidenceHash=$h.compileEvidenceHash;swiftPath=$compiled.swiftPath;swiftHash=$compiled.swiftHash;priorCompileReceiptBoundBinaryHashes=$true}
 $hostIndex++
}
if(@($hosts.runtimeCommit|Select-Object -Unique).Count -ne 3){throw 'Distinct postshape/fontstorage commits required'}
function Check-Bindings {foreach($h in $hosts){
 if((Get-FileHash $h.swiftPath).Hash.ToLowerInvariant() -cne $h.swiftHash){throw 'Recorded compiler toolchain drift'}
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
function Check-NoCompiler {if(@(Get-Process swift,swiftc,swift-frontend,lld-link,clang -ErrorAction SilentlyContinue).Count){throw 'Compiler activity forbids diagnostic test execution'}}
$rows=@();$errorText='';$filter=''
$taskSourceBindings=@();foreach($name in @('TaskIDTests.swift','RuntimeTests.swift')){$expected=if($name -ceq 'TaskIDTests.swift'){'bc720665b481a84ed717a6a8a20af721d8bfee7e29bcf984881e6dd4b6bed7c7'}else{'26a8a11ad70dcf5b64450fe75976e7149eadcaeccbc076143c6ccc0c21b32b6e'};foreach($h in $hosts){if((Get-FileHash (Join-Path $h.root ('Tests\SwiftRightRuntimeTests\'+$name))).Hash.ToLowerInvariant() -cne $expected){throw 'Exact diagnostic TaskID/settle source required'}};$taskSourceBindings+=[ordered]@{name=$name;hash=$expected}}

try{
 # Three cyclic orders; no warmups or additional test processes.
 for($round=0;$round -lt 3;$round++){
  $phase=1;$expectedTests=1;$filter='SwiftRightRuntimeTests.TaskIDTests/testSameIdDoesNotRestartTask'
  $order=switch($round){0{@(0,1,2)};1{@(1,2,0)};2{@(2,0,1)}}
  foreach($i in $order){
   Check-NoCompiler;Check-Lock;Check-Bindings;foreach($b in $testFrameworkBindings){if((Get-FileHash $b.path).Hash.ToLowerInvariant() -cne $b.hash){throw 'Installed test framework drift'}};$h=$hosts[$i];$dir=Join-Path $run ('round-{0:D2}-{1}' -f $round,$h.label);New-Item -ItemType Directory $dir|Out-Null
   $load=@(Get-CimInstance Win32_Processor|Select-Object DeviceID,LoadPercentage)
   $info=[Diagnostics.ProcessStartInfo]::new($h.binary);$info.Arguments=$filter;$info.WorkingDirectory=Split-Path $h.binary;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
   $p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o');$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$deadline=[DateTimeOffset]::UtcNow.AddSeconds(60);$timeout=$false
   [ordered]@{pid=$p.Id;path=$h.binary;startedAt=$started}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'owned-process.json')
   try{while(-not $p.WaitForExit(100)){Check-NoCompiler;Check-Lock;if([DateTimeOffset]::UtcNow -ge $deadline){$timeout=$true;throw 'Owned test runner deadline'}}}
   finally{
    if(-not $p.HasExited){$owned=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($owned -and $owned.Path -eq $h.binary -and $owned.StartTime.ToUniversalTime().ToString('o') -eq $started){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null}
    $text='';if($out.Wait(5000)){$text=$out.GetAwaiter().GetResult();[IO.File]::WriteAllText((Join-Path $dir 'stdout.txt'),$text)};if($err.Wait(5000)){[IO.File]::WriteAllText((Join-Path $dir 'stderr.txt'),$err.GetAwaiter().GetResult())}
    $rows+=[ordered]@{round=$round;phase=$phase;expectedTests=$expectedTests;label=$h.label;runtimeCommit=$h.runtimeCommit;sourceTreeHash=$h.sourceTreeHash;startedAt=$started;finishedAt=[DateTime]::UtcNow.ToString('o');exitCode=$p.ExitCode;timedOut=$timeout;requestedTestOnly=($text -match ('Executed '+$expectedTests+' tests?, with') -and $text.Contains('TaskIDTests') -and @([regex]::Matches($text,'Executed ([0-9]+) tests?, with')|Where-Object {[int]$_.Groups[1].Value -ne $expectedTests}).Count -eq 0);actualTestCount=if($text -match 'Executed ([0-9]+) tests?, with'){[int]$Matches[1]}else{0};processorLoadBefore=$load;stdoutHash=(Get-FileHash (Join-Path $dir 'stdout.txt')).Hash.ToLowerInvariant();stderrHash=(Get-FileHash (Join-Path $dir 'stderr.txt')).Hash.ToLowerInvariant();directory=Split-Path $dir -Leaf}
   }
   if(-not $rows[-1].requestedTestOnly){throw 'Exactly requested TaskID tests did not actually execute'}
  }
 }
}catch{$errorText=[string]$_}
finally{Check-Bindings;[ordered]@{kind='windows-diagnostic-message-trace-taskid';diagnosticOnly=$true;sourceTestsMessageChanged=$true;maximumTestProcesses=9;filter=$filter;desktopReservationRequired=$false;hosts=$hosts;testFrameworkBindings=$testFrameworkBindings;performanceTestHash=$performanceHash;taskSourceBindings=$taskSourceBindings;rows=$rows;error=$errorText;thresholdUnchanged=$true;compileInvoked=$false;nativeWindowOpened=$false;configuration='release';finishedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 15|Set-Content -Encoding UTF8 (Join-Path $run 'trace-receipt.json')}
