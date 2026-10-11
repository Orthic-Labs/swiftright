# Compiler-only; no executable launch, GUI, desktop lock or stage writes.
param([Parameter(Mandatory=$true)][string]$Package)
$ErrorActionPreference='Stop'
$expected=@('D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\stack-overlay\package','D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\custom-layout\package','D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\padding-frame\package','D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\preference-key\package','D:\Claude\swiftright\factory\native\windows\round1-seeded-hosts-v1\scroll-view\package')
if($expected -notcontains [IO.Path]::GetFullPath($Package)){throw 'Exact correction package required'}
$planPath=Join-Path $Package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json
$planHash=(Get-FileHash $planPath).Hash.ToLowerInvariant()
$verify=Join-Path $PSScriptRoot '..\verify-runtime-source.ps1'
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
}
Assert-Inputs
$out=Join-Path $Package 'build-r1'
if(Test-Path $out){throw 'Fresh build output required'}
New-Item -ItemType Directory $out|Out-Null
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$argsText='build --package-path "'+$Package+'" --scratch-path "'+(Join-Path $out 'scratch')+'" -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+$dep+'" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
$si=[Diagnostics.ProcessStartInfo]::new($plan.compilerPath,$argsText)
$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.WorkingDirectory=$Package
$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
$at=[DateTimeOffset]::UtcNow.ToString('o');$p=[Diagnostics.Process]::Start($si)
$started=$p.StartTime.ToUniversalTime().ToString('o');$pidOwned=$p.Id
$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync();$timedOut=$false
[ordered]@{pid=$pidOwned;path=$plan.compilerPath;startedAt=$started;argv=$argsText;cwd=$Package}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $out 'owned-process.json')
try {
 if(-not $p.WaitForExit(300000)){$timedOut=$true;throw 'Compiler deadline'}
} finally {
 $current=Get-Process -Id $pidOwned -ErrorAction SilentlyContinue
 if($current -and $current.Path -eq $plan.compilerPath -and $current.StartTime.ToUniversalTime().ToString('o') -eq $started){& taskkill /PID $pidOwned /T /F|Out-Null}
 $p.WaitForExit(5000)|Out-Null
 if($stdout.Wait(5000)){[IO.File]::WriteAllText((Join-Path $out 'compile.stdout.txt'),$stdout.GetAwaiter().GetResult())}
 if($stderr.Wait(5000)){[IO.File]::WriteAllText((Join-Path $out 'compile.stderr.txt'),$stderr.GetAwaiter().GetResult())}
 $record=[ordered]@{kind='factory-correction-compile-only';startedAt=$at;finishedAt=[DateTimeOffset]::UtcNow.ToString('o');pid=$pidOwned;processStartedAt=$started;argv=$argsText;cwd=$Package;planSha256=$planHash;sourceHash=$plan.sourceHash;rendererSha256=$plan.rendererSha256;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;compilerHash=$plan.compilerHash;timedOut=$timedOut;exitCode=$(if($p.HasExited){$p.ExitCode}else{$null});nativeWindowOpened=$false;nativeParity='hold';frozenTupleBound=$false;closureBinding=$null;ownedExited=$p.HasExited}
 if($p.HasExited -and $p.ExitCode -eq 0 -and -not $timedOut){
  Assert-Inputs
  $exes=@(Get-ChildItem (Join-Path $out 'scratch') -Filter FactoryProbe.exe -Recurse -File)
  if($exes.Count -ne 1){throw 'Ambiguous produced executable'}
  $exe=$exes[0];$bytes=[IO.File]::ReadAllBytes($exe.FullName);$pe=[BitConverter]::ToInt32($bytes,60)
  $subsystem=[BitConverter]::ToUInt16($bytes,$pe+24+68)
  if($subsystem -ne 2){throw 'GUI PE2 required'}
  Copy-Item $exe.FullName (Join-Path $out 'FactoryProbe.exe')
  $record.exePath=$exe.FullName;$record.exeSha256=(Get-FileHash $exe.FullName).Hash.ToLowerInvariant();$record.exeSubsystem=$subsystem
 }
 $record.files=@(Get-ChildItem $out -File|ForEach-Object{@{path=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})
 $record|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $out 'observation.json')
}
