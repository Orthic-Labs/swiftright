# Run only from interactive session under coordinator-owned desktop.lock.
# Uses targeted UIA reads. No global input, foreground/focus or lock mutation.
param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$LockOwner,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$CompileReceiptHash,[Parameter(Mandatory=$true)][string]$ExeHash)
$ErrorActionPreference='Stop'
$cleanupHelper=Join-Path $PSScriptRoot 'cleanup.ps1'
if((Get-FileHash $cleanupHelper).Hash.ToLowerInvariant() -ne '8fe6b669fcad351e2367ec4af6d143567bc8795b666ce7e780fd96ca4e4be462'){throw 'Cleanup helper drift'}
. $cleanupHelper
$sealHelper=Join-Path $PSScriptRoot 'stream-seal.ps1'
if((Get-FileHash $sealHelper).Hash.ToLowerInvariant() -ne '1ea23fcde17a985952d034170bb8ff56213de6eba76943c876ee7636ecc82199'){throw 'Stream seal helper drift'}
. $sealHelper
$closeHelper=Join-Path $PSScriptRoot 'owned-close.ps1'
if((Get-FileHash $closeHelper).Hash.ToLowerInvariant() -ne '776f10bc893f658098b1626bf950edccad82b0e84fda0ce4f44e3caa8b09dd46'){throw 'Owned close helper drift'}
. $closeHelper
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe pins required'}
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) { throw 'Native capture requires interactive desktop task' }
$outputPath=[IO.Path]::GetFullPath($RunRoot)
if(-not $outputPath.StartsWith('D:\Claude\swiftright\factory\native\windows\round1-native-v5\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output outside first capture lane'}
$pixelHelper=Join-Path $PSScriptRoot '..\pixels-background.ps1'
if((Get-FileHash -LiteralPath $pixelHelper).Hash.ToLowerInvariant() -ne '7172bf8d69f2523672dc57e6ba2889951ea4db4a89100b8b5b42c2bdef2da6ef'){throw 'Pixel helper drift'}
. $pixelHelper
$root='D:\Claude\swiftright\factory\native\windows\'
$packagePath=[IO.Path]::GetFullPath($Package)
if(-not $packagePath.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Package outside factory'}
$plan=Get-Content -Raw (Join-Path $packagePath 'plan.json')|ConvertFrom-Json
$approvedHosts=@{
 'D:\Claude\swiftright\factory\native\windows\round1-stack-layout-repair-v1\stack-overlay\package'=@{caseID='swiftui.stack-overlay.recipe/case/aac89c30fbc61515';sourceHash='sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee';planHash='8c89995f6eb23939a365d068b0eb3c8d407194a5cf1f720b9bdc71f01066e1e2';receiptRelative='build-r1\observation.json'}
 'D:\Claude\swiftright\factory\native\windows\round1-stack-layout-hosts-v1\custom-layout\package'=@{caseID='swiftui.custom-layout.recipe/case/b30ed0b185e8cb29';sourceHash='sha256:77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b';planHash='2ac073c551a52b7b3390c6e8c026bb7e2da989a1bf98f8a9bc87ca025b453124';receiptRelative='build-r1\observation.json'}
 'D:\Claude\swiftright\factory\native\windows\round1-next-hosts-v1\padding-frame\package'=@{caseID='swiftui.padding-frame.recipe/case/8805e6d0729b052d';sourceHash='sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b';planHash='6f1288f8b5860434e88a68212018310880a6cbff6a1736499543bdd302539e89';receiptRelative='build-v2-r1\observation.json'}
 'D:\Claude\swiftright\factory\native\windows\round1-next-hosts-v1\preference-key\package'=@{caseID='swiftui.preference-key.recipe/case/66b6b44aaff817d6';sourceHash='sha256:e104e949a6e0f8c6e9e41a6d2d7815a112a40e19d5919b82d2074fd7f5bf9c1f';planHash='b8347013716e2d13b1ac13bfd09191d9ca1f89d6deae20d7423c23997ae88e08';receiptRelative='build-v2-r1\observation.json'}
 'D:\Claude\swiftright\factory\native\windows\round1-scroll-host-v1\package'=@{caseID='swiftui.scroll-view.recipe/case/6716afb4fb55269b';sourceHash='sha256:cd6615468e11e0137c6e1c9ada25c0cdf2f5a0f4c33668ec63161674b743a2c4';planHash='87e220ea813bfc3a11fca006b1388865c1137f3d3cebd2f760baac96908ba904';receiptRelative='build-v3-r1\observation.json'}
}
$approved=$approvedHosts[$packagePath]
if(-not $approved){throw 'Exact supported host required'}
$receiptRelative=$approved.receiptRelative
if(-not $plan.executionEligible -or $plan.hostMode -ne 'renderer'){throw 'Probe is not eligible native renderer host'}
if($plan.stage -ne 'D:\Claude\sr0-r09' -or $plan.rendererSha256 -ne 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'){throw 'Unexpected stage or renderer pin'}
if((Get-FileHash -LiteralPath (Join-Path $packagePath $receiptRelative)).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Expected compile receipt drift'}
$compiled=Get-Content -Raw (Join-Path $packagePath $receiptRelative)|ConvertFrom-Json
if(-not $compiled.planSha256 -or (Get-FileHash -LiteralPath (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256){throw 'Compile plan drift'}
if($compiled.exitCode -ne 0 -or $compiled.sourceHash -ne $plan.sourceHash -or $compiled.rendererSha256 -ne $plan.rendererSha256){throw 'Compile receipt mismatch'}

if(-not $approved -or $plan.case.id -ne $approved.caseID -or $plan.sourceHash -ne $approved.sourceHash -or $compiled.planSha256 -ne $approved.planHash -or $compiled.exeSha256 -ne $ExeHash){throw 'Pinned Round1 host required'}
if($plan.runtimeSourceCommit -ne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b' -or $compiled.runtimeSourceCommit -ne $plan.runtimeSourceCommit -or $compiled.runtimeSourceTreeHash -ne $plan.runtimeSourceTreeHash -or $compiled.timedOut -or -not $compiled.ownedExited){throw 'Fresh runtime compile lineage mismatch'}
$runtimeVerifier=Join-Path $PSScriptRoot '..\verify-runtime-source.ps1'
if((Get-FileHash $runtimeVerifier).Hash.ToLowerInvariant() -ne $plan.runtimeVerifierHash){throw 'Runtime verifier drift'}
. $runtimeVerifier
$hostInputs=Join-Path $PSScriptRoot '..\round1-stack-layout-hosts-v1\shared\host-inputs.ps1'
if((Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Host input guard drift'}
. $hostInputs
Assert-FactoryRuntimeSource $plan $packagePath
Assert-HostCompilerInputs $packagePath $plan.sourceBindings
if((Get-FileHash (Join-Path $packagePath 'runtime-source-receipt.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'Runtime source receipt drift'}
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
if((Get-FileHash -LiteralPath 'D:\Claude\sr0-r09\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Renderer drift'}
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
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
function Read-UIA($node,[int]$depth=0) {
 if($depth -gt 40){throw 'UIA depth bound exceeded'}
 $c=$node.Current
 $record=[ordered]@{name=$c.Name;automationId=$c.AutomationId;controlType=$c.ControlType.ProgrammaticName;enabled=$c.IsEnabled;patterns=@($node.GetSupportedPatterns()|ForEach-Object{$_.ProgrammaticName});offscreen=$c.IsOffscreen;bounds=@($c.BoundingRectangle.X,$c.BoundingRectangle.Y,$c.BoundingRectangle.Width,$c.BoundingRectangle.Height);children=@()}
 $walker=[Windows.Automation.TreeWalker]::RawViewWalker
 $child=$walker.GetFirstChild($node);$count=0
 while($null -ne $child){if(++$count -gt 1000){throw 'UIA child bound exceeded'};$record.children+=Read-UIA $child ($depth+1);$child=$walker.GetNextSibling($child)}
 return $record
}
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
Copy-Item -LiteralPath (Join-Path $packagePath $receiptRelative) -Destination (Join-Path $outputPath 'observation.json')
Copy-Item -LiteralPath $hostInputs -Destination (Join-Path $outputPath 'host-inputs.ps1')
Copy-Item -LiteralPath $pixelHelper -Destination (Join-Path $outputPath 'pixels-background.ps1')
foreach($name in @('plan.json','Package.swift','runtime-source-receipt.json','runtime-source-tree.json')){Copy-Item -LiteralPath (Join-Path $packagePath $name) -Destination (Join-Path $outputPath $name)}
Copy-Item -LiteralPath (Join-Path $packagePath 'Sources') -Destination (Join-Path $outputPath 'Sources') -Recurse
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
 $primaryError=$null;$cleanupResult=$null;$streamErrors=@()
 $rawStreams=@(@{name='stdout';task=$null;file=$null;sealed=$false},@{name='stderr';task=$null;file=$null;sealed=$false})
 try {
 $ownedStartedAt=$p.StartTime.ToUniversalTime().ToString('o')
 $stdoutFile=[IO.File]::Open((Join-Path $dir 'host.stdout.txt'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$rawStreams[0].file=$stdoutFile
 $stderrFile=[IO.File]::Open((Join-Path $dir 'host.stderr.txt'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$rawStreams[1].file=$stderrFile
 $stdoutTask=$p.StandardOutput.BaseStream.CopyToAsync($stdoutFile);$rawStreams[0].task=$stdoutTask
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
  $element=[Windows.Automation.AutomationElement]::FromHandle($hwnd)
  if($null -eq $element -or $element.Current.ProcessId -ne $p.Id){throw 'UIA root ownership mismatch'}
  Assert-Background $p.Id $dir $foregroundBefore
  Assert-OwnedWindow $p.Id $exe $ownedStartedAt $hwnd
  $uia=Read-UIA $element
  Assert-Background $p.Id $dir $foregroundBefore
  $uia|ConvertTo-Json -Depth 80|Set-Content -Encoding UTF8 (Join-Path $dir 'native.uia.json')
  $fgAtCapture=([FactoryDesktop]::GetForegroundWindow() -eq $hwnd)
  if($fgAtCapture){throw 'Background-only guard: owned window foreground at capture'}
  $guard={Assert-OwnedWindow $p.Id $exe $ownedStartedAt $hwnd;Assert-Background $p.Id $dir $foregroundBefore;Check-Lock;if($p.HasExited){throw 'Owned renderer exited before pixels'}}
  $pixels=Capture-FactoryPixels $hwnd $p.Id $dir $guard
  Assert-Background $p.Id $dir $foregroundBefore
  $closeSourceGuard={
   if((Get-FileHash $closeHelper).Hash.ToLowerInvariant() -ne '776f10bc893f658098b1626bf950edccad82b0e84fda0ce4f44e3caa8b09dd46'){throw 'Owned close helper drift'}
   if((Get-FileHash (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256 -or (Get-FileHash (Join-Path $packagePath $receiptRelative)).Hash.ToLowerInvariant() -ne $CompileReceiptHash -or (Get-FileHash $exe).Hash.ToLowerInvariant() -ne $ExeHash){throw 'Owned close source/exe lineage drift'}
   if((Get-FileHash $runtimeVerifier).Hash.ToLowerInvariant() -ne $plan.runtimeVerifierHash -or (Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Owned close source verifier drift'}
   Assert-FactoryRuntimeSource $plan $packagePath
   Assert-HostCompilerInputs $packagePath $plan.sourceBindings
   foreach($binding in $plan.sourceBindings){
    $closeInput=[IO.Path]::GetFullPath((Join-Path $packagePath $binding.path))
    if(-not $closeInput.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $closeInput).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Owned close host source drift'}
   }
   if((Get-FileHash 'D:\Claude\sr0-r09\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Owned close renderer drift'}
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
  $records += [ordered]@{foregroundBeforeLaunch=$foregroundBefore.ToInt64();foregroundAfterWindow=$foregroundAfter.ToInt64();activationVeto='thread-cbt';hostValid=$validHost;probeForegroundAtCapture=$fgAtCapture;dpiAwarenessRequested='per-monitor-v2';backgroundPlacementRequested=$true;index=$i;case=$plan.case;manifestHash=$plan.manifestHash;exitCode=$p.ExitCode;exeSha256=$compiled.exeSha256;rendererSha256=$plan.rendererSha256;sourceHash=$plan.sourceHash;compileReceiptHash=$CompileReceiptHash;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;captureMethod='UIA+PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT)+CopyFromScreen';occlusionQualified=$false;nativeParity='hold';frozenTupleBound=$false;closureBinding=$null;reason='Single source-bound observation only; provider exports, tuple qualification &parity remain held';files=@(Get-ChildItem -LiteralPath $dir -File|ForEach-Object{[ordered]@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})}
 } catch {$primaryError=$_} finally {
  try{$cleanupResult=Invoke-FactoryOwnedCleanup $p $exe $ownedStartedAt -KnownStartedIdentity}catch{$cleanupResult=[ordered]@{confirmedOwnedExit=$false;status='cleanup-helper-error';error=[string]$_}}
  foreach($stream in $rawStreams){
   if($stream.sealed){continue}
   try{if($null -eq $stream.task){throw 'Raw stream setup incomplete'};if(-not $stream.task.Wait(5000)){throw 'Raw stream completion deadline'};$stream.task.GetAwaiter().GetResult()}catch{$streamErrors+=($stream.name+': '+[string]$_)}
   try{if($null -ne $stream.file){$stream.file.Flush($true)}}catch{$streamErrors+=($stream.name+' flush: '+[string]$_)}
   try{if($null -ne $stream.file){$stream.file.Dispose();$stream.sealed=$true}}catch{$streamErrors+=($stream.name+' close: '+[string]$_)}
  }
  foreach($raw in @('host.stdout.txt','host.stderr.txt')){try{if(-not(Test-Path (Join-Path $dir $raw))){[IO.File]::WriteAllBytes((Join-Path $dir $raw),[byte[]]@())}}catch{$streamErrors+=('raw setup: '+[string]$_)}}
  try{[ordered]@{ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt};lockOwner=$LockOwner;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;sourceHash=$plan.sourceHash;primaryError=if($null -ne $primaryError){[string]$primaryError}else{''};cleanup=$cleanupResult;streamErrors=$streamErrors;stdoutSha256=(Get-FileHash (Join-Path $dir 'host.stdout.txt')).Hash.ToLowerInvariant();stderrSha256=(Get-FileHash (Join-Path $dir 'host.stderr.txt')).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $dir 'capture-outcome.json')}catch{$streamErrors+=('outcome receipt: '+[string]$_)}
 }
 Assert-FactoryCaptureOutcome $primaryError $cleanupResult $streamErrors
}
foreach($record in $records){$record.files=@(Get-ChildItem -LiteralPath (Join-Path $outputPath ('native-{0:00}' -f $record.index)) -File|ForEach-Object{[ordered]@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})}
if((Get-FileHash $cleanupHelper).Hash.ToLowerInvariant() -ne '8fe6b669fcad351e2367ec4af6d143567bc8795b666ce7e780fd96ca4e4be462'){throw 'Cleanup helper drift after capture'}
if((Get-FileHash $sealHelper).Hash.ToLowerInvariant() -ne '1ea23fcde17a985952d034170bb8ff56213de6eba76943c876ee7636ecc82199'){throw 'Stream seal helper drift after capture'}
if((Get-FileHash $closeHelper).Hash.ToLowerInvariant() -ne '776f10bc893f658098b1626bf950edccad82b0e84fda0ce4f44e3caa8b09dd46'){throw 'Owned close helper drift after capture'}
Check-Lock
if((Get-FileHash -LiteralPath 'D:\Claude\sr0-r09\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Renderer drift after native batch'}
if((Get-FileHash (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256){throw 'Plan drift after capture'}
if((Get-FileHash (Join-Path $packagePath $receiptRelative)).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Compile receipt drift after capture'}
if((Get-FileHash $exe).Hash.ToLowerInvariant() -ne $ExeHash){throw 'Host binary drift after capture'}
foreach($binding in $plan.sourceBindings){
 $sourceInput=[IO.Path]::GetFullPath((Join-Path $packagePath $binding.path))
 if(-not $sourceInput.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $sourceInput).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Host source drift after capture'}
}
if((Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Host input helper drift after capture'}
if((Get-FileHash $pixelHelper).Hash.ToLowerInvariant() -ne '7172bf8d69f2523672dc57e6ba2889951ea4db4a89100b8b5b42c2bdef2da6ef'){throw 'Pixel helper drift after capture'}
Assert-FactoryRuntimeSource $plan $packagePath
Assert-HostCompilerInputs $packagePath $plan.sourceBindings
if((Get-FileHash (Join-Path $packagePath 'runtime-source-receipt.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'Runtime source receipt drift'}
$actualBridgeFiles=@((Join-Path $plan.bridgePackagePath 'Package.swift'))+@(Get-ChildItem -LiteralPath (Join-Path $plan.bridgePackagePath 'Sources') -Recurse -File|ForEach-Object{$_.FullName})
$expectedBridgeFiles=@($plan.bridgeBindings|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $_.path))})
if($actualBridgeFiles.Count -ne $expectedBridgeFiles.Count -or @($actualBridgeFiles|Where-Object{$expectedBridgeFiles -notcontains $_}).Count -ne 0){throw 'Staged bridge membership drift'}
foreach($binding in $plan.bridgeBindings){
 $bridgeInput=[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $binding.path))
 if(-not $bridgeInput.StartsWith($plan.bridgePackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $bridgeInput).Hash.ToLowerInvariant() -ne $binding.sha256){throw 'Bridge source drift'}
}
$records|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $outputPath 'native-observation.json')

if(@($records|Where-Object{-not $_.hostValid}).Count -gt 0){throw 'Native observations contain renderer failures'}
