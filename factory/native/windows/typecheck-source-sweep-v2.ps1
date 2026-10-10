# Serial declaration-only source sweep; no desktop/window/input or native qualification.
param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$RuntimeBuildRoot)
$ErrorActionPreference='Stop';$factory='D:\Claude\swiftright\factory\native\windows\'
$packagePath=[IO.Path]::GetFullPath($Package)
if(-not $packagePath.StartsWith($factory,[StringComparison]::OrdinalIgnoreCase)){throw 'Owned sweep archive required'}
$plan=Get-Content -Raw (Join-Path $packagePath 'sweep-plan.json')|ConvertFrom-Json
$runtime=Get-Content -Raw (Join-Path $RuntimeBuildRoot 'headless-receipt.json')|ConvertFrom-Json
if($plan.runtimeCommit -ne $runtime.sourceCommit -or $plan.runtimeSourceTreeHash -ne $runtime.sourceTreeHash -or @($runtime.commands|Where-Object {$_.command -eq 'build' -and $_.exitCode -eq 0}).Count -ne 1){throw 'Exact successfully built runtime required'}
$sourceReceipt=Join-Path $packagePath 'runtime-source-receipt.json'
if((Get-FileHash $sourceReceipt).Hash.ToLowerInvariant() -ne $plan.runtimeReceiptHash.Replace('sha256:','')){throw 'Source receipt drift'}
. (Join-Path $PSScriptRoot 'verify-runtime-source.ps1')
$sourcePlan=[pscustomobject]@{runtimePackagePath=$plan.runtimePackagePath;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash}
Assert-FactoryRuntimeSource $sourcePlan $packagePath
if(@($plan.rows).Count -ne 81){throw 'Fixed81 rows required'}
$modules=Join-Path $RuntimeBuildRoot 'scratch\out\Products\Release-windows-x86_64';$module=Join-Path $modules 'SwiftRightRuntime.swiftmodule'
$bindings=@(Get-ChildItem -LiteralPath $module -File|ForEach-Object{[ordered]@{path=$_.Name;hash=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})
if(-not $bindings.Count){throw 'Actual runtime module missing'}
$compiler=(Get-Command swiftc).Source;$rows=@();$errorText='';$totalDeadline=[DateTimeOffset]::UtcNow.AddMinutes(8)
try{
 foreach($row in $plan.rows){
  Assert-FactoryRuntimeSource $sourcePlan $packagePath
  foreach($b in $bindings){if((Get-FileHash (Join-Path $module $b.path)).Hash.ToLowerInvariant() -ne $b.hash){throw 'Per-row compiled module drift'}}
  if([DateTimeOffset]::UtcNow -gt $totalDeadline){throw 'Sweep deadline'}
  $dir=Join-Path $packagePath $row.directory;$source=Join-Path $dir 'Witness.swift'
  if([IO.Path]::GetFullPath($dir) -notlike ($packagePath+'\case-*')){throw 'Source archive escape'}
  if((Get-FileHash $source).Hash.ToLowerInvariant() -ne $row.sourceHash.Replace('sha256:','')){throw 'Witness source drift'}
  $info=[Diagnostics.ProcessStartInfo]::new($compiler);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $info.Arguments='-typecheck -swift-version 5 -I "'+$modules+'" "'+$source+'"'
  $p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o');$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$deadline=[DateTimeOffset]::UtcNow.AddSeconds(30)
  try{while(-not $p.WaitForExit(100)){if([DateTimeOffset]::UtcNow -gt $deadline){throw 'Owned compiler deadline'}}}
  finally{if(-not $p.HasExited){$owned=Get-Process -Id $p.Id -ErrorAction SilentlyContinue;if($owned -and $owned.Path -eq $compiler -and $owned.StartTime.ToUniversalTime().ToString('o') -eq $started){& taskkill /PID $p.Id /T /F|Out-Null};$p.WaitForExit(5000)|Out-Null};if($out.Wait(5000)){[IO.File]::WriteAllText((Join-Path $dir 'stdout.txt'),$out.GetAwaiter().GetResult())};if($err.Wait(5000)){[IO.File]::WriteAllText((Join-Path $dir 'stderr.txt'),$err.GetAwaiter().GetResult())}}
  $rows+=[ordered]@{index=$row.index;block=$row.block;case=$row.case;sourceHash=$row.sourceHash;exitCode=$p.ExitCode;stdoutHash=(Get-FileHash (Join-Path $dir 'stdout.txt')).Hash.ToLowerInvariant();stderrHash=(Get-FileHash (Join-Path $dir 'stderr.txt')).Hash.ToLowerInvariant();nativeWindowOpened=$false;rendererHostLinked=$false}
 }
 Assert-FactoryRuntimeSource $sourcePlan $packagePath
 foreach($b in $bindings){if((Get-FileHash (Join-Path $module $b.path)).Hash.ToLowerInvariant() -ne $b.hash){throw 'Compiled module drift'}}
}catch{$errorText=[string]$_}
finally{[ordered]@{kind='windows-fixed81-declaration-typechecks';moduleOriginCompileReceiptBound=$false;moduleProvenance='Actual observed module hashes checked before every row & after sweep; successful build receipt lacks module hashes';runtimeCommit=$plan.runtimeCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;planHash=(Get-FileHash (Join-Path $packagePath 'sweep-plan.json')).Hash.ToLowerInvariant();runtimeBuildReceiptHash=(Get-FileHash (Join-Path $RuntimeBuildRoot 'headless-receipt.json')).Hash.ToLowerInvariant();runtimeModuleBindings=$bindings;compiler=$compiler;compilerHash=(Get-FileHash $compiler).Hash.ToLowerInvariant();rows=$rows;error=$errorText;frozenTupleBound=$false;nativeCaseCaptureCount=0;finishedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 (Join-Path $packagePath 'sweep-receipt.json')}
