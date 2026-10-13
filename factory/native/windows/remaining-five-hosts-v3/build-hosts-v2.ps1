# Compiler-only; no executable launch, GUI, desktop lock or stage writes.
param([Parameter(Mandatory=$true)][string]$Package)
$ErrorActionPreference='Stop'
$expected=@('D:\Claude\swiftright\.factory-work\hosts\disabled\package','D:\Claude\swiftright\.factory-work\hosts\image\package','D:\Claude\swiftright\.factory-work\hosts\shapes.fill-stroke\package','D:\Claude\swiftright\.factory-work\hosts\text.bundled-font\package','D:\Claude\swiftright\.factory-work\hosts\toggle\package')
if($expected -cnotcontains [IO.Path]::GetFullPath($Package)){throw 'Exact correction package required'}
$planPath=Join-Path $Package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json
$planHash=(Get-FileHash $planPath).Hash.ToLowerInvariant()
$approvedPlans=@{
 'disabled'='488837bb2b9a594fe76b3d48e4a6253e2a9bd5968eb3a44aeb6934f93a39f544'
 'image'='48b30492c8a00581613769e207288a7af34869f02d80d1a73fc88be7276d9f15'
 'shapes.fill-stroke'='a00fdfd4a36eaa959ba0b71cd72cb489b1caa14b4311846740629e227e46e445'
 'text.bundled-font'='09736e706bbfd50f04ff623b00d710a599c7aa00ac641c0e651c669f7a932d7b'
 'toggle'='8bab1e788a6a95aa25468a6b071a25c30dd9ec2fa591d4103d9df8d8f85187dc'
}
$label=Split-Path (Split-Path $Package -Parent) -Leaf
if(-not $approvedPlans.ContainsKey($label) -or $planHash -cne $approvedPlans[$label]){throw 'Exact reviewed seeded plan required'}
$verify=Join-Path $PSScriptRoot 'shared\verify-runtime-source.ps1'
if((Get-FileHash $verify).Hash.ToLowerInvariant() -ne $plan.runtimeVerifierHash){throw 'Verifier drift'}
. $verify
$hostInputs=Join-Path $PSScriptRoot 'shared\host-inputs.ps1'
if((Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Host input guard drift'}
. $hostInputs
function Assert-Inputs {
 if((Get-FileHash $planPath).Hash.ToLowerInvariant() -ne $planHash){throw 'Plan drift'}
 if($plan.stage -ne 'D:\Claude\sr0-r09' -or $plan.runtimeSourceCommit -ne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'){throw 'Context drift'}
 if((Get-FileHash 'D:\Claude\sr0-r09\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Renderer drift'}
 if((Get-FileHash (Join-Path $Package 'runtime-source-receipt.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'Runtime receipt drift'}
 if((Get-FileHash (Join-Path $Package 'runtime-source-tree.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceTreeFileHash.Replace('sha256:','')){throw 'Runtime tree archive drift'}
 Assert-FactoryRuntimeSource $plan $Package
 Assert-HostCompilerInputs $Package $plan.sourceBindings
 $actualBridgeFiles=@((Join-Path $plan.bridgePackagePath 'Package.swift'))+@(Get-ChildItem -LiteralPath (Join-Path $plan.bridgePackagePath 'Sources') -Recurse -File|ForEach-Object{$_.FullName})
$expectedBridgeFiles=@($plan.bridgeBindings|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $_.path))})
if($actualBridgeFiles.Count -ne $expectedBridgeFiles.Count -or @($actualBridgeFiles|Where-Object{$expectedBridgeFiles -notcontains $_}).Count -ne 0){throw 'Staged bridge membership drift'}
foreach($b in $plan.bridgeBindings){
  $f=[IO.Path]::GetFullPath((Join-Path $plan.bridgePackagePath $b.path))
  if(-not $f.StartsWith($plan.bridgePackagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $f).Hash.ToLowerInvariant() -ne $b.sha256){throw 'Bridge input drift'}
 }
 if((Get-FileHash $plan.compilerPath).Hash.ToLowerInvariant() -ne $plan.compilerHash){throw 'Compiler drift'}
 $moduleContext=@{'module-origin-receipt.json'=$plan.runtimeModuleOrigin.receiptHash;'module-origin-accepted-replay.json'=$plan.runtimeModuleOrigin.acceptedReplayHash;'module-origin-independent-review.json'=$plan.runtimeModuleOrigin.independentReviewHash}
 foreach($name in $moduleContext.Keys){if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot ('dependencies\'+$name))).Hash.ToLowerInvariant() -cne $moduleContext[$name].Replace('sha256:','')){throw 'Archived module-origin context drift'}}
 $origin=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'dependencies\module-origin-receipt.json')|ConvertFrom-Json
 if($origin.sourceCommit -cne $plan.runtimeSourceCommit -or $origin.sourceTreeHash -cne $plan.runtimeSourceTreeHash -or $origin.status -cne 'success'){throw 'Module-origin source identity drift'}
}
Assert-Inputs
$controlAdmission=Join-Path $PSScriptRoot 'control-admission.ps1'
if((Get-FileHash -LiteralPath $controlAdmission).Hash.ToLowerInvariant() -cne '0348814bba0e8ea89de323603bcd096f10b68528a0ac762c1df9078e624fa39e'){throw 'Control admission guard drift'}
. $controlAdmission
Assert-CompletedBuildControls $PSScriptRoot $hostInputs
Assert-AdmissionInvocationProof $PSScriptRoot
$streamAdmission=Join-Path $PSScriptRoot 'stream-control-admission.ps1'
if((Get-FileHash -LiteralPath $streamAdmission).Hash.ToLowerInvariant() -cne 'f4fc632b3275c3c34ddd9ef095c075f282417f4ce155fcd1e96db576a5110ee2'){throw 'Stream admission drift'}
. $streamAdmission
Assert-CompilerStreamControls $PSScriptRoot
# Retained kernel handle identifies this process object even if its numeric PID exits/recycles.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FactoryOwnedCompilerHandleV2 {
 [DllImport("kernel32.dll", SetLastError=true)] public static extern bool TerminateProcess(IntPtr process, uint exitCode);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
}
'@
$cleanupHelper=Join-Path $PSScriptRoot 'cleanup-decision.ps1'
if((Get-FileHash -LiteralPath $cleanupHelper).Hash.ToLowerInvariant() -cne '018d89b825634a0dc238c1201d4fd97a23acbcdaf57b82333c6097e9efd92001'){throw 'Cleanup decision helper drift'}
. $cleanupHelper
$out=Join-Path $Package 'build-v3-r1'
$request=$plan.compileRequest
if($request.kind -cne 'swiftpm-windows-gui-release/1' -or $request.packagePath -cne $Package -or $request.scratchPath -cne (Join-Path $out 'scratch') -or $request.compilerPath -cne $plan.compilerPath -or $request.target -cne 'windows-x86_64' -or $request.configuration -cne 'release'){throw 'Exact prospective compile request mismatch'}
if(Test-Path -LiteralPath $out){throw 'Fresh versioned build output required'}
New-Item -ItemType Directory -Path $out|Out-Null
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$argsText='build --package-path "'+$Package+'" --scratch-path "'+(Join-Path $out 'scratch')+'" -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+$dep+'" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
$si=[Diagnostics.ProcessStartInfo]::new($plan.compilerPath,$argsText)
$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.WorkingDirectory=$Package
$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
$record=[ordered]@{kind='factory-remaining-five-compile-only-owned-handle-v1';planSha256=$planHash;sourceHash=$plan.sourceHash;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;compilerHash=$plan.compilerHash;compilerPath=$plan.compilerPath;target='windows-x86_64';configuration='release';rendererSha256=$plan.rendererSha256;argv=$argsText;cwd=$Package;startedAt=[DateTimeOffset]::UtcNow.ToString('o');processStartedAt=$null;pid=$null;exitCode=$null;timedOut=$false;ownedExited=$false;error=$null;cleanupError=$null;cleanupAction='none';descendantOwnership='not-observed';streamDrainComplete=$false;nativeWindowOpened=$false;nativeParity='hold';frozenTupleBound=$false;closureBinding=$null}
$receipt=Join-Path $out 'observation.json'
function Save-Receipt {$record|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath $receipt}
$streamHelper=Join-Path $PSScriptRoot 'stream-seal.ps1'
if((Get-FileHash -LiteralPath $streamHelper).Hash.ToLowerInvariant() -cne '4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'){throw 'Stream helper drift'}
. $streamHelper
$p=$null;$handle=[IntPtr]::Zero;$stdoutFile=$null;$stderrFile=$null;$streams=@()
$record.rawStreams=@();$record.rawFileHashes=@();$record.kernelWait=$null

Save-Receipt
try {
 $stdoutFile=[IO.File]::Open((Join-Path $out 'compile.stdout.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $streams+=@{name='stdout';source=$null;file=$stdoutFile;task=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false;closure=$null;closeTask=$null}
 $stderrFile=[IO.File]::Open((Join-Path $out 'compile.stderr.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $streams+=@{name='stderr';source=$null;file=$stderrFile;task=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false;closure=$null;closeTask=$null}
 $p=[Diagnostics.Process]::Start($si)
 $handle=$p.Handle # Force retained kernel handle before any wait or identity bookkeeping.
 $record.pid=$p.Id;$record.processStartedAt=$p.StartTime.ToUniversalTime().ToString('o');Save-Receipt
 foreach($stream in $streams){
  $source=if($stream.name -ceq 'stdout'){$p.StandardOutput.BaseStream}else{$p.StandardError.BaseStream}
  $stream.source=$source;$stream.task=$source.CopyToAsync($stream.file)
 }
 if(-not $p.WaitForExit(300000)){$record.timedOut=$true;$record.error='Compiler deadline exceeded'}
} catch {$record.error=[string]$_}
finally {
 # No Get-Process/PID lookup or taskkill. Wait status & termination operate on same retained handle.
 try {
  if($handle -ne [IntPtr]::Zero){
   $wait=[FactoryOwnedCompilerHandleV2]::WaitForSingleObject($handle,0)
   $action=Get-CompilerCleanupAction $wait ($record.timedOut -or $null -ne $record.error)
   $record.cleanupAction=$action;Save-Receipt
   if($action -eq 'terminate-owned-handle'){
    $record.descendantOwnership='unresolved-root-only-termination';Save-Receipt
    if(-not [FactoryOwnedCompilerHandleV2]::TerminateProcess($handle,124)){throw ('Terminate owned handle failed: '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
    $null=[FactoryOwnedCompilerHandleV2]::WaitForSingleObject($handle,5000)
   }
   $record.kernelWait=[FactoryOwnedCompilerHandleV2]::WaitForSingleObject($handle,0)
   $record.ownedExited=($record.kernelWait -eq 0)
   if($record.ownedExited){$record.exitCode=$p.ExitCode}
  }
 } catch {$record.cleanupError=[string]$_}
 Save-Receipt
 # No synchronous pipe Close/Flush/Dispose. Copy EOF & background destination closure each bounded5s.
 try {Complete-FactoryRawStreams $streams} catch {
  if($null -eq $record.cleanupError){$record.cleanupError=[string]$_}
 }
 foreach($stream in $streams){
  if(-not $stream.destinationClosed){
   Save-Receipt
   try{Close-FactoryRawStreamDestination $stream}catch{if($null -eq $record.cleanupError){$record.cleanupError=[string]$_}}
  }
 }
 $record.rawStreams=@($streams|ForEach-Object{Get-FactoryRawStreamState $_})
 $record.streamDrainComplete=($streams.Count -eq 2 -and @($record.rawStreams|Where-Object{-not $_.sealed -or -not $_.destinationClosed -or $_.taskStatus -cne 'RanToCompletion' -or $_.closureTaskStatus -cne 'RanToCompletion'}).Count -eq 0)
 foreach($stream in $streams){
  $state=Get-FactoryRawStreamState $stream
  $path=Join-Path $out ('compile.'+$stream.name+'.bin')
  $rawHash=Get-FactoryRawHash $path $state
  if($rawHash.qualification -ceq 'sealed-raw' -and (-not $record.ownedExited -or $record.kernelWait -ne 0 -or -not $record.streamDrainComplete)){$rawHash.qualification='diagnostic-partial';$rawHash.reason='compiler-kernel-or-two-stream-terminal-proof-missing'}
  $record.rawFileHashes+=@{path=('compile.'+$stream.name+'.bin');hash=$rawHash;state=$state}
 }
 $record.finishedAt=[DateTimeOffset]::UtcNow.ToString('o');Save-Receipt
 if($record.ownedExited -and $record.exitCode -eq 0 -and -not $record.timedOut -and $null -eq $record.error -and $null -eq $record.cleanupError -and $record.streamDrainComplete){
  try {
   Assert-Inputs
   $exes=@(Get-ChildItem -LiteralPath (Join-Path $out 'scratch') -Filter FactoryProbe.exe -Recurse -File)
   if($exes.Count -ne 1){throw 'Ambiguous produced executable'}
   $exe=$exes[0];$bytes=[IO.File]::ReadAllBytes($exe.FullName)
   $expectedExe=Join-Path $plan.compileRequest.scratchPath 'out\Products\Release-windows-x86_64\FactoryProbe.exe'
   if($exe.FullName -cne $expectedExe){throw 'Exact compile request output required'}
   if($bytes.Length -lt 64 -or $bytes[0] -ne 77 -or $bytes[1] -ne 90){throw 'Invalid PE header'}
   $pe=[BitConverter]::ToInt32($bytes,60)
   if($pe -lt 64 -or $pe+94 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 17744){throw 'Invalid PE offset/signature'}
   $machine=[BitConverter]::ToUInt16($bytes,$pe+4)
   if($machine -ne 34404){throw 'Actual x86_64 PE machine required'}
   $record.exeMachine=$machine
   $subsystem=[BitConverter]::ToUInt16($bytes,$pe+24+68)
   if($subsystem -ne 2){throw 'GUI PE2 required'}
   Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $out 'FactoryProbe.exe')
   $record.exePath=$exe.FullName;$record.exeSha256=(Get-FileHash -LiteralPath $exe.FullName).Hash.ToLowerInvariant();$record.exeSubsystem=$subsystem
   $moduleDirs=@(Get-ChildItem -LiteralPath (Join-Path $out 'scratch') -Recurse -Directory -Filter 'SwiftRightRuntime.swiftmodule')
   if($moduleDirs.Count -ne 1){throw 'Unique freshly built runtime module directory required'}
   $modules=@(Get-ChildItem -LiteralPath $moduleDirs[0].FullName -File)
   $targetModules=@('x86_64-unknown-windows-msvc.swiftmodule','x86_64-unknown-windows-msvc.swiftdoc')
   if($modules.Count -ne 2 -or @($modules|Where-Object{$targetModules -cnotcontains $_.Name}).Count -ne 0){throw 'Exact fresh runtime module pair required'}
   $moduleArchive=Join-Path $out 'runtime-module-archive';New-Item -ItemType Directory -Path $moduleArchive|Out-Null
   $record.runtimeModules=@($modules|ForEach-Object{
    if($_.Length -le 0){throw 'Empty produced runtime module'}
    $copy=Join-Path $moduleArchive $_.Name;Copy-Item -LiteralPath $_.FullName -Destination $copy
    $rawHash=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    if((Get-FileHash -LiteralPath $copy).Hash.ToLowerInvariant() -cne $rawHash){throw 'Runtime module archive mismatch'}
    @{path=$_.FullName;archivePath=$copy;sha256=$rawHash;bytes=[int64]$_.Length;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash}
   })
  } catch {$record.error=[string]$_}
 }
 # Raw streams never pass generic enumeration/hash callbacks. Unclosed bytes have null hash.
 $record.files=@($record.rawFileHashes|Where-Object{$null -ne $_.hash.sha256}|ForEach-Object{@{path=$_.path;sha256=$_.hash.sha256;qualification=$_.hash.qualification}})
 if($record.exeSha256){$record.files+=@{path='FactoryProbe.exe';sha256=$record.exeSha256;qualification='successful-compile-output'}}
 Save-Receipt
 # Retain pipe/process objects until bounded controller exit; never synchronously dispose a pending pipe.
}
if($record.exitCode -ne 0 -or $record.timedOut -or -not $record.ownedExited -or $null -ne $record.error -or $null -ne $record.cleanupError -or -not $record.streamDrainComplete){throw 'Compiler-only control unsuccessful; preserve receipt & refuse next build until unresolved ownership addressed'}
