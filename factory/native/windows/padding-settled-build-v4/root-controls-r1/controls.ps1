$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
$manifest=Join-Path $root 'root-stage-manifest.json'
if((Get-FileHash $manifest).Hash.ToLowerInvariant() -cne '36fd65d1962312ea8aa8786235fe2c11f05514716b37e65908a914c4e8b16334'){throw 'Reviewed stage manifest drift'}
$stage=Get-Content $manifest -Raw|ConvertFrom-Json
foreach($row in $stage.files){
 if($row.path.StartsWith('factory/native/windows/padding-settled-build-v4/')){$file=Join-Path $root $row.path.Replace('factory/native/windows/padding-settled-build-v4/','')}else{$file=Join-Path 'D:\Claude\swiftright' $row.path}
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
& "$root\run-serializer-control.ps1" -SwiftcSha256 '1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'
& "$root\build-hosts-v2.ps1" -Package "$root\package" -PreflightOnly
@{status='V4_HEADLESS_SERIALIZER_AND_BUILDER_PREFLIGHT_PASSED';stageSha256=(Get-FileHash $manifest).Hash.ToLowerInvariant();nativeWindowActions=0;completedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json
