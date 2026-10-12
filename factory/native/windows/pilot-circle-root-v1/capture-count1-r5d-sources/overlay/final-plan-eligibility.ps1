# Pure Circle final-plan admission predicate. It performs no IO or native action.
function Assert-CircleFinalPlanAdmission([object]$Plan){
 if($null -eq $Plan -or $Plan.kind -cne 'factory-circle-compiler-plan-v1'){throw 'Circle final plan kind mismatch'}
 if($Plan.phase -cne 'final'){throw 'Circle final plan phase mismatch'}
 if($Plan.executionEligible -ne $true){throw 'Circle final plan is not execution eligible'}
 $hasHostMode=@($Plan.PSObject.Properties.Name) -contains 'hostMode'
 if($hasHostMode -and $Plan.hostMode -cne 'renderer'){throw 'Circle explicit hostMode mismatch'}
 return $true
}
