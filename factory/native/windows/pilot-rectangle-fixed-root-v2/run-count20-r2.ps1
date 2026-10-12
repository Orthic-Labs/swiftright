$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\rectangle-fixed-r11-v2'
$preflight=Get-Content -LiteralPath (Join-Path $root 'control-count20-r2\root-preflight.json') -Raw|ConvertFrom-Json
if($preflight.status -cne 'preflight-passed' -or $preflight.nativeActions -ne 0 -or $preflight.lockActions -ne 0 -or $preflight.templateHash -cne '8815a3389513aed177a89140667c5c3d9e01b1e79f4eebecbd897bdb6f265eab' -or $preflight.sourceInputsHash -cne '18652bf750e4b3c21acf48cb5243b902bf83d59f494f1a08adedf39d5f16cda5'){throw 'exact admitted root preflight required'}
& (Join-Path $root 'overlay-count20-r2\coordinator-count20-v1.ps1') -Template $preflight.templatePath -TemplateHash $preflight.templateHash
Get-Content -LiteralPath (Join-Path $root 'control-count20-r2\coordinator.json') -Raw
