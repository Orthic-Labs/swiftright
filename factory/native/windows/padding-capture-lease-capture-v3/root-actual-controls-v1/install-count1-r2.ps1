$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\count1-r2.zip';$stage='D:\Claude\swiftright\.factory-work\count1-r2';$repo='D:\Claude\swiftright'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'caf9db6c9ac9ab165b614e4514183206f21851bca4c413a757493585253ae017'){throw 'Count1 transport zip drift'}
if(Test-Path -LiteralPath $stage){throw 'Fresh Count1 transport stage required'}
Expand-Archive -LiteralPath $zip -DestinationPath $stage
$m=Join-Path $stage 'transfer-manifest.json';if((Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant() -cne 'f711efe6b6d3947db2211859174996cf5649ccbd251f7eb07c9a6c2de4c30556'){throw 'Count1 manifest drift'}
$rows=@(([IO.File]::ReadAllText($m)|ConvertFrom-Json).files)
foreach($r in $rows){$f=Join-Path (Join-Path $stage 'source') ($r.path -replace '/','\');$d=Join-Path $repo ($r.path -replace '/','\');if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw ('Count1 source drift '+$r.path)};if(Test-Path -LiteralPath $d){throw ('Fresh admitted input required '+$r.path)};if($f.EndsWith('.ps1')){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw ('Count1 source parse failed '+$r.path)}}}
foreach($r in $rows){$f=Join-Path (Join-Path $stage 'source') ($r.path -replace '/','\');$d=Join-Path $repo ($r.path -replace '/','\');[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($d))|Out-Null;[IO.File]::Copy($f,$d,$false)}
[ordered]@{kind='root-count1-input-admission-v1';status='PASS';files=$rows;nativeLaunches=0;lockActions=0}|ConvertTo-Json -Depth 8

& (Join-Path $repo "factory\native\windows\padding-capture-lease-capture-v3\root-metadata-controls-v1\transport-r2\test-transport-path-controls.ps1")
