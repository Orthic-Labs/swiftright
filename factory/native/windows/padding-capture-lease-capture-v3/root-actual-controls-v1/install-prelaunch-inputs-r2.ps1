$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\prelaunch-inputs.zip';$stage='D:\Claude\swiftright\.factory-work\prelaunch-inputs'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne '4f668bf6b0eec5a6c6e0e198db557716476a46a87257247f9a54f9b865803600'){throw 'Root prelaunch zip drift'}
if(Test-Path -LiteralPath $stage){throw 'Fresh staged extraction required'}
Expand-Archive -LiteralPath $zip -DestinationPath $stage
$ErrorActionPreference='Stop'
$staged='D:\Claude\swiftright\.factory-work\prelaunch-inputs';$repo='D:\Claude\swiftright'
$m=Join-Path $staged 'transfer-manifest.json';if((Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant() -cne '2c9102785485c5214ca64f122846792a66a2999846d91e4013a4215fd530cb1e'){throw 'Prelaunch transport pin mismatch'}
$rows=@(([IO.File]::ReadAllText($m)|ConvertFrom-Json).files)
foreach($r in $rows){$p=Join-Path (Join-Path $staged 'source') ($r.path -replace '/','\');if((Get-Item -LiteralPath $p).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $r.sha256.Replace('sha256:','')){throw ('Staged bytes mismatch: '+$r.path)}}
foreach($r in $rows){$dest=Join-Path $repo ($r.path -replace '/','\');if(Test-Path -LiteralPath $dest){if((Get-Item -LiteralPath $dest).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant() -cne $r.sha256.Replace('sha256:','')){throw ('Existing immutable bytes differ: '+$r.path)}}}
foreach($r in $rows){$p=Join-Path (Join-Path $staged 'source') ($r.path -replace '/','\');$dest=Join-Path $repo ($r.path -replace '/','\');if(-not(Test-Path -LiteralPath $dest)){[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))|Out-Null;[IO.File]::Copy($p,$dest,$false)};Write-Output ('PRELAUNCH_INPUT_PASS '+$r.path+' '+(Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant())}
$builder='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis';Write-Output ('BUILDER_EXISTS '+(Test-Path -LiteralPath $builder));foreach($rel in @('preflight.ps1','package\plan.json','package\build-capture-lease-r1\observation.json')){$p=Join-Path $builder $rel;Write-Output ('BUILDER_INPUT '+$p+' exists='+(Test-Path -LiteralPath $p));if(Test-Path -LiteralPath $p){Write-Output ((Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant())}}

$cached='D:\Claude\swiftright\.factory-work\controls-source';$repo='D:\Claude\swiftright'
$manifest=Join-Path $cached 'transfer-manifest.json'
if((Get-FileHash -LiteralPath $manifest).Hash.ToLowerInvariant() -cne '0f0405fc0d7633cfff105942cbfffbbe7fe62cd404cc517c5264f5c21ad43f2a'){throw 'Frozen76 source transport manifest drift'}
$sourceRows=@(([IO.File]::ReadAllText($manifest)|ConvertFrom-Json).files)
foreach($r in $sourceRows){$f=Join-Path $cached ($r.path -replace '/','\');$dest=Join-Path $repo ($r.path -replace '/','\');if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256.Replace('sha256:','')){throw ('Frozen source cached drift: '+$r.path)};if(Test-Path -LiteralPath $dest){if((Get-Item -LiteralPath $dest).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant() -cne $r.sha256.Replace('sha256:','')){throw ('Existing frozen source differs: '+$r.path)}};if($f.EndsWith('.ps1')){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw ('Frozen source parse failure: '+$r.path)}}}
foreach($r in $sourceRows){$f=Join-Path $cached ($r.path -replace '/','\');$dest=Join-Path $repo ($r.path -replace '/','\');if(-not(Test-Path -LiteralPath $dest)){[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))|Out-Null;[IO.File]::Copy($f,$dest,$false)}}
Write-Output ('ROOT_FROZEN_SOURCE_ADMITTED count='+$sourceRows.Count)
$preflight='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\preflight.ps1'
& $preflight -Phase Launch -CompileReceiptSha256 '1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf' -ExeSha256 '3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a' -SerializerControlSha256 '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
Write-Output 'ROOT_PRELAUNCH_ADMISSION_PASS nativeLaunches=0'
