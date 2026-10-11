$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
if((Get-FileHash "$root\build-hosts-v2.ps1").Hash.ToLowerInvariant() -cne '9d597e93291233783f7cba00c361b72cc67abadd9dced0f7d87b3d344b6edcc1'){throw 'Reviewed builder drift'}
& "$root\build-hosts-v2.ps1" -Package "$root\package"
@{completedAt=[DateTime]::UtcNow.ToString('o');status='COMPILER_REQUEST_RETURNED';nativeActions=0}|ConvertTo-Json
