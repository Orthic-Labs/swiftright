$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\rectangle-fixed-r11-v2'
$preflight=Get-Content -LiteralPath (Join-Path $root 'control-count20-r3\root-preflight.json') -Raw|ConvertFrom-Json
if($preflight.status -cne 'preflight-passed' -or $preflight.nativeActions -ne 0 -or $preflight.lockActions -ne 0 -or $preflight.templateHash -cne 'd032edeffba82ae2eea3fad814f9da3d68bedf0a825357449f1872a247b57ec7' -or $preflight.sourceInputsHash -cne '8b4e7fdadbe3ece6f9356db3991b0619c13451ed961ffa1668c56d4f7c300f44'){throw 'exact admitted root preflight required'}
& (Join-Path $root 'overlay-count20-r3\coordinator-count20-v1.ps1') -Template $preflight.templatePath -TemplateHash $preflight.templateHash
Get-Content -LiteralPath (Join-Path $root 'control-count20-r3\coordinator.json') -Raw
