# Offline source controls only; no compiler, native process, GUI, lock, remote or filesystem mutation beyond output.
param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputPath){throw 'Fresh source-control output required'}
$here=$PSScriptRoot
$issuer=[IO.File]::ReadAllText((Join-Path $here 'issue-before-launch.ps1'))
$integration=[IO.File]::ReadAllText((Join-Path $here 'support\integration.ps1'))
$runner=[IO.File]::ReadAllText((Join-Path $here 'capture-repeat.ps1'))
$rows=@(
 @{control='wrong-tuple-kind';passed=($issuer.Contains('factory-source-bound-candidate-canonical-tuple-v1') -and $integration.Contains('Candidate tuple wrapper/case boundary mismatch'))},
 @{control='wrong-case';passed=($integration.Contains('$tuple.case.id -cne $plan.case.id') -and $integration.Contains('$tuple.case.hash -cne $plan.case.hash'))},
 @{control='wrong-runtime';passed=($integration.Contains('$tuple.tuple.runtimeCommit -cne $plan.runtimeSourceCommit') -and $integration.Contains('$candidate.runtime.sourceCommit -cne $plan.runtimeSourceCommit'))},
 @{control='wrong-renderer';passed=($integration.Contains('$tuple.tuple.rendererHash -cne') -and $integration.Contains('$candidate.renderer.sha256 -cne'))},
 @{control='wrong-metadata';passed=($issuer.Contains("[IO.FileMode]::CreateNew") -and $issuer.Contains('$file.Flush($true)') -and $integration.Contains('Issued metadata exact raw reference mismatch'))},
 @{control='writer-binding';passed=($runner.Contains('Copy-Item -LiteralPath $candidateSource') -and $runner.Contains('candidateTupleRef=$issuedMetadata.candidateTuple') -and $runner.Contains('candidateBindingRef=$issuedMetadata.sourceBoundCandidateTuple'))},
 @{control='phase-ordering';passed=($runner.Contains('capture-ordering-worker-ready') -and $runner.Contains('capture-ordering-pixels-start') -and $runner.Contains('capture-ordering-pixels-complete') -and $runner.Contains('capture-ordering-close-pending'))}
)
if(@($rows|Where-Object{-not $_.passed}).Count){throw 'Source string control failed'}
[ordered]@{kind='factory-source-string-controls-v1';status='passed';controls=$rows;nativeActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $OutputPath
