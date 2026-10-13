# JSON decoders may yield Int32 or Int64. Match exact nonnegative bounded integer value only.
function Test-ControlIntegerEqual($Value,[long]$Expected) {
 if($Value -isnot [int] -and $Value -isnot [long]){return $false}
 if($Expected -lt 0 -or $Expected -gt [int]::MaxValue -or $Value -lt 0 -or $Value -gt [int]::MaxValue){return $false}
 return ([long]$Value -eq $Expected)
}
# Actual control-output admission; no child creation, compiler or native calls.
function Assert-CompletedBuildControls([string]$BuilderRoot,[string]$HostHelper) {
 $root=[IO.Path]::GetFullPath($BuilderRoot)
 $dir=Join-Path $root 'control-results'
 $cleanup=Get-Content -LiteralPath (Join-Path $dir 'cleanup-controls.json') -Raw|ConvertFrom-Json
 $hostControls=Get-Content -LiteralPath (Join-Path $dir 'host-input-controls.json') -Raw|ConvertFrom-Json
 $decodedParse=Get-Content -LiteralPath (Join-Path $dir 'parse-controls.json') -Raw|ConvertFrom-Json
 $parse=@($decodedParse)
 if($cleanup.kind -cne 'pure-production-cleanup-decision-v2' -or $cleanup.synthetic -isnot [bool] -or -not $cleanup.synthetic -or -not (Test-ControlIntegerEqual $cleanup.positiveCases 3) -or -not (Test-ControlIntegerEqual $cleanup.nativeCalls 0) -or -not (Test-ControlIntegerEqual $cleanup.compilerInvocations 0)){throw 'Cleanup control outcome invalid'}
 if($cleanup.helperSha256 -cne (Get-FileHash -LiteralPath (Join-Path $root 'cleanup-decision.ps1')).Hash.ToLowerInvariant()){throw 'Cleanup controls stale'}
 $expectedFaults=@('unknown-status','wait-failed','running-without-abort')
 $actualFaults=@($cleanup.faults|ForEach-Object{$_.name})
 if($actualFaults.Count -ne 3 -or @($actualFaults|Select-Object -Unique).Count -ne 3 -or @($actualFaults|Where-Object{$expectedFaults -cnotcontains $_}).Count -ne 0){throw 'Cleanup fault coverage invalid'}
 foreach($fault in $cleanup.faults){if($fault.rejected -isnot [bool] -or -not $fault.rejected){throw 'Cleanup fault accepted'}}
 if($hostControls.kind -cne 'synthetic-production-host-input-guard-controls' -or $hostControls.synthetic -isnot [bool] -or -not $hostControls.synthetic -or $hostControls.pass -isnot [bool] -or -not $hostControls.pass -or $hostControls.normalPassed -isnot [bool] -or -not $hostControls.normalPassed -or -not (Test-ControlIntegerEqual $hostControls.compilerInvocations 0) -or -not (Test-ControlIntegerEqual $hostControls.nativeWindows 0)){throw 'Host input controls invalid'}
 if($hostControls.helperSha256 -cne (Get-FileHash -LiteralPath $HostHelper).Hash.ToLowerInvariant()){throw 'Host input controls stale'}
 $expectedHostFaults=@('missing-source','extra-unbound-source','equal-count-wrong-source','omitted-binding','raw-hash-drift')
 $actualHostFaults=@($hostControls.faults|ForEach-Object{$_.fault})
 if($actualHostFaults.Count -ne 5 -or @($actualHostFaults|Select-Object -Unique).Count -ne 5 -or @($actualHostFaults|Where-Object{$expectedHostFaults -cnotcontains $_}).Count -ne 0){throw 'Host control coverage invalid'}
 foreach($fault in $hostControls.faults){if($fault.rejected -isnot [bool] -or -not $fault.rejected){throw 'Host fault accepted'}}
 $expectedParse=@('build-hosts-v2.ps1','cleanup-decision.ps1','control-admission.ps1','pure-controls\test-cleanup.ps1','pure-controls\test-host-inputs.ps1','run-controls.ps1','pure-controls\reserved-assignment-lint.ps1','pure-controls\parse-controls.ps1','pure-controls\test-integer-admission.ps1')|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $root $_))}
 $actualParse=@($parse|ForEach-Object{[IO.Path]::GetFullPath($_.path)})
 if($actualParse.Count -ne $expectedParse.Count -or @($actualParse|Select-Object -Unique).Count -ne $expectedParse.Count -or @($actualParse|Where-Object{$expectedParse -cnotcontains $_}).Count -ne 0){throw 'Parse coverage invalid'}
 foreach($row in $parse){
  $path=[IO.Path]::GetFullPath($row.path)
  if($null -eq $row.errors -or @($row.errors).Count -ne 0 -or $row.sha256 -cne (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()){throw 'Parse controls failed/stale'}
 }
}
function Assert-AdmissionInvocationProof([string]$BuilderRoot) {
 $root=[IO.Path]::GetFullPath($BuilderRoot)
 $proof=Get-Content -LiteralPath (Join-Path $root 'control-results\admission-controls.json') -Raw|ConvertFrom-Json
 if($proof.kind -cne 'actual-production-admission-controls-v3' -or $proof.actualGeneratedOutputsPassed -isnot [bool] -or -not $proof.actualGeneratedOutputsPassed -or $proof.fixturePositivePassed -isnot [bool] -or -not $proof.fixturePositivePassed -or -not (Test-ControlIntegerEqual $proof.compilerInvocations 0) -or -not (Test-ControlIntegerEqual $proof.nativeCalls 0)){throw 'Actual admission invocation proof invalid'}
 if($proof.admissionHelperSha256 -cne (Get-FileHash -LiteralPath (Join-Path $root 'control-admission.ps1')).Hash.ToLowerInvariant()){throw 'Admission invocation proof stale'}
 $expected=@('missing-cleanup','stale-cleanup','failed-cleanup','failed-host','failed-parser','stale-parser','bool-positive-count')
 $actual=@($proof.faults|ForEach-Object{$_.name})
 if($actual.Count -ne 7 -or @($actual|Select-Object -Unique).Count -ne 7 -or @($actual|Where-Object{$expected -cnotcontains $_}).Count -ne 0){throw 'Admission fault coverage invalid'}
 foreach($fault in $proof.faults){if($fault.rejected -isnot [bool] -or -not $fault.rejected){throw 'Admission fault accepted'}}
 $integerControls=Get-Content -LiteralPath (Join-Path $root 'control-results\integer-controls.json') -Raw|ConvertFrom-Json
 if($integerControls.kind -cne 'production-integer-admission-controls-v3' -or -not (Test-ControlIntegerEqual $integerControls.positiveInt32 2) -or -not (Test-ControlIntegerEqual $integerControls.positiveInt64 2) -or -not (Test-ControlIntegerEqual $integerControls.compilerInvocations 0) -or -not (Test-ControlIntegerEqual $integerControls.nativeCalls 0) -or $integerControls.helperSha256 -cne (Get-FileHash -LiteralPath (Join-Path $root 'control-admission.ps1')).Hash.ToLowerInvariant()){throw 'Integer admission controls stale/invalid'}
 $expectedIntegerFaults=@('bool','float','decimal','negative','out-of-range','wrong-int64','string','null','array')
 $actualIntegerFaults=@($integerControls.faults|ForEach-Object{$_.name})
 if($actualIntegerFaults.Count -ne 9 -or @($actualIntegerFaults|Select-Object -Unique).Count -ne 9 -or @($actualIntegerFaults|Where-Object{$expectedIntegerFaults -cnotcontains $_}).Count -ne 0){throw 'Integer fault coverage invalid'}
 foreach($fault in $integerControls.faults){if($fault.rejected -isnot [bool] -or -not $fault.rejected){throw 'Integer fault accepted'}}
 $lint=Get-Content -LiteralPath (Join-Path $root 'control-results\reserved-lint.json') -Raw|ConvertFrom-Json
 if($lint.kind -cne 'reserved-automatic-assignment-lint-v3' -or $lint.pass -isnot [bool] -or -not $lint.pass){throw 'Reserved-assignment lint failed'}
 $actualScripts=@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1'|Where-Object{$_.FullName -notmatch '\\control-results\\|\\control-fixtures\\'})
 $paths=@($lint.files|ForEach-Object{[IO.Path]::GetFullPath($_.path)})
 if($paths.Count -ne $actualScripts.Count -or @($paths|Select-Object -Unique).Count -ne $actualScripts.Count -or @($actualScripts|Where-Object{$paths -cnotcontains $_.FullName}).Count -ne 0){throw 'Reserved-assignment lint coverage invalid'}
 foreach($row in $lint.files){if(@($row.reservedAssignments).Count -ne 0 -or $row.sha256 -cne (Get-FileHash -LiteralPath $row.path).Hash.ToLowerInvariant()){throw 'Reserved-assignment lint stale'}}
}
