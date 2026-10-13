param([Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$helper=Join-Path $Stage 'workload-incremental-v6\shared\Sr0OwnedJobProcess.cs';Add-Type -Path $helper
$sizes=[ordered]@{basic=[Runtime.InteropServices.Marshal]::SizeOf([type][Sr0OwnedJobProcess+BasicLimitInformation]);extended=[Runtime.InteropServices.Marshal]::SizeOf([type][Sr0OwnedJobProcess+ExtendedLimitInformation]);accounting=[Runtime.InteropServices.Marshal]::SizeOf([type][Sr0OwnedJobProcess+BasicAccountingInformation])}
if($sizes.basic -ne 64 -or $sizes.extended -ne 144 -or $sizes.accounting -ne 48){throw 'Exact Win64 native struct sizes rejected'}
$out=Join-Path $Stage 'actual-job-controls-r1';if(Test-Path -LiteralPath $out){throw 'Fresh controls required'};[IO.Directory]::CreateDirectory($out)|Out-Null
$ps=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe';$script=Join-Path $Stage 'workload-incremental-v6\job-controls-v2.ps1';$rows=@()
foreach($mode in @('positive','spawned-descendant','timeout','output-cap','wrong-memory-flag','resume-before-assignment','drop-active-query')){
 $dir=Join-Path $out $mode;[IO.Directory]::CreateDirectory($dir)|Out-Null;$childOut=Join-Path $dir 'inner';[IO.Directory]::CreateDirectory($childOut)|Out-Null
 $controlArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$script,'-Mode',$mode,'-OutRoot',$childOut);$argline=(@($controlArgs|ForEach-Object{[Sr0OwnedJobProcess]::QuoteWindowsArgument($_)}) -join ' ');$cmd=[Sr0OwnedJobProcess]::BuildCommandLine($ps,$argline)
 $job=[IntPtr]::Zero;$p=[IntPtr]::Zero;$th=[IntPtr]::Zero;$or=[IntPtr]::Zero;$er=[IntPtr]::Zero;[uint32]$pidOwned=0;$assigned=$false;$done=$false;$terminal=$false;$drained=$false;$readable=$false;[uint32]$active=1;[uint32]$code=259;$timedOut=$false;$capHit=$false;$peak=0;$samples=0;$op=$null;$ep=$null;$of=$null;$ef=$null;$ot=$null;$et=$null;$wait=258
 try{
  $job=[Sr0OwnedJobProcess]::CreateJob();if($job -eq [IntPtr]::Zero -or -not [Sr0OwnedJobProcess]::ConfigureJob($job,1073741824)){throw 'Outer owned control job configuration failed'}
  if(-not [Sr0OwnedJobProcess]::CreateSuspended($ps,$cmd,$dir,[ref]$p,[ref]$th,[ref]$or,[ref]$er,[ref]$pidOwned)){throw 'Outer suspended child failed'}
  if(-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,$p)){throw 'Outer job assignment failed'};$assigned=$true
  $op=New-Object IO.FileStream($or,[IO.FileAccess]::Read,$false);$ep=New-Object IO.FileStream($er,[IO.FileAccess]::Read,$false)
  $of=[IO.File]::Open((Join-Path $dir 'stdout.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$ef=[IO.File]::Open((Join-Path $dir 'stderr.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$ot=$op.CopyToAsync($of);$et=$ep.CopyToAsync($ef);
  if([Sr0OwnedJobProcess]::ResumeThread($th,$p) -eq [uint32]::MaxValue){throw 'Outer resume failed'}
  $watch=[Diagnostics.Stopwatch]::StartNew()
  do{$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($p,250);try{$observed=[Diagnostics.Process]::GetProcessById([int]$pidOwned);$rss=$observed.WorkingSet64;$samples++;$peak=[math]::Max($peak,$rss);$observed.Dispose()}catch{};if($watch.Elapsed.TotalSeconds -gt 40){$timedOut=$true;break};if($peak -gt 268435456 -or $of.Length -gt 2MB -or $ef.Length -gt 2MB){$capHit=$true;break}}while($wait -ne 0)
  if($timedOut -or $capHit){[Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null;$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($p,5000)}
  $terminal=($wait -eq 0);$od=$ot.Wait(10000);$ed=$et.Wait(10000);$drained=$od -and $ed
  for($q=0;$q -lt 40;$q++){$readable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active);if($readable -and $active -eq 0){break};[Threading.Thread]::Sleep(100)}
  $exitRead=[Sr0OwnedJobProcess]::GetExitCodeProcess($p,[ref]$code);$done=$terminal -and $drained -and $readable -and $active -eq 0
  if(-not $done -or -not $exitRead -or $code -eq 259 -or $timedOut -or $capHit){throw ('Outer control process rejected: '+$mode)}
 }finally{
  if(-not $done -and $p -ne [IntPtr]::Zero){if($assigned){[Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null}else{[Sr0OwnedJobProcess]::TerminateProcess($p,124)|Out-Null};$wait=[Sr0OwnedJobProcess]::WaitForSingleObject($p,5000);$terminal=($wait -eq 0);$drained=($null -ne $ot -and $null -ne $et -and $ot.Wait(5000) -and $et.Wait(5000));$readable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active);$done=$terminal -and $drained -and $readable -and $active -eq 0}
  if($p -ne [IntPtr]::Zero){$exitRead=[Sr0OwnedJobProcess]::GetExitCodeProcess($p,[ref]$code)}
  foreach($stream in @($op,$ep,$of,$ef)){if($stream){$stream.Dispose()}};foreach($h in @($th,$p,$or,$er,$job)){if($h -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($h)|Out-Null}}
  $supervisor=[ordered]@{kind='root-sr0-owned-control-process-v1';mode=$mode;pid=$pidOwned;assigned=$assigned;kernelWait=$wait;exitCode=$code;terminal=$terminal;streamsDrained=$drained;activeReadable=$readable;activeProcesses=$active;quiescent=$done;timedOut=$timedOut;capHit=$capHit;peakRssBytes=$peak;rssSamples=$samples;rssCapBytes=268435456;deadlineSeconds=40;jobMemoryBytes=1073741824}
  [IO.File]::WriteAllText((Join-Path $dir 'supervisor.json'),($supervisor|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 }
 $receipts=@(Get-ChildItem -LiteralPath $childOut -Filter 'control-receipt.json' -Recurse -File);if($receipts.Count -ne 1){throw ('Exact control receipt missing '+$mode)};$r=[IO.File]::ReadAllText($receipts[0].FullName)|ConvertFrom-Json
 $negative=$mode -in @('resume-before-assignment','drop-active-query');$expected=if($negative){'expected-rejected'}else{'passed'};$expectedExit=if($negative){1}else{0}
 if($code -ne $expectedExit -or $r.outcome -cne $expected -or -not $r.cleanup_quiescent -or -not $r.kernel_terminal){throw ('Actual control receipt rejected '+$mode+': '+$r.failure)}
 $rows += [ordered]@{mode=$mode;status='passed';exitCode=$code;controlReceipt=$receipts[0].FullName;sha256=(Get-FileHash -LiteralPath $receipts[0].FullName).Hash.ToLowerInvariant();supervisor=$supervisor}
}
$result=[ordered]@{kind='root-sr0-v6-real-job-controls-v1';status='passed';sizes=$sizes;controls=$rows;nativeWindowActions=0;compilerActions=0;lockActions=0;at=[DateTimeOffset]::UtcNow.ToString('o')};[IO.File]::WriteAllText((Join-Path $out 'root-controls.json'),($result|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false));$result|ConvertTo-Json -Depth 12
