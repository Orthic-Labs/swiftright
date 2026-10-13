$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count1-r11'
$control=Join-Path $root 'control-count1-r5'
$preflight=Join-Path $control 'package-preflight.json'
if((Get-Item -LiteralPath $preflight).Length -gt 2097152){throw 'source preflight bounds'}
$p=Get-Content -LiteralPath $preflight -Raw|ConvertFrom-Json
if($p.status -cne 'source-package-preflight-passed' -or $p.nativeActions -ne 0 -or $p.lockActions -ne 0 -or $p.compilerActions -ne 0 -or $p.namespace -cne 'text-mta-r11-count1-r11' -or $p.sourceInputsHash -cne 'a620d7915a974fed7ef90bda5a2ccd32b89a9cc65ec4b88bfd1baae09bb47b4e'){throw 'exact source preflight required'}
$template=Join-Path $control 'config-template.json'
if((Get-Item -LiteralPath $template).Length -gt 2097152){throw 'config bounds'}
$hash=(Get-FileHash -LiteralPath $template).Hash.ToLowerInvariant()
& (Join-Path $root 'overlay-count1-r5\coordinator-count1-v3.ps1') -Template $template -TemplateHash $hash
Get-Content -LiteralPath (Join-Path $control 'coordinator.json') -Raw
