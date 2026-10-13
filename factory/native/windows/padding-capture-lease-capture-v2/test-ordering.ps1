param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'support\integration.ps1')
$order=[pscustomobject]@{kind='factory-isolated-uia-parent-ordering-v1';clockDomain='parent-process-local-stopwatch';crossProcessClockQualified=$false;parentProcessID=1;frequency=100;workerVerifiedTicks=10;pixelsStartTicks=20;pixelsEndTicks=30;ownedCloseStartTicks=40}
if(-not(Test-FactoryParentOrdering $order)){throw 'Ordering baseline rejected'}
$rows=@()
foreach($fault in @('pixels-before-worker','close-before-pixels','missing-worker','string-time','foreign-clock','invented-cross-clock')){
 $copy=$order|ConvertTo-Json|ConvertFrom-Json
 switch($fault){'pixels-before-worker' {$copy.pixelsStartTicks=5};'close-before-pixels' {$copy.ownedCloseStartTicks=25};'missing-worker' {$copy.workerVerifiedTicks=$null};'string-time' {$copy.workerVerifiedTicks='10'};'foreign-clock' {$copy.clockDomain='UTC-common'};'invented-cross-clock' {$copy.crossProcessClockQualified=$true}}
 if(Test-FactoryParentOrdering $copy){throw ('Unsafe order accepted: '+$fault)}
 $rows+=@{name=$fault;acceptedBaseline=$true;rejected=$true}
}
if(Test-Path -LiteralPath $OutputPath){throw 'Fresh ordering output required'}
@{kind='factory-parent-ordering-controls-v1';controls=$rows;synthetic=$true;nativeActions=0}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $OutputPath
