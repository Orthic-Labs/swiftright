$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
$p='D:\Claude\swiftright\.factory-work\root-tools\text-late-cleanup-r2\cleanup-result.json'
$f=Get-Item -LiteralPath $p -Force
if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $f.Length -gt 2097152){throw 'unsafe cleanup receipt'}
$d=[IO.File]::ReadAllText($p)|ConvertFrom-Json
if($d.kind -cne 'text-count20-r9-owned-cleanup-v1' -or $d.qualificationClaim -ne $false -or $d.lockAction -cne 'none'){throw 'cleanup receipt kind/claim'}
[pscustomobject]@{path=$p;bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();receipt=$d}|ConvertTo-Json -Depth 20
