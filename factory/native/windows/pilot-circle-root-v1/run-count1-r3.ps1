$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\circle-r11-v1'
$preflight=Get-Content -LiteralPath (Join-Path $root 'control-count1-r3\root-preflight.json') -Raw|ConvertFrom-Json
if($preflight.status -cne 'preflight-passed' -or $preflight.nativeActions -ne 0 -or $preflight.lockActions -ne 0 -or $preflight.templateHash -cne '6f868776627c1167cafe1ffb32f7fe55cc8d9fecc2425cf6c686d02d98694b9e' -or $preflight.sourceInputsHash -cne '7ba58fa834e0ec068aacab7a62d162b0973314b3e10678809b489abe4d85bbb9'){throw 'exact admitted Circle root preflight required'}
& (Join-Path $root 'overlay-count1-r3\coordinator-count1-v3.ps1') -Template $preflight.templatePath -TemplateHash $preflight.templateHash
Get-Content -LiteralPath (Join-Path $root 'control-count1-r3\coordinator.json') -Raw
