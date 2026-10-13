$ErrorActionPreference='Stop'
$src='D:\Claude\swiftright\.factory-work\transports\mac-schema-count1-r2.json';$dst='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3\coordinator-single-r1\mac-schema-receipt-r1.json'
if((Get-FileHash -LiteralPath $src).Hash.ToLowerInvariant() -cne '11b7a770c05ab3fae3037fa3a8df01c4d202d2f039d91279fb9199a77c4686d2'){throw 'schema receipt bytes drift'}
if(Test-Path -LiteralPath $dst){throw 'Immutable receipt exists'};[IO.File]::Copy($src,$dst,$false)
@{status='PASS_EXACT_SCHEMA_RECEIPT';sha256=(Get-FileHash -LiteralPath $dst).Hash.ToLowerInvariant();nativeActions=0}|ConvertTo-Json
