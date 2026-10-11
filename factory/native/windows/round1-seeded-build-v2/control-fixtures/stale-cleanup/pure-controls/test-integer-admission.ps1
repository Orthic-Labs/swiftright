param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Fresh integer control output required'}
$helper=Join-Path $PSScriptRoot '..\control-admission.ps1'
. $helper
$positive=@([int]3,[long]3,[int]0,[long]0)
foreach($value in $positive){if(-not (Test-ControlIntegerEqual $value ([long]$value))){throw 'Exact typed integer rejected'}}
$faults=@(
 @{name='bool';value=$true;expected=3},
 @{name='float';value=[double]3;expected=3},
 @{name='decimal';value=[decimal]3;expected=3},
 @{name='negative';value=[long]-1;expected=3},
 @{name='out-of-range';value=[long]::MaxValue;expected=3},
 @{name='wrong-int64';value=[long]4;expected=3},
 @{name='string';value='3';expected=3},
 @{name='null';value=$null;expected=3},
 @{name='array';value=@(3);expected=3}
)
$rows=@()
foreach($case in $faults){
 if(Test-ControlIntegerEqual $case.value $case.expected){throw ('Integer fault accepted: '+$case.name)}
 $rows+=@{name=$case.name;rejected=$true}
}
@{kind='production-integer-admission-controls-v3';positiveInt32=2;positiveInt64=2;faults=$rows;helperSha256=(Get-FileHash -LiteralPath $helper).Hash.ToLowerInvariant();compilerInvocations=0;nativeCalls=0}|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath $Output
