# Diagnostic Count1 plan predicate. Historical v1 predicate remains separate.
function Assert-CircleFinalPlanAdmission([object]$Plan){
 if($null -eq $Plan){throw 'Circle final plan missing'}
 if($Plan.kind -ceq 'factory-circle-incremental-compile-plan-v1'){
  if([string]::IsNullOrWhiteSpace([string]$Plan.candidate)){throw 'Circle diagnostic candidate missing'}
  if($Plan.phase -cne 'final' -or $Plan.executionEligible -ne $true){throw 'Circle diagnostic final eligibility mismatch'}
  if($Plan.qualification -cne 'diagnostic-native-only-not-qualified'){throw 'Circle diagnostic qualification drift'}
  if($Plan.compileRequest.maxParallelJobs -ne 1 -or $Plan.compileRequest.maxFrontendThreads -ne 1){throw 'Circle diagnostic compiler budget mismatch'}
  if($Plan.tuple.hostHashes.windows -notmatch '^sha256:[0-9a-f]{64}$' -or $Plan.rendererSha256 -notmatch '^[0-9a-f]{64}$'){throw 'Circle diagnostic measured host closure missing'}
  return $true
 }
 if(($Plan.kind -cne 'factory-circle-compiler-plan-v1' -and $Plan.kind -cne 'factory-circle-incremental-compile-plan-v1')){throw 'Circle final plan kind mismatch'}
 if($Plan.phase -cne 'final' -or $Plan.executionEligible -ne $true){throw 'Circle final plan phase/eligibility mismatch'}
 if(($Plan.PSObject.Properties.Name -contains 'hostMode') -and $Plan.hostMode -cne 'renderer'){throw 'Circle explicit hostMode mismatch'}
 return $true
}
