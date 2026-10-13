$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\text-style-r11-v1'
$preflight=Get-Content -LiteralPath (Join-Path $root 'control-count1-r2\root-preflight.json') -Raw|ConvertFrom-Json
if($preflight.status -cne 'preflight-passed' -or $preflight.nativeActions -ne 0 -or $preflight.lockActions -ne 0 -or $preflight.templateHash -cne 'd7701f2e5ed1b67fd9cdc1e16c64f0d7828aa3405a7aba1db10d9cb88fe68a61' -or $preflight.sourceInputsHash -cne 'fb268462f3c4ae0a85b3939dfb4c7d02910d32b880ae57e9c528702240ef549d'){throw 'exact admitted Text root preflight required'}
& (Join-Path $root 'overlay-count1-r2\coordinator-count1-v3.ps1') -Template $preflight.templatePath -TemplateHash $preflight.templateHash
Get-Content -LiteralPath (Join-Path $root 'control-count1-r2\coordinator.json') -Raw
