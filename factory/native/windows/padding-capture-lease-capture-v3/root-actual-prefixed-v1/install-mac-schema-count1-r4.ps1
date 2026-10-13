$ErrorActionPreference='Stop'
$src='D:\Claude\swiftright\.factory-work\transports\mac-schema-count1-r4.json';$dst='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3\coordinator-single-r1\mac-schema-receipt-r1.json'
if((Get-FileHash -LiteralPath $src).Hash.ToLowerInvariant() -cne '26fd600fb798ac0268ede293d97f3f2bfa514ddd9be5790b7f030a6e5506888d'){throw 'schema receipt bytes drift'}
if(Test-Path -LiteralPath $dst){throw 'Immutable receipt exists'};[IO.File]::Copy($src,$dst,$false)
@{status='PASS_EXACT_SCHEMA_RECEIPT';sha256=(Get-FileHash -LiteralPath $dst).Hash.ToLowerInvariant();nativeActions=0}|ConvertTo-Json
