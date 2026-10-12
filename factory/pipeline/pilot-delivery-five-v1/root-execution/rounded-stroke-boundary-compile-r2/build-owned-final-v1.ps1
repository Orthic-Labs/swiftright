# Root-owned compiler only. No native window, desktop lock, or Rust invocation.
param([Parameter(Mandatory=$true)][string]$PlanPath,[Parameter(Mandatory=$true)][string]$PlanSha256,[ValidateSet('prebuild','final')][string]$Phase='prebuild',[switch]$PreflightOnly,[ValidateRange(1,10)][int]$Attempt=1)
$ErrorActionPreference='Stop'
$stage='D:\Claude\swiftright\.factory-work\hosts\rounded-stroke-boundary'
function Hash([string]$p) { $f=Get-Item -LiteralPath $p -Force;if($f.PSIsContainer -or $f.Length -gt 67108864 -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded regular file required'};(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Load([string]$p) { if((Get-Item -LiteralPath $p).Length -gt 4194304){throw 'JSON limit'};Get-Content -LiteralPath $p -Raw|ConvertFrom-Json }
if([IO.Path]::GetFullPath($PlanPath) -cne (Join-Path $stage ('package\plan-'+$Phase+'-v4.json'))){throw 'exact owned plan path required'}
if((Hash $PlanPath) -cne $PlanSha256){throw 'plan hash mismatch'}
$plan=Load $PlanPath;$package=Join-Path $stage 'package';$scratch=Join-Path $package 'build-bound-r1\scratch';$out=Join-Path $stage ($Phase+'-r'+$Attempt)
if($plan.kind -cne 'factory-pilot-five-compiler-plan-v1' -or $plan.phase -cne $Phase -or $plan.candidate -cne 'swiftui.shapes.fill-stroke.abi-rect-border.v1'){throw 'plan identity mismatch'}
if($plan.compileRequest.packagePath -cne $package -or $plan.compileRequest.scratchPath -cne $scratch -or $plan.compileRequest.kind -cne 'swiftpm-windows-gui-release/1' -or $plan.compileRequest.configuration -cne 'release' -or $plan.compileRequest.target -cne 'windows-x86_64'){throw 'compile request mismatch'}
if($plan.runtimeSourceCommit -cne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b' -or $plan.rendererSha256 -cne 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93' -or $plan.compilerHash -cne '1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'){throw 'tuple source pin mismatch'}
function Verify-Rows([string]$root,$rows,[bool]$membership) {
 $root=[IO.Path]::GetFullPath($root);$seen=@{};$total=0
 foreach($r in @($rows)){if($r.path -match '(^/|\\|:|(^|/)\.\.(/|$))' -or $seen.ContainsKey([string]$r.path)){throw 'unsafe duplicate binding'};$p=[IO.Path]::GetFullPath((Join-Path $root $r.path));if(-not $p.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'binding escape'};$seen[[string]$r.path]=$p;$n=(Get-Item -LiteralPath $p).Length;$total+=$n;if($seen.Count -gt 256 -or $total -gt 268435456 -or (Hash $p) -cne ([string]$r.sha256).Replace('sha256:','')){throw 'source bytes mismatch'}}
 if($membership){$actual=@((Join-Path $root 'Package.swift'))+@(Get-ChildItem -LiteralPath (Join-Path $root 'Sources') -Recurse -File|ForEach-Object{$_.FullName});$expected=@($seen.Values|Where-Object{$_ -eq (Join-Path $root 'Package.swift') -or $_.StartsWith((Join-Path $root 'Sources')+'\')});if($actual.Count -ne $expected.Count -or @($actual|Where-Object{$expected -cnotcontains $_}).Count){throw 'source membership mismatch'}}
}
function Assert-Inputs {
 if((Hash $PlanPath) -cne $PlanSha256 -or (Hash $plan.compilerPath) -cne $plan.compilerHash -or (Hash $plan.rendererPath) -cne $plan.rendererSha256){throw 'operational hash drift'}
 if($plan.runtimePackagePath -cne 'D:\Claude\swiftright\.factory-work\runtime-stage\runtime' -or $plan.bridgePackagePath -cne 'D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge'){throw 'dependency root mismatch'}
 Verify-Rows $package $plan.sourceBindings $true
 if((Hash (Join-Path $package 'runtime-source-receipt.json')) -cne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'runtime receipt drift'}
 if((Hash (Join-Path $package 'runtime-source-tree.json')) -cne $plan.runtimeSourceTreeHash.Replace('sha256:','')){throw 'runtime tree drift'}
 Verify-Rows $plan.runtimePackagePath (Load (Join-Path $package 'runtime-source-tree.json')) $true
 Verify-Rows $plan.bridgePackagePath $plan.bridgeBindings $true
 if((Hash (Join-Path $package 'Sources\FactoryProbe\Witness.swift')) -cne $plan.sourceHash.Replace('sha256:','')){throw 'witness drift'}
 if((Hash (Join-Path $PSScriptRoot 'Sr0OwnedJobProcess.cs')) -cne $plan.helperSha256){throw 'owned helper drift'}
 if($Phase -ceq 'final'){if($plan.case.id -cne 'swiftui.shapes.fill-stroke.recipe/case/3583aa7a825127bc' -or $plan.case.hash -notmatch '^sha256:[0-9a-f]{64}$' -or $plan.expectedHostHash -notmatch '^sha256:[0-9a-f]{64}$'){throw 'fresh final case/host binding required'}}elseif($null -ne $plan.case){throw 'prebuild must not claim measured case'}
}
if($plan.compileRequest.maxParallelJobs -ne 1){throw 'bounded single compile job required'}
Assert-Inputs
if(Test-Path -LiteralPath $out){throw 'fresh phase receipt directory required'}
if($PreflightOnly){[ordered]@{kind='factory-pilot-five-preflight-v1';phase=$Phase;status='passed';planSha256=$PlanSha256;compilerStarted=$false;nativeActions=0;memoryCapBytes=1073741824}|ConvertTo-Json;return}
Add-Type -Path (Join-Path $PSScriptRoot 'Sr0OwnedJobProcess.cs')
New-Item -ItemType Directory -Path $out|Out-Null
$stdout=Join-Path $out 'compile.stdout.bin';$stderr=Join-Path $out 'compile.stderr.bin';$receipt=Join-Path $out 'observation.json'
$dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$argv='build --build-system native -v --package-path "'+$package+'" --scratch-path "'+$scratch+'" --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+$dep+'" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
$record=[ordered]@{kind='factory-pilot-five-owned-compile-v1';phase=$Phase;case=$plan.case;planSha256=$PlanSha256;sourceHash=$plan.sourceHash;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;compilerHash=$plan.compilerHash;compilerPath=$plan.compilerPath;target='windows-x86_64';configuration='release';rendererSha256=$plan.rendererSha256;argv=$argv;cwd=$package;startedAt=[DateTimeOffset]::UtcNow.ToString('o');processStartedAt=$null;finishedAt=$null;pid=$null;exitCode=$null;timedOut=$false;outputCapExceeded=$false;ownedExited=$false;error=$null;cleanupError=$null;streamDrainComplete=$false;streamsSealed=$false;originalHandleRetained=$false;jobActiveReadable=$false;jobActiveCount=$null;kernelWait=$null;memoryCapBytes=1073741824;jobFlags=512;nativeActions=0;qualification='compile-only-not-native'}
function Save {$record|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $receipt -Encoding UTF8}
$job=[IntPtr]::Zero;$handle=[IntPtr]::Zero;$thread=[IntPtr]::Zero;$or=[IntPtr]::Zero;$er=[IntPtr]::Zero;[uint32]$pidOwned=0;$op=$null;$ep=$null;$of=$null;$ef=$null;$ot=$null;$et=$null;$failed=$null
$priorPath=$env:Path;$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$priorPath
Save
try {
 Assert-Inputs
 $job=[Sr0OwnedJobProcess]::CreateJob();if($job -eq [IntPtr]::Zero -or -not [Sr0OwnedJobProcess]::ConfigureJobWithFlags($job,512,1073741824)){throw 'job cap configuration failed'}
 if(-not [Sr0OwnedJobProcess]::CreateSuspended($plan.compilerPath,[Sr0OwnedJobProcess]::BuildCommandLine($plan.compilerPath,$argv),$package,[ref]$handle,[ref]$thread,[ref]$or,[ref]$er,[ref]$pidOwned)){throw 'suspended compiler start failed'}
 $record.pid=$pidOwned;$record.originalHandleRetained=($handle -ne [IntPtr]::Zero);$record.processStartedAt=[Diagnostics.Process]::GetProcessById($pidOwned).StartTime.ToUniversalTime().ToString('o')
 $op=New-Object IO.FileStream($or,[IO.FileAccess]::Read,$false);$ep=New-Object IO.FileStream($er,[IO.FileAccess]::Read,$false)
 $of=[IO.File]::Open($stdout,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$ef=[IO.File]::Open($stderr,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$ot=$op.CopyToAsync($of);$et=$ep.CopyToAsync($ef)
 if(-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,$handle)){throw 'assignment before resume failed'}
 if([Sr0OwnedJobProcess]::ResumeThread($thread,$handle) -eq [uint32]::MaxValue){throw 'resume failed'}
 Save;$watch=[Diagnostics.Stopwatch]::StartNew()
 do {$record.kernelWait=[Sr0OwnedJobProcess]::WaitForSingleObject($handle,250);$record.outputCapExceeded=((Get-Item $stdout).Length -gt 8388608 -or (Get-Item $stderr).Length -gt 8388608);$record.timedOut=$watch.Elapsed.TotalSeconds -ge 600;if($record.outputCapExceeded -or $record.timedOut){throw 'compile output/time cap exceeded'}}while($record.kernelWait -eq 258)
 [uint32]$code=259;if($record.kernelWait -ne 0 -or -not [Sr0OwnedJobProcess]::GetExitCodeProcess($handle,[ref]$code)){throw 'retained exit certificate unavailable'};$record.exitCode=[int64]$code;$record.ownedExited=$true
 if(-not $ot.Wait(15000) -or -not $et.Wait(15000)){throw 'stream drain timeout'};$ot.GetAwaiter().GetResult();$et.GetAwaiter().GetResult();$record.streamDrainComplete=$true
 [uint32]$active=1;$record.jobActiveReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active);$record.jobActiveCount=$active;if(-not $record.jobActiveReadable -or $active -ne 0){throw 'job not quiescent'}
 $of.Flush();$of.Dispose();$of=$null;$ef.Flush();$ef.Dispose();$ef=$null;$record.streamsSealed=$true
 $record.stdoutSha256=Hash $stdout;$record.stderrSha256=Hash $stderr;$record.stdoutBytes=(Get-Item $stdout).Length;$record.stderrBytes=(Get-Item $stderr).Length
 if($code -ne 0){throw "compiler exit $code"}
 $exe=Join-Path $scratch 'x86_64-unknown-windows-msvc\release\FactoryProbe.exe';$record.exePath=$exe;$record.exeSha256=Hash $exe;$record.exeBytes=(Get-Item $exe).Length
 if($Phase -ceq 'final' -and ('sha256:'+$record.exeSha256) -cne $plan.expectedHostHash){throw 'final host bytes drift from prebuild'}
 Assert-Inputs
}catch {$failed=$_.Exception.Message;$record.error=$failed}
finally {
 if($failed){if($job -ne [IntPtr]::Zero){[void][Sr0OwnedJobProcess]::TerminateJobObject($job,124)};if($handle -ne [IntPtr]::Zero){[void][Sr0OwnedJobProcess]::TerminateProcess($handle,124);[void][Sr0OwnedJobProcess]::WaitForSingleObject($handle,15000)}}
 if($ot){[void]$ot.Wait(5000)};if($et){[void]$et.Wait(5000)}
 foreach($s in @($of,$ef,$op,$ep)){if($s){$s.Dispose()}}
 if($job -ne [IntPtr]::Zero){[uint32]$a=1;$known=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$a);$record.cleanupJobReadable=$known;$record.cleanupJobActive=$a;if(-not $known -or $a -ne 0){$record.cleanupError='job quiescence not certified'}}
 foreach($h in @($or,$er,$thread,$handle,$job)){if($h -ne [IntPtr]::Zero){[void][Sr0OwnedJobProcess]::CloseHandle($h)}}
 $env:Path=$priorPath;$record.finishedAt=[DateTimeOffset]::UtcNow.ToString('o');Save
}
if($record.error -or $record.cleanupError){throw ($record.error+' '+$record.cleanupError)}
[ordered]@{status='compiled';phase=$Phase;case=$record.case;planSha256=$PlanSha256;exeSha256=$record.exeSha256;exeBytes=$record.exeBytes;nativeActions=0;memoryCapBytes=1073741824;streamsSealed=$record.streamsSealed;jobActiveCount=$record.jobActiveCount}|ConvertTo-Json -Depth 8
