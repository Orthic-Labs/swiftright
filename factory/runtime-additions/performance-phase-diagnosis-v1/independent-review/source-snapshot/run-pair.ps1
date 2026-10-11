param([Parameter(Mandatory=$true)][string]$InputRoot,[Parameter(Mandatory=$true)][string]$RunRoot)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$inputDir=[IO.Path]::GetFullPath($InputRoot);$run=[IO.Path]::GetFullPath($RunRoot)
if($run -notmatch '^D:\\Claude\\factory-swiftright-perfphase-[A-Za-z0-9_-]+$' -or (Test-Path -LiteralPath $run)){throw 'Fresh additive owned run root required'}
$config=Get-Content -LiteralPath (Join-Path $inputDir 'config.json') -Raw|ConvertFrom-Json
function Hash($path){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
if((Hash $config.compiler) -cne $config.compilerHash){throw 'Exact fixed compiler required'}
$diag=Join-Path $inputDir 'PerformancePhaseDiagnosisTests.swift';if((Hash $diag) -cne $config.diagnosticHash){throw 'Diagnostic source hash differs'}
New-Item -ItemType Directory -Path $run|Out-Null
Copy-Item -LiteralPath (Join-Path $inputDir 'config.json') -Destination (Join-Path $run 'config.json')
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Platforms\6.4.0\Windows.platform\Developer\Library\XCTest-6.4.0\usr\bin64;C:\Users\adrds\AppData\Local\Programs\Swift\Platforms\6.4.0\Windows.platform\Developer\Library\Testing-6.4.0\usr\bin64;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$processRuns=@();$hosts=@();$errorText=''
function Capture($name,$exe,$argv,$cwd,$timeoutSec){
 $dir=Join-Path $run $name;New-Item -ItemType Directory -Path $dir|Out-Null
 $info=[Diagnostics.ProcessStartInfo]::new($exe);$info.Arguments=($argv|ForEach-Object {'"'+($_ -replace '"','\"')+'"'}) -join ' ';$info.WorkingDirectory=$cwd;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $load=@(Get-CimInstance Win32_Processor|Select-Object DeviceID,LoadPercentage)
 $p=[Diagnostics.Process]::Start($info);$start=$p.StartTime.ToUniversalTime().ToString('o');$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$origin=@();$seen=@{};$timedOut=$false;$deadline=[DateTimeOffset]::UtcNow.AddSeconds($timeoutSec)
 while(-not $p.HasExited){
  $all=@(Get-CimInstance Win32_Process);$ids=@($p.Id);$changed=$true
  while($changed){$changed=$false;foreach($x in $all){if($x.ParentProcessId -in $ids -and $x.ProcessId -notin $ids){$ids+= $x.ProcessId;$changed=$true}}}
  foreach($x in $all|Where-Object ProcessId -in $ids){$key=[string]$x.ProcessId+'|'+[string]$x.CreationDate;if(-not $seen.ContainsKey($key)){$seen[$key]=$true;$origin+=[ordered]@{pid=$x.ProcessId;parentPid=$x.ParentProcessId;creationDate=[string]$x.CreationDate;executablePath=$x.ExecutablePath;commandLine=$x.CommandLine}}}
  if([DateTimeOffset]::UtcNow -ge $deadline){$timedOut=$true;$owned=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($owned -and $owned.Path -eq $exe -and $owned.StartTime.ToUniversalTime().ToString('o') -eq $start){& taskkill /PID $p.Id /T /F|Out-Null};break}
  $p.WaitForExit(500)|Out-Null
 }
 if(-not $p.WaitForExit(5000)){throw 'Owned process did not exit after bounded stop'};$stdout=$out.GetAwaiter().GetResult();$stderr=$err.GetAwaiter().GetResult()
 [IO.File]::WriteAllText((Join-Path $dir 'stdout.txt'),$stdout);[IO.File]::WriteAllText((Join-Path $dir 'stderr.txt'),$stderr)
 $record=[ordered]@{name=$name;executable=$exe;executableHash=Hash $exe;argv=@($argv);cwd=$cwd;startedAt=$start;endedAt=[DateTime]::UtcNow.ToString('o');pid=$p.Id;returncode=$p.ExitCode;timedOut=$timedOut;createNoWindow=$true;stdoutHash=Hash (Join-Path $dir 'stdout.txt');stderrHash=Hash (Join-Path $dir 'stderr.txt');cimOrigins=$origin;processorLoadBefore=$load}
 $record|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $dir 'process.json')
 $script:processRuns+= $record
 return [pscustomobject]@{record=$record;stdout=$stdout;stderr=$stderr}
}
function VerifyOriginal($h){
 $root=[IO.Path]::GetFullPath($h.originalRoot)
 if($root -notmatch '^D:\\Claude\\factory-swiftright-(baseline-8e47b89|font-37429120)-20261011\\runtime$'){throw 'Exact preserved input root required'}
 foreach($b in $h.bindings){$f=Join-Path $root $b.path;if((Hash $f) -cne $b.sha256 -or (Get-Item -LiteralPath $f).Length -ne $b.bytes){throw 'Preserved input source differs: '+$b.path}}
 $actual=@((Get-Item -LiteralPath (Join-Path $root 'Package.swift')), (Get-ChildItem -LiteralPath (Join-Path $root 'Sources') -Recurse -File -Filter '*.swift'),(Get-ChildItem -LiteralPath (Join-Path $root 'Tests') -Recurse -File -Filter '*.swift'))|ForEach-Object {$_}
 if($actual.Count -ne @($h.bindings).Count){throw 'Input source coverage differs'}
}
try{
 $version=Capture 'compiler-version' $config.compiler @('--version') $run 30
 foreach($h in $config.hosts){
  VerifyOriginal $h
  $dir=Join-Path $run $h.label;New-Item -ItemType Directory -Path $dir|Out-Null
  $runtime=Join-Path $dir 'runtime';New-Item -ItemType Directory -Path $runtime|Out-Null
  foreach($part in @('Package.swift','Sources','Tests')){Copy-Item -LiteralPath (Join-Path $h.originalRoot $part) -Destination $runtime -Recurse}
  foreach($b in $h.bindings){if((Hash (Join-Path $runtime $b.path)) -cne $b.sha256){throw 'Copied source differs'}}
  Copy-Item -LiteralPath $diag -Destination (Join-Path $runtime 'Tests\SwiftRightRuntimeTests\PerformancePhaseDiagnosisTests.swift')
  $scratch=Join-Path $dir 'scratch'
  $build=Capture ($h.label+'-build') $config.compiler @('build','--package-path',$runtime,'--scratch-path',$scratch,'-c','release','--build-tests','-Xswiftc','-enable-testing') $runtime 900
  if($build.record.returncode -ne 0){throw 'Diagnostic compile failed: '+$h.label}
  $bins=@(Get-ChildItem -LiteralPath $scratch -Recurse -File -Filter 'SwiftRightRuntimeTests-test-runner.exe')
  if($bins.Count -ne 1){throw 'Unique compiled test runner required'}
  $binary=$bins[0].FullName;$dll=Join-Path $bins[0].DirectoryName 'SwiftRightRuntimeTests.dll'
  $hosts+=[ordered]@{label=$h.label;commit=$h.commit;sourceBindings=$h.bindings;originalRoot=$h.originalRoot;diagnosticHash=$config.diagnosticHash;runtime=$runtime;binary=$binary;binaryHash=Hash $binary;dllHash=Hash $dll;compilerHash=$config.compilerHash}
 }
 # Exactly one serial matched pair. Original order fixed before any measurements.
 foreach($h in $hosts){
  $result=Capture ($h.label+'-test') $h.binary @('SwiftRightRuntimeTests.PerformancePhaseDiagnosisTests/testMatchedOriginalWorkload') (Split-Path $h.binary) 60
  if($result.stdout -notmatch '(?m)^PHASE_DIAG (.+)$'){throw 'Actual diagnostic output absent'}
  $phase=$Matches[1]|ConvertFrom-Json
  if(-not $phase.optimized -or @($phase.observations).Count -ne 90 -or $phase.limitsMS.typing -ne 2 -or $phase.limitsMS.scroll -ne 4 -or $phase.limitsMS.rowEdit -ne 15){throw 'Exact workload or limits differ'}
  $phase|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $run ($h.label+'-phase.json'))
 }
 foreach($h in $config.hosts){VerifyOriginal $h}
}catch{$errorText=[string]$_}
finally{
 [ordered]@{schema='matched-performance-phase-receipt-v1';hypothesis=$config.hypothesis;limitsMS=$config.limitsMS;order=@('original','current');pairCount=1;hosts=$hosts;processRuns=$processRuns;error=$errorText;runtimeEdits=0;originalTestsEdits=0;nativeWindowOpened=$false;desktopLockRequired=$false;finishedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 20|Set-Content -Encoding UTF8 (Join-Path $run 'receipt.json')
}
if($errorText){throw $errorText}
'ONE matched phase pair retained at '+$run
