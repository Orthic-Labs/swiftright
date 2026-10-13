# Tuple12 matrix runner v8. Root runs after parser review on Dell.
# Every coordinator is a suspended owned job child; outputs & receipts are retained.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$Driver,
  [Parameter(Mandatory)][string]$Worker,
  [Parameter(Mandatory)][string]$Coordinator,
  [Parameter(Mandatory)][string]$ExpectWorker,
  [Parameter(Mandatory)][string]$ExpectCoordinator,
  [Parameter(Mandatory)][string]$SmokeReceipt,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [Parameter(Mandatory)][string]$ExpectDriver,
  [Parameter(Mandatory)][string]$OutRoot,
  [ValidateSet('F1','F6Reduced','Full')][string]$Mode = 'F1',
  [ValidateSet(20)][int]$Runs = 20,
  [ValidateRange(30,1200)][int]$CoordinatorTimeoutSeconds = 1200,
  [ValidateRange(1048576,67108864)][int64]$CoordinatorStreamCapBytes = 8388608,
  [ValidateRange(134217728,4294967296)][int64]$CoordinatorRssCapBytes = 2147483648,
  [ValidateRange(60,10800)][int]$TotalMatrixTimeoutSeconds = 10800,
  [string]$Lock = 'D:\Claude\desktop.lock'
)
$ErrorActionPreference = 'Stop'
$expectedExe = $ExpectExe.ToLowerInvariant(); $expectedDll = $ExpectDll.ToLowerInvariant(); $expectedDriver = $ExpectDriver.ToLowerInvariant(); $expectedWorker = $ExpectWorker.ToLowerInvariant(); $expectedCoordinator = $ExpectCoordinator.ToLowerInvariant()
foreach ($name in @('ExpectExe','ExpectDll','ExpectDriver','ExpectWorker','ExpectCoordinator')) { if ((Get-Variable -Name $name -ValueOnly) -notmatch '^[0-9a-f]{64}$') { throw "$name is not SHA-256" } }
function Full-Leaf([string]$path) { $item=Get-Item -LiteralPath $path -ErrorAction Stop; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse input rejected: $path" }; $item.FullName }
function Hash-Lower([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Read-BoundedText([string]$path,[Int64]$maxBytes=8388608) { $item=Get-Item -LiteralPath $path -ErrorAction Stop; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt $maxBytes) { throw "bounded receipt read rejected: $path" }; [IO.File]::ReadAllText($path) }
function Write-Exclusive([string]$path,[string]$text) { if (Test-Path -LiteralPath $path) { throw "output exists: $path" }; $s=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read); try { $b=[Text.Encoding]::UTF8.GetBytes($text); $s.Write($b,0,$b.Length); $s.Flush($true) } finally { $s.Dispose() } }
function Lock-Free([string]$path) { try { $t=[IO.File]::ReadAllText($path).Trim(); if ($t -eq 'free') { return $true }; $o=$t|ConvertFrom-Json; foreach($k in @('state','status','value')) { if ($o.PSObject.Properties.Name -contains $k -and [string]$o.$k -eq 'free') { return $true } } } catch {}; $false }
function Wait-LockFree([string]$path,[int]$Seconds) { $watch=[Diagnostics.Stopwatch]::StartNew(); while($watch.Elapsed.TotalSeconds -lt $Seconds){ if(Lock-Free $path){return $true}; Start-Sleep -Seconds 1 }; $false }
function Assert-Receipt([string]$path) { $r=Read-BoundedText $path|ConvertFrom-Json; if ($r.status -ne 'passed' -or $r.workerExitCode -ne 0 -or $r.driverExitCode -ne 0 -or $r.childExitCode -ne 0) { throw "receipt not admitted: $path" }; if ($r.driverScript.sha256.ToLowerInvariant() -cne $expectedDriver -or $r.exe.sha256.ToLowerInvariant() -cne $expectedExe -or $r.renderer.sha256.ToLowerInvariant() -cne $expectedDll) { throw "receipt hash mismatch: $path" }; $r }

$helperPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\workload-incremental-v6\shared\Sr0OwnedJobProcess.cs'))
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw "shared helper missing: $helperPath" }
Add-Type -Path $helperPath
$baseFull=Full-Leaf $Base; $driverFull=Full-Leaf $Driver; $workerFull=Full-Leaf $Worker; $coordinatorFull=Full-Leaf $Coordinator; $smokeFull=Full-Leaf $SmokeReceipt
if ((Hash-Lower $driverFull) -cne $expectedDriver -or (Hash-Lower $workerFull) -cne $expectedWorker -or (Hash-Lower $coordinatorFull) -cne $expectedCoordinator) { throw 'candidate source hash mismatch' }
$smoke=Assert-Receipt $smokeFull
$bin=Join-Path $baseFull 'scratch\out\Products\Release-windows-x86_64'; $exe=Join-Path $bin 'FreshOnBridge.exe'; $dll=Join-Path $bin 'swiftright_render.dll'
if ((Hash-Lower $exe) -cne $expectedExe -or (Hash-Lower $dll) -cne $expectedDll) { throw 'candidate artifact hash mismatch' }
if (Test-Path -LiteralPath $OutRoot) { if (-not (Get-Item -LiteralPath $OutRoot).PSIsContainer -or @(Get-ChildItem -LiteralPath $OutRoot -Force).Count -ne 0) { throw 'OutRoot must be fresh directory' } } else { [IO.Directory]::CreateDirectory($OutRoot)|Out-Null }

$configs=@([pscustomobject]@{Fixture='F1';Variant=''})
if ($Mode -eq 'F6Reduced') { $configs=@([pscustomobject]@{Fixture='F6';Variant='reduced'}) }
if ($Mode -eq 'Full') { $configs=@(
  [pscustomobject]@{Fixture='F1';Variant=''},[pscustomobject]@{Fixture='F2';Variant=''},[pscustomobject]@{Fixture='F3';Variant='list-0s'},[pscustomobject]@{Fixture='F3';Variant='list-1s'},[pscustomobject]@{Fixture='F3';Variant='list-3s'},[pscustomobject]@{Fixture='F3';Variant='vstack-1s'},[pscustomobject]@{Fixture='F3';Variant='vstack-3s'},[pscustomobject]@{Fixture='F3';Variant='lazy-1s'},[pscustomobject]@{Fixture='F3';Variant='lazy-3s'},[pscustomobject]@{Fixture='F4';Variant=''},[pscustomobject]@{Fixture='F5';Variant=''},[pscustomobject]@{Fixture='F6';Variant=''},[pscustomobject]@{Fixture='F6';Variant='reduced'},[pscustomobject]@{Fixture='F7';Variant=''},[pscustomobject]@{Fixture='F8';Variant=''},[pscustomobject]@{Fixture='F9';Variant=''} ) }

function Invoke-OwnedCoordinator([string[]]$arguments,[string]$stdoutPath,[string]$stderrPath,[string]$workDir,[int]$DeadlineSeconds) {
  $job=[IntPtr]::Zero;$process=[IntPtr]::Zero;$thread=[IntPtr]::Zero;$stdoutRead=[IntPtr]::Zero;$stderrRead=[IntPtr]::Zero;$assigned=$false;$jobQuiescent=$false
  $outPipe=$null;$errPipe=$null;$outFile=$null;$errFile=$null;$outTask=$null;$errTask=$null;$terminal=$false;$timedOut=$false;$outputExceeded=$false;$rssExceeded=$false;$terminateAttempted=$false;$terminateSucceeded=$false
  [uint32]$kernelExit=259;[uint32]$active=1;$activeReadable=$false;[int64]$peakRss=0;[int64]$rssSamples=0;$wait=[uint32]258;$outDone=$false;$errDone=$false;$cleanupZero=$false;$result=$null
  try {
    $job=[Sr0OwnedJobProcess]::CreateJob(); if ($job -eq [IntPtr]::Zero) { throw 'coordinator job create failed' }
    if (-not [Sr0OwnedJobProcess]::ConfigureJob($job,1073741824)) { throw 'coordinator job memory cap failed' }
    $argText=($arguments|ForEach-Object { [Sr0OwnedJobProcess]::QuoteWindowsArgument([string]$_) }) -join ' '
    $powershell=Join-Path $PSHOME 'powershell.exe';$cmdline=[Sr0OwnedJobProcess]::BuildCommandLine($powershell,$argText)
    [uint32]$coordinatorPid=0
    if (-not [Sr0OwnedJobProcess]::CreateSuspended($powershell,$cmdline,$workDir,[ref]$process,[ref]$thread,[ref]$stdoutRead,[ref]$stderrRead,[ref]$coordinatorPid)) { throw 'coordinator suspended create failed' }
    $outPipe=New-Object IO.FileStream($stdoutRead,[IO.FileAccess]::Read,$false);$errPipe=New-Object IO.FileStream($stderrRead,[IO.FileAccess]::Read,$false)
    $outFile=[IO.File]::Open($stdoutPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$errFile=[IO.File]::Open($stderrPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $outTask=$outPipe.CopyToAsync($outFile);$errTask=$errPipe.CopyToAsync($errFile)
    if (-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,$process)) { throw 'coordinator job assignment failed' }; $assigned=$true
    if ([Sr0OwnedJobProcess]::ResumeThread($thread,$process) -eq [uint32]::MaxValue) { throw 'coordinator resume failed' }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while ($true) {
      $wait=[Sr0OwnedJobProcess]::WaitForSingleObject($process,1000)
      try { $p=[Diagnostics.Process]::GetProcessById([int]$coordinatorPid);$rss=[int64]$p.WorkingSet64;$rssSamples++;if($rss -gt $peakRss){$peakRss=$rss};$p.Dispose() } catch {}
      if ((Get-Item -LiteralPath $stdoutPath).Length -gt $CoordinatorStreamCapBytes -or (Get-Item -LiteralPath $stderrPath).Length -gt $CoordinatorStreamCapBytes) { $outputExceeded=$true;break }
      if ($peakRss -gt $CoordinatorRssCapBytes) { $rssExceeded=$true;break }
      if ($wait -eq [Sr0OwnedJobProcess]::WaitObject0) { $terminal=$true;break }
      if ($watch.Elapsed.TotalSeconds -ge $DeadlineSeconds) { $timedOut=$true;break }
    }
    if ($timedOut -or $outputExceeded -or $rssExceeded) { $terminateAttempted=$true;$terminateSucceeded=[Sr0OwnedJobProcess]::TerminateJobObject($job,124);$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($process,15000);$terminal=($wait -eq [Sr0OwnedJobProcess]::WaitObject0) }
    $outDone=$outTask.Wait(30000);$errDone=$errTask.Wait(30000)
    if (-not $outDone -or -not $errDone) { [Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null;$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($process,15000);$terminal=($wait -eq [Sr0OwnedJobProcess]::WaitObject0);$outDone=$outTask.Wait(5000);$errDone=$errTask.Wait(5000) }
    $activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active)
    if ($active -ne 0) { [Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null;$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($process,15000);$terminal=($wait -eq [Sr0OwnedJobProcess]::WaitObject0);for($q=0;$q -lt 60 -and $active -ne 0;$q++){ $activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active);if($activeReadable -and $active -eq 0){break};[Sr0OwnedJobProcess]::WaitForSingleObject($process,250)|Out-Null } }
    $cleanupZero=$terminal -and $outDone -and $errDone -and $activeReadable -and $active -eq 0
    $readExit=[Sr0OwnedJobProcess]::GetExitCodeProcess($process,[ref]$kernelExit)
    $reportedExit=$null;if($readExit){$reportedExit=[int64]$kernelExit}
    $result=[ordered]@{ started=$true;processId=$coordinatorPid;originalHandleRetained=($process -ne [IntPtr]::Zero);jobHandleRetained=($job -ne [IntPtr]::Zero);assigned=$assigned;terminal=$terminal;kernelExit=$reportedExit;streamsDrained=($outDone -and $errDone);activeReadable=$activeReadable;activeProcesses=$active;cleanupZero=$cleanupZero;timedOut=$timedOut;outputExceeded=$outputExceeded;rssExceeded=$rssExceeded;terminateAttempted=$terminateAttempted;terminateSucceeded=$terminateSucceeded;peakRssBytes=$peakRss;rssSamples=$rssSamples;deadlineSeconds=$DeadlineSeconds;streamCapBytes=$CoordinatorStreamCapBytes;rssCapBytes=$CoordinatorRssCapBytes}
  } finally {
    if (-not $cleanupZero -and $process -ne [IntPtr]::Zero) { if($assigned -and $job -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null}else{[Sr0OwnedJobProcess]::TerminateProcess($process,124)|Out-Null};$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($process,15000);$terminal=($wait -eq [Sr0OwnedJobProcess]::WaitObject0);if($outTask){$outDone=$outTask.Wait(5000)}else{$outDone=$false};if($errTask){$errDone=$errTask.Wait(5000)}else{$errDone=$false};if($job -ne [IntPtr]::Zero){for($q=0;$q -lt 60;$q++){$activeReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active);if($activeReadable -and $active -eq 0){break};[Sr0OwnedJobProcess]::WaitForSingleObject($process,250)|Out-Null};$cleanupZero=$terminal -and $outDone -and $errDone -and $activeReadable -and $active -eq 0} }
    if($outPipe){$outPipe.Dispose()};if($errPipe){$errPipe.Dispose()};if($outFile){$outFile.Dispose()};if($errFile){$errFile.Dispose()};if($thread -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($thread)|Out-Null};if($process -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($process)|Out-Null};if($stdoutRead -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($stdoutRead)|Out-Null};if($stderrRead -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($stderrRead)|Out-Null};if($job -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($job)|Out-Null}
    if($null -ne $result){$result.terminal=$terminal;$result.streamsDrained=($outDone -and $errDone);$result.activeReadable=$activeReadable;$result.activeProcesses=$active;$result.cleanupZero=$cleanupZero}
  }
  if($null -ne $result){return $result}
}

$matrixWatch=[Diagnostics.Stopwatch]::StartNew();$index=0;$failedCount=0;$abortRemaining=$false
foreach($cfg in $configs){$slug=if($cfg.Variant){"$($cfg.Fixture)-$($cfg.Variant)"}else{$cfg.Fixture};for($run=1;$run -le $Runs;$run++){$index++;$caseRoot=Join-Path $OutRoot ("{0}-r{1}-{2}" -f $slug,$run,[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($caseRoot)|Out-Null;$stdoutPath=Join-Path $caseRoot 'coordinator.stdout.bin';$stderrPath=Join-Path $caseRoot 'coordinator.stderr.bin';$terminalPath=Join-Path $caseRoot 'matrix-run.json';$coordInfo=$null;$receiptPath=$null;$failure=$null;$caseStatus='failed';$coordExit=$null
  try {
    if($matrixWatch.Elapsed.TotalSeconds -ge $TotalMatrixTimeoutSeconds){throw 'total matrix deadline reached; preserving remaining cases'}
    $lockWaitSeconds=[int][math]::Max(1,[math]::Floor($TotalMatrixTimeoutSeconds-$matrixWatch.Elapsed.TotalSeconds));if(-not (Wait-LockFree $Lock $lockWaitSeconds)){throw 'desktop lock did not become free before total matrix deadline'}
    $coordinatorArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$coordinatorFull,'-Base',$baseFull,'-Worker',$workerFull,'-Driver',$driverFull,'-ExpectDriver',$expectedDriver,'-ExpectWorker',$expectedWorker,'-ExpectExe',$expectedExe,'-ExpectDll',$expectedDll,'-OutRoot',$caseRoot,'-Fixture',$cfg.Fixture,'-KeyMode','char','-Lock',$Lock);if($cfg.Variant){$coordinatorArgs+=@('-Variant',$cfg.Variant)}
    $remaining=[math]::Floor($TotalMatrixTimeoutSeconds-$matrixWatch.Elapsed.TotalSeconds);$effectiveDeadline=[int][math]::Min($CoordinatorTimeoutSeconds,[math]::Max(1,$remaining));$coordInfo=Invoke-OwnedCoordinator $coordinatorArgs $stdoutPath $stderrPath $baseFull $effectiveDeadline;$coordExit=$coordInfo.kernelExit
    $receipts=@(Get-ChildItem -LiteralPath $caseRoot -Filter 'worker-*.json' -File -Recurse -ErrorAction SilentlyContinue);if($receipts.Count -ne 1){throw "expected one worker receipt, got $($receipts.Count)"};$receiptPath=$receipts[0].FullName;[void](Assert-Receipt $receiptPath)
    if(-not $coordInfo.cleanupZero -or $coordInfo.timedOut -or $coordInfo.outputExceeded -or $coordInfo.rssExceeded -or $coordExit -ne 0){throw 'coordinator owned cleanup or bounded execution proof failed'};$caseStatus='passed'
  } catch {$failure=$_.Exception.Message;$failedCount++;$abortRemaining=$true}
  $terminal=[ordered]@{kind='sr0-tuple12-matrix-run-v8';index=$index;mode=$Mode;fixture=$cfg.Fixture;variant=$cfg.Variant;run=$run;runs=$Runs;status=$caseStatus;failure=$failure;abortRemaining=$abortRemaining;base=$baseFull;driver=$driverFull;driverSha256=$expectedDriver;worker=$workerFull;workerSha256=$expectedWorker;coordinator=$coordinatorFull;coordinatorSha256=$expectedCoordinator;exeSha256=$expectedExe;rendererSha256=$expectedDll;workerReceipt=$receiptPath;coordinatorExit=$coordExit;coordinatorKernel=$coordInfo;smokeReceipt=$smokeFull;targetedDelivery=$true;noActivate=$true;jobMemoryBytes=1073741824;coordinatorDeadlineSeconds=$CoordinatorTimeoutSeconds;totalMatrixDeadlineSeconds=$TotalMatrixTimeoutSeconds;lockReleased=$false;lockReleaseProof='none-without-scheduled-native-cleanup-proof';output=$caseRoot;rawStdout=$stdoutPath;rawStderr=$stderrPath};Write-Exclusive $terminalPath (($terminal|ConvertTo-Json -Depth 12)+"`r`n");$linePrefix=if($caseStatus -eq 'passed'){'PASS'}else{'FAIL'};Write-Output ($linePrefix+" $slug run=$run/$Runs output=$caseRoot");if($abortRemaining){break}}
  if($abortRemaining){break}
}
if($failedCount -eq 0){Write-Output ("MATRIX_PASS mode={0} configs={1} runs={2} total={3} deadline={4}" -f $Mode,$configs.Count,$Runs,$index,$TotalMatrixTimeoutSeconds);exit 0}
Write-Output ("MATRIX_FAIL mode={0} configs={1} runs={2} total={3} failures={4}; receipts preserved" -f $Mode,$configs.Count,$Runs,$index,$failedCount);exit 1
