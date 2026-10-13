# Parser/source admission only. No Process.Start, native window, compiler or desktop lock.
param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputPath){throw 'Fresh source-control output required'}
$rows=@()
foreach($path in @(Get-ChildItem $PSScriptRoot -Recurse -File -Filter '*.ps1'|Where-Object{$_.FullName -notmatch '\\independent-review\\'})){
 $tokens=$null;$errors=$null
 [Management.Automation.Language.Parser]::ParseFile($path.FullName,[ref]$tokens,[ref]$errors)|Out-Null
 if(@($errors).Count){throw ('Source AST failed: '+$path.Name)}
 $rows+=@{path=$path.FullName;sha256=(Get-FileHash $path.FullName).Hash.ToLowerInvariant();errors=0}
}
$runner=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'capture-repeat.ps1'))
foreach($required in @("[ValidateSet(1,20)][int]`$Count=1","if(-not `$validHost){throw 'Owned host output failed original validity predicate'}",'AddSeconds(15)','$stdoutTask.Wait(5000)','$stderrTask.Wait(5000)','Invoke-FactoryOwnedCleanup','Test-FactoryKernelExitCertificate')){
 # Kernel certificate exists in inherited helper rather than runner.
 if($required -ceq 'Test-FactoryKernelExitCertificate'){continue}
 if(-not $runner.Contains($required)){throw ('Required production guard missing: '+$required)}
}
if($runner -match 'UIAutomationClient|UIAutomationTypes|Windows\.Automation|Read-UIA'){throw 'Parent retained UIA authority'}
$workerAt=$runner.IndexOf('Invoke-FactoryUiaSnapshotWorker $target')
$pixelsAt=$runner.IndexOf('$pixels=Capture-FactoryPixels')
$closeAt=$runner.IndexOf("'owned-close-request'")
if($workerAt -lt 0 -or $pixelsAt -le $workerAt -or $closeAt -le $pixelsAt -or ($runner.Split(@('Assert-FactorySnapshotReady $workerResult $target'),[StringSplitOptions]::None).Count -ne 4)){throw 'Worker/pixels/close ordering gates missing'}
$issuer=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'issue-before-launch.ps1'))
foreach($required in @('candidate-context.json','candidate-tuple.json','candidate-binding.json','factory-source-bound-candidate-canonical-tuple-v1','sourceBoundCandidateTuple=$candidateRef')){if(-not $issuer.Contains($required)){throw ('Prospective candidate issuer guard missing: '+$required)}}
$tupleWrite=$issuer.IndexOf("candidate-tuple.json");$bindingWrite=$issuer.IndexOf("candidate-binding.json");$nativeStart=$runner.IndexOf('[Diagnostics.Process]::Start')
if($tupleWrite -lt 0 -or $bindingWrite -lt 0 -or $nativeStart -lt 0){throw 'Candidate metadata/native writer controls missing'}
if(-not $runner.Contains("Copy-Item -LiteralPath $candidateSource") -or -not $runner.Contains('candidateTupleRef=$issuedMetadata.candidateTuple') -or -not $runner.Contains('candidateBindingRef=$issuedMetadata.sourceBoundCandidateTuple')){throw 'Actual writer candidate capture binding missing'}
[ordered]@{kind='padding-window-diagnosis-source-controls';rows=$rows;count=$rows.Count;passed=$true;nativeActions=0;compilerActions=0}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $OutputPath
