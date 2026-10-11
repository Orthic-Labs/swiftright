# Pure actual polling decision; original6s breach retained independently of bounded30s diagnostic.
function Get-FactoryStartupState([double]$ElapsedSeconds,$Exited,[long]$Hwnd){
 if([double]::IsNaN($ElapsedSeconds) -or [double]::IsInfinity($ElapsedSeconds) -or $ElapsedSeconds -lt 0 -or $Exited -isnot [bool]){throw 'Invalid startup sample'}
 $state=if($Exited){'exited'}elseif($ElapsedSeconds -gt 30){'deadline'}elseif($Hwnd -ne 0){'ready'}else{'waiting'}
 return [ordered]@{elapsedSeconds=$ElapsedSeconds;originalSixSecondBreach=($ElapsedSeconds -gt 6);diagnosticLimitSeconds=30;state=$state}
}
