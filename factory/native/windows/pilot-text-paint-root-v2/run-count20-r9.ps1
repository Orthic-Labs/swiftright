$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r9'
$control=Join-Path $root 'control-count20-r5';$admission=Join-Path $root 'admission-count20-r5'
$coordinator=Join-Path $root 'overlay-count20-r5\coordinator-count20-lifecycle-v1.ps1';$template=Join-Path $control 'config-template.json'
if((Get-FileHash -LiteralPath $coordinator).Hash.ToLowerInvariant() -cne 'd73e8c79d007939b8add37e6a95c61bf000c698f28acc71b4311d8e695860a46' -or (Get-FileHash -LiteralPath $template).Hash.ToLowerInvariant() -cne '80c1efb9e923050f97d5b5ea5a033aedbbe5b5ddb1047fb56a480e90731db948' -or (Get-FileHash -LiteralPath (Join-Path $admission 'source-inputs.json')).Hash.ToLowerInvariant() -cne '6c335ddead9c023b1faf40bc9e02fb679112f48ec1955934dd28ce4268789c22'){throw 'reviewed source/template/coordinator drift'}
$preflight=Get-Content -LiteralPath (Join-Path $control 'package-preflight.json') -Raw|ConvertFrom-Json
if($preflight.status -cne 'source-count20-preflight-passed' -or $preflight.profile -cne 'text' -or $preflight.count -ne 20 -or $preflight.nativeActions -ne 0 -or $preflight.lockActions -ne 0 -or $preflight.compilerActions -ne 0 -or $preflight.sourceInputsHash -cne '6c335ddead9c023b1faf40bc9e02fb679112f48ec1955934dd28ce4268789c22'){throw 'measured source preflight required'}
& $coordinator -Template $template -TemplateHash '80c1efb9e923050f97d5b5ea5a033aedbbe5b5ddb1047fb56a480e90731db948'
Get-Content -LiteralPath (Join-Path $control 'coordinator.json') -Raw
