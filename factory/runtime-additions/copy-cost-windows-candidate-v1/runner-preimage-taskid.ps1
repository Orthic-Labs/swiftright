param(
  [Parameter(Mandatory=$true)][string]$InputRoot,
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [Parameter(Mandatory=$true)][string]$ExecutionToken
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$ExpectedToken='RUN-NOW-PERFORMANCE-PAIR-COMPLETE'
if($ExecutionToken -cne $ExpectedToken){throw 'Execution is held until compilerbridge_review performance pair confirmation'}

function Full([string]$p){return [IO.Path]::GetFullPath($p)}
$ownedInputRoot=Full $InputRoot
$run=Full $RunRoot
if($ownedInputRoot -notmatch '^D:\\Claude\\factory-swiftright-taskid-three-input-[A-Za-z0-9_-]+$'){throw 'Owned fresh D:\\Claude input root required'}
if($run -notmatch '^D:\\Claude\\factory-swiftright-taskid-three-run-[A-Za-z0-9_-]+$'){throw 'Owned fresh D:\\Claude run root required'}
if(Test-Path -LiteralPath $run){throw 'Run root already exists; no overwrite/retry'}
$planPath=Join-Path $ownedInputRoot 'source-plan.json'
if(-not (Test-Path -LiteralPath $planPath)){throw 'Source plan missing'}
$plan=Get-Content -LiteralPath $planPath -Raw|ConvertFrom-Json
if($plan.schema -cne 'taskid-windows-three-variants-source-plan-v1'){throw 'Unexpected source plan'}
if(@($plan.variants).Count -ne 3){throw 'Exactly three variants required'}
if($plan.commonPins.filter -cne 'SwiftRightRuntimeTests.TaskIDTests/testSameIdDoesNotRestartTask' -or $plan.commonPins.configuration -cne 'release' -or [int]$plan.commonPins.taskBodySleepMilliseconds -ne 40 -or [int]$plan.commonPins.settleSleepMilliseconds -ne 120){throw 'Exact TaskID workload pins required'}

function Hash([string]$path){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function BindingRows([string]$root,[object[]]$expected){
  $root=Full $root
  $actual=@{}
  foreach($f in @(Get-ChildItem -LiteralPath $root -Recurse -File)){
    $rel=$f.FullName.Substring($root.Length+1).Replace('\','/')
    $actual[$rel]=[ordered]@{path=$rel;bytes=[int64]$f.Length;sha256=(Hash $f.FullName);creationTimeUtc=$f.CreationTimeUtc.ToString('o');lastWriteTimeUtc=$f.LastWriteTimeUtc.ToString('o')}
  }
  $rows=@()
  foreach($e in @($expected)){
    $path=[string]$e.path
    if($path -match '(^|/)\.\.(/|$)' -or $path -match '^[A-Za-z]:'){throw 'Noncanonical source binding'}
    if(-not $actual.ContainsKey($path)){throw "Missing source file: $path"}
    $a=$actual[$path]
    if([int64]$e.bytes -ne $a.bytes -or ([string]$e.sha256).ToLowerInvariant() -cne $a.sha256){throw "Source binding differs: $path"}
    $rows+=$a
  }
  if($actual.Count -ne @($expected).Count){$extra=(@($actual.Keys|Where-Object {$_ -notin @($expected.path)}) -join ',');throw "Unexpected source files: $extra"}
  return @($rows|Sort-Object path)
}
function WriteJson([string]$path,[object]$value){$value|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $path -Encoding UTF8}
function CimSnapshot([int[]]$ids){
  $all=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
  @($all|Where-Object {$_.ProcessId -in $ids}|ForEach-Object{[ordered]@{pid=[int]$_.ProcessId;parentPid=[int]$_.ParentProcessId;creationDate=[string]$_.CreationDate;executablePath=[string]$_.ExecutablePath;commandLine=[string]$_.CommandLine}})
}
function RunOwned([string]$name,[string]$exe,[string[]]$argv,[string]$cwd,[string]$outDir,[int]$timeoutSec){
  New-Item -ItemType Directory -Path $outDir -Force|Out-Null
  $info=[Diagnostics.ProcessStartInfo]::new($exe)
  $info.Arguments=(($argv|ForEach-Object {'"'+($_ -replace '"','\\"')+'"'}) -join ' ')
  $info.WorkingDirectory=$cwd
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $before=@(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue|Select-Object DeviceID,LoadPercentage)
  $record=[ordered]@{name=$name;executable=$exe;executableHash=(Hash $exe);argv=@($argv);cwd=$cwd;startedAt=$null;endedAt=$null;pid=$null;exitCode=$null;timedOut=$false;stdoutHash=$null;stderrHash=$null;stdoutBytes=$null;stderrBytes=$null;processorLoadBefore=$before;cimObserved=@()}
  $p=$null;$stdout='';$stderr='';$stdoutFile=$null;$stderrFile=$null;$errorText=$null;$observed=@{};$ids=@()
  try{
    $p=[Diagnostics.Process]::new();$p.StartInfo=$info
    if(-not $p.Start()){throw 'Process failed to start'}
    $record.pid=[int]$p.Id;$ids=@([int]$p.Id);$record.startedAt=$p.StartTime.ToUniversalTime().ToString('o')
    $stdoutFile=[IO.File]::Create((Join-Path $outDir 'stdout.txt'));$stderrFile=[IO.File]::Create((Join-Path $outDir 'stderr.txt'))
    $stdoutTask=$p.StandardOutput.BaseStream.CopyToAsync($stdoutFile);$stderrTask=$p.StandardError.BaseStream.CopyToAsync($stderrFile)
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($timeoutSec)
    while(-not $p.HasExited){
      $all=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
      $changed=$true
      while($changed){$changed=$false;foreach($x in $all){if($x.ParentProcessId -in $ids -and $x.ProcessId -notin $ids){$ids+=[int]$x.ProcessId;$changed=$true}}}
      foreach($x in @(CimSnapshot $ids)){$key="$($x.pid)|$($x.creationDate)";if(-not $observed.ContainsKey($key)){$observed[$key]=$x}}
      if([DateTimeOffset]::UtcNow -ge $deadline){$record.timedOut=$true;break}
      $p.WaitForExit(50)|Out-Null
    }
    if($record.timedOut -and -not $p.HasExited){
      $owned=Get-Process -Id $p.Id -ErrorAction SilentlyContinue
      if($owned -and $owned.Path -eq $exe -and $owned.StartTime.ToUniversalTime().ToString('o') -ceq $record.startedAt){& taskkill /PID $p.Id /T /F|Out-Null}
    }
    if(-not $p.WaitForExit(10000)){throw 'Owned process did not exit after bounded stop'}
    $stdoutTask.GetAwaiter().GetResult();$stderrTask.GetAwaiter().GetResult()
    $stdoutFile.Dispose();$stderrFile.Dispose();$stdoutFile=$null;$stderrFile=$null
    $stdout=[IO.File]::ReadAllText((Join-Path $outDir 'stdout.txt'));$stderr=[IO.File]::ReadAllText((Join-Path $outDir 'stderr.txt'))
    $record.exitCode=[int]$p.ExitCode
    $record.endedAt=[DateTime]::UtcNow.ToString('o')
  }catch{$errorText=[string]$_;$record.endedAt=[DateTime]::UtcNow.ToString('o')}
  finally{
    if($p){$p.Dispose()}
    $stdoutPath=Join-Path $outDir 'stdout.txt';$stderrPath=Join-Path $outDir 'stderr.txt'
    if($stdoutFile){$stdoutFile.Dispose()};if($stderrFile){$stderrFile.Dispose()}
    if(-not(Test-Path -LiteralPath $stdoutPath)){[IO.File]::WriteAllBytes($stdoutPath,[byte[]]@())}
    if(-not(Test-Path -LiteralPath $stderrPath)){[IO.File]::WriteAllBytes($stderrPath,[byte[]]@())}
    $record.stdoutHash=Hash (Join-Path $outDir 'stdout.txt');$record.stderrHash=Hash (Join-Path $outDir 'stderr.txt')
    $record.stdoutBytes=(Get-Item (Join-Path $outDir 'stdout.txt')).Length;$record.stderrBytes=(Get-Item (Join-Path $outDir 'stderr.txt')).Length
    $record.cimObserved=@($observed.Values)
    if($errorText){$record.error=$errorText}
    WriteJson (Join-Path $outDir 'process.json') $record
  }
  return [pscustomobject]@{record=$record;stdout=$stdout;stderr=$stderr}
}

New-Item -ItemType Directory -Path $run|Out-Null
$receipt=[ordered]@{schema='taskid-windows-three-variants-receipt-v1';status='actual-headless-run';executionTokenAccepted=$true;inputRoot=$ownedInputRoot;runRoot=$run;configuration='release';filter=$plan.commonPins.filter;variants=@();runtimeEdits=0;fullSuite=$false;nativeWindowOpened=$false;desktopReservationRequired=$false;error=$null;startedAt=[DateTime]::UtcNow.ToString('o');toolchain=$null}
$errorText=$null
try{
  $swift='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
  $swiftc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swiftc.exe'
  $env:Path=(Split-Path -Parent $swift)+';C:\Users\adrds\AppData\Local\Programs\Swift\Platforms\6.4.0\Windows.platform\Developer\Library\XCTest-6.4.0\usr\bin64;C:\Users\adrds\AppData\Local\Programs\Swift\Platforms\6.4.0\Windows.platform\Developer\Library\Testing-6.4.0\usr\bin64;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
  $receipt.environment=[ordered]@{path=$env:Path;SDKROOT=$env:SDKROOT;INCLUDE=$env:INCLUDE;LIB=$env:LIB} 
  $receipt.toolchain=[ordered]@{swiftPath=$swift;swiftHash=(Hash $swift);swiftcPath=$swiftc;swiftcHash=(Hash $swiftc);swiftLastWriteUtc=(Get-Item $swift).LastWriteTimeUtc.ToString('o');swiftcLastWriteUtc=(Get-Item $swiftc).LastWriteTimeUtc.ToString('o');powershellVersion=$PSVersionTable.PSVersion.ToString()}
  foreach($v in @($plan.variants)){
    $name=[string]$v.name;$inputVariant=Join-Path $ownedInputRoot ('variants\'+$name);$variantRun=Join-Path $run $name;$runtime=Join-Path $variantRun 'runtime';$scratch=Join-Path $variantRun 'scratch';$logs=Join-Path $variantRun 'process'
    New-Item -ItemType Directory -Path $variantRun|Out-Null
    $before=BindingRows $inputVariant $v.bindings
    Copy-Item -LiteralPath $inputVariant -Destination $runtime -Recurse
    $copied=BindingRows $runtime $v.bindings
    $beforeContent=@($before|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}});$copiedContent=@($copied|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})
    if((ConvertTo-Json $beforeContent -Depth 10 -Compress) -ne (ConvertTo-Json $copiedContent -Depth 10 -Compress)){throw "Copied source bytes differ: $name"}
    $argv=@('test','--package-path',$runtime,'--scratch-path',$scratch,'-c','release','--filter',$plan.commonPins.filter)
    $runResult=RunOwned $name $swift $argv $runtime $logs 900
    $executables=@()
    if(Test-Path -LiteralPath $scratch){foreach($f in @(Get-ChildItem -LiteralPath $scratch -Recurse -File|Where-Object {$_.Extension -ieq '.exe'})){$executables+=[ordered]@{path=$f.FullName;bytes=[int64]$f.Length;sha256=(Hash $f.FullName);creationTimeUtc=$f.CreationTimeUtc.ToString('o');lastWriteTimeUtc=$f.LastWriteTimeUtc.ToString('o')}}}
    $runner=@($executables|Where-Object {$_.path -match 'SwiftRightRuntimeTests-test-runner\.exe$'})
    $after=BindingRows $runtime $v.bindings
    $beforeContent=@($before|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}});$afterContent=@($after|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})
    $sourceDrift=(ConvertTo-Json $beforeContent -Depth 10 -Compress) -cne (ConvertTo-Json $afterContent -Depth 10 -Compress)
    $stdout=$runResult.stdout
    $diag=if($stdout -match 'DIAG variant=terminal'){ 'terminal-commit-observed' }elseif($stdout -match 'DIAG variant=retained'){ 'retained-graph-observed' }elseif($name -eq 'original'){ 'original-assertions-only' }else{'no-diagnostic-marker'}
    $receipt.variants += [ordered]@{name=$name;declaredTreeSha256=$v.declaredTreeSha256;sourceBindings=$after;sourceBindingsSha256=$v.bindingsSha256;runtimePath=$runtime;scratchPath=$scratch;command=[ordered]@{executable=$swift;executableHash=(Hash $swift);argv=@($argv);cwd=$runtime};process=$runResult.record;executables=$executables;testRunner=$runner;diagnosticMarker=$diag;sourceDrift=$sourceDrift;originalFailureNotFixedClaim=($name -eq 'original')}
  }
}catch{$errorText=[string]$_;$receipt.error=$errorText}
finally{
  $receipt.finishedAt=[DateTime]::UtcNow.ToString('o')
  WriteJson (Join-Path $run 'receipt.json') $receipt
}
if($errorText){throw $errorText}
Write-Output (Get-Content -LiteralPath (Join-Path $run 'receipt.json') -Raw)
