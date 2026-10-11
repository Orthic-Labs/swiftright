$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\rectangle-r11'
& (Join-Path $root 'overlay-count20-r3\coordinator-count20-r3.ps1') -Template (Join-Path $root 'control-count20-r3\config-template.json') -TemplateHash '448b340079577398f01abd7b8184bf3acc5f7fc645d88cc5440cc418ccd9dce2'
Get-Content -Raw (Join-Path $root 'control-count20-r3\coordinator.json')
