$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.work\sr0-startupguard-source.zip';$root='D:\Claude\swiftright\.work\sr0-r12-typecheck';$dll='D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'cc681f8316b763a8abd1303311fa5950cd461fbbeee7541c1edb7dbd51620c10'){throw 'SR0 source zip drift'}
if(-not(Test-Path -LiteralPath $root -PathType Container)){throw 'Original hash-verified source stage absent'}
$running=@(Get-CimInstance Win32_Process|Where-Object{$_.CommandLine -like '*sr0-r12-typecheck*' -and $_.Name -match '^(swift.*|clang.*)\.exe$'});if($running.Count){throw 'Prior owned source compilation still running; no duplicate'}
$patchZip='D:\Claude\swiftright\.work\sr0-source-import-r4.zip';$patch='D:\Claude\swiftright\.work\sr0-r12-typecheck\import-patch-r4'
if((Get-FileHash -LiteralPath $patchZip).Hash.ToLowerInvariant() -cne '2bdee07495eec7740adca6fa7dd9ecf4758afb49b891218ccc4f10b13903d53f'){throw 'Import patch zip drift'}
if(Test-Path -LiteralPath $patch){throw 'Fresh import patch stage required'}
Expand-Archive -LiteralPath $patchZip -DestinationPath $patch
$target=Join-Path $root 'src\probes\sr0-s\fresh-on-bridge\Sources\FreshOnBridge\StartupGuard.swift'
if((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -cne 'fdd0f3c53c365738c7acccc7fcad26bbc358ce12d760ac28a226e19174327104'){throw 'Original failed StartupGuard source drift'}
if((Get-FileHash -LiteralPath (Join-Path $patch 'StartupGuard.swift')).Hash.ToLowerInvariant() -cne '05f2f684da848e9c362fb27578c38cbce252f46e5141c0044fa64825f4415e17'){throw 'Patched StartupGuard bytes drift'}
[IO.File]::Copy((Join-Path $patch 'StartupGuard.swift'),$target,$true)
[IO.File]::Copy((Join-Path $patch 'transport-manifest-r4.json'),(Join-Path $root 'transport-manifest-r4.json'),$false)
$m=Join-Path $root 'transport-manifest-r4.json';if((Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant() -cne 'f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca'){throw 'Updated SR0 source manifest drift'}
$rows=@(([IO.File]::ReadAllText($m)|ConvertFrom-Json).files);$src=Join-Path $root 'src'
foreach($r in $rows){$f=Join-Path $src ($r.path -replace '/','\');if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw ('SR0 source file drift '+$r.path)};if($r.path -cin @('probes/sr0-s/fresh-on-bridge/scripts/build-fresh.ps1','probes/sr0-s/fresh-on-bridge/scripts/drive-fixture.ps1')){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw ('SR0 source parse failure '+$r.path)}}}
$swift='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
$env:Path=(Split-Path -Parent $swift)+';'+$env:Path
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass='BelowNormal'
& $swift --version | Out-File -Encoding UTF8 (Join-Path $root 'swift-version.txt')
if($LASTEXITCODE -ne 0){throw 'Swift toolchain preflight failed'}
$env:Path=(Split-Path -Parent $swift)+';C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
$log=Join-Path $root 'build-r4.stdout.txt';$err=Join-Path $root 'build-r4.stderr.txt'
if((Test-Path -LiteralPath $log) -or (Test-Path -LiteralPath $err)){throw 'Fresh raw build streams required'}
$dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$argv='build -c release --scratch-path "'+(Join-Path $src 'scratch')+'" -Xlinker "/MANIFEST:EMBED" -Xlinker "'+$dep+'"'
$working=Join-Path $src 'probes\sr0-s\fresh-on-bridge'
$proc=Start-Process -FilePath $swift -ArgumentList $argv -WorkingDirectory $working -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError $err -PassThru
$retainedCompilerHandle=$proc.Handle;$proc.WaitForExit();$proc.Refresh();$code=$proc.ExitCode;if($null -eq $code){throw 'Original retained compiler exit code unavailable'}

$exe=Join-Path $src 'scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe'
$exeref=$null;if($code -eq 0){if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Compiled FreshOnBridge absent'};$exeref=[ordered]@{path=$exe;bytes=(Get-Item -LiteralPath $exe).Length;sha256=(Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()}}
$receipt=[ordered]@{kind='root-sr0-startupguard-windows-build-v1';parserScope='invoked-build-script-and-candidate-driver';historicalUnusedStageScriptParseFailurePreserved=$true;exitCode=$code;sourceManifestSha256=(Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant();sourceFilesVerified=$rows.Count;overlayCommit='db08e1a11fbb61e3789c7c1687c936a33c06d523';rendererSha256=(Get-FileHash -LiteralPath $dll).Hash.ToLowerInvariant();swift=[ordered]@{path=$swift;sha256=(Get-FileHash -LiteralPath $swift).Hash.ToLowerInvariant()};exe=$exeref;stdout=[ordered]@{path=$log;sha256=(Get-FileHash -LiteralPath $log).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $log).Length};stderr=[ordered]@{path=$err;sha256=(Get-FileHash -LiteralPath $err).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $err).Length};nativeLaunches=0;lockActions=0;qualification='hold';at=[DateTimeOffset]::UtcNow.ToString('o')}
$receipt|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $root 'build-r4-receipt.json');$receipt|ConvertTo-Json -Depth 8
if($code -ne 0){throw ('Source-bound Windows fixture build failed '+$code)}
