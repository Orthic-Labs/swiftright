$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle'
if((Get-FileHash "$root\build-hosts-v2.ps1").Hash.ToLowerInvariant() -cne '09de02418ae4115819ea0ac86d38e19e2af234240dec059b8fd519636696d655'){throw 'Reviewed builder drift'}
& "$root\build-hosts-v2.ps1" -Package "$root\package"
@{completedAt=[DateTime]::UtcNow.ToString('o');status='COMPILER_REQUEST_RETURNED';nativeActions=0}|ConvertTo-Json
