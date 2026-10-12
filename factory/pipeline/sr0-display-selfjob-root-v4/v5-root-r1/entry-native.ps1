$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r1'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne '35d17ff8c1c50f3b582aabf334fcf885c6313d0bd81daa42c210ed9bf51ab6b4' -or (Get-FileHash (Join-Path $root 'one-run-plan.json')).Hash.ToLowerInvariant() -cne 'cde4aa3714853039ab0279c2b7e5cc821dad19655be1d3d60c3786da65166105'){throw 'v5 observer/plan drift'}
foreach($label in @('collector','coordinator','display','observer','wrapper')){$c=Get-Content -Raw (Join-Path $root ('actual-'+$label+'-controls.json'))|ConvertFrom-Json;if($c.status -cne 'passed'){throw 'actual v5 controls required'}}
$plan=Get-Content -Raw (Join-Path $root 'one-run-plan.json')|ConvertFrom-Json
if(Test-Path $plan.runRoot){throw 'fresh owned v5 run required'}
[IO.Directory]::CreateDirectory($plan.runRoot)|Out-Null
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'observer-source-r2.ps1') -PlanPath (Join-Path $root 'one-run-plan.json') -OutputPath 'D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\observer-v5-r1.json' -TransportHelperPath 'D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4\Sr0RootTransportJobV1.cs' -TransportHelperSha256 'f70ab1ebe1f70ea4833bb1944a1195e89875684882ae0541a5f9a3da5904dd2c' -DeadlineSeconds 1000
exit $LASTEXITCODE
