$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$base='D:\Claude\swiftright\factory\native\windows\.work\rectangle-fixed-r11-v2'
& (Join-Path $base 'overlay-count1-r1\coordinator-count1-r1.ps1') -Template (Join-Path $base 'control-count1-r1\config-template.json') -TemplateHash '89e4495c622e47e80115903f7359d1d95c273d53ce09e5279088d3a7e4868a9a'
Get-Content -Raw (Join-Path $base 'control-count1-r1\coordinator.json')
Get-Content -Raw (Join-Path $base 'control-count1-r1\task-result.json')
