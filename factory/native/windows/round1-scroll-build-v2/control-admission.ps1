# Actual control-output admission; no child creation, compiler or native calls.
function Assert-CompletedBuildControls([string]$BuilderRoot,[string]$HostHelper) {
 $root=[IO.Path]::GetFullPath($BuilderRoot)
 $dir=Join-Path $root 'control-results'
 $cleanup=Get-Content -LiteralPath (Join-Path $dir 'cleanup-controls.json') -Raw|ConvertFrom-Json
 $host=Get-Content -LiteralPath (Join-Path $dir 'host-input-controls.json') -Raw|ConvertFrom-Json
 $parse=@(Get-Content -LiteralPath (Join-Path $dir 'parse-controls.json') -Raw|ConvertFrom-Json)
 if($cleanup.kind -cne 'pure-production-cleanup-decision-v2' -or $cleanup.synthetic -isnot [bool] -or -not $cleanup.synthetic -or $cleanup.positiveCases -isnot [int] -or $cleanup.positiveCases -ne 3 -or $cleanup.nativeCalls -isnot [int] -or $cleanup.nativeCalls -ne 0 -or $cleanup.compilerInvocations -isnot [int] -or $cleanup.compilerInvocations -ne 0){throw 'Cleanup control outcome invalid'}
 if($cleanup.helperSha256 -cne (Get-FileHash -LiteralPath (Join-Path $root 'cleanup-decision.ps1')).Hash.ToLowerInvariant()){throw 'Cleanup controls stale'}
 $expectedFaults=@('unknown-status','wait-failed','running-without-abort')
 $actualFaults=@($cleanup.faults|ForEach-Object{$_.name})
 if($actualFaults.Count -ne 3 -or @($actualFaults|Select-Object -Unique).Count -ne 3 -or @($actualFaults|Where-Object{$expectedFaults -cnotcontains $_}).Count -ne 0){throw 'Cleanup fault coverage invalid'}
 foreach($fault in $cleanup.faults){if($fault.rejected -isnot [bool] -or -not $fault.rejected){throw 'Cleanup fault accepted'}}
 if($host.kind -cne 'synthetic-production-host-input-guard-controls' -or $host.synthetic -isnot [bool] -or -not $host.synthetic -or $host.pass -isnot [bool] -or -not $host.pass -or $host.normalPassed -isnot [bool] -or -not $host.normalPassed -or $host.compilerInvocations -isnot [int] -or $host.compilerInvocations -ne 0 -or $host.nativeWindows -isnot [int] -or $host.nativeWindows -ne 0){throw 'Host input controls invalid'}
 if($host.helperSha256 -cne (Get-FileHash -LiteralPath $HostHelper).Hash.ToLowerInvariant()){throw 'Host input controls stale'}
 $expectedHostFaults=@('missing-source','extra-unbound-source','equal-count-wrong-source','omitted-binding','raw-hash-drift')
 $actualHostFaults=@($host.faults|ForEach-Object{$_.fault})
 if($actualHostFaults.Count -ne 5 -or @($actualHostFaults|Select-Object -Unique).Count -ne 5 -or @($actualHostFaults|Where-Object{$expectedHostFaults -cnotcontains $_}).Count -ne 0){throw 'Host control coverage invalid'}
 foreach($fault in $host.faults){if($fault.rejected -isnot [bool] -or -not $fault.rejected){throw 'Host fault accepted'}}
 $expectedParse=@('build-host-v2.ps1','cleanup-decision.ps1','control-admission.ps1','pure-controls\test-cleanup.ps1','pure-controls\test-host-inputs.ps1')|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $root $_))}
 $actualParse=@($parse|ForEach-Object{[IO.Path]::GetFullPath($_.path)})
 if($actualParse.Count -ne $expectedParse.Count -or @($actualParse|Select-Object -Unique).Count -ne $expectedParse.Count -or @($actualParse|Where-Object{$expectedParse -cnotcontains $_}).Count -ne 0){throw 'Parse coverage invalid'}
 foreach($row in $parse){
  $path=[IO.Path]::GetFullPath($row.path)
  if($null -eq $row.errors -or @($row.errors).Count -ne 0 -or $row.sha256 -cne (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()){throw 'Parse controls failed/stale'}
 }
}
