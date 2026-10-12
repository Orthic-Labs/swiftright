$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r2'
if((Get-FileHash (Join-Path $root 'observer-source-v5-r1.ps1')).Hash.ToLowerInvariant() -cne 'a9cecf369df580f9f0ae63ed8746812bc6a6bd0e56b289c6af47e72ed3c398fe' -or (Get-FileHash (Join-Path $root 'one-run-plan.json')).Hash.ToLowerInvariant() -cne '566c0441fccdf55b81dca579bd1fd1eab24e24f5eb0f9b0339047327472586f2'){throw 'v5 observer/plan drift'}
foreach($label in @('collector','coordinator','display','observer','wrapper','predicate','materializer')){$c=Get-Content -Raw (Join-Path $root ('actual-'+$label+'-controls.json'))|ConvertFrom-Json;if(($label -in @('collector','observer','predicate') -and $c.status -cne 'passed-source-controls') -or ($label -notin @('collector','observer','predicate') -and $c.status -cne 'passed')){throw 'actual v5 controls required'}}
$plan=Get-Content -Raw (Join-Path $root 'one-run-plan.json')|ConvertFrom-Json
if(Test-Path $plan.runRoot){throw 'fresh owned v5 run required'}
[IO.Directory]::CreateDirectory($plan.runRoot)|Out-Null
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'observer-source-v5-r1.ps1') -PlanPath (Join-Path $root 'one-run-plan.json') -OutputPath 'D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\observer-v5-r2.json' -TransportHelperPath 'D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4\Sr0RootTransportJobV1.cs' -TransportHelperSha256 'f70ab1ebe1f70ea4833bb1944a1195e89875684882ae0541a5f9a3da5904dd2c' -DeadlineSeconds 1000
exit $LASTEXITCODE
