$ErrorActionPreference='Stop'
$repo='D:\Claude\swiftright'
$root=Join-Path $repo 'factory\native\windows\native-host-validity-fix-v1'
$manifest=Join-Path $root 'root-stage-manifest.json'
if((Get-FileHash $manifest).Hash.ToLowerInvariant() -cne 'f1f03d5dfea9938d6cd360713481b9d3f80fcee48fbfb13b2f4e3ef905dec679'){throw 'Stage drift'}
$stage=Get-Content $manifest -Raw|ConvertFrom-Json
foreach($row in $stage.files){$file=Join-Path $repo $row.path;if((Get-FileHash $file).Hash.ToLowerInvariant() -cne $row.hash.Replace('sha256:','') -or (Get-Item $file).Length -ne $row.bytes){throw ('Source drift '+$row.path)}}
$out=Join-Path $root 'actual-controls-r1'
if(Test-Path $out){throw 'Fresh output required'}
New-Item -ItemType Directory -Path $out|Out-Null
& (Join-Path $root 'test-host-output.ps1') -OutputPath (Join-Path $out 'control.json')
Get-Content (Join-Path $out 'control.json') -Raw
