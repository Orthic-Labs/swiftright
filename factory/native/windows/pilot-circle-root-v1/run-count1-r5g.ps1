$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\circle-mta-r11-v5g'
$control=Join-Path $root 'control-count1-r5';$p=Get-Content -LiteralPath (Join-Path $control 'package-preflight.json') -Raw|ConvertFrom-Json
if($p.status -cne 'source-package-preflight-passed' -or $p.nativeActions -ne 0 -or $p.lockActions -ne 0 -or $p.compilerActions -ne 0 -or $p.namespace -cne 'circle-mta-r11-v5g' -or $p.sourceInputsHash -cne 'f366528edd3cb557a33e5cec1c942af295a34ecab50657d5bc9c0420c1170f64'){throw 'exact source preflight required'}
$template=Join-Path $control 'config-template.json';if((Get-Item -LiteralPath $template).Length -gt 2097152){throw 'config bounds'};$hash=(Get-FileHash -LiteralPath $template).Hash.ToLowerInvariant()
& (Join-Path $root 'overlay-count1-r5\coordinator-count1-v3.ps1') -Template $template -TemplateHash $hash
Get-Content -LiteralPath (Join-Path $control 'coordinator.json') -Raw
