$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\rectangle-fixed-r11-v2'
$preflight=Get-Content -LiteralPath (Join-Path $root 'control-count20-r4\root-preflight.json') -Raw|ConvertFrom-Json
if($preflight.status -cne 'preflight-passed' -or $preflight.nativeActions -ne 0 -or $preflight.lockActions -ne 0){throw 'frozen root preflight required'}
& (Join-Path $root 'overlay-count20-r4\coordinator-count20-v1.ps1') -Template $preflight.templatePath -TemplateHash $preflight.templateHash
Get-Content -LiteralPath (Join-Path $root 'control-count20-r4\coordinator.json') -Raw
