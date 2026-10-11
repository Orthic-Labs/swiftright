$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.work\sr0-stage-inputs\startupguard-smoke-r1.zip';$stage='D:\Claude\swiftright\.work\sr0-f1-smoke-v1'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne '465b5bbe620dab2668e42e67c1c28432ea45017071ec730193bdc45fdef1bd40'){throw 'source ZIP drift'}
if(Test-Path -LiteralPath $stage){throw 'Exclusive smoke control stage exists'}
Expand-Archive -LiteralPath $zip -DestinationPath $stage
$m=Join-Path $stage 'source-manifest.json';if((Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant() -cne 'dd8fa2b6945d358bda5c8ce7674801eef1baac06aec09fa5d22c38905844567e'){throw 'source manifest drift'}
$rows=@((Get-Content -Raw -LiteralPath $m|ConvertFrom-Json).files);if($rows.Count -ne 2){throw 'exact two script controls required'}
foreach($r in $rows){if($r.path -cnotin @('worker.ps1','coordinator.ps1')){throw 'unknown member'};$f=Join-Path $stage $r.path;if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256 -or (Get-Item -LiteralPath $f).Length -ne $r.bytes){throw 'source control drift'};$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ForEach-Object{Write-Output $_.Message};throw ('Actual Windows parse failed '+$r.path)}}
$base='D:\Claude\swiftright\.work\sr0-r12-typecheck\src';$driver=Join-Path $base 'probes\sr0-s\fresh-on-bridge\scripts\drive-fixture.ps1'
if((Get-FileHash -LiteralPath $driver).Hash.ToLowerInvariant() -cne '1683b96e2b0e9ac06cf93777d2274d5f4ece9c40092d90799de95b98e77436e9'){throw 'compiled driver source drift'}
[ordered]@{kind='root-sr0-smoke-source-parse-admission-v1';files=$rows;driverSha256='1683b96e2b0e9ac06cf93777d2274d5f4ece9c40092d90799de95b98e77436e9';nativeActions=0}|ConvertTo-Json -Depth 8
& (Join-Path $stage 'coordinator.ps1') -Base $base -Worker (Join-Path $stage 'worker.ps1') -Driver $driver -ExpectExe '87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374' -ExpectDll '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2' -OutRoot 'D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-smoke-v1'
