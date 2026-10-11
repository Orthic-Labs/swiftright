$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle'
$manifest=Join-Path $root 'root-stage-manifest.json'
if((Get-FileHash $manifest).Hash.ToLowerInvariant() -cne '53cb09f053872cfa35a5469ef220aaa5238a06c3fbd3ab80c4c72a2531e623ef'){throw 'Reviewed stage manifest drift'}
$stage=Get-Content $manifest -Raw|ConvertFrom-Json
foreach($row in $stage.files){
 if($row.path.StartsWith('factory/native/windows/stack-lifecycle-next-build-v1/')){$file=Join-Path $root $row.path.Replace('factory/native/windows/stack-lifecycle-next-build-v1/','')}else{$file=Join-Path 'D:\Claude\swiftright' $row.path}
 $expected=if($row.hash){$row.hash}else{$row.sha256}
 if((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $expected.Replace('sha256:','') -or (Get-Item -LiteralPath $file).Length -ne $row.bytes){throw ('Stage row drift '+$row.path)}
}
& "$root\preflight.ps1" -Phase Compile
& "$root\test-json-array-shape.ps1" -OutputRoot "$root\json-array-controls"
& "$root\test-producer-source-scope.ps1" -OutputRoot "$root\source-scope-controls"
& "$root\run-controls.ps1"
& "$root\parse-stream-controls.ps1" -Output "$root\stream-parse.json"
& "$root\run-stream-controls.ps1"
& "$root\test-stream-admission.ps1" -OutputRoot "$root\stream-admission-faults"
& "$root\build-hosts-v2.ps1" -Package "$root\package" -PreflightOnly
@{status='LIFECYCLE_HEADLESS_AND_BUILDER_PREFLIGHT_PASSED';stageSha256=(Get-FileHash $manifest).Hash.ToLowerInvariant();nativeWindowActions=0;completedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json
