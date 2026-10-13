$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline';$zip=Join-Path $stage 'source-stage-r1.zip'
if((Get-Item $zip).Length -gt 1MB -or (Get-FileHash $zip).Hash.ToLowerInvariant() -cne 'b7d08cbe3a59ed9926e37fb33702346b2210536cca08e0aa8fadfb9615689517'){throw 'archive drift'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
if(Test-Path (Join-Path $stage 'package')){throw 'fresh Text package required'}
[IO.Compression.ZipFile]::ExtractToDirectory($zip,$stage)
$mp=Join-Path $stage 'stage-manifest-r1.json';if((Get-FileHash $mp).Hash.ToLowerInvariant() -cne '6260d869af111dd220d78433dba3e8566b263cc68f10c1b06f3d93e2d01fa556'){throw 'stage manifest drift'}
$m=Get-Content -Raw $mp|ConvertFrom-Json
foreach($row in $m.rows){$f=Join-Path $stage $row.path;if((Get-Item $f).Length -ne $row.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){throw 'staged source drift'}}
& (Join-Path $stage 'build-text-r1.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild.json') -PlanSha256 '38a699dcb022f8740a242c82a8402200fd36953f2ea07401d722edad20ffc4cd' -Phase prebuild -PreflightOnly
