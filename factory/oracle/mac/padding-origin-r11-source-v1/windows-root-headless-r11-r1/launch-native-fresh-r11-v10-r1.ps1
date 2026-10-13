$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$ns='D:\Claude\swiftright\.factory-work\windows-replay-r11';$stage='D:\Claude\swiftright\.factory-work\windows-replay-r11\mac-schema-r2';$producer='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3'
$m=[IO.File]::ReadAllText((Join-Path $stage 'stage-manifest.json'))|ConvertFrom-Json
foreach($r in $m.files){$f=Join-Path $stage $r.path;if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Mac schema stage drift'}}
$overlay=Join-Path $ns 'overlay-v10';$control=Join-Path $ns 'coordinator-r1'
& (Join-Path $overlay 'resume-issued-coordinator-fresh-r11-v10.ps1') `
 -CompileReceiptHash '1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf' `
 -ExeHash '3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a' `
 -SerializerControlSha256 '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba' `
 -IssuedMetadataPath (Join-Path $control 'issued-metadata.json') -IssuedMetadataHash '7d1747fd3fbd62ddb3f6adfc4e3b9519636ee64b0ae6c759a53b103e176b03cb' `
 -GuardControlsPath (Join-Path $ns 'controls-full-r2\metadata-controls.json') -GuardControlsHash 'b9b55c9e5c1cba7d35bb217a88bd01b279e94d6188334ba643014af05db5a525' `
 -FreshGuardControlsPath (Join-Path $control 'fresh-guard.json') -FreshGuardControlsHash '77a7bc1ed917c176042b7aaa0afdb94c6dc67fb915cb2e03e54dd4c56aeab402' `
 -MacSchemaReceiptPath (Join-Path $stage 'mac-schema-receipt.json') -MacSchemaReceiptHash '20b11b0841f7ca730635f0dc4cfd3e31a02633ea9947f2f78ab2682e6ece47d1' `
 -ProducerRoot $producer -ControlRoot $control -RunRoot (Join-Path $ns 'replays\r1') -OutputRoot (Join-Path $ns 'replays') `
 -IntegrationGuardPath (Join-Path $overlay 'integration-fresh-r11-v6.ps1') -IntegrationGuardHash 'da5c99adc1919faf5a78cd4159b225e3ec7b38e30e92b099f6b724969445a1d7' `
 -SchemaPath (Join-Path $stage 'common.schema.json') -Count 20
