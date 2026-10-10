# CIM-only diagnostic startup; no module-origin qualification.
param([Parameter(Mandatory=$true)][string]$RunRoot)
$ErrorActionPreference='Stop'
$root='D:\Claude\factory-swiftright-module-origin-37429120-20261011';$run=$root+'\module-provenance-startup-r3';$source=$root+'\runtime'
$swift='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
$toolchain='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\'
function Hash([string]$p){return 'sha256:'+((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant())}
$traversal=Join-Path $PSScriptRoot 'owned-descendants.ps1'
if((Hash $traversal) -cne 'sha256:cf3f9d563f665d6d759a3209963de44346ad4b72f6f0317cd52d298bca09cbe4'){throw 'Traversal source drift'}
. $traversal
if($RunRoot -cne $run -or (Test-Path -LiteralPath $run)){throw 'Exact fresh observation root required'}
if((Hash ($root+'\runtime-source-receipt.json')) -cne 'sha256:b28564f02cd32b96d348626a92e67c231d0ea5919ae93e836c9e6cfdb47d2fb7' -or (Hash ($root+'\runtime-source.tar')) -cne 'sha256:b081f6c36766d7c5a272dcaca032af0882ca3099c58cccfbea35739917e330ec' -or (Hash $swift) -cne 'sha256:1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'){throw 'Pinned inputs drift'}
$snapshot=Get-Content -Raw ($root+'\runtime-source-receipt.json')|ConvertFrom-Json
if(@(Get-ChildItem -LiteralPath $source -Recurse -File).Count -ne @($snapshot.completeSnapshotBindings).Count){throw 'Disk coverage'}
foreach($b in $snapshot.completeSnapshotBindings){if((Hash (Join-Path $source $b.path)) -cne $b.sha256){throw 'Source drift'}}
$inventory=@(Get-CimInstance Win32_Process -OperationTimeoutSec 2)
if(@($inventory|Where-Object{$_.Name -in @('swift.exe','swiftc.exe','swift-build.exe','swift-frontend.exe','clang.exe','lld-link.exe')}).Count){throw 'Compiler already active'}
New-Item -ItemType Directory -Path $run|Out-Null
Copy-Item -LiteralPath $PSCommandPath -Destination ($run+'\startup-observe-r3.ps1');Copy-Item -LiteralPath $traversal -Destination ($run+'\owned-descendants.ps1')
$arguments=@('build','-c','release','--package-path',$source,'--scratch-path',($run+'\scratch'))
$launchArguments='build -c release --package-path "'+$source+'" --scratch-path "'+($run+'\scratch')+'"'
$observations=@();$descendants=@{};$owned=$null;$process=$null;$errorText='';$cleanup=@();$stdout='';$stderr=''
function Phase([string]$name,$data){[ordered]@{phase=$name;observedAt=[DateTimeOffset]::UtcNow.ToString('o');data=$data}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 ($run+'\phase-'+$name+'.json')}
try {
  $env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
  $info=[Diagnostics.ProcessStartInfo]::new($swift);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WorkingDirectory=$source
  $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.Arguments=$launchArguments
  $launchBefore=[DateTimeOffset]::UtcNow;Phase 'before-start' @{executable=$swift;argv=$arguments;arguments=$launchArguments;cwd=$source;coordinatorPid=$PID}
  $process=[Diagnostics.Process]::Start($info);$returnedPid=$process.Id
  Phase 'returned-pid' @{pid=$returnedPid;launchBefore=$launchBefore.ToString('o')}
  $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
  $deadline=[DateTimeOffset]::UtcNow.AddSeconds(3)
  do {
    $os=Get-CimInstance Win32_Process -Filter ('ProcessId='+$returnedPid) -OperationTimeoutSec 2
    $row=[ordered]@{observedAt=[DateTimeOffset]::UtcNow.ToString('o');pid=$returnedPid;osPresent=[bool]$os;path=$null;commandLine=$null;startedAt=$null;parentPid=$null}
    if($os){
      $row.path=$os.ExecutablePath;$row.commandLine=$os.CommandLine;$row.startedAt=$os.CreationDate.ToUniversalTime().ToString('o');$row.parentPid=$os.ParentProcessId
      if($os.ParentProcessId -ne $PID -or $os.CreationDate.ToUniversalTime() -lt $launchBefore.UtcDateTime.AddSeconds(-1)){throw 'Returned process parent/start guard'}
      $owned=[ordered]@{pid=$returnedPid;path=$row.path;startedAt=$row.startedAt}
    }
    # Durable OS row precedes all ancestry traversal.
    $observations+=$row;$observations|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 ($run+'\startup-observations.json')
    if(-not $os){break}
    $all=@(Get-CimInstance Win32_Process -OperationTimeoutSec 2)
    $all|Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine,CreationDate|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 ($run+'\raw-process-inventory.json')
    $found=@(Get-OwnedDescendants -Rows $all -RootPid $returnedPid -RootStartedAt $os.CreationDate)
    foreach($child in $found){$descendants[[string]$child.pid]=$child}
    Phase 'traversal-completed' @{childCount=$found.Count}
    Start-Sleep -Milliseconds 100
  }while([DateTimeOffset]::UtcNow -lt $deadline)
}catch{$errorText=[string]$_}
finally {
  # Every target comes from returned PID or recorded live ancestry; no external PID inputs.
  $targets=@($descendants.Values);if($owned){$targets+=,$owned}
  $cleanupDeadline=[DateTimeOffset]::UtcNow.AddSeconds(20)
  foreach($target in $targets){
    $entry=[ordered]@{pid=$target.pid;path=$target.path;startedAt=$target.startedAt;verifiedExit=$false;action='none'}
    if([DateTimeOffset]::UtcNow -ge $cleanupDeadline){$entry.error='Overall cleanup deadline';$cleanup+=$entry;continue}
    $current=Get-CimInstance Win32_Process -Filter ('ProcessId='+$target.pid) -OperationTimeoutSec 2
    if(-not $current){$entry.verifiedExit=$true;$entry.action='already-exited'}
    elseif($current.ExecutablePath -ceq $target.path -and $current.CreationDate.ToUniversalTime().ToString('o') -ceq $target.startedAt -and $current.ExecutablePath.StartsWith($toolchain,[StringComparison]::OrdinalIgnoreCase)){
      $entry.action='terminate-owned-cim';$entry.returnValue=(Invoke-CimMethod -InputObject $current -MethodName Terminate -OperationTimeoutSec 2).ReturnValue
      $entry.verifiedExit=(-not (Get-CimInstance Win32_Process -Filter ('ProcessId='+$target.pid) -OperationTimeoutSec 2))
    }else{$entry.error='Owned path/start/toolchain cleanup guard refused'}
    $cleanup+=$entry;$cleanup|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 ($run+'\cleanup-progress.json')
  }
  if($outTask -and $errTask){
    $drain=[DateTimeOffset]::UtcNow.AddSeconds(5)
    while(-not ($outTask.IsCompleted -and $errTask.IsCompleted) -and [DateTimeOffset]::UtcNow -lt $drain){Start-Sleep -Milliseconds 100}
    if($outTask.IsCompleted){$stdout=$outTask.GetAwaiter().GetResult()}else{$errorText+='; stdout drain incomplete'}
    if($errTask.IsCompleted){$stderr=$errTask.GetAwaiter().GetResult()}else{$errorText+='; stderr drain incomplete'}
  }
  [IO.File]::WriteAllText(($run+'\startup.stdout.txt'),$stdout);[IO.File]::WriteAllText(($run+'\startup.stderr.txt'),$stderr)
  $result=[ordered]@{kind='factory-module-compiler-startup-observation';version=3;moduleOriginQualified=$false;testRunnerExecuted=$false;synthetic=$false;launchExecutable=$swift;launchHash=(Hash $swift);launchArgv=$arguments;launchArguments=$launchArguments;launchCwd=$source;owned=$owned;observations=$observations;cleanup=$cleanup;error=$errorText;helperHash=(Hash $PSCommandPath);traversalHash=(Hash $traversal);finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}
  $result|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 ($run+'\startup-receipt.json')
}
if($errorText -or @($cleanup|Where-Object{-not $_.verifiedExit}).Count){throw 'Diagnostic failed or cleanup unverified; preserved raw only'}
