# Diagnostic only: capture actual compiler startup identity, then stop owned build.
param([Parameter(Mandatory=$true)][string]$RunRoot)
$ErrorActionPreference='Stop'
$root='D:\Claude\factory-swiftright-module-origin-37429120-20261011'
$run=$root+'\module-provenance-startup-r2';$source=$root+'\runtime'
$swift='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
$toolchain='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\'
function Hash([string]$p){return 'sha256:'+((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant())}
if($RunRoot -cne $run -or (Test-Path -LiteralPath $run)){throw 'Exact fresh observation root required'}
if((Hash ($root+'\runtime-source-receipt.json')) -cne 'sha256:b28564f02cd32b96d348626a92e67c231d0ea5919ae93e836c9e6cfdb47d2fb7' -or (Hash ($root+'\runtime-source.tar')) -cne 'sha256:b081f6c36766d7c5a272dcaca032af0882ca3099c58cccfbea35739917e330ec' -or (Hash $swift) -cne 'sha256:1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'){throw 'Pinned observation input drift'}
$snapshot=Get-Content -Raw ($root+'\runtime-source-receipt.json')|ConvertFrom-Json
$disk=@(Get-ChildItem -LiteralPath $source -Recurse -File)
if($disk.Count -ne @($snapshot.completeSnapshotBindings).Count){throw 'Source disk coverage'}
foreach($b in $snapshot.completeSnapshotBindings){if((Hash (Join-Path $source $b.path)) -cne $b.sha256){throw 'Source drift'}}
if(@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -in @('swift','swiftc','swift-build','swift-frontend','clang','lld-link')}).Count){throw 'Compiler already active'}
New-Item -ItemType Directory -Path $run|Out-Null;Copy-Item -LiteralPath $PSCommandPath -Destination ($run+'\startup-observe.ps1')
$arguments=@('build','-c','release','--package-path',$source,'--scratch-path',($run+'\scratch'))
$process=$null;$start=$null;$descendants=@{};$observations=@();$errorText='';$cleanup=[ordered]@{attempted=$false;verifiedExit=$false;action='none'};$stdout='';$stderr=''
try {
  $env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
  $info=[Diagnostics.ProcessStartInfo]::new($swift);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WorkingDirectory=$source
  $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;foreach($arg in $arguments){$info.ArgumentList.Add($arg)}
  $process=[Diagnostics.Process]::Start($info);$start=$process.StartTime.ToUniversalTime().ToString('o')
  $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
  $deadline=[DateTimeOffset]::UtcNow.AddSeconds(3)
  do {
    $row=[ordered]@{observedAt=[DateTimeOffset]::UtcNow.ToString('o');pid=$process.Id;launchStartedAt=$start;hasExited=$process.HasExited;mainModulePath=$null;mainModuleHash=$null;dotNetPath=$null;dotNetStart=$null;cimExecutablePath=$null;cimCommandLine=$null;cimCreationDate=$null;errors=@()}
    try{$row.mainModulePath=$process.MainModule.FileName;if($row.mainModulePath){$row.mainModuleHash=Hash $row.mainModulePath}}catch{$row.errors+=('MainModule: '+[string]$_)}
    try{$current=Get-Process -Id $process.Id -ErrorAction Stop;$row.dotNetPath=$current.Path;$row.dotNetStart=$current.StartTime.ToUniversalTime().ToString('o')}catch{$row.errors+=('GetProcess: '+[string]$_)}
    try{$os=Get-CimInstance Win32_Process -Filter ('ProcessId='+$process.Id);if($os){$row.cimExecutablePath=$os.ExecutablePath;$row.cimCommandLine=$os.CommandLine;$row.cimCreationDate=$os.CreationDate.ToUniversalTime().ToString('o')}}catch{$row.errors+=('CIM: '+[string]$_)}
    $all=@(Get-CimInstance Win32_Process);$parents=@([uint32]$process.Id);$found=@()
    do {
      $next=@($all|Where-Object{$_.ParentProcessId -in $parents -and $_.ProcessId -ne $process.Id -and $_.ExecutablePath -and $_.ExecutablePath.StartsWith($toolchain,[StringComparison]::OrdinalIgnoreCase) -and $_.CreationDate.ToUniversalTime() -ge [DateTime]::Parse($start).ToUniversalTime() -and $_.ProcessId -notin $found})
      $parents=@($next.ProcessId);$found+=@($next.ProcessId)
      foreach($child in $next){$descendants[[string]$child.ProcessId]=[ordered]@{pid=$child.ProcessId;path=$child.ExecutablePath;startedAt=$child.CreationDate.ToUniversalTime().ToString('o');commandLine=$child.CommandLine}}
    }while($parents.Count)
    $row.descendants=@($descendants.Values);$observations+=$row
    $observations|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 ($run+'\startup-observations.json')
    if($process.HasExited){break};Start-Sleep -Milliseconds 100
  }while([DateTimeOffset]::UtcNow -lt $deadline)
}catch{$errorText=[string]$_}
finally {
  if($process -and -not $process.HasExited){
    $cleanup.attempted=$true;$cleanup.action='kill-owned-observed-tree'
    $current=Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if($current -and $current.StartTime.ToUniversalTime().ToString('o') -ceq $start -and $current.Path.StartsWith($toolchain,[StringComparison]::OrdinalIgnoreCase)){
      $cleanup.path=$current.Path;$cleanup.sha256=Hash $current.Path
      try{$process.Kill($true);$null=$process.WaitForExit(5000)}catch{$cleanup.error=[string]$_}
      $cleanup.verifiedExit=$process.HasExited
    }else{$cleanup.error='Owned start/path guard refused cleanup'}
  }elseif($process){$cleanup.action='child-exited-naturally';$cleanup.verifiedExit=$true}
  $childCleanup=@()
  foreach($child in $descendants.Values){
    $entry=[ordered]@{pid=$child.pid;path=$child.path;startedAt=$child.startedAt;verifiedExit=$false}
    $actual=Get-CimInstance Win32_Process -Filter ('ProcessId='+$child.pid)
    if(-not $actual){$entry.verifiedExit=$true}
    elseif($actual.ExecutablePath -ceq $child.path -and $actual.CreationDate.ToUniversalTime().ToString('o') -ceq $child.startedAt){
      try{$owned=Get-Process -Id $child.pid -ErrorAction Stop;$owned.Kill($true);$null=$owned.WaitForExit(5000);$entry.verifiedExit=$owned.HasExited}catch{$entry.error=[string]$_}
    }else{$entry.error='Descendant identity guard refused cleanup'}
    $childCleanup+=$entry
  }
  if(@($childCleanup|Where-Object{-not $_.verifiedExit}).Count){$cleanup.verifiedExit=$false}
  $cleanup.descendants=$childCleanup
  if($outTask -and $errTask){
    $drain=[DateTimeOffset]::UtcNow.AddSeconds(5)
    while(-not ($outTask.IsCompleted -and $errTask.IsCompleted) -and [DateTimeOffset]::UtcNow -lt $drain){Start-Sleep -Milliseconds 100}
    if($outTask.IsCompleted){$stdout=$outTask.GetAwaiter().GetResult()}else{$errorText+='; stdout drain incomplete'}
    if($errTask.IsCompleted){$stderr=$errTask.GetAwaiter().GetResult()}else{$errorText+='; stderr drain incomplete'}
  }
  [IO.File]::WriteAllText(($run+'\startup.stdout.txt'),$stdout);[IO.File]::WriteAllText(($run+'\startup.stderr.txt'),$stderr)
  $result=[ordered]@{kind='factory-module-compiler-startup-observation';version=1;moduleOriginQualified=$false;testRunnerExecuted=$false;synthetic=$false;launchExecutable=$swift;launchHash=(Hash $swift);launchArgv=$arguments;launchCwd=$source;startedAt=$start;observations=$observations;cleanup=$cleanup;error=$errorText;sourceReceiptHash=(Hash ($root+'\runtime-source-receipt.json'));helperHash=(Hash $PSCommandPath);finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}
  $result|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 ($run+'\startup-receipt.json')
}
if($errorText -or -not $cleanup.verifiedExit){throw 'Startup observation failed or cleanup unverified; inspect preserved raw'}
