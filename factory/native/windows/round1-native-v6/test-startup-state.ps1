# Actual production decision controls; no OS process/window operations.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path $OutputRoot){throw 'Fresh controls required'}
. (Join-Path $PSScriptRoot 'startup-state.ps1')
New-Item -ItemType Directory $OutputRoot|Out-Null
$rows=@()
foreach($caseRow in @(
 @{mode='before6-no-window';time=5.9;exited=$false;hwnd=0;state='waiting';breach=$false},
 @{mode='exact6-ready';time=6.0;exited=$false;hwnd=123;state='ready';breach=$false},
 @{mode='late-ready-retains-breach';time=6.1;exited=$false;hwnd=123;state='ready';breach=$true},
 @{mode='exact30-no-window';time=30.0;exited=$false;hwnd=0;state='waiting';breach=$true},
 @{mode='over30-window-not-success';time=30.1;exited=$false;hwnd=123;state='deadline';breach=$true},
 @{mode='exit-priority';time=30.1;exited=$true;hwnd=123;state='exited';breach=$true}
)){
 $actual=Get-FactoryStartupState $caseRow.time $caseRow.exited $caseRow.hwnd
 if($actual.state -cne $caseRow.state -or $actual.originalSixSecondBreach -ne $caseRow.breach){throw ('Startup actual control failed '+$caseRow.mode)}
 $rows+=[ordered]@{mode=$caseRow.mode;actual=$actual}
}
foreach($bad in @(-1,[double]::NaN,[double]::PositiveInfinity)){
 $rejected=$false;try{Get-FactoryStartupState $bad $false 0|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw 'Invalid startup duration accepted'};$rows+=[ordered]@{mode='invalid-duration';rejected=$true}
}
$rejected=$false;try{Get-FactoryStartupState 1 1 0|Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Numeric exited boolean accepted'}
$rows+=[ordered]@{mode='numeric-exited';rejected=$true}
$rows|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
