# Run only from interactive session under coordinator-owned desktop.lock.
# Uses targeted UIA reads. No global input, foreground/focus or lock mutation.
param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$LockOwner,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$CompileReceiptHash,[Parameter(Mandatory=$true)][string]$ExeHash)
$ErrorActionPreference='Stop'
$cleanupHelper=Join-Path $PSScriptRoot '..\helpers\cleanup-v3.ps1'
if((Get-FileHash $cleanupHelper).Hash.ToLowerInvariant() -ne 'cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13'){throw 'Cleanup helper drift'}
. $cleanupHelper
$sealHelper=Join-Path $PSScriptRoot '..\helpers\stream-seal.ps1'
if((Get-FileHash $sealHelper).Hash.ToLowerInvariant() -ne '4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'){throw 'Stream seal helper drift'}
. $sealHelper
$closeHelper=Join-Path $PSScriptRoot '..\helpers\owned-close.ps1'
if((Get-FileHash $closeHelper).Hash.ToLowerInvariant() -ne 'd0898e1a2ebdefce64fbf5b16cbc3b9f72578e2f0efb649ee001c182f7aaec7c'){throw 'Owned close helper drift'}
. $closeHelper
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe pins required'}
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) { throw 'Native capture requires interactive desktop task' }
$outputPath=[IO.Path]::GetFullPath($RunRoot)
if(-not $outputPath.StartsWith('D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\stack-layout\native\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output outside first capture lane'}
$pixelHelper=Join-Path $PSScriptRoot '..\helpers\pixels-background.ps1'
if((Get-FileHash -LiteralPath $pixelHelper).Hash.ToLowerInvariant() -ne '7172bf8d69f2523672dc57e6ba2889951ea4db4a89100b8b5b42c2bdef2da6ef'){throw 'Pixel helper drift'}
. $pixelHelper
$uiaWorkerSourceRoot=Join-Path $PSScriptRoot 'uia-worker-mta-v1'
$uiaWorkerContract=Join-Path $uiaWorkerSourceRoot 'worker-contract.json'
if(-not (Test-Path -LiteralPath $uiaWorkerContract -PathType Leaf)){throw 'Stack MTA UIA worker contract missing'}
. (Join-Path $uiaWorkerSourceRoot 'invoke-stack-uia-worker.ps1')
$root='D:\Claude\swiftright\'
$packagePath=[IO.Path]::GetFullPath($Package)
if(-not $packagePath.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Package outside factory'}
$plan=Get-Content -Raw (Join-Path $packagePath 'plan.json')|ConvertFrom-Json
$sourceJoin=Join-Path $PSScriptRoot 'stack-source-join.ps1'
. $sourceJoin
$receiptRelative=$StackReceiptRelative
$planHash=$StackPlanHash
Assert-StackLifecycleSource $Package $CompileReceiptHash $ExeHash | Out-Null
if($plan.executionEligible -ne $false -or $plan.hostMode -ne 'renderer'){throw 'Probe is not eligible native renderer host'}
if($plan.rendererSha256 -ne $StackRendererHash){throw 'Unexpected renderer pin'}
if((Get-FileHash -LiteralPath (Join-Path $packagePath $receiptRelative)).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Expected compile receipt drift'}
$compiled=Get-Content -Raw (Join-Path $packagePath $receiptRelative)|ConvertFrom-Json
if(-not $compiled.planSha256 -or (Get-FileHash -LiteralPath (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256){throw 'Compile plan drift'}
if($compiled.exitCode -ne 0 -or $compiled.sourceHash -ne $plan.sourceHash -or $compiled.rendererSha256 -ne $plan.rendererSha256){throw 'Compile receipt mismatch'}

if($plan.case.id -ne 'swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258' -or $plan.sourceHash -ne ('sha256:'+$StackSourceHash) -or $compiled.planSha256 -ne $StackPlanHash -or $compiled.exeSha256 -ne $ExeHash){throw 'Pinned canonical stack host required'}
if($plan.runtimeSourceCommit -ne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b' -or $compiled.runtimeSourceCommit -ne $plan.runtimeSourceCommit -or $compiled.runtimeSourceTreeHash -ne $plan.runtimeSourceTreeHash -or $compiled.timedOut -or -not $compiled.ownedExited){throw 'Fresh runtime compile lineage mismatch'}
$hostInputs=Join-Path $PSScriptRoot '..\helpers\host-inputs.ps1'
if((Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Host input guard drift'}
. $hostInputs
$actualBridgeFiles=@((Join-Path $plan.bridgePackagePath 'Package.swift'))+@(Get-ChildItem -LiteralPath (Join-Path $plan.bridgePackagePath 'Sources') -Recurse -File|ForEach-Object{$_.FullName})
$expectedBridgeFiles=@($plan.bridgeBindings|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $_.path))})
if($actualBridgeFiles.Count -ne $expectedBridgeFiles.Count -or @($actualBridgeFiles|Where-Object{$expectedBridgeFiles -notcontains $_}).Count -ne 0){throw 'Staged bridge membership drift'}
foreach($binding in $plan.bridgeBindings){
 $bridgeInput=[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $binding.path))
 if(-not $bridgeInput.StartsWith($plan.bridgePackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $bridgeInput).Hash.ToLowerInvariant() -ne $binding.sha256){throw 'Bridge source drift'}
}
$exe=[IO.Path]::GetFullPath($compiled.exePath)
if(-not $exe.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Executable outside package'}
function Check-Lock {if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -ne $LockOwner){throw 'Desktop lock ownership lost'}}
Check-Lock
foreach($binding in $plan.sourceBindings){
 $inputPath=[IO.Path]::GetFullPath((Join-Path $packagePath $binding.path))
 if(-not $inputPath.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Source binding escapes package'}
 if((Get-FileHash -LiteralPath $inputPath).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Source binding drift'}
}
if((Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -ne $compiled.exeSha256){throw 'Executable drift'}
$exeBytes=[IO.File]::ReadAllBytes($exe);$peOffset=[BitConverter]::ToInt32($exeBytes,60)
if([BitConverter]::ToUInt16($exeBytes,$peOffset+24+68) -ne 2){throw 'Background-only renderer requires GUI subsystem'}
if((Get-FileHash -LiteralPath $plan.rendererPath).Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Renderer drift'}
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class FactoryDesktop {
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int cx,int cy,uint flags);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@
[FactoryDesktop]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))|Out-Null
function Assert-Background([int]$childPID,[string]$directory,[IntPtr]$before) {
 $fg=[FactoryDesktop]::GetForegroundWindow();[uint32]$fgpid=0
 [FactoryDesktop]::GetWindowThreadProcessId($fg,[ref]$fgpid)|Out-Null
 if($fgpid -eq $childPID -or $fgpid -eq $PID){
  [ordered]@{foregroundBefore=$before.ToInt64();foregroundAfter=$fg.ToInt64();foregroundPID=$fgpid;createNoWindow=$true;guard='owned-foreground-abort'}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $directory 'launch-observation.json')
  throw 'Background-only guard: owned process foreground'
 }
}
function Assert-OwnedWindow([int]$childPID,[string]$path,[string]$startedAt,[IntPtr]$hwnd) {
 $current=Get-Process -Id $childPID -ErrorAction Stop
 if($current.HasExited -or $current.Path -ne $path -or $current.StartTime.ToUniversalTime().ToString('o') -ne $startedAt){throw 'Owned renderer identity drift'}
 [uint32]$windowPID=0
 if($hwnd -eq [IntPtr]::Zero -or [FactoryDesktop]::GetWindowThreadProcessId($hwnd,[ref]$windowPID) -eq 0 -or $windowPID -ne $childPID){throw 'Owned HWND identity drift'}
}
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
Copy-Item -LiteralPath (Join-Path $packagePath $receiptRelative) -Destination (Join-Path $outputPath 'observation.json')
Copy-Item -LiteralPath $hostInputs -Destination (Join-Path $outputPath 'host-inputs.ps1')
Copy-Item -LiteralPath $pixelHelper -Destination (Join-Path $outputPath 'pixels-background.ps1')
foreach($name in @('plan.json','Package.swift','runtime-source-receipt.json','runtime-source-tree.json')){Copy-Item -LiteralPath (Join-Path $packagePath $name) -Destination (Join-Path $outputPath $name)}
Copy-Item -LiteralPath (Join-Path $packagePath 'Sources') -Destination (Join-Path $outputPath 'Sources') -Recurse
Copy-Item -LiteralPath $uiaWorkerSourceRoot -Destination (Join-Path $outputPath 'uia-worker-mta-v1') -Recurse
$records=@()
for($i=1;$i -le 1;$i++){
 Check-Lock
 $dir=Join-Path $outputPath ('native-{0:00}' -f $i)
 if(Test-Path -LiteralPath $dir){throw 'Replay output exists; prepare fresh package'}
 New-Item -ItemType Directory -Path $dir|Out-Null
 $foregroundBefore=[FactoryDesktop]::GetForegroundWindow()
 $startInfo=[Diagnostics.ProcessStartInfo]::new($exe)
 $startInfo.UseShellExecute=$false;$startInfo.CreateNoWindow=$true
 $startInfo.RedirectStandardOutput=$true;$startInfo.RedirectStandardError=$true
 $p=[Diagnostics.Process]::Start($startInfo)
 $ownedStartedAt='';$stdoutFile=$null;$stderrFile=$null;$stdoutTask=$null;$stderrTask=$null
 $primaryError=$null;$cleanupResult=$null;$streamErrors=@();$preCleanupExitObservation=$null
 $rawStreams=@(@{name='stdout';task=$null;file=$null;source=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false},@{name='stderr';task=$null;file=$null;source=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false})
 try {
 $ownedStartedAt=$p.StartTime.ToUniversalTime().ToString('o')
 $stdoutFile=[IO.File]::Open((Join-Path $dir 'host.stdout.txt'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$rawStreams[0].file=$stdoutFile
 $stderrFile=[IO.File]::Open((Join-Path $dir 'host.stderr.txt'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$rawStreams[1].file=$stderrFile
 $rawStreams[0].source=$p.StandardOutput.BaseStream
 $stdoutTask=$p.StandardOutput.BaseStream.CopyToAsync($stdoutFile);$rawStreams[0].task=$stdoutTask
 $rawStreams[1].source=$p.StandardError.BaseStream
 $stderrTask=$p.StandardError.BaseStream.CopyToAsync($stderrFile);$rawStreams[1].task=$stderrTask

 [ordered]@{pid=$p.Id;path=$exe;startedAt=$p.StartTime.ToUniversalTime().ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'owned-process.json')
  $deadline=[DateTime]::UtcNow.AddSeconds(6)
  do{$p.Refresh();Assert-Background $p.Id $dir $foregroundBefore;if($p.HasExited){throw 'Renderer exited before capture'};if([DateTime]::UtcNow -gt $deadline){throw 'Renderer window deadline'};Start-Sleep -Milliseconds 100}while($null -eq $p.MainWindowHandle -or $p.MainWindowHandle -eq [IntPtr]::Zero)
  $hwnd=$p.MainWindowHandle
  $foregroundAfter=[FactoryDesktop]::GetForegroundWindow()
  [ordered]@{foregroundBefore=$foregroundBefore.ToInt64();foregroundAfter=$foregroundAfter.ToInt64();ownedWindow=$hwnd.ToInt64();createNoWindow=$true}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'launch-observation.json')
  if($foregroundAfter -eq $hwnd){throw 'Background-only guard: owned window activated'}
  Assert-OwnedWindow $p.Id $exe $ownedStartedAt $hwnd
  # Keep ordinary test window behind user's windows, without activation.
  if(-not [FactoryDesktop]::SetWindowPos($hwnd,[IntPtr]::new(1),0,0,0,0,0x0013)){throw 'Background placement failed'}
  for($pause=0;$pause -lt 5;$pause++){Assert-Background $p.Id $dir $foregroundBefore;Start-Sleep -Milliseconds 100}
  Check-Lock
  Assert-OwnedWindow $p.Id $exe $ownedStartedAt $hwnd
  $target=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt;hwnd=$hwnd.ToInt64();lockOwner=$LockOwner}
  $workerRoot=Join-Path $dir 'uia-worker'
  $workerGuard={Assert-OwnedWindow $p.Id $exe $ownedStartedAt $hwnd;Assert-Background $p.Id $dir $foregroundBefore;Check-Lock;if($p.HasExited){throw 'Owned renderer exited before UIA worker'}}
  $workerResult=Invoke-StackUiaSnapshotWorker $target $workerRoot $workerGuard $uiaWorkerSourceRoot
  $uia=Get-Content -Raw -LiteralPath $workerResult.snapshotPath|ConvertFrom-Json
  Assert-Background $p.Id $dir $foregroundBefore
  $uia|ConvertTo-Json -Depth 80|Set-Content -Encoding UTF8 (Join-Path $dir 'native.uia.json')
  $fgAtCapture=([FactoryDesktop]::GetForegroundWindow() -eq $hwnd)
  if($fgAtCapture){throw 'Background-only guard: owned window foreground at capture'}
  $guard={Assert-OwnedWindow $p.Id $exe $ownedStartedAt $hwnd;Assert-Background $p.Id $dir $foregroundBefore;Check-Lock;if($p.HasExited){throw 'Owned renderer exited before pixels'}}
  $pixels=Capture-FactoryPixels $hwnd $p.Id $dir $guard
  Assert-Background $p.Id $dir $foregroundBefore
  $closeSourceGuard={
   Assert-StackLifecycleSource $packagePath $CompileReceiptHash $ExeHash | Out-Null
   if((Get-FileHash $closeHelper).Hash.ToLowerInvariant() -ne 'd0898e1a2ebdefce64fbf5b16cbc3b9f72578e2f0efb649ee001c182f7aaec7c'){throw 'Owned close helper drift'}
   if((Get-FileHash (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256 -or (Get-FileHash (Join-Path $packagePath $receiptRelative)).Hash.ToLowerInvariant() -ne $CompileReceiptHash -or (Get-FileHash $exe).Hash.ToLowerInvariant() -ne $ExeHash){throw 'Owned close source/exe lineage drift'}
      foreach($binding in $plan.sourceBindings){
    $closeInput=[IO.Path]::GetFullPath((Join-Path $packagePath $binding.path))
    if(-not $closeInput.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $closeInput).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Owned close host source drift'}
   }
   if((Get-FileHash -LiteralPath $plan.rendererPath).Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Owned close renderer drift'}
   $actual=@((Join-Path $plan.bridgePackagePath 'Package.swift'))+@(Get-ChildItem -LiteralPath (Join-Path $plan.bridgePackagePath 'Sources') -Recurse -File|ForEach-Object{$_.FullName})
   $expected=@($plan.bridgeBindings|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $_.path))})
   if($actual.Count -ne $expected.Count -or @($actual|Where-Object{$expected -notcontains $_}).Count){throw 'Owned close bridge membership drift'}
   foreach($binding in $plan.bridgeBindings){
    $closeInput=[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $binding.path))
    if(-not $closeInput.StartsWith($plan.bridgePackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $closeInput).Hash.ToLowerInvariant() -ne $binding.sha256){throw 'Owned close bridge byte drift'}
   }
  }
  [uint32]$closePID=0
  [FactoryDesktop]::GetWindowThreadProcessId($hwnd,[ref]$closePID)|Out-Null
  $close=Request-FactoryOwnedClose $hwnd $p.Id $closePID {Assert-OwnedWindow $p.Id $exe $ownedStartedAt $hwnd} $closeSourceGuard {Check-Lock} {Assert-Background $p.Id $dir $foregroundBefore} {param($target,$message,$w,$l) [FactoryDesktop]::PostMessage($target,$message,$w,$l)}
  $close|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'owned-close.json')
  $exitDeadline=[DateTime]::UtcNow.AddSeconds(15)
  while(-not $p.WaitForExit(100)){
   Assert-Background $p.Id $dir $foregroundBefore;Check-Lock
   if([DateTime]::UtcNow -gt $exitDeadline){throw 'Owned renderer child deadline'}
  }
  Assert-Background $p.Id $dir $foregroundBefore
  if(-not $stdoutTask.Wait(5000) -or -not $stderrTask.Wait(5000)){throw 'Owned output stream deadline'}
  Complete-FactoryRawStreams $rawStreams
  $hostOutput=Get-Content -Raw (Join-Path $dir 'host.stdout.txt')
  $validHost=($p.ExitCode -eq 0 -and $hostOutput -match 'FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto' -and $hostOutput -match 'FACTORY_RENDERER_READY' -and $hostOutput -match 'FACTORY_COMMIT' -and $hostOutput -notmatch 'FACTORY_(RENDER|STARTUP)_ERROR')
  $records += [ordered]@{diagnosticScope=$plan.diagnosticScope;diagnosticPlanHash=$StackPlanHash;diagnosticMainHash='sha256:1463629c6136d2dd1bf47b2ff21bfefcc3273f8d606608e3c10c5267062348a1';foregroundBeforeLaunch=$foregroundBefore.ToInt64();foregroundAfterWindow=$foregroundAfter.ToInt64();activationVeto='thread-cbt';hostValid=$validHost;probeForegroundAtCapture=$fgAtCapture;dpiAwarenessRequested='per-monitor-v2';backgroundPlacementRequested=$true;index=$i;case=$plan.case;manifestHash=$plan.manifestHash;exitCode=$p.ExitCode;exeSha256=$compiled.exeSha256;rendererSha256=$plan.rendererSha256;sourceHash=$plan.sourceHash;compileReceiptHash=$CompileReceiptHash;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;captureMethod='UIA+PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT)+CopyFromScreen';occlusionQualified=$false;nativeParity='hold';frozenTupleBound=$false;closureBinding=$null;reason='Diagnostic host lifecycle localization only; excluded from native repetition/parity evidence';files=@(Get-ChildItem -LiteralPath $dir -File|ForEach-Object{[ordered]@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})}
 } catch {$primaryError=$_} finally {
  try{$preCleanupExitObservation=[ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');kernelWaitResult=[FactoryProcessWaitV6]::WaitForSingleObject($p.Handle,0);hasExitedObserved=[bool]$p.HasExited;rawStreams=@($rawStreams|ForEach-Object{Get-FactoryRawStreamState $_})}}catch{$streamErrors+=('Pre-cleanup exit observation: '+[string]$_)}
  try{$cleanupResult=Invoke-FactoryOwnedCleanup $p $exe $ownedStartedAt -KnownStartedIdentity}catch{$cleanupResult=[ordered]@{confirmedOwnedExit=$false;status='cleanup-helper-error';error=[string]$_}}
  if(-not $cleanupResult.confirmedOwnedExit){try{Write-FactoryDiagnosticJson (Join-Path $dir 'owned-exit-failure.json') ([ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');preCleanupExitObservation=$preCleanupExitObservation;cleanup=$cleanupResult})}catch{$streamErrors+=('Owned exit diagnostic receipt: '+[string]$_)}}
  foreach($stream in $rawStreams){
   if($stream.sealed){continue}
   try{if($null -eq $stream.task){throw 'Raw stream setup incomplete'};if(-not $stream.task.Wait(5000)){throw 'Raw stream completion deadline'};$stream.task.GetAwaiter().GetResult();$stream.copyCompleted=$true}catch{$streamErrors+=($stream.name+': '+[string]$_)}
   if(-not $stream.copyCompleted){try{Write-FactoryDiagnosticJson (Join-Path $dir ($stream.name+'.raw-copy-failure.json')) ([ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');qualification='diagnostic-partial';stream=Get-FactoryRawStreamState $stream;cleanup=$cleanupResult;primaryError=if($null -ne $primaryError){[string]$primaryError}else{''}})}catch{$streamErrors+=($stream.name+' diagnostic receipt: '+[string]$_)}}
   try{if($null -ne $stream.file){Close-FactoryRawStreamDestination $stream}}catch{$streamErrors+=($stream.name+' destination closure: '+[string]$_)}
  }
  foreach($raw in @('host.stdout.txt','host.stderr.txt')){try{if(-not(Test-Path (Join-Path $dir $raw))){[IO.File]::WriteAllBytes((Join-Path $dir $raw),[byte[]]@())}}catch{$streamErrors+=('raw setup: '+[string]$_)}}
  $rawStates=@($rawStreams|ForEach-Object{Get-FactoryRawStreamState $_});$stdoutHashState=Get-FactoryRawHash (Join-Path $dir 'host.stdout.txt') $rawStates[0];$stderrHashState=Get-FactoryRawHash (Join-Path $dir 'host.stderr.txt') $rawStates[1]
  foreach($hashState in @($stdoutHashState,$stderrHashState)){if($hashState.qualification -eq 'unqualified'){$streamErrors+=('Raw hash unqualified: '+$hashState.reason+' '+$hashState.error)}}
  try{[ordered]@{diagnosticScope=$plan.diagnosticScope;diagnosticPlanHash=$StackPlanHash;diagnosticLineage=$plan.diagnosticLineage;ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt};lockOwner=$LockOwner;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;sourceHash=$plan.sourceHash;macSourceProofHash=$null;primaryError=if($null -ne $primaryError){[string]$primaryError}else{''};preCleanupExitObservation=$preCleanupExitObservation;cleanup=$cleanupResult;streamErrors=$streamErrors;rawStreams=$rawStates;rawHashStates=[ordered]@{stdout=$stdoutHashState;stderr=$stderrHashState};rawHashesQualification=if($stdoutHashState.qualification -eq 'unqualified' -or $stderrHashState.qualification -eq 'unqualified'){'unqualified'}elseif(@($rawStreams|Where-Object{-not $_.sealed}).Count){'diagnostic-partial'}else{'sealed-raw'};stdoutSha256=$stdoutHashState.sha256;stderrSha256=$stderrHashState.sha256}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $dir 'capture-outcome.json')}catch{$streamErrors+=('outcome receipt: '+[string]$_)}
 }
 Assert-FactoryCaptureOutcome $primaryError $cleanupResult $streamErrors
}
foreach($record in $records){$record.files=@(Get-ChildItem -LiteralPath (Join-Path $outputPath ('native-{0:00}' -f $record.index)) -File|ForEach-Object{[ordered]@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})}
if((Get-FileHash $cleanupHelper).Hash.ToLowerInvariant() -ne 'cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13'){throw 'Cleanup helper drift after capture'}
if((Get-FileHash $sealHelper).Hash.ToLowerInvariant() -ne '4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'){throw 'Stream seal helper drift after capture'}
if((Get-FileHash $closeHelper).Hash.ToLowerInvariant() -ne 'd0898e1a2ebdefce64fbf5b16cbc3b9f72578e2f0efb649ee001c182f7aaec7c'){throw 'Owned close helper drift after capture'}
Check-Lock
if((Get-FileHash -LiteralPath $plan.rendererPath).Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Renderer drift after native batch'}
if((Get-FileHash (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256){throw 'Plan drift after capture'}
if((Get-FileHash (Join-Path $packagePath $receiptRelative)).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Compile receipt drift after capture'}
if((Get-FileHash $exe).Hash.ToLowerInvariant() -ne $ExeHash){throw 'Host binary drift after capture'}
foreach($binding in $plan.sourceBindings){
 $sourceInput=[IO.Path]::GetFullPath((Join-Path $packagePath $binding.path))
 if(-not $sourceInput.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $sourceInput).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Host source drift after capture'}
}
if((Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Host input helper drift after capture'}
if((Get-FileHash $pixelHelper).Hash.ToLowerInvariant() -ne '7172bf8d69f2523672dc57e6ba2889951ea4db4a89100b8b5b42c2bdef2da6ef'){throw 'Pixel helper drift after capture'}
$actualBridgeFiles=@((Join-Path $plan.bridgePackagePath 'Package.swift'))+@(Get-ChildItem -LiteralPath (Join-Path $plan.bridgePackagePath 'Sources') -Recurse -File|ForEach-Object{$_.FullName})
$expectedBridgeFiles=@($plan.bridgeBindings|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $_.path))})
if($actualBridgeFiles.Count -ne $expectedBridgeFiles.Count -or @($actualBridgeFiles|Where-Object{$expectedBridgeFiles -notcontains $_}).Count -ne 0){throw 'Staged bridge membership drift'}
foreach($binding in $plan.bridgeBindings){
 $bridgeInput=[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $binding.path))
 if(-not $bridgeInput.StartsWith($plan.bridgePackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $bridgeInput).Hash.ToLowerInvariant() -ne $binding.sha256){throw 'Bridge source drift'}
}
Assert-StackLifecycleSource $packagePath $CompileReceiptHash $ExeHash | Out-Null
$records|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $outputPath 'native-observation.json')

if(@($records|Where-Object{-not $_.hostValid}).Count -gt 0){throw 'Native observations contain renderer failures'}
