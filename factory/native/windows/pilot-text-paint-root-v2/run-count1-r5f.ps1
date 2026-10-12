$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-v5f'
$control=Join-Path $root 'control-count1-r5';$p=Get-Content -LiteralPath (Join-Path $control 'package-preflight.json') -Raw|ConvertFrom-Json
if($p.status -cne 'source-package-preflight-passed' -or $p.nativeActions -ne 0 -or $p.lockActions -ne 0 -or $p.compilerActions -ne 0 -or $p.namespace -cne 'text-mta-r11-v5f' -or $p.sourceInputsHash -cne 'c87890c5cd085cca5643489e7268803eef0b11d6f530383ac4186f0e03c9ed9b'){throw 'exact source preflight required'}
$template=Join-Path $control 'config-template.json';if((Get-Item -LiteralPath $template).Length -gt 2097152){throw 'config bounds'};$hash=(Get-FileHash -LiteralPath $template).Hash.ToLowerInvariant()
& (Join-Path $root 'overlay-count1-r5\coordinator-count1-v3.ps1') -Template $template -TemplateHash $hash
Get-Content -LiteralPath (Join-Path $control 'coordinator.json') -Raw
