# Run only from interactive session under coordinator-owned desktop.lock.
# Uses targeted UIA reads. No global input, foreground/focus or lock mutation.
param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$LockOwner,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$CompileReceiptHash,[Parameter(Mandatory=$true)][string]$ExeHash,[Parameter(Mandatory=$true)][string]$SerializerControlSha256,[ValidateSet(1,20)][int]$Count=1,[Parameter(Mandatory=$true)][string]$IssuedMetadataPath,[Parameter(Mandatory=$true)][string]$IssuedMetadataHash)
$ErrorActionPreference='Stop'
$captureRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cleanupHelper=Join-Path $captureRoot 'support\cleanup.ps1'
if((Get-FileHash $cleanupHelper).Hash.ToLowerInvariant() -ne 'a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7'){throw 'Cleanup helper drift'}
. $cleanupHelper
$sealHelper=Join-Path $captureRoot 'support\stream-seal.ps1'
if((Get-FileHash $sealHelper).Hash.ToLowerInvariant() -ne '4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'){throw 'Stream seal helper drift'}
. $sealHelper
$closeHelper=Join-Path $captureRoot 'support\owned-close.ps1'
if((Get-FileHash $closeHelper).Hash.ToLowerInvariant() -ne 'd0898e1a2ebdefce64fbf5b16cbc3b9f72578e2f0efb649ee001c182f7aaec7c'){throw 'Owned close helper drift'}
. $closeHelper
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$' -or $SerializerControlSha256 -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe/serializer control pins required'}
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) { throw 'Native capture requires interactive desktop task' }
$timingHelper=Join-Path $captureRoot 'support\lifecycle-timing.ps1'
if((Get-FileHash $timingHelper).Hash.ToLowerInvariant() -cne 'c6951ea443587b3027141f4d08ddc942b8d364a7b920bee16e3a5cc76b7c62a5'){throw 'Lifecycle timing helper drift'}
. $timingHelper
$rootManifest=Get-Content -Raw (Join-Path $captureRoot 'root-stage-manifest.json')|ConvertFrom-Json
$bindingEntry=@($rootManifest.files|Where-Object{$_.path -eq 'factory/native/windows/padding-capture-lease-capture-v3/integration-bindings.json'})
if($bindingEntry.Count -ne 1 -or $bindingEntry[0].sha256 -ne ('sha256:'+(Get-FileHash -LiteralPath (Join-Path $captureRoot 'integration-bindings.json')).Hash.ToLowerInvariant()) -or $bindingEntry[0].bytes -ne (Get-Item -LiteralPath (Join-Path $captureRoot 'integration-bindings.json')).Length){throw 'Integration binding manifest drift'}
. (Join-Path $captureRoot 'support\integration.ps1')
Assert-FactoryIntegrationSources $captureRoot
. (Join-Path $captureRoot 'dependencies\uia-worker\invoke-worker.ps1')
. (Join-Path $captureRoot 'dependencies\uia-worker\schema.ps1')
. (Join-Path $captureRoot 'support\final-exit-certificate.ps1')
Initialize-FactoryFinalExitNative
. (Join-Path $captureRoot 'support\all-owned-release.ps1')
. (Join-Path $captureRoot 'dependencies\uia-worker\support\final-exit-certificate.ps1')
. (Join-Path $captureRoot 'support\first-proof.ps1')
$outputPath=[IO.Path]::GetFullPath($RunRoot)
if(-not $outputPath.StartsWith('D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output outside first capture lane'}
$pixelHelper=Join-Path $captureRoot 'support\pixels-background.ps1'
if((Get-FileHash -LiteralPath $pixelHelper).Hash.ToLowerInvariant() -ne '7172bf8d69f2523672dc57e6ba2889951ea4db4a89100b8b5b42c2bdef2da6ef'){throw 'Pixel helper drift'}
. $pixelHelper
$packagePath=[IO.Path]::GetFullPath($Package)
if(-not $packagePath.StartsWith('D:\Claude\swiftright\.factory-work\hosts\',[StringComparison]::OrdinalIgnoreCase)){throw 'Package outside compiled host workspace'}
$plan=Get-Content -Raw (Join-Path $packagePath 'plan.json')|ConvertFrom-Json
$approved=@{caseID='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258';sourceHash='sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b';planHash='ee83748cd42326e57676e47d8fec777bd8466706ba2c72a01eb9b5b71292de10';receiptRelative='build-capture-lease-r1\observation.json'}
$receiptRelative=$approved.receiptRelative
$capturePlan=Get-Content -Raw (Join-Path $captureRoot 'capture-plan.json')|ConvertFrom-Json
if($CompileReceiptHash -cne $capturePlan.actualBuild.compileReceiptSha256 -or $ExeHash -cne $capturePlan.actualBuild.exeSha256){throw 'Exact actual lease build receipt/exe pins required'}
$expectedOutput=if($Count -eq 1){$capturePlan.dispatch.first.runRoot}else{$capturePlan.dispatch.batch.runRoot}
if($outputPath -cne $expectedOutput){throw 'Exact fresh single/batch capture lane required'}
if($packagePath -cne $capturePlan.compiledHostPackagePath){throw 'Exact padding-window-diagnosis host package required'}
if($Count -eq 20){Assert-PaddingFirstCaptureProof -CaptureRoot $captureRoot -CompiledReceiptPath (Join-Path $packagePath $receiptRelative) -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256 -ExpectedRunRoot $capturePlan.dispatch.first.runRoot}
if($plan.case.id -cne $approved.caseID -or $plan.sourceHash -cne $approved.sourceHash){throw 'Exact padding window diagnosis source identity required'}
$buildPreflight=$capturePlan.launchPreflightPath
if(-not (Test-Path -LiteralPath $buildPreflight -PathType Leaf)){throw 'Reviewed build preflight missing'}
if((Get-FileHash -LiteralPath $buildPreflight).Hash.ToLowerInvariant() -ne $capturePlan.launchPreflightSha256.Replace('sha256:','')){throw 'Reviewed build preflight drift'}
& $buildPreflight -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256  | Out-Null
if($plan.executionEligible -ne $false -or $plan.hostMode -ne 'renderer'){throw 'Probe is not eligible native renderer host'}
if($plan.rendererPath -ne $capturePlan.renderer.rollingInputPath -or $plan.rendererSha256 -ne $capturePlan.renderer.sha256.Replace('sha256:','')){throw 'Unexpected renderer pin'}
if((Get-FileHash -LiteralPath (Join-Path $packagePath $receiptRelative)).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Expected compile receipt drift'}
$compiled=Get-Content -Raw (Join-Path $packagePath $receiptRelative)|ConvertFrom-Json
if(-not $compiled.planSha256 -or (Get-FileHash -LiteralPath (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256){throw 'Compile plan drift'}
if($compiled.exitCode -ne 0 -or $compiled.sourceHash -ne $plan.sourceHash -or $compiled.rendererSha256 -ne $plan.rendererSha256){throw 'Compile receipt mismatch'}

if(-not $approved -or $plan.case.id -ne $approved.caseID -or $plan.sourceHash -ne $approved.sourceHash -or $compiled.planSha256 -ne $approved.planHash -or $compiled.exeSha256 -ne $ExeHash){throw 'Pinned Round1 host required'}
if($plan.runtimeSourceCommit -ne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b' -or $compiled.runtimeSourceCommit -ne $plan.runtimeSourceCommit -or $compiled.runtimeSourceTreeHash -ne $plan.runtimeSourceTreeHash -or $compiled.timedOut -or -not $compiled.ownedExited){throw 'Fresh runtime compile lineage mismatch'}
$runtimeVerifier=Join-Path $captureRoot 'support\verify-runtime-source.ps1'
if((Get-FileHash $runtimeVerifier).Hash.ToLowerInvariant() -ne $plan.runtimeVerifierHash){throw 'Runtime verifier drift'}
. $runtimeVerifier
$hostInputs=Join-Path $captureRoot 'support\host-inputs.ps1'
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

$issuedMetadata=Assert-LeaseIssuedMetadata $IssuedMetadataPath $IssuedMetadataHash $outputPath $Count $CompileReceiptHash $ExeHash $SerializerControlSha256 $captureRoot
New-Item -ItemType Directory -Path $outputPath|Out-Null
Copy-Item -LiteralPath $IssuedMetadataPath -Destination (Join-Path $outputPath 'issued-metadata.json')
foreach($candidateFile in @('candidate-tuple.json','candidate-binding.json')){
 $candidateSource=Join-Path (Split-Path -Parent $IssuedMetadataPath) $candidateFile
 if(-not (Test-Path -LiteralPath $candidateSource -PathType Leaf)){throw ('Prelaunch candidate file missing: '+$candidateFile)}
 Copy-Item -LiteralPath $candidateSource -Destination (Join-Path $outputPath $candidateFile)
}
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
$records=@()
for($i=1;$i -le $Count;$i++){
 Check-Lock
 $dir=Join-Path $outputPath ('native-{0:00}' -f $i)
 if(Test-Path -LiteralPath $dir){throw 'Replay output exists; prepare fresh package'}
 New-Item -ItemType Directory -Path $dir|Out-Null
 $foregroundBefore=[FactoryDesktop]::GetForegroundWindow()
 $startInfo=[Diagnostics.ProcessStartInfo]::new($exe)
 $startInfo.Arguments='--factory-capture-lease-seconds=40'
 $startInfo.UseShellExecute=$false;$startInfo.CreateNoWindow=$true
 $startInfo.RedirectStandardOutput=$true;$startInfo.RedirectStandardError=$true
 if((Get-FileHash -LiteralPath $buildPreflight).Hash.ToLowerInvariant() -ne $capturePlan.launchPreflightSha256.Replace('sha256:','')){throw 'Reviewed build preflight drift before child launch'}
 & $buildPreflight -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256  | Out-Null
 $workerRoot=Join-Path $dir 'uia-worker'
 $workerAttempted=$false
 $inventory=[ordered]@{kind='factory-owned-uia-slot-inventory-v1';lockOwner=$LockOwner;rendererDirectory=$dir;roots=@($workerRoot);attempted=$false}
 Write-FactoryDiagnosticJson (Join-Path $dir 'declared-worker-inventory.json') $inventory
 $launchRequest=[ordered]@{utc=[DateTimeOffset]::UtcNow.ToString('o');ticks=[Diagnostics.Stopwatch]::GetTimestamp();frequency=[Diagnostics.Stopwatch]::Frequency}
 $p=$null;$launchReturn=$null
 $timingSamples=[Collections.Generic.List[object]]::new();$retainedTimingHandle=[IntPtr]::Zero
 $ownedStartedAt='';$stdoutFile=$null;$stderrFile=$null;$stdoutTask=$null;$stderrTask=$null
 $finalStart=$null;$workerResult=$null;$finalReleaseError='';$primaryError=$null;$cleanupResult=$null;$streamErrors=@();$preCleanupExitObservation=$null
 $rawStreams=@(@{name='stdout';task=$null;file=$null;source=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false},@{name='stderr';task=$null;file=$null;source=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false})
 try {
 $p=[Diagnostics.Process]::Start($startInfo)
 $retainedTimingHandle=$p.Handle
 $launchReturn=[ordered]@{utc=[DateTimeOffset]::UtcNow.ToString('o');ticks=[Diagnostics.Stopwatch]::GetTimestamp()}
 $timingSamples.Add((Get-FactoryLifecycleTimingSample 'launch-return' $p $retainedTimingHandle $rawStreams))
 $ownedStartedAt=$p.StartTime.ToUniversalTime().ToString('o')
 $finalStart=[ordered]@{pid=$p.Id;retainedHandle=$retainedTimingHandle.ToInt64();path=$exe;startedAt=$ownedStartedAt;lockOwner=$LockOwner;workerId=$dir;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash}
 Write-FactoryDiagnosticJson (Join-Path $dir 'final-start.json') $finalStart
 $allocated=@($issuedMetadata.captures|Where-Object{$_.run -eq $i})
 if($allocated.Count -ne 1){throw 'Unique allocated capture identity required'}
 Write-FactoryDiagnosticJson (Join-Path $dir 'measured-capture-identity.json') ([ordered]@{kind='factory-measured-capture-identity-v1';issuedMetadataHash=$IssuedMetadataHash;run=$i;captureID=$allocated[0].captureID;imageID=$allocated[0].imageID;plannedHostIdentity=$allocated[0].plannedHostIdentity;plannedClockIdentity=$allocated[0].plannedClockIdentity;ownedIdentity=$finalStart;measuredHostIdentity=[ordered]@{id=$allocated[0].plannedHostIdentity;hash=('sha256:'+$ExeHash);pid=$p.Id;path=$exe;startedAt=$ownedStartedAt};measuredClockIdentity=[ordered]@{clockId=$allocated[0].plannedClockIdentity;clockKind='process-local-stopwatch';frequency=[Diagnostics.Stopwatch]::Frequency;processID=$PID;ticks=$launchReturn.ticks;utc=$launchReturn.utc;crossProcessQualified=$false};clock=[ordered]@{kind='process-local-stopwatch';frequency=[Diagnostics.Stopwatch]::Frequency;processID=$PID;utc=$launchReturn.utc;ticks=$launchReturn.ticks;crossProcessQualified=$false}})
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
  $target=[pscustomobject]@{pid=$p.Id;hwnd=$hwnd.ToInt64();path=$exe;startedAt=$ownedStartedAt;lockOwner=$LockOwner}
  $workerGuard={Check-Lock;Assert-OwnedWindow $target.pid $target.path $target.startedAt ([IntPtr]::new([long]$target.hwnd));Assert-Background $target.pid $dir $foregroundBefore}
  Assert-FactoryIntegrationSources $captureRoot
  $workerAttempted=$true;$inventory.attempted=$true
  Write-FactoryDiagnosticJson (Join-Path $dir 'owned-worker-inventory.json') $inventory
  $workerResult=Invoke-FactoryUiaSnapshotWorker $target $workerRoot $workerGuard
  Assert-FactorySnapshotReady $workerResult $target
  Copy-Item -LiteralPath $workerResult.snapshotPath -Destination (Join-Path $dir 'native.uia.json')
  $ordering=[ordered]@{kind='factory-isolated-uia-parent-ordering-v1';issuedMetadataHash=$IssuedMetadataHash;rendererIdentity=$finalStart;parentProcessID=$PID;clockDomain='parent-process-local-stopwatch';frequency=[Diagnostics.Stopwatch]::Frequency;workerReceiptRef=$workerResult.workerReceiptPath;workerReceiptHash=$workerResult.workerReceiptSha256;workerFinalCertificateRef=$workerResult.finalCertificatePath;workerFinalCertificateHash=(Get-FileHash -LiteralPath $workerResult.finalCertificatePath).Hash.ToLowerInvariant();snapshotHash=$workerResult.snapshotSha256;workerVerifiedTicks=[Diagnostics.Stopwatch]::GetTimestamp();pixelsStartTicks=$null;pixelsEndTicks=$null;ownedCloseStartTicks=$null;ownedCloseEndTicks=$null;pixelReceiptRef=$null;pixelReceiptHash=$null;pixelSamples=@();ownedCloseReceiptRef=$null;ownedCloseReceiptHash=$null;crossProcessClockQualified=$false}
  Write-FactoryDiagnosticJson (Join-Path $dir 'capture-ordering-worker-ready.json') $ordering
  $fgAtCapture=([FactoryDesktop]::GetForegroundWindow() -eq $hwnd)
  if($fgAtCapture){throw 'Background-only guard: owned window foreground at capture'}
  $guard={Assert-OwnedWindow $p.Id $exe $ownedStartedAt $hwnd;Assert-Background $p.Id $dir $foregroundBefore;Check-Lock;if($p.HasExited){throw 'Owned renderer exited before pixels'}}
  Assert-FactorySnapshotReady $workerResult $target
  $ordering.pixelsStartTicks=[Diagnostics.Stopwatch]::GetTimestamp()
  Write-FactoryDiagnosticJson (Join-Path $dir 'capture-ordering-pixels-start.json') $ordering
  $pixels=Capture-FactoryPixels $hwnd $p.Id $dir $guard
  $ordering.pixelsEndTicks=[Diagnostics.Stopwatch]::GetTimestamp()
  $ordering.pixelReceiptRef=Join-Path $dir 'native.pixels.json'
  $ordering.pixelReceiptHash=(Get-FileHash -LiteralPath $ordering.pixelReceiptRef).Hash.ToLowerInvariant()
  $ordering.pixelSamples=@((Get-Content -Raw -LiteralPath $ordering.pixelReceiptRef|ConvertFrom-Json).samples)
  Write-FactoryDiagnosticJson (Join-Path $dir 'capture-ordering-pixels-complete.json') $ordering
  Assert-Background $p.Id $dir $foregroundBefore
  $closeSourceGuard={
   if((Get-FileHash $closeHelper).Hash.ToLowerInvariant() -ne 'd0898e1a2ebdefce64fbf5b16cbc3b9f72578e2f0efb649ee001c182f7aaec7c'){throw 'Owned close helper drift'}
   if((Get-FileHash (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256 -or (Get-FileHash (Join-Path $packagePath $receiptRelative)).Hash.ToLowerInvariant() -ne $CompileReceiptHash -or (Get-FileHash $exe).Hash.ToLowerInvariant() -ne $ExeHash){throw 'Owned close source/exe lineage drift'}
   if((Get-FileHash $runtimeVerifier).Hash.ToLowerInvariant() -ne $plan.runtimeVerifierHash -or (Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Owned close source verifier drift'}
   Assert-FactoryRuntimeSource $plan $packagePath
   Assert-HostCompilerInputs $packagePath $plan.sourceBindings
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
  Assert-FactorySnapshotReady $workerResult $target
  $ordering.ownedCloseStartTicks=[Diagnostics.Stopwatch]::GetTimestamp()
  Assert-CandidatePhaseAdmission ([pscustomobject]@{phase='close-pending';nativeWindowActions=0;compilerActions=0})
  Write-FactoryDiagnosticJson (Join-Path $dir 'capture-ordering-close-pending.json') $ordering
  $timingSamples.Add((Get-FactoryLifecycleTimingSample 'owned-close-request' $p $retainedTimingHandle $rawStreams))
  $close=Request-FactoryOwnedClose $hwnd $p.Id $closePID {Assert-OwnedWindow $p.Id $exe $ownedStartedAt $hwnd} $closeSourceGuard {Check-Lock} {Assert-Background $p.Id $dir $foregroundBefore} {param($target,$message,$w,$l) [FactoryDesktop]::PostMessage($target,$message,$w,$l)}
  $close|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dir 'owned-close.json')
  $exitDeadline=[DateTime]::UtcNow.AddSeconds(15)
  $ordering.ownedCloseEndTicks=[Diagnostics.Stopwatch]::GetTimestamp()
  $ordering.ownedCloseReceiptRef=Join-Path $dir 'owned-close.json'
  $ordering.ownedCloseReceiptHash=(Get-FileHash -LiteralPath $ordering.ownedCloseReceiptRef).Hash.ToLowerInvariant()
  Write-FactoryDiagnosticJson (Join-Path $dir 'capture-ordering.json') $ordering
  $timingSamples.Add((Get-FactoryLifecycleTimingSample 'owned-close-return' $p $retainedTimingHandle $rawStreams))
  while(-not $p.WaitForExit(100)){
   Assert-Background $p.Id $dir $foregroundBefore;Check-Lock
   $timingSamples.Add((Get-FactoryLifecycleTimingSample 'native-exit-poll' $p $retainedTimingHandle $rawStreams))
   if([DateTime]::UtcNow -gt $exitDeadline){throw 'Owned renderer child deadline'}
  }
  Assert-Background $p.Id $dir $foregroundBefore
  $timingSamples.Add((Get-FactoryLifecycleTimingSample 'native-exit-wait-return' $p $retainedTimingHandle $rawStreams))
  $timingSamples.Add((Get-FactoryLifecycleTimingSample 'raw-eof-wait-start' $p $retainedTimingHandle $rawStreams))
  if(-not $stdoutTask.Wait(5000) -or -not $stderrTask.Wait(5000)){throw 'Owned output stream deadline'}
  $timingSamples.Add((Get-FactoryLifecycleTimingSample 'raw-eof-wait-return' $p $retainedTimingHandle $rawStreams))
  Complete-FactoryRawStreams $rawStreams
  $hostOutput=Get-Content -Raw (Join-Path $dir 'host.stdout.txt')
  $validHost=($p.ExitCode -eq 0 -and $hostOutput -match 'FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto' -and $hostOutput -match 'FACTORY_RENDERER_READY' -and $hostOutput -match 'FACTORY_COMMIT' -and $hostOutput -notmatch 'FACTORY_(RENDER|STARTUP)_ERROR')
  if(-not $validHost){throw 'Owned host output failed original validity predicate'}
   $records += [ordered]@{foregroundBeforeLaunch=$foregroundBefore.ToInt64();foregroundAfterWindow=$foregroundAfter.ToInt64();activationVeto='thread-cbt';hostValid=$validHost;probeForegroundAtCapture=$fgAtCapture;dpiAwarenessRequested='per-monitor-v2';backgroundPlacementRequested=$true;index=$i;case=$plan.case;manifestHash=$plan.manifestHash;exitCode=$p.ExitCode;exeSha256=$compiled.exeSha256;rendererSha256=$plan.rendererSha256;sourceHash=$plan.sourceHash;compileReceiptHash=$CompileReceiptHash;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;candidateTupleRef=$issuedMetadata.candidateTuple;candidateBindingRef=$issuedMetadata.sourceBoundCandidateTuple;captureMethod='UIA+PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT)+CopyFromScreen';occlusionQualified=$false;nativeParity='hold';frozenTupleBound=$false;closureBinding=$null;reason='Single source-bound observation only; provider exports, tuple qualification &parity remain held';files=@(Get-ChildItem -LiteralPath $dir -File|ForEach-Object{[ordered]@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})}
 } catch {$primaryError=$_} finally {
  try{$timingSamples.Add((Get-FactoryLifecycleTimingSample 'pre-original-cleanup' $p $retainedTimingHandle $rawStreams))}catch{$streamErrors+=('Lifecycle timing precleanup: '+[string]$_)}
  try{$preCleanupExitObservation=[ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');kernelWaitResult=[FactoryProcessWaitV5]::WaitForSingleObject($p.Handle,0);hasExitedObserved=[bool]$p.HasExited;rawStreams=@($rawStreams|ForEach-Object{Get-FactoryRawStreamState $_})}}catch{$streamErrors+=('Pre-cleanup exit observation: '+[string]$_)}
  try{$cleanupResult=Invoke-FactoryOwnedCleanup $p $exe $ownedStartedAt -KnownStartedIdentity}catch{$cleanupResult=[ordered]@{confirmedOwnedExit=$false;status='cleanup-helper-error';error=[string]$_}}
  try{$timingSamples.Add((Get-FactoryLifecycleTimingSample 'post-original-cleanup' $p $retainedTimingHandle $rawStreams))}catch{$streamErrors+=('Lifecycle timing postcleanup: '+[string]$_)}
  if(-not $cleanupResult.confirmedOwnedExit){try{Write-FactoryDiagnosticJson (Join-Path $dir 'owned-exit-failure.json') ([ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');preCleanupExitObservation=$preCleanupExitObservation;cleanup=$cleanupResult})}catch{$streamErrors+=('Owned exit diagnostic receipt: '+[string]$_)}}
  foreach($stream in $rawStreams){
   if($stream.sealed){continue}
   try{if($null -eq $stream.task){throw 'Raw stream setup incomplete'};if(-not $stream.task.Wait(5000)){throw 'Raw stream completion deadline'};$stream.task.GetAwaiter().GetResult();$stream.copyCompleted=$true}catch{$streamErrors+=($stream.name+': '+[string]$_)}
   if(-not $stream.copyCompleted){try{Write-FactoryDiagnosticJson (Join-Path $dir ($stream.name+'.raw-copy-failure.json')) ([ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');qualification='diagnostic-partial';stream=Get-FactoryRawStreamState $stream;cleanup=$cleanupResult;primaryError=if($null -ne $primaryError){[string]$primaryError}else{''}})}catch{$streamErrors+=($stream.name+' diagnostic receipt: '+[string]$_)}}
   try{if($null -ne $stream.file){Close-FactoryRawStreamDestination $stream}}catch{$streamErrors+=($stream.name+' destination closure: '+[string]$_)}
  }
  foreach($raw in @('host.stdout.txt','host.stderr.txt')){try{if(-not(Test-Path (Join-Path $dir $raw))){[IO.File]::WriteAllBytes((Join-Path $dir $raw),[byte[]]@())}}catch{$streamErrors+=('raw setup: '+[string]$_)}}
  $rawStates=@($rawStreams|ForEach-Object{Get-FactoryRawStreamState $_})
  $stdoutHashState=Get-FactoryRawHash (Join-Path $dir 'host.stdout.txt') $rawStates[0]
  $stderrHashState=Get-FactoryRawHash (Join-Path $dir 'host.stderr.txt') $rawStates[1]
  foreach($hashState in @($stdoutHashState,$stderrHashState)){if($hashState.qualification -ne 'sealed-raw'){$streamErrors+=('Raw hash not sealed: '+$hashState.qualification+' '+$hashState.reason+' '+$hashState.error)}}
  $rawQualification=if($stdoutHashState.qualification -eq 'unqualified' -or $stderrHashState.qualification -eq 'unqualified'){'unqualified'}elseif($stdoutHashState.qualification -eq 'diagnostic-partial' -or $stderrHashState.qualification -eq 'diagnostic-partial'){'diagnostic-partial'}else{'sealed-raw'}
  try{$timingSamples.Add((Get-FactoryLifecycleTimingSample 'raw-closure-final' $p $retainedTimingHandle $rawStreams));[ordered]@{kind='padding-window-retained-handle-timing-v1';launchRequest=$launchRequest;launchReturn=$launchReturn;ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt};compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;stdoutSha256=$stdoutHashState.sha256;stderrSha256=$stderrHashState.sha256;rawHashesQualification=$rawQualification;nativeExitDeadlineSeconds=15;rawDrainMilliseconds=5000;observations=$timingSamples.ToArray();authority='observational only; cleanup certificate remains original helper'}|ConvertTo-Json -Depth 16|Set-Content -Encoding UTF8 (Join-Path $dir 'lifecycle-timing.json')}catch{$streamErrors+=('Lifecycle timing receipt: '+[string]$_)}
  try{[ordered]@{ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt};lockOwner=$LockOwner;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;sourceHash=$plan.sourceHash;primaryError=if($null -ne $primaryError){[string]$primaryError}else{''};preCleanupExitObservation=$preCleanupExitObservation;cleanup=$cleanupResult;streamErrors=$streamErrors;rawStreams=$rawStates;rawHashesQualification=$rawQualification;stdoutSha256=$stdoutHashState.sha256;stderrSha256=$stderrHashState.sha256}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $dir 'capture-outcome.json')}catch{$streamErrors+=('outcome receipt: '+[string]$_)}
  if(-not $workerAttempted){try{Write-FactoryDiagnosticJson (Join-Path $dir 'owned-worker-inventory.json') $inventory;Write-FactoryDiagnosticJson (Join-Path $dir 'uia-no-start.json') ([ordered]@{kind='factory-uia-slot-no-start-v1';root=$workerRoot;lockOwner=$LockOwner;rendererDirectory=$dir;attempted=$false;noInvocationConfirmed=$true})}catch{}}
  # Separate release-only snapshot; never changes original outcome/cleanup/errors.
  try{
   Assert-FactoryIntegrationSources $captureRoot
   $finalStreams=@()
   for($rawIndex=0;$rawIndex -lt 2;$rawIndex++){
    $rawState=$rawStates[$rawIndex]|ConvertTo-Json -Depth 16|ConvertFrom-Json
    $rawPath=Join-Path $dir (@('host.stdout.txt','host.stderr.txt')[$rawIndex])
    $rawHash=Get-FactoryRawHash $rawPath $rawState
    $rawState|Add-Member path $rawPath
    $rawState|Add-Member sha256 $rawHash.sha256
    $finalStreams+=@($rawState)
   }
   $finalSample=Get-FactoryFinalExitSample $retainedTimingHandle $finalStart
   $finalCertificate=New-FactoryFinalExitCertificate $finalSample $finalStart $finalStreams
   $finalPath=Join-Path $dir 'final-exit-certificate.json'
   Write-FactoryDiagnosticJson $finalPath $finalCertificate
   Write-FactoryDiagnosticJson (Join-Path $dir 'terminal-worker.json') ([ordered]@{kind='factory-terminal-worker-v1';terminalResultConfirmed=$true;start=$finalStart;finalCertificateRef=$finalPath;finalCertificateHash=(Get-FileHash -LiteralPath $finalPath).Hash.ToLowerInvariant();originalOutcomeRef=(Join-Path $dir 'capture-outcome.json');originalOutcomeHash=(Get-FileHash -LiteralPath (Join-Path $dir 'capture-outcome.json')).Hash.ToLowerInvariant()})
  }catch{$finalReleaseError=[string]$_;try{Write-FactoryDiagnosticJson (Join-Path $dir 'final-release-hold.json') ([ordered]@{qualification='failed-or-successful-observation-only';error=$finalReleaseError})}catch{# Original primary outcome retains priority.
  }}

 }
 Assert-FactoryCaptureOutcome $primaryError $cleanupResult $streamErrors
}
foreach($record in $records){$record.files=@(Get-ChildItem -LiteralPath (Join-Path $outputPath ('native-{0:00}' -f $record.index)) -File|ForEach-Object{[ordered]@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})}
if((Get-FileHash $cleanupHelper).Hash.ToLowerInvariant() -ne 'a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7'){throw 'Cleanup helper drift after capture'}
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
