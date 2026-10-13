$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\transports\native-repeat7-source.zip';$stage='D:\Claude\swiftright\.factory-work\controls\native-repeat7-source';$repo='D:\Claude\swiftright'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne '602d3ada0e91c01640920d883eb2df09146d7783bdf17af09006f325beaa764e'){throw 'source zip drift'};if(Test-Path -LiteralPath $stage){throw 'exclusive source stage exists'};Expand-Archive -LiteralPath $zip -DestinationPath $stage
$m=Join-Path $stage 'manifest.json';if((Get-FileHash -LiteralPath $m).Hash.ToLowerInvariant() -cne '825f850618f55a88d21767e408cfa836dc29367dcf7eaebb9a5eb4025865f749'){throw 'source manifest drift'}
$rows=@((Get-Content -Raw -LiteralPath $m|ConvertFrom-Json).files)
foreach($r in $rows){$src=Join-Path $stage ($r.path -replace '/','\');$dst=Join-Path $repo ($r.path -replace '/','\');if((Get-FileHash -LiteralPath $src).Hash.ToLowerInvariant() -cne $r.sha256 -or (Get-Item -LiteralPath $src).Length -ne $r.bytes){throw 'source member drift'};if(Test-Path -LiteralPath $dst){throw 'immutable new source exists'};$tok=$null;$err=$null;[System.Management.Automation.Language.Parser]::ParseFile($src,[ref]$tok,[ref]$err)|Out-Null;if($err.Count){throw 'actual source parse failed'}}
foreach($r in $rows){$src=Join-Path $stage ($r.path -replace '/','\');$dst=Join-Path $repo ($r.path -replace '/','\');[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))|Out-Null;[IO.File]::Copy($src,$dst,$false)}
@{status='PASS_EXACT_SIX_REPEAT7_SOURCE_FILES_WINDOWS_PARSER';files=$rows;nativeActions=0;lockActions=0}|ConvertTo-Json -Depth 8

$src='D:\Claude\swiftright\.factory-work\transports\mac-schema-count20-r7.json';$dst='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3\coordinator-repeat-r1\mac-schema-receipt-r1.json'
if((Get-FileHash -LiteralPath $src).Hash.ToLowerInvariant() -cne '89505798b980d5d39b8cafe0ee95148c82810e6a3f40c1ecccbde6c819471c09'){throw 'schema receipt bytes drift'};if(Test-Path -LiteralPath $dst){throw 'Immutable schema exists'};[IO.File]::Copy($src,$dst,$false)
@{status='PASS_EXACT_COUNT20_SCHEMA_RECEIPT';sha256=(Get-FileHash -LiteralPath $dst).Hash.ToLowerInvariant();nativeActions=0}|ConvertTo-Json
