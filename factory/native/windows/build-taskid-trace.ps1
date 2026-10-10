# Fresh factory-only diagnostic sources; build tests without executing test runner.
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop';$rootPath=[IO.Path]::GetFullPath($Root)
if($rootPath -cne 'D:\Claude\factory-swiftright-taskid-trace-20261011'){throw 'Exact owned diagnostic root required'}
$sourcePlan=Get-Content -Raw (Join-Path $rootPath 'source-plan.json')|ConvertFrom-Json
if($sourcePlan.proposalHash -cne 'sha256:25d12312a1b42d7a29b328b98a13aceff3b5b06e19cc7c4acf3dbe44d8c57030' -or @($sourcePlan.variants).Count -ne 3){throw 'Exact diagnostic proposal required'}
$swift=(Get-Command swift).Source;$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$rows=@();$errorText=''
function Check-Source($Variant,$Receipt,$Runtime) {
 $receiptPath=Join-Path (Split-Path $Runtime) 'runtime-source-receipt.json'
 if(('sha256:'+(Get-FileHash $receiptPath).Hash.ToLowerInvariant()) -cne $Variant.diagnosticSourceReceiptHash -or -not $Receipt.diagnosticOnly -or $Receipt.kind -cne 'factory-diagnostic-runtime-source' -or $Receipt.diagnosticTaskSourceHash -cne 'sha256:bc720665b481a84ed717a6a8a20af721d8bfee7e29bcf984881e6dd4b6bed7c7' -or $Receipt.originalTaskSourceHash -cne 'sha256:6f6e2d750e32e9169d34599620666b4846c174e5aea12e2db343f636e729d1dc'){throw 'Diagnostic receipt pin differs'}
 foreach($b in $Receipt.completeSnapshotBindings){$path=[IO.Path]::GetFullPath((Join-Path $Runtime $b.path));if(-not $path.StartsWith($Runtime+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $path).Hash.ToLowerInvariant() -cne $b.sha256.Replace('sha256:','')){throw 'Diagnostic source drift'}}
 if(@(Get-ChildItem $Runtime -Recurse -File).Count -ne @($Receipt.completeSnapshotBindings).Count){throw 'Diagnostic source coverage differs'}
 if(('sha256:'+(Get-FileHash (Join-Path (Split-Path $Runtime) 'diagnostic-source.tar')).Hash.ToLowerInvariant()) -cne $Receipt.snapshotArchiveHash){throw 'Diagnostic source archive drift'}
}
try {
 foreach($variant in $sourcePlan.variants){
  if($variant.label -cnotin @('baseline','postshape','fontstorage')){throw 'Unexpected diagnostic variant'}
  $base=Join-Path $rootPath $variant.label;$runtime=Join-Path $base 'runtime';$run=Join-Path $base 'build'
  if(Test-Path $run){throw 'Fresh diagnostic build required'}
  $receipt=Get-Content -Raw (Join-Path $base 'runtime-source-receipt.json')|ConvertFrom-Json
  Check-Source $variant $receipt $runtime;New-Item -ItemType Directory $run|Out-Null
  $info=[Diagnostics.ProcessStartInfo]::new($swift);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $info.Arguments='build --build-tests --package-path "'+$runtime+'" --scratch-path "'+(Join-Path $run 'scratch')+'" -c release'
  $p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o');$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$deadline=[DateTimeOffset]::UtcNow.AddMinutes(10);$timeout=$false
  [ordered]@{pid=$p.Id;path=$swift;startedAt=$started}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $run 'owned-process.json')
  try {while(-not $p.WaitForExit(100)){if([DateTimeOffset]::UtcNow -ge $deadline){$timeout=$true;throw 'Owned diagnostic build deadline'}}}
  finally {if(-not $p.HasExited){$owned=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($owned -and $owned.Path -eq $swift -and $owned.StartTime.ToUniversalTime().ToString('o') -eq $started){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null};if($out.Wait(5000)){[IO.File]::WriteAllText((Join-Path $run 'stdout.txt'),$out.GetAwaiter().GetResult())};if($err.Wait(5000)){[IO.File]::WriteAllText((Join-Path $run 'stderr.txt'),$err.GetAwaiter().GetResult())}}
  Check-Source $variant $receipt $runtime
  $products=Join-Path $run 'scratch\out\Products\Release-windows-x86_64';$bindings=@();foreach($name in @('SwiftRightRuntimeTests-test-runner.exe','SwiftRightRuntimeTests.dll')){if(Test-Path (Join-Path $products $name)){$bindings+=[ordered]@{path=(Join-Path $products $name);sha256=(Get-FileHash (Join-Path $products $name)).Hash.ToLowerInvariant()}}}
  $row=[ordered]@{label=$variant.label;sourceCommit=$receipt.sourceCommit;sourceTreeHash=$receipt.sourceTreeHash;diagnosticCompleteSnapshotHash=$receipt.completeSnapshotHash;diagnosticSourceReceiptHash=$variant.diagnosticSourceReceiptHash;exitCode=$p.ExitCode;timedOut=$timeout;binaryBindings=$bindings;swiftPath=$swift;swiftHash=(Get-FileHash $swift).Hash.ToLowerInvariant();arguments=$info.Arguments;stdoutHash=(Get-FileHash (Join-Path $run 'stdout.txt')).Hash.ToLowerInvariant();stderrHash=(Get-FileHash (Join-Path $run 'stderr.txt')).Hash.ToLowerInvariant();diagnosticOnly=$true;testRunnerExecuted=$false;nativeWindowOpened=$false;finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}
  $row|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $run 'build-receipt.json');$rows+=$row
  if($p.ExitCode -ne 0 -or $bindings.Count -ne 2){throw 'Diagnostic build unsuccessful'}
 }
}catch{$errorText=[string]$_}
finally{[ordered]@{kind='windows-taskid-diagnostic-builds';sourcePlanHash=(Get-FileHash (Join-Path $rootPath 'source-plan.json')).Hash.ToLowerInvariant();rows=$rows;error=$errorText;diagnosticOnly=$true;selectedTestProcesses=0;nativeWindowOpened=$false;finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $rootPath 'build-receipt.json')}
