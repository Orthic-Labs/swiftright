$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline';$z=Join-Path $stage 'source-stage-r2.zip'
if((Get-Item $z).Length -gt 1MB -or (Get-FileHash $z).Hash.ToLowerInvariant() -cne 'b3bb661c4c069ef2ca627824f346820ee1428d8cdce010fa95da9c07eadb5b45'){throw 'source archive drift'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($z,$stage)
$mp=Join-Path $stage 'stage-manifest-r2.json';if((Get-FileHash $mp).Hash.ToLowerInvariant() -cne '7f5bff5d21a5a51e6efaa3ec7b62c3bd472c9bd8c8820d76a631affa4f854f9f'){throw 'manifest drift'}
$m=Get-Content -Raw $mp|ConvertFrom-Json;foreach($row in $m.rows){$f=Join-Path $stage $row.path;if((Get-Item $f).Length -ne $row.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){throw 'file drift'}}
& (Join-Path $stage 'build-text-r2.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild-r2.json') -PlanSha256 '7ef11e3921290d8872dad95e8f16d5bb16c03430dfe72671206020c2df0a107a' -Phase prebuild -Attempt 2 -PreflightOnly
