$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
$manifest=Join-Path $root 'root-stage-manifest.json'
if((Get-FileHash -LiteralPath $manifest).Hash.ToLowerInvariant() -cne '5756aa3041c7559b53c5d1ca7b8c7ea0cfa791adae3f2b5480699eec050f99d3'){throw 'Reviewed manifest drift'}
$stage=Get-Content -Raw -LiteralPath $manifest|ConvertFrom-Json
$prefix='factory/native/windows/padding-settled-build-v1/'
foreach($row in $stage.files){if(-not $row.path.StartsWith($prefix,[StringComparison]::Ordinal)){throw 'Unowned source reference'};$rel=$row.path.Substring($prefix.Length);$path=Join-Path $root $rel;if((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $row.hash.Replace('sha256:','') -or (Get-Item -LiteralPath $path).Length -ne $row.bytes){throw 'Transferred source drift'}}
& "$root\preflight.ps1" -Phase Compile
& "$root\run-controls.ps1"
& "$root\parse-stream-controls.ps1" -Output "$root\stream-parse.json"
& "$root\run-stream-controls.ps1"
& "$root\test-stream-admission.ps1" -OutputRoot "$root\stream-admission-faults"
[ordered]@{kind='root-padding-headless-controls';status='complete';utc=[DateTimeOffset]::UtcNow.ToString('o');sourceManifestHash='5756aa3041c7559b53c5d1ca7b8c7ea0cfa791adae3f2b5480699eec050f99d3';nativeWindows=0;desktopLockAcquired=$false}|ConvertTo-Json
