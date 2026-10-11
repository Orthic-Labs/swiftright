# Prepared pure controls; production namespace guard only, no processes/windows.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path $OutputRoot){throw 'Fresh fixture root required'}
. (Join-Path $PSScriptRoot 'namespace.ps1')
New-Item -ItemType Directory $OutputRoot|Out-Null
$results=@()
function Check([string]$name,[string[]]$actual,[string[]]$expected,[bool]$reject,[bool]$file=$false){
 $dir=Join-Path $OutputRoot $name;New-Item -ItemType Directory $dir|Out-Null
 foreach($n in $actual){if($file){New-Item -ItemType File (Join-Path $dir $n)|Out-Null}else{New-Item -ItemType Directory (Join-Path $dir $n)|Out-Null}}
 $failed=$false;try{Assert-RepeatNamespace $dir $expected}catch{$failed=$true}
 if($failed -ne $reject){throw ('Control failed '+$name)}
 $script:results+=[ordered]@{name=$name;rejected=$failed}
}
Check 'empty' @() @() $false
Check 'normal' @('run-001','run-002') @('run-001','run-002') $false
Check 'missing' @('run-001') @('run-001','run-002') $true
Check 'extra' @('run-001','unbound') @('run-001') $true
Check 'equal-count-wrong' @('run-002') @('run-001') $true
Check 'duplicate' @('run-001') @('run-001','run-001') $true
Check 'file' @('run-001') @('run-001') $true $true
$results|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
