# One fresh compiler-only capture; fixed source, compiler & output paths.
param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$Receipt,[Parameter(Mandatory=$true)][string]$RunRoot)
$ErrorActionPreference='Stop'
$root='D:\Claude\factory-swiftright-module-origin-37429120-20261011'
$source=$root+'\runtime';$receiptPath=$root+'\runtime-source-receipt.json';$run=$root+'\module-provenance-run'
$archivePath=$root+'\runtime-source.tar';$scratch=$run+'\scratch'
$swift='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
$commit='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
$tree='sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'
$completeHash='sha256:e9af9fcc9e3aedd7590249f4adc0f26d32190d4f50f70b698d73bbf6ab76ed6f'
$receiptHash='sha256:b28564f02cd32b96d348626a92e67c231d0ea5919ae93e836c9e6cfdb47d2fb7'
$archiveHash='sha256:b081f6c36766d7c5a272dcaca032af0882ca3099c58cccfbea35739917e330ec'
$compilerHash='sha256:1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'
function Hash([string]$p){return 'sha256:'+((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant())}
function Canonical-Bindings($bindings){
  $parts=@($bindings|ForEach-Object{'{"path":'+(ConvertTo-Json -InputObject ([string]$_.path) -Compress)+',"sha256":'+(ConvertTo-Json -InputObject ([string]$_.sha256) -Compress)+'}'})
  $bytes=[Text.Encoding]::UTF8.GetBytes('['+($parts -join ',')+']')
  return 'sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant())
}
function Validate-Bindings($bindings){
  $rows=@($bindings);if($rows.Count -eq 0){throw 'Empty bindings'}
  $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $previous=$null
  foreach($b in $rows){
    if((@($b.PSObject.Properties.Name|Sort-Object) -join ',') -cne 'path,sha256'){throw 'Binding shape'}
    if($b.path -isnot [string] -or $b.path -notmatch '^[^\\:]+$' -or $b.path.StartsWith('/') -or @($b.path.Split('/')|Where-Object{$_ -in @('','.', '..')}).Count){throw 'Binding path escape'}
    if($b.sha256 -isnot [string] -or $b.sha256 -cnotmatch '^sha256:[0-9a-f]{64}$'){throw 'Binding hash'}
    if(-not $seen.Add($b.path)){throw 'Duplicate binding'}
    if($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous,$b.path) -ge 0){throw 'Unsorted bindings'}
    $previous=$b.path
  }
}
function Check-Inputs {
  if((Hash $receiptPath) -cne $receiptHash -or (Hash $archivePath) -cne $archiveHash -or (Hash $swift) -cne $compilerHash){throw 'Frozen input hash drift'}
  $snapshot=Get-Content -Raw -LiteralPath $receiptPath|ConvertFrom-Json
  if($snapshot.kind -cne 'factory-additive-runtime-source' -or $snapshot.synthetic -ne $false -or $snapshot.sourceCommit -cne $commit -or $snapshot.runtimePackagePath -cne $source -or $snapshot.sourceTreeHash -cne $tree -or $snapshot.completeSnapshotHash -cne $completeHash -or $snapshot.snapshotArchiveHash -cne $archiveHash){throw 'Snapshot identity'}
  Validate-Bindings $snapshot.completeSnapshotBindings;Validate-Bindings $snapshot.sourceBindings
  if((Canonical-Bindings $snapshot.completeSnapshotBindings) -cne $completeHash -or (Canonical-Bindings $snapshot.sourceBindings) -cne $tree){throw 'Canonical snapshot hash'}
  $sourceRows=@($snapshot.completeSnapshotBindings|Where-Object{$_.path -ceq 'Package.swift' -or $_.path.StartsWith('Sources/',[StringComparison]::Ordinal)})
  if((Canonical-Bindings $sourceRows) -cne $tree){throw 'Source coverage'}
  $disk=@(Get-ChildItem -LiteralPath $source -Recurse -File|ForEach-Object{$_.FullName.Substring($source.Length+1).Replace('\','/')})
  if($disk.Count -ne @($snapshot.completeSnapshotBindings).Count -or @($disk|Where-Object{$_ -cnotin @($snapshot.completeSnapshotBindings.path)}).Count){throw 'Full disk coverage'}
  $rows=@()
  foreach($binding in $snapshot.completeSnapshotBindings){
    $p=Join-Path $source $binding.path;$item=Get-Item -LiteralPath $p
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Source reparse point'}
    if((Hash $p) -cne $binding.sha256){throw 'Source drift'}
    $rows += [ordered]@{path=$binding.path;sha256=$binding.sha256;bytes=$item.Length}
  }
  return ,$rows
}
if($SourceRoot -cne $source -or $Receipt -cne $receiptPath -or $RunRoot -cne $run){throw 'Exact owned paths required'}
if(Test-Path -LiteralPath $run){throw 'Fresh RunRoot required'}
$before=Check-Inputs
if(@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -in @('swift','swiftc','swift-frontend','clang','lld-link')}).Count){throw 'Existing compiler child; serial build required'}
New-Item -ItemType Directory -Path $run|Out-Null
$helperCopy=$run+'\module-origin-build.ps1';Copy-Item -LiteralPath $PSCommandPath -Destination $helperCopy
$helperHash=Hash $PSCommandPath;if((Hash $helperCopy) -cne $helperHash){throw 'Helper archive mismatch'}
$arguments=@('build','-c','release','--package-path',$source,'--scratch-path',$scratch)
$moduleRoot=$scratch+'\out\Products\Release-windows-x86_64\SwiftRightRuntime.swiftmodule'
$names=@('x86_64-unknown-windows-msvc.swiftdoc','x86_64-unknown-windows-msvc.swiftmodule')
$process=$null;$owned=$null;$start=$null;$finish=$null;$exitCode=$null;$timedOut=$false;$errorText='';$after=$null;$outputs=$null;$modules=@()
$cleanup=[ordered]@{attempted=$false;verifiedExit=$false;action='none'}
try {
  $env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
  $info=[Diagnostics.ProcessStartInfo]::new($swift);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WorkingDirectory=$source
  $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  foreach($arg in $arguments){$info.ArgumentList.Add($arg)}
  $process=[Diagnostics.Process]::Start($info);$start=$process.StartTime.ToUniversalTime().ToString('o')
  $actualPath=$process.MainModule.FileName
  if($actualPath -cne $swift){throw 'Owned compiler path mismatch'}
  $os=Get-CimInstance Win32_Process -Filter ('ProcessId='+$process.Id)
  if(-not $os -or $os.ExecutablePath -cne $swift -or [string]::IsNullOrEmpty($os.CommandLine)){throw 'OS compiler process observation unavailable'}
  $owned=[ordered]@{pid=$process.Id;path=$actualPath;argv=$arguments;workingDirectory=$source;startedAt=$start;observedExecutable=$os.ExecutablePath;observedCommandLine=$os.CommandLine}
  $owned|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 ($run+'\owned-process.json')
  $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
  $deadline=[DateTimeOffset]::UtcNow.AddMinutes(15)
  while(-not $process.WaitForExit(100)){if([DateTimeOffset]::UtcNow -ge $deadline){$timedOut=$true;throw 'Owned compiler deadline exceeded'}}
  while(-not ($outTask.IsCompleted -and $errTask.IsCompleted)){
    if([DateTimeOffset]::UtcNow -ge $deadline){$timedOut=$true;throw 'Compiler output drain deadline exceeded'}
    Start-Sleep -Milliseconds 100
  }
  $finish=[DateTimeOffset]::UtcNow.ToString('o');$exitCode=$process.ExitCode
  $outputs=[ordered]@{}
  foreach($stream in @('stdout','stderr')){
    $p=$run+'\build.'+$stream+'.txt';$task=if($stream -eq 'stdout'){$outTask}else{$errTask}
    [IO.File]::WriteAllText($p,$task.GetAwaiter().GetResult())
    $outputs[$stream]=[ordered]@{path=$p;sha256=(Hash $p);bytes=(Get-Item -LiteralPath $p).Length}
  }
  if($exitCode -ne 0){throw "Compiler exit $exitCode"}
  $files=@(Get-ChildItem -LiteralPath $moduleRoot -Force)
  if($files.Count -ne 2 -or @($files|Where-Object{$_.PSIsContainer -or $_.Name -cnotin $names}).Count){throw 'Exact module coverage required'}
  New-Item -ItemType Directory -Path ($run+'\module-archive')|Out-Null
  foreach($name in $names){
    $p=$moduleRoot+'\'+$name;$copy=$run+'\module-archive\'+$name;$item=Get-Item -LiteralPath $p
    if($item.Length -le 0 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid module file'}
    $hash=Hash $p;Copy-Item -LiteralPath $p -Destination $copy
    if((Hash $p) -cne $hash -or (Hash $copy) -cne $hash -or (Get-Item -LiteralPath $copy).Length -ne $item.Length){throw 'Module copy mismatch'}
    $modules += [ordered]@{sourcePath=$p;relativeSourcePath=$name;archivePath=$copy;sha256=$hash;bytes=$item.Length}
  }
  $after=Check-Inputs
  if((ConvertTo-Json -InputObject $before -Compress -Depth 8) -cne (ConvertTo-Json -InputObject $after -Compress -Depth 8)){throw 'Source before/after mismatch'}
  if((Hash $PSCommandPath) -cne $helperHash -or (Hash $helperCopy) -cne $helperHash){throw 'Helper drift'}
  $cleanup=[ordered]@{attempted=$false;verifiedExit=$process.HasExited;action='child-exited-naturally'}
}catch{$errorText=[string]$_}
finally {
  if($process -and -not $process.HasExited){
    $cleanup=[ordered]@{attempted=$true;verifiedExit=$false;action='kill-owned-tree'}
    $current=Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if($current -and $current.Path -ceq $swift -and $current.StartTime.ToUniversalTime().ToString('o') -ceq $start){& taskkill /PID $process.Id /T /F|Out-Null;$null=$process.WaitForExit(5000);$cleanup.verifiedExit=$process.HasExited}
  }
  if(-not $finish){$finish=[DateTimeOffset]::UtcNow.ToString('o')}
  $result=[ordered]@{kind='factory-windows-module-origin';version=2;status=if($errorText){'failed'}else{'success'};error=$errorText;runRoot=$run;sourceRoot=$source;sourceReceipt=$receiptPath;sourceReceiptBeforeHash=$receiptHash;sourceReceiptAfterHash=(Hash $receiptPath);sourceArchive=[ordered]@{path=$archivePath;beforeHash=$archiveHash;afterHash=(Hash $archivePath);bytes=(Get-Item -LiteralPath $archivePath).Length};sourceCommit=$commit;sourceTreeHash=$tree;completeSnapshotHash=$completeHash;sourceBefore=$before;sourceAfter=$after;compiler=[ordered]@{path=$swift;beforeHash=$compilerHash;afterHash=(Hash $swift)};helper=[ordered]@{sha256=$helperHash;archivePath=$helperCopy};command=[ordered]@{executable=$swift;arguments=$arguments;launchArguments=($arguments -join ' ');workingDirectory=$source;configuration='release';testRunnerExecuted=$false};process=$owned;startedAt=$start;finishedAt=$finish;buildExitCode=$exitCode;timedOut=$timedOut;ownedProcessCleanup=$cleanup;testRunnerExecuted=$false;output=$outputs;moduleSearchRoot=$moduleRoot;moduleCollection='immediately-after-successful-owned-compiler-exit';moduleBindings=$modules}
  $result|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 ($run+'\module-provenance-receipt.json')
}
if($errorText){throw $errorText}
