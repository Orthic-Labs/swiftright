# Run only from interactive session under coordinator-owned desktop.lock.
# Uses targeted UIA reads. No global input, foreground/focus or lock mutation.
param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$LockOwner,[Parameter(Mandatory=$true)][string]$ProducerRoot,[Parameter(Mandatory=$true)][string]$AdmissionRoot,[Parameter(Mandatory=$true)][string]$ControlRoot,[Parameter(Mandatory=$true)][string]$OutputRoot,[Parameter(Mandatory=$true)][string]$IntegrationGuardPath,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IntegrationGuardHash,[Parameter(Mandatory=$true)][string]$SourceInputsPath,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SourceInputsHash,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$CompileReceiptHash,[Parameter(Mandatory=$true)][string]$ExeHash,[Parameter(Mandatory=$true)][string]$SerializerControlSha256,[ValidateSet(1)][int]$Count=1,[Parameter(Mandatory=$true)][string]$IssuedMetadataPath,[Parameter(Mandatory=$true)][string]$IssuedMetadataHash,[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
$overlayRoot=[IO.Path]::GetFullPath($PSScriptRoot)
. (Join-Path $overlayRoot 'final-plan-eligibility.ps1')
$captureRoot=[IO.Path]::GetFullPath($ProducerRoot)
$admissionRoot=[IO.Path]::GetFullPath($AdmissionRoot)
$controlRoot=[IO.Path]::GetFullPath($ControlRoot)
$outputRoot=[IO.Path]::GetFullPath($OutputRoot)
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
if(-not(Test-Path -LiteralPath $admissionRoot -PathType Container)){throw 'Explicit admission root missing'}
if (-not $PreflightOnly -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) { throw 'Native capture requires interactive desktop task' }
$timingHelper=Join-Path $captureRoot 'support\lifecycle-timing.ps1'
if((Get-FileHash $timingHelper).Hash.ToLowerInvariant() -cne 'c6951ea443587b3027141f4d08ddc942b8d364a7b920bee16e3a5cc76b7c62a5'){throw 'Lifecycle timing helper drift'}
. $timingHelper
$guardPath=[IO.Path]::GetFullPath($IntegrationGuardPath)
if((Get-FileHash -LiteralPath $guardPath).Hash.ToLowerInvariant() -cne $IntegrationGuardHash){throw 'Prefixed integration guard drift'}
. $guardPath
. (Join-Path $captureRoot 'dependencies\uia-worker\schema.ps1')
. (Join-Path $captureRoot 'support\final-exit-certificate.ps1')
Initialize-FactoryFinalExitNative
. (Join-Path $captureRoot 'support\all-owned-release.ps1')
. (Join-Path $captureRoot 'dependencies\uia-worker\support\final-exit-certificate.ps1')
. (Join-Path $captureRoot 'dependencies\uia-worker\schema.ps1')
$outputPath=[IO.Path]::GetFullPath($RunRoot)
if(-not $outputPath.StartsWith($outputRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output outside fresh capture lane'}
$pixelHelper=Join-Path $captureRoot 'support\pixels-background.ps1'
if((Get-FileHash -LiteralPath $pixelHelper).Hash.ToLowerInvariant() -ne '7172bf8d69f2523672dc57e6ba2889951ea4db4a89100b8b5b42c2bdef2da6ef'){throw 'Pixel helper drift'}
. $pixelHelper
$packagePath=[IO.Path]::GetFullPath($Package)
$plan=Get-Content -Raw (Join-Path $packagePath 'plan.json')|ConvertFrom-Json
$sourceInputs=[IO.Path]::GetFullPath($SourceInputsPath)
if(-not (Test-Path -LiteralPath $sourceInputs -PathType Leaf)){throw 'Circle source-input manifest missing'}
if((Get-FileHash -LiteralPath $sourceInputs).Hash.ToLowerInvariant() -cne $SourceInputsHash){throw 'Circle source-input manifest drift'}
$sourceDocument=Get-Content -Raw -LiteralPath $sourceInputs|ConvertFrom-Json
if($sourceDocument.kind -cne 'factory-circle-source-inputs-v1' -or $sourceDocument.count -ne 1 -or [string]::IsNullOrWhiteSpace($sourceDocument.caseID) -or [string]::IsNullOrWhiteSpace($sourceDocument.sourceHash) -or [string]::IsNullOrWhiteSpace($sourceDocument.tupleID)){throw 'Circle source-input identity incomplete'}
Assert-FactoryIntegrationSources $captureRoot $sourceDocument
$uiaWorkerPath=[IO.Path]::GetFullPath([string]$sourceDocument.uiaWorkerPath)
if([string]::IsNullOrWhiteSpace([string]$sourceDocument.uiaWorkerPath) -or $sourceDocument.uiaWorkerHash -notmatch '^[0-9a-f]{64}$' -or -not(Test-Path -LiteralPath $uiaWorkerPath -PathType Leaf) -or (Get-FileHash -LiteralPath $uiaWorkerPath).Hash.ToLowerInvariant() -cne $sourceDocument.uiaWorkerHash){throw 'Explicit admitted UIA worker overlay missing or drifted'}
. $uiaWorkerPath
if($CompileReceiptHash -cne $sourceDocument.compileReceiptHash -or $ExeHash -cne $sourceDocument.exeHash){throw 'Measured Circle compile/exe pins differ from source inputs'}
$capturePlanPath=[IO.Path]::GetFullPath([string]$sourceDocument.capturePlanPath)
if(-not (Test-Path -LiteralPath $capturePlanPath -PathType Leaf)){throw 'Measured Circle capture plan missing'}
if($sourceDocument.capturePlanHash -notmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $capturePlanPath).Hash.ToLowerInvariant() -cne $sourceDocument.capturePlanHash){throw 'Measured Circle capture plan drift'}
$receiptPath=[IO.Path]::GetFullPath([string]$sourceDocument.compileReceiptPath)
$capturePlan=Get-Content -Raw $capturePlanPath|ConvertFrom-Json
if(-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)){throw 'Measured Circle compile receipt missing'}
if($CompileReceiptHash -cne $sourceDocument.compileReceiptHash -or $ExeHash -cne $sourceDocument.exeHash){throw 'Exact Circle build pins required'}
if(-not $outputPath.StartsWith($outputRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Exact fresh Circle Count1 capture lane required'}
if($packagePath -cne [IO.Path]::GetFullPath([string]$sourceDocument.compiledHostPackagePath)){throw 'Compiled host package path differs from measured source inputs'}
if($plan.kind -ne 'factory-circle-compiler-plan-v1' -or $plan.candidate -ne 'swiftui.circle.fixed.pilot-next' -or $plan.case.id -cne $sourceDocument.caseID -or $plan.sourceHash -ne $sourceDocument.sourceHash -or $plan.tuple.id -ne $sourceDocument.tupleID){throw 'Circle package source identity mismatch'}
$buildPreflight=[IO.Path]::GetFullPath([string]$sourceDocument.buildPreflightPath)
if(-not (Test-Path -LiteralPath $buildPreflight -PathType Leaf)){throw 'Reviewed build preflight missing'}
if($sourceDocument.buildPreflightHash -notmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $buildPreflight).Hash.ToLowerInvariant() -ne $sourceDocument.buildPreflightHash){throw 'Reviewed Circle build preflight drift'}
& $buildPreflight -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256 -SourceInputsPath $sourceInputs -SourceInputsHash $SourceInputsHash -PlanPath (Join-Path $packagePath 'plan.json') -PlanHash $sourceDocument.planHash -CompileReceiptPath $receiptPath -ExePath ([string]$sourceDocument.exeRef.path) -RendererPath $sourceDocument.rendererPath -SerializerPath $sourceDocument.serializerRef.path | Out-Null
Assert-CircleFinalPlanAdmission $plan|Out-Null
if($plan.rendererPath -ne $sourceDocument.rendererPath -or $plan.rendererSha256 -ne $sourceDocument.rendererSha256){throw 'Unexpected Circle renderer pin'}
if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Measured Circle compile receipt drift'}
$compiled=Get-Content -Raw $receiptPath|ConvertFrom-Json
if(-not $compiled.planSha256 -or (Get-FileHash -LiteralPath (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256){throw 'Circle compile plan drift'}
if($compiled.kind -ne 'factory-circle-owned-compile-v1' -or $compiled.exitCode -ne 0 -or $compiled.sourceHash -ne $plan.sourceHash -or $compiled.rendererSha256 -ne $plan.rendererSha256 -or $compiled.streamsSealed -ne $true -or $compiled.streamDrainComplete -ne $true -or $compiled.originalHandleRetained -ne $true -or $compiled.jobActiveCount -ne 0 -or $compiled.kernelWait -ne 0 -or $compiled.ownedExited -ne $true){throw 'Compile receipt mismatch'}

$measuredPlanHash=(Get-FileHash -LiteralPath (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant()
if($compiled.planSha256 -ne $measuredPlanHash -or $compiled.exeSha256 -ne $ExeHash){throw 'Measured host plan/executable closure mismatch'}
if([string]::IsNullOrWhiteSpace($sourceDocument.runtimeSourceCommit) -or $plan.runtimeSourceCommit -ne $sourceDocument.runtimeSourceCommit -or $compiled.runtimeSourceCommit -ne $plan.runtimeSourceCommit -or $compiled.runtimeSourceTreeHash -ne $plan.runtimeSourceTreeHash -or $compiled.timedOut -or -not $compiled.ownedExited){throw 'Fresh Circle runtime compile lineage mismatch'}
$runtimeClosure=Join-Path $captureRoot 'support\circle-runtime-closure-v1.ps1'
if(-not (Test-Path -LiteralPath $runtimeClosure -PathType Leaf)){throw 'Circle runtime closure helper missing'}
. $runtimeClosure
$runtimeAssets=Assert-CircleRuntimeClosure $plan $sourceDocument $packagePath $captureRoot
$runtimeVerifier=[string]$runtimeAssets.runtimeVerifierPath
$hostInputs=[string]$runtimeAssets.hostInputsPath
. $runtimeVerifier
. $hostInputs
$hostInputs=[string]$runtimeAssets.hostInputsPath
if((Get-CircleHash $hostInputs) -cne [string]$runtimeAssets.hostInputsHash){throw 'Host input guard drift'}
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
if(-not $PreflightOnly){Check-Lock}

if($sourceDocument.caseID -cne $plan.case.id -or $sourceDocument.tupleID -cne $plan.tuple.id -or $sourceDocument.sourceHash -cne $plan.sourceHash -or $sourceDocument.capturePlanHash -notmatch '^[0-9a-f]{64}$'){throw 'Circle source-input package identity mismatch'}
$issuedMetadata=Get-Content -Raw -LiteralPath $IssuedMetadataPath|ConvertFrom-Json
if((Get-FileHash -LiteralPath $IssuedMetadataPath).Hash.ToLowerInvariant() -cne $IssuedMetadataHash){throw 'Issued metadata hash mismatch'}
$issuedMetadata=Assert-LeaseIssuedMetadata $IssuedMetadataPath $IssuedMetadataHash $outputPath 1 $CompileReceiptHash $ExeHash $SerializerControlSha256 $captureRoot $sourceDocument
if($issuedMetadata.sourceHash -cne $compiled.sourceHash -or $issuedMetadata.sourceHash -ne $sourceDocument.sourceHash -or @($issuedMetadata.captures).Count -ne 1 -or @($issuedMetadata.captures|Where-Object{$_.run -ne 1 -or $_.captureID -notmatch '^capture/[0-9a-f]{32}$' -or $_.imageID -notmatch '^image/[0-9a-f]{32}$'}).Count -ne 0){throw 'Issued Circle Count1 identity mismatch'}
if(-not $PreflightOnly){
 New-Item -ItemType Directory -Path $outputPath|Out-Null
 Copy-Item -LiteralPath $IssuedMetadataPath -Destination (Join-Path $outputPath 'issued-metadata.json')
 foreach($candidateFile in @('candidate-tuple.json','candidate-binding.json')){
  $candidateSource=Join-Path (Split-Path -Parent $IssuedMetadataPath) $candidateFile
  if(-not (Test-Path -LiteralPath $candidateSource -PathType Leaf)){throw ('Prelaunch candidate file missing: '+$candidateFile)}
  Copy-Item -LiteralPath $candidateSource -Destination (Join-Path $outputPath $candidateFile)
 }
} else {
 [ordered]@{kind='factory-circle-count1-prelaunch-v1';status='passed-source-only';runRoot=$RunRoot;outputRoot=$OutputRoot;packagePath=$packagePath;issuedMetadataHash=$IssuedMetadataHash;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;sourceInputsHash=$SourceInputsHash;nativeWindowActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $ControlRoot 'capture-preflight.json') -Encoding UTF8
 return
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
 Copy-Item -LiteralPath $receiptPath -Destination (Join-Path $outputPath 'observation.json')
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
 if((Get-FileHash -LiteralPath $buildPreflight).Hash.ToLowerInvariant() -ne $sourceDocument.buildPreflightHash){throw 'Reviewed Circle build preflight drift before child launch'}
 & $buildPreflight -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256 -SourceInputsPath $sourceInputs -SourceInputsHash $SourceInputsHash -PlanPath (Join-Path $packagePath 'plan.json') -PlanHash $sourceDocument.planHash -CompileReceiptPath $receiptPath -ExePath ([string]$sourceDocument.exeRef.path) -RendererPath $sourceDocument.rendererPath -SerializerPath $sourceDocument.serializerRef.path | Out-Null
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
  $deadline=[DateTime]::UtcNow.AddSeconds(30)
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
  Assert-FactoryIntegrationSources $captureRoot $sourceDocument
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
   if((Get-FileHash (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256 -or (Get-FileHash $receiptPath).Hash.ToLowerInvariant() -ne $CompileReceiptHash -or (Get-FileHash $exe).Hash.ToLowerInvariant() -ne $ExeHash){throw 'Owned close source/exe lineage drift'}
   if((Get-CircleHash $runtimeVerifier) -cne [string]$runtimeAssets.runtimeVerifierHash -or (Get-CircleHash $hostInputs) -cne [string]$runtimeAssets.hostInputsHash){throw 'Owned close source verifier drift'}
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
   $records += [ordered]@{foregroundBeforeLaunch=$foregroundBefore.ToInt64();foregroundAfterWindow=$foregroundAfter.ToInt64();activationVeto='thread-cbt';hostValid=$validHost;ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt};hwnd=$hwnd.ToInt64();probeForegroundAtCapture=$fgAtCapture;dpiAwarenessRequested='per-monitor-v2';backgroundPlacementRequested=$true;index=$i;case=$issuedMetadata.case;compiledPlanCase=$plan.case;manifestHash=$plan.manifestHash;exitCode=$p.ExitCode;exeSha256=$compiled.exeSha256;rendererSha256=$plan.rendererSha256;sourceHash=$plan.sourceHash;compileReceiptHash=$CompileReceiptHash;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;candidateTupleRef=$issuedMetadata.candidateTuple;candidateBindingRef=$issuedMetadata.sourceBoundCandidateTuple;captureMethod='UIA+PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT)+CopyFromScreen';occlusionQualified=$false;nativeParity='hold';frozenTupleBound=$false;closureBinding=$null;reason='Single source-bound observation only; provider exports, tuple qualification &parity remain held';files=@(Get-ChildItem -LiteralPath $dir -File|ForEach-Object{[ordered]@{path=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})}
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
  try{$timingSamples.Add((Get-FactoryLifecycleTimingSample 'raw-closure-final' $p $retainedTimingHandle $rawStreams));[ordered]@{kind='factory-circle-retained-handle-timing-v1';launchRequest=$launchRequest;launchReturn=$launchReturn;ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt};compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;stdoutSha256=$stdoutHashState.sha256;stderrSha256=$stderrHashState.sha256;rawHashesQualification=$rawQualification;nativeExitDeadlineSeconds=15;rawDrainMilliseconds=5000;observations=$timingSamples.ToArray();authority='observational only; cleanup certificate remains original helper'}|ConvertTo-Json -Depth 16|Set-Content -Encoding UTF8 (Join-Path $dir 'lifecycle-timing.json')}catch{$streamErrors+=('Lifecycle timing receipt: '+[string]$_)}
  try{[ordered]@{ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt};lockOwner=$LockOwner;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;sourceHash=$plan.sourceHash;primaryError=if($null -ne $primaryError){[string]$primaryError}else{''};preCleanupExitObservation=$preCleanupExitObservation;cleanup=$cleanupResult;streamErrors=$streamErrors;rawStreams=$rawStates;rawHashesQualification=$rawQualification;stdoutSha256=$stdoutHashState.sha256;stderrSha256=$stderrHashState.sha256;rawHashStates=[ordered]@{stdout=[ordered]@{sha256=$stdoutHashState.sha256;qualification=$stdoutHashState.qualification;error=$stdoutHashState.error};stderr=[ordered]@{sha256=$stderrHashState.sha256;qualification=$stderrHashState.qualification;error=$stderrHashState.error}}}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $dir 'capture-outcome.json')}catch{$streamErrors+=('outcome receipt: '+[string]$_)}
  if(-not $workerAttempted){try{Write-FactoryDiagnosticJson (Join-Path $dir 'owned-worker-inventory.json') $inventory;Write-FactoryDiagnosticJson (Join-Path $dir 'uia-no-start.json') ([ordered]@{kind='factory-uia-slot-no-start-v1';root=$workerRoot;lockOwner=$LockOwner;rendererDirectory=$dir;attempted=$false;noInvocationConfirmed=$true})}catch{}}
  # Separate release-only snapshot; never changes original outcome/cleanup/errors.
  try{
   Assert-FactoryIntegrationSources $captureRoot $sourceDocument
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
if((Get-FileHash -LiteralPath $plan.rendererPath).Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Circle renderer drift after native capture'}
if((Get-FileHash (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant() -ne $compiled.planSha256){throw 'Plan drift after capture'}
if((Get-FileHash $receiptPath).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Circle compile receipt drift after capture'}
if((Get-FileHash $exe).Hash.ToLowerInvariant() -ne $ExeHash){throw 'Host binary drift after capture'}
foreach($binding in $plan.sourceBindings){
 $sourceInput=[IO.Path]::GetFullPath((Join-Path $packagePath $binding.path))
 if(-not $sourceInput.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $sourceInput).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Host source drift after capture'}
}
if((Get-CircleHash $hostInputs) -cne [string]$runtimeAssets.hostInputsHash){throw 'Host input helper drift after capture'}
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
