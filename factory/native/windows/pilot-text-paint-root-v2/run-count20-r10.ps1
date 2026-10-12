$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r10'
$control=Join-Path $root 'control-count20-r10';$admission=Join-Path $root 'admission-count20-r10'
$coordinator=Join-Path $root 'overlay-count20-r10\coordinator-count20-lifecycle-v1.ps1';$template=Join-Path $control 'config-template.json'
if((Get-FileHash -LiteralPath $coordinator).Hash.ToLowerInvariant() -cne 'd73e8c79d007939b8add37e6a95c61bf000c698f28acc71b4311d8e695860a46' -or (Get-FileHash -LiteralPath $template).Hash.ToLowerInvariant() -cne '5cebff95d8fa7332d7dad388e4038f9702962b6ec9b4381d6bf26688af442e3f' -or (Get-FileHash -LiteralPath (Join-Path $admission 'source-inputs.json')).Hash.ToLowerInvariant() -cne 'eef7fb4a996c890a450192b08db1e94d491d7c4476d913d88112aeebe32ffdc4'){throw 'reviewed source/template/coordinator drift'}
$preflight=Get-Content -LiteralPath (Join-Path $control 'package-preflight.json') -Raw|ConvertFrom-Json
if($preflight.status -cne 'source-count20-preflight-passed' -or $preflight.profile -cne 'text' -or $preflight.count -ne 20 -or $preflight.nativeActions -ne 0 -or $preflight.lockActions -ne 0 -or $preflight.compilerActions -ne 0 -or $preflight.sourceInputsHash -cne 'eef7fb4a996c890a450192b08db1e94d491d7c4476d913d88112aeebe32ffdc4'){throw 'measured source preflight required'}
& $coordinator -Template $template -TemplateHash '5cebff95d8fa7332d7dad388e4038f9702962b6ec9b4381d6bf26688af442e3f'
Get-Content -LiteralPath (Join-Path $control 'coordinator.json') -Raw
