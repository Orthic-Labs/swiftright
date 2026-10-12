$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-v5g'
$control=Join-Path $root 'control-count1-r5';$p=Get-Content -LiteralPath (Join-Path $control 'package-preflight.json') -Raw|ConvertFrom-Json
if($p.status -cne 'source-package-preflight-passed' -or $p.nativeActions -ne 0 -or $p.lockActions -ne 0 -or $p.compilerActions -ne 0 -or $p.namespace -cne 'text-mta-r11-v5g' -or $p.sourceInputsHash -cne '7ca9e0d5d811e316bc01a90447a17243b9430290112ce7979abbf8d678b6a9e3'){throw 'exact source preflight required'}
$template=Join-Path $control 'config-template.json';if((Get-Item -LiteralPath $template).Length -gt 2097152){throw 'config bounds'};$hash=(Get-FileHash -LiteralPath $template).Hash.ToLowerInvariant()
& (Join-Path $root 'overlay-count1-r5\coordinator-count1-v3.ps1') -Template $template -TemplateHash $hash
Get-Content -LiteralPath (Join-Path $control 'coordinator.json') -Raw
