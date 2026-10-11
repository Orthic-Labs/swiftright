$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.work\sr0-startupguard-source.zip';$root='D:\Claude\swiftright\.work\sr0-r12-typecheck';$dll='D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'cc681f8316b763a8abd1303311fa5950cd461fbbeee7541c1edb7dbd51620c10'){throw 'SR0 source zip drift'}
if(Test-Path -LiteralPath $root){throw 'Fresh SR0 typecheck stage required'}
Expand-Archive -LiteralPath $zip -DestinationPath $root
$m=Join-Path $root 'transport-manifest.json';if((Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant() -cne '290903786896cdc91fccb4c6aba01d725e637f1602df9291bc89a9d16d071603'){throw 'SR0 source manifest drift'}
$rows=@(([IO.File]::ReadAllText($m)|ConvertFrom-Json).files);$src=Join-Path $root 'src'
foreach($r in $rows){$f=Join-Path $src ($r.path -replace '/','\');if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw ('SR0 source file drift '+$r.path)};if($f.EndsWith('.ps1')){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw ('SR0 source parse failure '+$r.path)}}}
$swift='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
$env:Path=(Split-Path -Parent $swift)+';'+$env:Path
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass='BelowNormal'
& $swift --version | Out-File -Encoding UTF8 (Join-Path $root 'swift-version.txt')
if($LASTEXITCODE -ne 0){throw 'Swift toolchain preflight failed'}
$log=Join-Path $root 'build.stdout.txt';$err=Join-Path $root 'build.stderr.txt';$build=Join-Path $src 'probes\sr0-s\fresh-on-bridge\scripts\build-fresh.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $build -Base $src -Dll $dll -ExpectDllSha256 '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2' 1> $log 2> $err
$code=$LASTEXITCODE
$exe=Join-Path $src 'scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe'
$exeref=$null;if($code -eq 0){if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Compiled FreshOnBridge absent'};$exeref=[ordered]@{path=$exe;bytes=(Get-Item -LiteralPath $exe).Length;sha256=(Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()}}
$receipt=[ordered]@{kind='root-sr0-startupguard-windows-build-v1';exitCode=$code;sourceManifestSha256=(Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant();sourceFilesVerified=$rows.Count;overlayCommit='db08e1a11fbb61e3789c7c1687c936a33c06d523';rendererSha256=(Get-FileHash -LiteralPath $dll).Hash.ToLowerInvariant();swift=[ordered]@{path=$swift;sha256=(Get-FileHash -LiteralPath $swift).Hash.ToLowerInvariant()};exe=$exeref;stdout=[ordered]@{path=$log;sha256=(Get-FileHash -LiteralPath $log).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $log).Length};stderr=[ordered]@{path=$err;sha256=(Get-FileHash -LiteralPath $err).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $err).Length};nativeLaunches=0;lockActions=0;qualification='hold';at=[DateTimeOffset]::UtcNow.ToString('o')}
$receipt|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $root 'build-receipt.json');$receipt|ConvertTo-Json -Depth 8
if($code -ne 0){throw ('Source-bound Windows fixture build failed '+$code)}
