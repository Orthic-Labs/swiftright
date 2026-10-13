param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'support\all-owned-release.ps1')
$rows=@();$failedOutcome=[ordered]@{primaryError='Owned renderer child deadline';cleanup=[ordered]@{kernelWaitResult=258};hostValid=$false}
$before=$failedOutcome|ConvertTo-Json -Depth 8 -Compress
if(-not(Test-FactoryCombinedReleaseAuthority $true $true)){throw 'Complete combined proof rejected'}
foreach($case in @(@('renderer-only',$true,$false),@('worker-only',$false,$true),@('none',$false,$false),@('string-worker',$true,'true'),@('string-renderer','true',$true),@('missing-worker',$true,$null))){
 $callbacks=0
 if(Test-FactoryCombinedReleaseAuthority $case[1] $case[2]){$callbacks++}
 if($callbacks -ne 0){throw ('Unsafe combined callback: '+$case[0])}
 $rows+=@{name=$case[0];acceptedBaseline=$true;releaseCallbacks=$callbacks;rejected=$true}
}
if(($failedOutcome|ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'Original failed observation relabeled'}
if(Test-Path -LiteralPath $OutputPath){throw 'Fresh control output required'}
@{kind='factory-combined-release-policy-controls-v1';synthetic=$true;controls=$rows;originalFailedOutcomePreserved=$true;nativeActions=0;lockWrites=0}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $OutputPath
