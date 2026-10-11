$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$overlay='D:\Claude\swiftright\factory\native\windows\.work\rectangle-r11\overlay-count1-r3'
& (Join-Path $overlay 'coordinator-count1-r3.ps1') -Template 'D:\Claude\swiftright\factory\native\windows\.work\rectangle-r11\control-count1-r3\config-template.json' -TemplateHash '01baf297326029b654997ce41f824abb39b485f41a6e60795789171f651054ca'
Get-Content -Raw 'D:\Claude\swiftright\factory\native\windows\.work\rectangle-r11\control-count1-r3\coordinator.json'
