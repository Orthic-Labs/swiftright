# Source-only prepared cached Padding compiler entry. Root owns execution.
# Reuses donor package/scratch; never mutates donor plan, package, or cache.
param(
 [Parameter(Mandatory=$true)][string]$FreshPlanPath,
 [Parameter(Mandatory=$true)][string]$FreshPlanSha256,
 [Parameter(Mandatory=$true)][string]$FreshInputRoot,
 [Parameter(Mandatory=$true)][string]$OperationalPackage,
 [Parameter(Mandatory=$true)][string]$OperationalScratch,
 [Parameter(Mandatory=$true)][string]$OperationalPlanPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$OperationalPlanSha256,
 [Parameter(Mandatory=$true)][string]$OperationalReceiptPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$OperationalReceiptSha256,
 [Parameter(Mandatory=$true)][string]$CompilerPath,
 [Parameter(Mandatory=$true)][string]$RendererPath,
 [Parameter(Mandatory=$true)][string]$JobHelperPath,
 [Parameter(Mandatory=$true)][string]$BridgeRoot,
 [Parameter(Mandatory=$true)][string]$OutputRoot,
 [Parameter(Mandatory=$true)][string]$OperationalExpectedOutputPath,
 [ValidateSet('preflight','final')][string]$Phase='preflight',
 [switch]$PreflightOnly,
 [ValidateRange(1,10)][int]$Attempt=1
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$MaxFile=67108864L;$MaxTotal=268435456L;$OutCap=8388608L;$MemoryCap=1073741824L;$JobFlags=512
function Full([string]$p){return [IO.Path]::GetFullPath($p)}
function Hex([string]$v){$h=([string]$v).Replace('sha256:','').ToLowerInvariant();if($h -notmatch '^[0-9a-f]{64}$'){throw "invalid sha256 value: $h"};return $h}
function Hash([string]$p){
 $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
 if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $i.Length -gt $MaxFile){throw "bounded regular file required: $p"}
 $size=[long]$i.Length;$n=[long]0;$h=[Security.Cryptography.SHA256]::Create();$s=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{$b=New-Object byte[] 1048576;while(($r=$s.Read($b,0,$b.Length)) -gt 0){$n+=$r;if($n -gt $MaxFile){throw 'hash size bound exceeded'};[void]$h.TransformBlock($b,0,$r,$b,0)};[void]$h.TransformFinalBlock($b,0,0);$x=([BitConverter]::ToString($h.Hash)).Replace('-','').ToLowerInvariant()}finally{$s.Dispose();$h.Dispose()}
 $j=Get-Item -LiteralPath $p -Force;if($n -ne $size -or $j.Length -ne $size){throw "file changed while hashing: $p"};return $x
}
function Json([string]$p){$i=Get-Item -LiteralPath $p -Force;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $i.Length -gt 4194304){throw "bounded JSON required: $p"};Get-Content -LiteralPath $p -Raw|ConvertFrom-Json}
function SafePath([string]$root,[string]$rel){
 if([string]::IsNullOrWhiteSpace($rel) -or $rel.StartsWith('/') -or $rel.StartsWith('\') -or $rel.Contains(':') -or $rel.Contains('\') -or $rel.Split('/') -contains '..'){throw "unsafe binding path: $rel"}
 $r=Full $root;$p=Full (Join-Path $r ($rel -replace '/','\'));if(-not $p.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)){throw "binding escapes root: $rel"}
 $parts=$rel.Split('/');$cur=$r;foreach($part in $parts){$cur=Join-Path $cur $part;$q=Get-Item -LiteralPath $cur -Force -ErrorAction Stop;if(($q.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "reparse component: $rel"}}
 return $p
}
function VerifyRows([string]$root,$rows,[string]$label){$seen=@{};$total=[long]0;foreach($row in @($rows)){if($null -eq $row.path -or $null -eq $row.sha256){throw "$label row incomplete"};$p=SafePath $root ([string]$row.path);$k=([string]$row.path).ToLowerInvariant();if($seen.ContainsKey($k)){throw "$label duplicate row"};$seen[$k]=$true;$i=Get-Item -LiteralPath $p -Force;$total+=$i.Length;if($seen.Count -gt 256 -or $total -gt $MaxTotal){throw "$label bounds exceeded"};if((Hash $p) -cne (Hex $row.sha256)){throw "$label hash drift: $($row.path)"};if($row.PSObject.Properties.Name -contains 'bytes' -and $null -ne $row.bytes -and [int64]$row.bytes -ne [int64]$i.Length){throw "$label byte drift: $($row.path)"}};return [pscustomobject]@{count=$seen.Count;bytes=$total}}
function VerifyRef([string]$root,$ref,[string]$label){$p=SafePath $root ([string]$ref.path);$i=Get-Item -LiteralPath $p -Force;if([int64]$ref.bytes -ne $i.Length){throw "$label byte mismatch"};if((Hash $p) -cne (Hex $ref.sha256)){throw "$label hash mismatch"};return $p}
$fresh=Full $FreshPlanPath;$input=Full $FreshInputRoot;$opkg=Full $OperationalPackage;$oscratch=Full $OperationalScratch;$oplanPath=Full $OperationalPlanPath;$oreceiptPath=Full $OperationalReceiptPath;$compiler=Full $CompilerPath;$renderer=Full $RendererPath;$helper=Full $JobHelperPath;$bridge=Full $BridgeRoot;$out=Full $OutputRoot;$expectedExePath=Full $OperationalExpectedOutputPath
foreach($required in @($fresh,$input,$opkg,$oscratch,$oplanPath,$oreceiptPath,$compiler,$renderer,$helper,$bridge)){if(-not (Test-Path -LiteralPath $required)){throw "required path missing: $required"}}
if((Hash $fresh) -cne (Hex $FreshPlanSha256)){throw 'fresh plan hash mismatch'}
if((Hash $oplanPath) -cne (Hex $OperationalPlanSha256)){throw 'donor plan hash mismatch'}
if((Hash $oreceiptPath) -cne (Hex $OperationalReceiptSha256)){throw 'donor receipt hash mismatch'}
$plan=Json $fresh;$oplan=Json $oplanPath;$receipt=Json $oreceiptPath
if($plan.kind -cne 'windows-padding-fresh-compile-plan-v1'){throw 'fresh plan kind mismatch'}
if($plan.executionEligible -ne $false -or $plan.compileCommand.nativeActions -ne 0){throw 'fresh plan must remain compile-only'}
if($plan.runtimeSourceCommit -cne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'){throw 'runtime commit drift'}
if((Hex $plan.compilerHash) -cne (Hex $oplan.compilerHash) -or (Hex $plan.rendererSha256) -cne (Hex $oplan.rendererSha256)){throw 'fresh/donor tool hash drift'}
if((Hex $plan.compilerHash) -cne (Hash $compiler) -or (Hex $plan.rendererSha256) -cne (Hash $renderer)){throw 'compiler or renderer bytes drift'}
if($receipt.kind -cne 'factory-padding-capture-lease-compile-only-owned-handle-v1' -or $receipt.exitCode -ne 0 -or $receipt.timedOut -ne $false -or $receipt.ownedExited -ne $true -or $receipt.streamDrainComplete -ne $true -or $receipt.kernelWait -ne 0 -or (($receipt.PSObject.Properties.Name -contains 'nativeWindowOpened') -and $receipt.nativeWindowOpened -ne $false)){throw 'donor receipt is not successful compile-only evidence'}
if(@($receipt.rawStreams).Count -ne 2 -or @($receipt.rawStreams|Where-Object{$_.copyCompleted -ne $true -or $_.destinationClosed -ne $true -or $_.sealed -ne $true -or $_.hashQualification -cne 'sealed-raw'}).Count -ne 0){throw 'donor stream terminal proof incomplete'}
if((Hex $receipt.compilerHash) -cne (Hex $plan.compilerHash) -or (Hex $receipt.rendererSha256) -cne (Hex $plan.rendererSha256) -or (Hex $receipt.runtimeSourceTreeHash) -cne (Hex $plan.runtimeSourceTreeHash)){throw 'donor receipt lineage mismatch'};if((Hex $oplan.runtimeSourceTreeFileHash) -ne (Hex $receipt.runtimeSourceTreeHash)){throw 'donor runtime tree file lineage mismatch'}
if((Hash $oplanPath) -cne (Hex $receipt.planSha256)){throw 'donor plan/receipt hash mismatch'}
$donorSource=VerifyRows $opkg $oplan.sourceBindings 'donor-source';$source=VerifyRows $input $plan.sourceBindings 'fresh-source';$bridgeRows=VerifyRows $bridge $plan.bridgeBindings 'bridge';$runtimePackagePath=[string]$plan.runtimePackagePath;if([string]::IsNullOrWhiteSpace($runtimePackagePath)){throw 'fresh runtimePackagePath missing'};$runtimeRoot=Full $runtimePackagePath;$runtimeTreePath=[string]$plan.runtimeSourceTreePath;if([string]::IsNullOrWhiteSpace($runtimeTreePath)){throw 'fresh runtimeSourceTreePath missing; implicit tree paths are refused'};$runtimeTreePath=Full $runtimeTreePath;if(-not(Test-Path -LiteralPath $runtimeTreePath -PathType Leaf)){throw 'fresh runtime-source-tree.json missing'};$runtimeTreeHash=Hash $runtimeTreePath;if((Hex $runtimeTreeHash) -cne (Hex $plan.runtimeSourceTreeFileHash) -or (Hex $runtimeTreeHash) -cne (Hex $plan.runtimeSourceTreeHash)){throw 'runtime source tree file hash drift'};$runtimeRows=Json $runtimeTreePath;$runtimeVerified=VerifyRows $runtimeRoot $runtimeRows 'runtime-source-tree';if($runtimeVerified.count -lt 1){throw 'runtime source tree rows missing'}
if($donorSource.count -ne 13 -or $source.count -ne 13){throw 'exact 13 source rows required'}
$dr=@($oplan.sourceBindings);$fr=@($plan.sourceBindings);for($i=0;$i -lt 13;$i++){if(([string]$dr[$i].path) -cne ([string]$fr[$i].path) -or (Hex $dr[$i].sha256) -cne (Hex $fr[$i].sha256)){throw "fresh source row drift: $i"}}
$freshCasePath=VerifyRef $input $plan.freshInputRefs.case 'fresh-case';$freshManifestPath=VerifyRef $input $plan.freshInputRefs.manifest 'fresh-manifest';$freshTuplePath=VerifyRef $input $plan.freshInputRefs.tuple 'fresh-tuple'
$freshCase=Json $freshCasePath;$freshManifest=Json $freshManifestPath;$freshTuple=Json $freshTuplePath;$tupleDoc=if($freshTuple.tuple){$freshTuple.tuple}else{$freshTuple}
if($freshCase.kind -cne 'case' -or $freshCase.id -cne $plan.case.id -or $freshCase.tuple.id -ne $tupleDoc.id -or (Hex $freshCase.tuple.hostHashes.windows) -ne (Hex $plan.expectedHostHashes.windows)){throw 'fresh case identity drift'}
if($freshManifest.case.id -ne $freshCase.id -or (Hex $freshManifest.case.hash) -ne (Hex $plan.case.hash) -or (Hex $freshManifest.sourceHash) -ne (Hex $plan.sourceHash) -or $freshManifest.executionEligible -ne $true){throw 'fresh manifest lineage drift'}
if($tupleDoc.id -ne 'sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011' -or (Hex $tupleDoc.hostHashes.macos) -ne '13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777' -or (Hex $tupleDoc.hostHashes.windows) -ne '3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a' -or (Hex $tupleDoc.rendererHash) -ne (Hex $plan.rendererSha256) -or $tupleDoc.runtimeCommit -ne $plan.runtimeSourceCommit){throw 'fresh tuple host/runtime lineage drift'}
if($plan.compileRequest.maxParallelJobs -ne 1){throw 'fresh plan maxParallelJobs must be 1'};if($plan.compileRequest.PSObject.Properties.Name -contains 'maxFrontendThreadsObserved' -and $null -ne $plan.compileRequest.maxFrontendThreadsObserved){throw 'frontend thread observation must remain null'}
if($plan.memoryBudget.bytes -ne $MemoryCap -or $plan.memoryBudget.jobLimitFlags -ne $JobFlags -or $plan.memoryBudget.killOnJobClose -ne $false){throw 'memory policy drift'}
if((Hash $helper) -cne (Hex $plan.memoryBudget.helperSha256)){throw 'job helper hash drift'}
if($plan.compileRequest.packagePath -cne 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\package' -or $plan.compileRequest.scratchPath -cne 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\scratch-r1'){throw 'fresh plan paths drift'}
$expectedOut=[string]$plan.expectedOutput
$argv=[string]$receipt.argv
$cacheExe=Full (Join-Path $oscratch 'out\Products\Release-windows-x86_64\FactoryProbe.exe');if($expectedExePath -cne $cacheExe){throw 'expected output is not operational cache executable'}
if(-not $argv.Contains($opkg) -or -not $argv.Contains($oscratch)){throw 'donor operational argv/cache not bound'}
if($argv -notlike '*-c release*' -or $argv -notlike '*MANIFEST:EMBED*' -or $argv -notlike '*SUBSYSTEM:WINDOWS*' -or $argv -notlike '*ENTRY:mainCRTStartup*'){throw 'donor GUI argv drift'}
if($argv -match '(^|\s)(-j|--jobs)(\s|$)' -or $argv -match '(^|\s)-Xswiftc\s+-num-threads(\s|$)'){throw 'donor argv unexpectedly claims frontend/job override'};$cachedArgv=($argv+' --jobs 1').Trim();if($cachedArgv -notmatch '(^|\s)--jobs\s+1(\s|$)' -or $cachedArgv -match '(^|\s)-Xswiftc\s+-num-threads(\s|$)'){throw 'fresh cached argv concurrency policy mismatch'}
if($receipt.argv -cne $argv){throw 'donor argv receipt drift'}
if($out.StartsWith($opkg+'\',[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($oscratch+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'fresh output may not be donor package/cache'}
if(Test-Path -LiteralPath $out){throw 'fresh output already exists'}
if($PreflightOnly){[ordered]@{status='preflight-passed';kind='factory-padding-incremental-root-v4';phase=$Phase;freshPlanSha256=$FreshPlanSha256;donorPlanSha256=(Hex $receipt.planSha256);donorReceiptSha256=(Hex $OperationalReceiptSha256);operationalPackage=$opkg;operationalScratch=$oscratch;sourceRows=$source.count;sourceBytes=$source.bytes;bridgeRows=$bridgeRows.count;runtimeRows=$runtimeVerified.count;runtimeBytes=$runtimeVerified.bytes;memoryCapBytes=$MemoryCap;jobFlags=$JobFlags;maxParallelJobs=1;maxFrontendThreadsObserved=$null;nativeActions=0;cachedArgv=$cachedArgv}|ConvertTo-Json -Depth 8;return}
Add-Type -Path $helper
New-Item -ItemType Directory -Path $out -Force:$false|Out-Null
$stdout=Join-Path $out 'compile.stdout.bin';$stderr=Join-Path $out 'compile.stderr.bin';$obs=Join-Path $out 'observation.json';$record=[ordered]@{kind='factory-padding-incremental-owned-compile-v4';phase=$Phase;attempt=$Attempt;freshPlanPath=$fresh;freshPlanSha256=(Hex $FreshPlanSha256);donorPlanPath=$oplanPath;donorPlanSha256=(Hex $OperationalPlanSha256);donorReceiptPath=$oreceiptPath;donorReceiptSha256=(Hex $OperationalReceiptSha256);operationalPackage=$opkg;operationalScratch=$oscratch;argv=$cachedArgv;donorArgv=$argv;compilerHash=(Hex $plan.compilerHash);rendererSha256=(Hex $plan.rendererSha256);sourceHash=$plan.sourceHash;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;nativeActions=0;memoryCapBytes=$MemoryCap;jobFlags=$JobFlags;maxParallelJobs=1;maxFrontendThreadsObserved=$null;startedAt=$null;finishedAt=$null;pid=$null;exitCode=$null;timedOut=$false;outputCapExceeded=$false;ownedExited=$false;streamDrainComplete=$false;streamsSealed=$false;jobActiveReadable=$false;jobActiveCount=$null;cleanupPollMilliseconds=0;kernelWait=$null;kernelExitCodeRaw=$null;kernelExitCodeSigned=$null;stdoutSha256=$null;stderrSha256=$null;exePath=$null;exeSha256=$null;exeBytes=$null;error=$null;cleanupError=$null}
function Save{ $record|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $obs -Encoding UTF8 }
[uint32]$pidOwned=0;$job=[IntPtr]::Zero;$handle=[IntPtr]::Zero;$thread=[IntPtr]::Zero;$or=[IntPtr]::Zero;$er=[IntPtr]::Zero;$op=$null;$ep=$null;$of=$null;$ef=$null;$ot=$null;$et=$null;$failed=$null;$priorPath=$env:Path
try{
 $record.startedAt=[DateTimeOffset]::UtcNow.ToString('o');Save
 $env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$priorPath
 $job=[Sr0OwnedJobProcess]::CreateJob();if($job -eq [IntPtr]::Zero -or -not [Sr0OwnedJobProcess]::ConfigureJobWithFlags($job,$JobFlags,$MemoryCap)){throw 'job cap configuration failed'}
 if(-not [Sr0OwnedJobProcess]::CreateSuspended($compiler,[Sr0OwnedJobProcess]::BuildCommandLine($compiler,$cachedArgv),$opkg,[ref]$handle,[ref]$thread,[ref]$or,[ref]$er,[ref]$pidOwned)){throw 'suspended compiler start failed'}
 $record.pid=$pidOwned;$record.originalHandleRetained=($handle -ne [IntPtr]::Zero)
 $op=[IO.FileStream]::new($or,[IO.FileAccess]::Read,$false);$ep=[IO.FileStream]::new($er,[IO.FileAccess]::Read,$false);$of=[IO.File]::Open($stdout,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$ef=[IO.File]::Open($stderr,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$ot=$op.CopyToAsync($of);$et=$ep.CopyToAsync($ef)
 if(-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,$handle)){throw 'assignment before resume failed'};if([Sr0OwnedJobProcess]::ResumeThread($thread,$handle) -eq [uint32]::MaxValue){throw 'resume failed'};Save
 $sw=[Diagnostics.Stopwatch]::StartNew();do{$record.kernelWait=[Sr0OwnedJobProcess]::WaitForSingleObject($handle,250);$record.outputCapExceeded=((Get-Item $stdout).Length -gt $OutCap -or (Get-Item $stderr).Length -gt $OutCap);$record.timedOut=$sw.Elapsed.TotalSeconds -ge 600;if($record.outputCapExceeded -or $record.timedOut){throw 'compile output/time cap exceeded'}}while($record.kernelWait -eq 258)
 [uint32]$code=259;if($record.kernelWait -ne 0 -or -not [Sr0OwnedJobProcess]::GetExitCodeProcess($handle,[ref]$code)){throw 'retained exit certificate unavailable'};$record.exitCode=[int64]$code;$record.ownedExited=$true
 if(-not $ot.Wait(15000) -or -not $et.Wait(15000)){throw 'stream drain timeout'};$ot.GetAwaiter().GetResult();$et.GetAwaiter().GetResult();$record.streamDrainComplete=$true;$of.Flush();$ef.Flush();$of.Dispose();$ef.Dispose();$of=$null;$ef=$null;$record.streamsSealed=$true;$record.stdoutSha256=Hash $stdout;$record.stderrSha256=Hash $stderr
 if($code -ne 0){throw "compiler exit $code"}
 $exe=$expectedExePath;$record.exePath=$exe;$record.exeSha256=Hash $exe;$record.exeBytes=(Get-Item -LiteralPath $exe).Length;if($record.exeSha256 -cne (Hex $plan.expectedHostHashes.windows) -or $record.exeSha256 -cne (Hex $tupleDoc.hostHashes.windows)){throw 'fresh Windows host hash drift'}
}catch{$failed=[string]$_.Exception.Message;$record.error=$failed}
finally{
 if($failed -and $job -ne [IntPtr]::Zero){[void][Sr0OwnedJobProcess]::TerminateJobObject($job,124);if($handle -ne [IntPtr]::Zero){[void][Sr0OwnedJobProcess]::WaitForSingleObject($handle,5000)}};if($ot){[void]$ot.Wait(5000)};if($et){[void]$et.Wait(5000)};foreach($s in @($of,$ef,$op,$ep)){if($s){$s.Dispose()}};if($handle -ne [IntPtr]::Zero){$record.kernelWait=[Sr0OwnedJobProcess]::WaitForSingleObject($handle,0);[uint32]$finalCode=259;if([Sr0OwnedJobProcess]::GetExitCodeProcess($handle,[ref]$finalCode)){$record.kernelExitCodeRaw=[uint64]$finalCode;$record.kernelExitCodeSigned=[int32]$finalCode}};if($job -ne [IntPtr]::Zero){$cleanupWatch=[Diagnostics.Stopwatch]::StartNew();$active=1;$known=$false;do{$known=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active);if($known -and $active -eq 0){break};if($cleanupWatch.ElapsedMilliseconds -lt 15000){Start-Sleep -Milliseconds 250}}while($cleanupWatch.ElapsedMilliseconds -lt 15000);$record.cleanupPollMilliseconds=$cleanupWatch.ElapsedMilliseconds;$record.jobActiveReadable=$known;$record.jobActiveCount=$active;if(-not $known -or $active -ne 0){$record.cleanupError='job quiescence not certified'}};foreach($h in @($or,$er,$thread,$handle,$job)){if($h -ne [IntPtr]::Zero){[void][Sr0OwnedJobProcess]::CloseHandle($h)}};$env:Path=$priorPath;$record.finishedAt=[DateTimeOffset]::UtcNow.ToString('o');Save}
if($record.error -or $record.cleanupError){throw (($record.error+' '+$record.cleanupError).Trim())};[ordered]@{status='compiled';kind=$record.kind;phase=$Phase;freshPlanSha256=$record.freshPlanSha256;exeSha256=$record.exeSha256;exeBytes=$record.exeBytes;nativeActions=0;memoryCapBytes=$MemoryCap;jobActiveCount=$record.jobActiveCount;streamsSealed=$record.streamsSealed}|ConvertTo-Json -Depth 8
