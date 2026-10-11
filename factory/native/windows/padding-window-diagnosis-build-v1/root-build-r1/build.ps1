$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis'
if((Get-FileHash "$root\build-hosts-v2.ps1").Hash.ToLowerInvariant() -cne 'b9771ac8e8bec20169aa7d1609e669dbb08330ad7fd0b709c374ea03769e7384'){throw 'Reviewed builder drift'}
& "$root\build-hosts-v2.ps1" -Package "$root\package"
@{completedAt=[DateTime]::UtcNow.ToString('o');status='COMPILER_REQUEST_RETURNED';nativeActions=0}|ConvertTo-Json
