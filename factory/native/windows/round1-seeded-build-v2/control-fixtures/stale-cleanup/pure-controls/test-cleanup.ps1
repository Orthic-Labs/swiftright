param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Fresh pure output required'}
. (Join-Path $PSScriptRoot '..\cleanup-decision.ps1')
if((Get-CompilerCleanupAction 0 $false) -ne 'natural-exit-no-termination'){throw 'Natural-exit decision'}
if((Get-CompilerCleanupAction 0 $true) -ne 'natural-exit-no-termination'){throw 'Exit-at-deadline must never terminate'}
if((Get-CompilerCleanupAction 258 $true) -ne 'terminate-owned-handle'){throw 'Deadline decision'}
$rows=@()
foreach($case in @(@{name='unknown-status';status=1;abort=$true},@{name='wait-failed';status=[uint32]::MaxValue;abort=$true},@{name='running-without-abort';status=258;abort=$false})){
 $rejected=$false;try{Get-CompilerCleanupAction $case.status $case.abort|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw ('Fault accepted: '+$case.name)}
 $rows+=@{name=$case.name;rejected=$true}
}
@{kind='pure-production-cleanup-decision-v2';synthetic=$true;positiveCases=3;faults=$rows;nativeCalls=0;compilerInvocations=0;helperSha256=(Get-FileHash (Join-Path $PSScriptRoot '..\cleanup-decision.ps1')).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 -LiteralPath $Output
