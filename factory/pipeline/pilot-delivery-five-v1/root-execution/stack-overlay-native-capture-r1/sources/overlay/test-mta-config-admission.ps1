# Source control: calls production predicate from final-exit-certificate-mta-v1.ps1.
param([string]$OutputPath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $PSScriptRoot 'final-exit-certificate-mta-v1.ps1')
$expected=[pscustomobject]@{workerId='D:\capture\native-01\uia-worker';lockOwner='owner-r9'}
function C($kind,$apartment,$parent){
 [pscustomobject]@{kind=$kind;apartment=$apartment;parentApartment=$parent;outputRoot=$expected.workerId;target=[pscustomobject]@{lockOwner=$expected.lockOwner}}
}
$cases=@(
 [pscustomobject]@{name='legacy-v1';config=(C 'factory-uia-snapshot-worker-config-v1' $null $null);accepted=$true},
 [pscustomobject]@{name='mta-v2';config=(C 'factory-uia-snapshot-worker-config-v2' 'MTA' 'STA');accepted=$true},
 [pscustomobject]@{name='mta-v2-parent-mta';config=(C 'factory-uia-snapshot-worker-config-v2' 'MTA' 'MTA');accepted=$true},
 [pscustomobject]@{name='v2-sta-worker';config=(C 'factory-uia-snapshot-worker-config-v2' 'STA' 'STA');accepted=$false},
 [pscustomobject]@{name='v2-missing-apartment';config=(C 'factory-uia-snapshot-worker-config-v2' $null 'STA');accepted=$false},
 [pscustomobject]@{name='unknown-v3';config=(C 'factory-uia-snapshot-worker-config-v3' 'MTA' 'STA');accepted=$false},
 [pscustomobject]@{name='wrong-output-root';config=((C 'factory-uia-snapshot-worker-config-v2' 'MTA' 'STA')|ForEach-Object{$_.outputRoot='D:\wrong';$_});accepted=$false}
)
$rows=@($cases|ForEach-Object{$actual=[bool](Test-FactoryUiaWorkerConfigAdmission $_.config $expected);if($actual -ne $_.accepted){throw ('config admission fault: '+$_.name)};[ordered]@{name=$_.name;accepted=$actual}})
$result=[ordered]@{kind='factory-uia-worker-config-admission-controls-v1';status='SOURCE_CONTROLS_PASS';productionPredicate='Test-FactoryUiaWorkerConfigAdmission';cases=$rows;nativeActions=0;compilerActions=0}
if([string]::IsNullOrWhiteSpace($OutputPath)){$result|ConvertTo-Json -Depth 10}else{$result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $OutputPath -Encoding UTF8}
