$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
if((Get-FileHash "$root\build-hosts-v2.ps1").Hash.ToLowerInvariant() -cne 'aca8470812578317e7f450e7a1b066d7711d9340020eb751f6e68eaca5a023e8'){throw 'Reviewed builder drift'}
& "$root\build-hosts-v2.ps1" -Package "$root\package"
@{completedAt=[DateTime]::UtcNow.ToString('o');status='COMPILER_REQUEST_RETURNED';nativeActions=0}|ConvertTo-Json
