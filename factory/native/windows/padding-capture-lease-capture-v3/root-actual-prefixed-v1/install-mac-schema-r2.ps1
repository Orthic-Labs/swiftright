$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\transports\prefixed-mac-schema-r1.zip';$stage='D:\Claude\swiftright\.factory-work\controls\prefixed-mac-schema-r1'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne '6fb074a969005f3cdd4dfeba303dc19e56daaf3cbf79b701d05f3eff53e1a85d'){throw 'Mac schema zip drift'}
if(-not(Test-Path -LiteralPath $stage -PathType Container)){throw 'Extracted source stage required'}
$rows=@'
[{"count": 1, "path": "mac-schema-count1-r1.json", "bytes": 1758, "sha256": "42096056292e84107b5ea67fe012ace2e16de5182f70cc576dd9e28f82cbc434"}, {"count": 20, "path": "mac-schema-count20-r1.json", "bytes": 1758, "sha256": "f5e5bbd33507b90166f697cca9e312bef2a103638f19a8a7b0247391240b794e"}]
'@|ConvertFrom-Json
$here='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3'
foreach($r in $rows){$src=Join-Path $stage $r.path;if((Get-Item -LiteralPath $src).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $src).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Schema receipt staged drift'};$lane=if($r.count -eq 1){'coordinator-single-r1'}else{'coordinator-repeat-r1'};$dst=Join-Path (Join-Path $here $lane) 'mac-schema-receipt-r1.json';if(Test-Path -LiteralPath $dst){throw 'Immutable schema receipt exists'};[IO.File]::Copy($src,$dst,$false)}
[ordered]@{status='PASS_EXACT_MAC_SCHEMA_RECEIPTS';nativeActions=0;lockActions=0;receipts=$rows}|ConvertTo-Json -Depth 8
