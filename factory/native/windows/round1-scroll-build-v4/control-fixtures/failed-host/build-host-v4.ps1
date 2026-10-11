# Compiler-only; no executable launch, GUI, desktop lock or stage writes.
param([Parameter(Mandatory=$true)][string]$Package)
$ErrorActionPreference='Stop'
$expected='D:\Claude\swiftright\factory\native\windows\round1-scroll-host-v1\package'
if($expected -cne [IO.Path]::GetFullPath($Package)){throw 'Exact scroll correction package required'}
$planPath=Join-Path $Package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json
$planHash=(Get-FileHash $planPath).Hash.ToLowerInvariant()
if($planHash -cne '87e220ea813bfc3a11fca006b1388865c1137f3d3cebd2f760baac96908ba904'){throw 'Exact reviewed scroll plan required'}
$verify=Join-Path $PSScriptRoot '..\verify-runtime-source.ps1'
if((Get-FileHash $verify).Hash.ToLowerInvariant() -ne $plan.runtimeVerifierHash){throw 'Verifier drift'}
. $verify
$hostInputs=Join-Path $PSScriptRoot '..\round1-scroll-host-v1\shared\host-inputs.ps1'
if((Get-FileHash $hostInputs).Hash.ToLowerInvariant() -ne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'Host input guard drift'}
. $hostInputs
function Assert-Inputs {
 if((Get-FileHash $planPath).Hash.ToLowerInvariant() -ne $planHash){throw 'Plan drift'}
 if($plan.stage -ne 'D:\Claude\sr0-r09' -or $plan.runtimeSourceCommit -ne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'){throw 'Context drift'}
 if((Get-FileHash 'D:\Claude\sr0-r09\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -ne $plan.rendererSha256){throw 'Renderer drift'}
 if((Get-FileHash (Join-Path $Package 'runtime-source-receipt.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'Runtime receipt drift'}
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
}
Assert-Inputs
$controlAdmission=Join-Path $PSScriptRoot 'control-admission.ps1'
if((Get-FileHash -LiteralPath $controlAdmission).Hash.ToLowerInvariant() -cne '3691bca9bc9245f53f89b0368fdb607ab0a4f9f8724c1bf8a1bc417e3470962f'){throw 'Control admission guard drift'}
. $controlAdmission
Assert-CompletedBuildControls $PSScriptRoot $hostInputs
Assert-AdmissionInvocationProof $PSScriptRoot
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
if(Test-Path -LiteralPath $out){throw 'Fresh versioned build output required'}
New-Item -ItemType Directory -Path $out|Out-Null
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$argsText='build --package-path "'+$Package+'" --scratch-path "'+(Join-Path $out 'scratch')+'" -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+$dep+'" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
$si=[Diagnostics.ProcessStartInfo]::new($plan.compilerPath,$argsText)
$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.WorkingDirectory=$Package
$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
$record=[ordered]@{kind='factory-compile-only-owned-handle-v2';planSha256=$planHash;sourceHash=$plan.sourceHash;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;compilerHash=$plan.compilerHash;rendererSha256=$plan.rendererSha256;argv=$argsText;cwd=$Package;startedAt=[DateTimeOffset]::UtcNow.ToString('o');processStartedAt=$null;pid=$null;exitCode=$null;timedOut=$false;ownedExited=$false;error=$null;cleanupError=$null;cleanupAction='none';descendantOwnership='not-observed';streamDrainComplete=$false;nativeWindowOpened=$false;nativeParity='hold';frozenTupleBound=$false;closureBinding=$null}
$receipt=Join-Path $out 'observation.json'
function Save-Receipt {$record|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath $receipt}
$p=$null;$handle=[IntPtr]::Zero;$stdoutFile=$null;$stderrFile=$null;$stdoutTask=$null;$stderrTask=$null
Save-Receipt
try {
 $stdoutFile=[IO.File]::Open((Join-Path $out 'compile.stdout.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $stderrFile=[IO.File]::Open((Join-Path $out 'compile.stderr.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $p=[Diagnostics.Process]::Start($si)
 $handle=$p.Handle # Force retained kernel handle before any wait or identity bookkeeping.
 $record.pid=$p.Id;$record.processStartedAt=$p.StartTime.ToUniversalTime().ToString('o');Save-Receipt
 $stdoutTask=$p.StandardOutput.BaseStream.CopyToAsync($stdoutFile);$stderrTask=$p.StandardError.BaseStream.CopyToAsync($stderrFile)
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
   $record.ownedExited=([FactoryOwnedCompilerHandleV2]::WaitForSingleObject($handle,0) -eq 0)
   if($record.ownedExited){$record.exitCode=$p.ExitCode}
  }
 } catch {$record.cleanupError=[string]$_}
 Save-Receipt
 try {
  $a=$false;$b=$false
  if($null -ne $stdoutTask){$a=$stdoutTask.Wait(5000)}
  if($null -ne $stderrTask){$b=$stderrTask.Wait(5000)}
  $record.streamDrainComplete=$a -and $b
  if(-not $a -and $null -ne $p){$p.StandardOutput.Close()}
  if(-not $b -and $null -ne $p){$p.StandardError.Close()}
 } catch {if($null -eq $record.cleanupError){$record.cleanupError=[string]$_}}
 foreach($f in @($stdoutFile,$stderrFile)){if($null -ne $f){try{$f.Flush();$f.Dispose()}catch{if($null -eq $record.cleanupError){$record.cleanupError=[string]$_}}}}
 $record.finishedAt=[DateTimeOffset]::UtcNow.ToString('o');Save-Receipt
 if($record.ownedExited -and $record.exitCode -eq 0 -and -not $record.timedOut -and $null -eq $record.error -and $null -eq $record.cleanupError -and $record.streamDrainComplete){
  try {
   Assert-Inputs
   $exes=@(Get-ChildItem -LiteralPath (Join-Path $out 'scratch') -Filter FactoryProbe.exe -Recurse -File)
   if($exes.Count -ne 1){throw 'Ambiguous produced executable'}
   $exe=$exes[0];$bytes=[IO.File]::ReadAllBytes($exe.FullName)
   if($bytes.Length -lt 64 -or $bytes[0] -ne 77 -or $bytes[1] -ne 90){throw 'Invalid PE header'}
   $pe=[BitConverter]::ToInt32($bytes,60)
   if($pe -lt 64 -or $pe+94 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 17744){throw 'Invalid PE offset/signature'}
   $subsystem=[BitConverter]::ToUInt16($bytes,$pe+24+68)
   if($subsystem -ne 2){throw 'GUI PE2 required'}
   Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $out 'FactoryProbe.exe')
   $record.exePath=$exe.FullName;$record.exeSha256=(Get-FileHash -LiteralPath $exe.FullName).Hash.ToLowerInvariant();$record.exeSubsystem=$subsystem
  } catch {$record.error=[string]$_}
 }
 $record.files=@(Get-ChildItem -LiteralPath $out -File|Where-Object{$_.Name -ne 'observation.json'}|ForEach-Object{@{path=$_.Name;bytes=[int64]$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
 Save-Receipt
 if($null -ne $p){$p.Dispose()}
}
if($record.exitCode -ne 0 -or $record.timedOut -or -not $record.ownedExited -or $null -ne $record.error -or $null -ne $record.cleanupError -or -not $record.streamDrainComplete){throw 'Compiler-only control unsuccessful; preserve receipt & refuse next build until unresolved ownership addressed'}
