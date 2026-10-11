$ErrorActionPreference='Stop'
$expected='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
$destination='D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll'
$candidates=@('D:\Claude\swiftright\.work\sr0-r11\renderer\swiftright_render.dll','D:\Claude\sr0-r11\renderer\swiftright_render.dll')
$source=$null
foreach($candidate in $candidates){if(Test-Path -LiteralPath $candidate){if((Get-FileHash -LiteralPath $candidate).Hash.ToLowerInvariant() -cne $expected){throw 'Canonical renderer hash mismatch'};$source=$candidate;break}}
if(-not $source){throw 'Canonical renderer source unavailable'}
New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent)|Out-Null
$copied=$false
if(Test-Path -LiteralPath $destination){if((Get-FileHash -LiteralPath $destination).Hash.ToLowerInvariant() -cne $expected){throw 'Existing owned input hash mismatch'}}else{[IO.File]::Copy($source,$destination,$false);$copied=$true}
if((Get-FileHash -LiteralPath $destination).Hash.ToLowerInvariant() -cne $expected){throw 'Owned copy hash mismatch'}
[ordered]@{kind='factory-canonical-renderer-copy-v1';source=$source;destination=$destination;sha256=$expected;copied=$copied;utc=[DateTimeOffset]::UtcNow.ToString('o');desktopLockAcquired=$false;nativeExecuted=$false;deletedFiles=0}|ConvertTo-Json
