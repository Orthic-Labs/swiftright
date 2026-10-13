$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r10'
$wrapper='D:\Claude\swiftright\.factory-work\root-tools\sr0-staged-controls-r10b-source.ps1'
if((Get-FileHash -LiteralPath $wrapper).Hash.ToLowerInvariant() -cne 'e128d4e35d622ccc6183534e8f161107a06f88288abf01fefe3df2303f3e3aa3'){throw 'exact wrapper pin required'}
$failed='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r10\drain-controls-r10.json'
$retired='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r10\drain-controls-r10b-held.json'
if((Get-FileHash -LiteralPath $failed).Hash.ToLowerInvariant() -cne 'a7330f2f513ae723cd3bc7cbeaf046b0663520425345127be73f16d46fcb54aa' -or (Test-Path -LiteralPath $retired)){throw 'exact failed receipt & fresh preservation path required'}
if(@(Get-CimInstance Win32_Process|Where-Object{$_.CommandLine -and $_.CommandLine.Contains('sr0-staged-controls-r10b-entry.ps1')}).Count -ne 0){throw 'previous exact entry still live'}
Move-Item -LiteralPath $failed -Destination $retired
$preflight='D:\Claude\swiftright\.factory-work\root-tools\source-root-r10\factory\pipeline\sr0-display-selfjob-v4\prospective-native-stage-v1\entry-native-r8.ps1'
$pin=(Get-FileHash -LiteralPath $preflight).Hash.ToLowerInvariant()
if($pin -cne '4444285063e55cba8d7a3d989d9bfb3bfbf94b19f85bc77c6793f441184a15dd'){throw 'exact preflight pin required'}
& $wrapper -StageRoot $stage -PlanPath (Join-Path $stage 'one-run-plan-r8.json') -ExpectedPlanSha256 '28bb2ce28978e637484de01d80f0d9972845f8ff97107a345993ccbc3815d1eb' -PreflightPath $preflight -ExpectedPreflightSha256 $pin -OutputPath $failed -GateReceiptPath (Join-Path $stage 'staged-controls-gate-r10c.json')
