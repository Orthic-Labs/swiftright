$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\count1-inputs-r1.zip';$stage='D:\Claude\swiftright\.factory-work\count1-inputs-r1';$repo='D:\Claude\swiftright'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne '5f8f9b6619e6a080bb66b371af581b75171a1d2800358fd4319332d50885b5d2'){throw 'Count1 transport zip drift'}
if(Test-Path -LiteralPath $stage){throw 'Fresh Count1 transport stage required'}
Expand-Archive -LiteralPath $zip -DestinationPath $stage
$m=Join-Path $stage 'transfer-manifest.json';if((Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant() -cne 'af7ffdfe8129cca75b854715865940edd2ccfb1bf977ceaa2cef8e138d7d56ee'){throw 'Count1 manifest drift'}
$rows=@(([IO.File]::ReadAllText($m)|ConvertFrom-Json).files)
foreach($r in $rows){$f=Join-Path (Join-Path $stage 'source') ($r.path -replace '/','\');$d=Join-Path $repo ($r.path -replace '/','\');if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw ('Count1 source drift '+$r.path)};if(Test-Path -LiteralPath $d){throw ('Fresh admitted input required '+$r.path)};if($f.EndsWith('.ps1')){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw ('Count1 source parse failed '+$r.path)}}}
foreach($r in $rows){$f=Join-Path (Join-Path $stage 'source') ($r.path -replace '/','\');$d=Join-Path $repo ($r.path -replace '/','\');[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($d))|Out-Null;[IO.File]::Copy($f,$d,$false)}
[ordered]@{kind='root-count1-input-admission-v1';status='PASS';files=$rows;nativeLaunches=0;lockActions=0}|ConvertTo-Json -Depth 8
