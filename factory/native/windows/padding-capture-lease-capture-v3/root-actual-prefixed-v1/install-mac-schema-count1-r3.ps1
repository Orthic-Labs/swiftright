$ErrorActionPreference='Stop'
$src='D:\Claude\swiftright\.factory-work\transports\mac-schema-count1-r3.json';$dst='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3\coordinator-single-r1\mac-schema-receipt-r1.json'
if((Get-FileHash -LiteralPath $src).Hash.ToLowerInvariant() -cne '6fc3fa0405ce9e68d1793b6659af84943c81c00a153e2312ace2d5024c5094d9'){throw 'schema receipt bytes drift'}
if(Test-Path -LiteralPath $dst){throw 'Immutable receipt exists'};[IO.File]::Copy($src,$dst,$false)
@{status='PASS_EXACT_SCHEMA_RECEIPT';sha256=(Get-FileHash -LiteralPath $dst).Hash.ToLowerInvariant();nativeActions=0}|ConvertTo-Json
