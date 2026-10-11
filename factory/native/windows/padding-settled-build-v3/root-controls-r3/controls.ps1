$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
$manifest=Join-Path $root 'root-stage-manifest.json'
if((Get-FileHash $manifest).Hash.ToLowerInvariant() -cne '6a83289103471c1d4b2221c81479bbe3cd5aea501eec3e35c0aaccb309a20800'){throw 'Stage manifest drift'}
$m=Get-Content $manifest -Raw|ConvertFrom-Json
foreach($row in $m.files){
 $relative=$row.path.Replace('factory/native/windows/padding-settled-build-v3/','')
 if($relative -ceq $row.path){throw 'Stage prefix wrong'}
 $file=Join-Path $root $relative
 if((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $row.hash.Replace('sha256:','') -or (Get-Item -LiteralPath $file).Length -ne $row.bytes){throw ('Stage file drift '+$relative)}
}
& "$root\preflight.ps1" -Phase Compile
& "$root\test-json-array-shape.ps1" -OutputRoot "$root\json-array-controls"
& "$root\test-producer-source-scope.ps1" -OutputRoot "$root\source-scope-controls"
& "$root\run-controls.ps1"
& "$root\parse-stream-controls.ps1" -Output "$root\stream-parse.json"
& "$root\run-stream-controls.ps1"
& "$root\test-stream-admission.ps1" -OutputRoot "$root\stream-admission-faults"
& "$root\build-hosts-v2.ps1" -Package "$root\package" -PreflightOnly
@{status='HEADLESS_CONTROLS_AND_BUILD_PREFLIGHT_PASSED';stageSha256=(Get-FileHash $manifest).Hash.ToLowerInvariant();compilerRuns=0;nativeRuns=0;completedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json
