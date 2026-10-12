# Root-owned guarded final entry; archive prebuild inputs before copy.
param([switch]$PreflightOnly)
$ErrorActionPreference = 'Stop'
$stage = 'D:\Claude\swiftright\.factory-work\hosts\bundled-font-compiled'
$archive = Join-Path $stage 'prebuild-archive-attempt-2'
$finalReceipt = Join-Path $stage 'final-r1\observation.json'
$planTarget = Join-Path $stage 'package\plan-final-v4.json'
$builderTarget = Join-Path $stage 'build-owned-final-v1.ps1'
$requestRoot = $PSScriptRoot
if ($PreflightOnly) {
  if ((Test-Path -LiteralPath $finalReceipt) -or (Test-Path -LiteralPath $archive)) { throw 'preflight requires untouched final stage' }
  if ((Test-Path -LiteralPath $planTarget) -or (Test-Path -LiteralPath $builderTarget)) { throw 'preflight refuses existing final inputs' }
  $requestPlan = Join-Path $requestRoot 'plan-final-v4.json'
  $requestBuilder = Join-Path $requestRoot 'build-owned-final-v1.ps1'
  if (-not (Test-Path -LiteralPath $requestPlan) -or -not (Test-Path -LiteralPath $requestBuilder)) { throw 'preflight request files missing' }
  $planHash = (Get-FileHash -LiteralPath $requestPlan -Algorithm SHA256).Hash.ToLowerInvariant()
  $builderHash = (Get-FileHash -LiteralPath $requestBuilder -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($planHash.Length -ne 64 -or $builderHash.Length -ne 64) { throw 'preflight request hashes unavailable' }
  [ordered]@{status='request-inputs-ready'; preflightKind='hash-only-request-input-preflight'; compilerAdmission=$false; builderPreflightRequired=$true; planSha256=$planHash; builderSha256=$builderHash; archiveCreated=$false; finalInputsInstalled=$false; nativeActions=0} | ConvertTo-Json -Compress
  exit 0
}
if (Test-Path -LiteralPath $finalReceipt) { throw 'refuse overwrite of existing final receipt' }
if (Test-Path -LiteralPath $archive) { throw 'refuse overwrite of prebuild archive' }
if ((Test-Path -LiteralPath $planTarget) -or (Test-Path -LiteralPath $builderTarget)) { throw 'refuse overwrite of final inputs' }
New-Item -ItemType Directory -Path $archive | Out-Null
Copy-Item -LiteralPath (Join-Path $requestRoot 'plan-prebuild-v4.json') -Destination (Join-Path $archive 'plan-prebuild-v4.json')
Copy-Item -LiteralPath (Join-Path $requestRoot 'build-owned-pilot-v1.ps1') -Destination (Join-Path $archive 'build-owned-pilot-v1.ps1')
Copy-Item -LiteralPath (Join-Path $requestRoot 'plan-final-v4.json') -Destination $planTarget
Copy-Item -LiteralPath (Join-Path $requestRoot 'build-owned-final-v1.ps1') -Destination $builderTarget
$planHash = (Get-FileHash -LiteralPath $planTarget -Algorithm SHA256).Hash.ToLowerInvariant()
$builderPreflight = @(& $builderTarget -PlanPath $planTarget -PlanSha256 $planHash -Phase final -Attempt 1 -PreflightOnly)
if ($builderPreflight.Count -eq 0) { throw 'builder PreflightOnly returned no success record' }
$builderPreflightRecord = ($builderPreflight -join "`n") | ConvertFrom-Json
if ($builderPreflightRecord.status -cne 'passed') { throw 'builder PreflightOnly did not return passed status' }
& $builderTarget -PlanPath $planTarget -PlanSha256 $planHash -Phase final -Attempt 1
