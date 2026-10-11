# Pure fake-process fault controls call actual production helper, no OS processes/windows.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path $OutputRoot){throw 'Fresh output required'}
. (Join-Path $PSScriptRoot 'cleanup.ps1')
New-Item -ItemType Directory $OutputRoot|Out-Null
function Mock([string]$Mode){
 $p=[pscustomobject]@{Handle=[IntPtr]::new(123);Id=42;Path='fixture';StartTime=[datetime]::Parse('2026-10-11T00:00:00Z').ToUniversalTime();HasExited=($Mode -eq 'already-exited');Mode=$Mode;Killed=$false}
 $p|Add-Member ScriptMethod Refresh {}
 $p|Add-Member ScriptMethod Kill {$this.Killed=$true;if($this.Mode -eq 'exit-race'){$this.HasExited=$true;throw 'simulated already exited'};if($this.Mode -ne 'timeout'){$this.HasExited=$true}}
 $p|Add-Member ScriptMethod WaitForExit {param($ms) return $this.HasExited}
 return $p
}
$results=@()
foreach($mode in @('normal','already-exited','exit-race','identity-drift','timeout')){
 $p=Mock $mode;$start=$p.StartTime.ToString('o');$script:fixture=$p
 if($mode -eq 'identity-drift'){$script:fixture=[pscustomobject]@{Path='different-owner';StartTime=$p.StartTime}}
 $r=Invoke-FactoryOwnedCleanup $p 'fixture' $start 1 {param($id) return $script:fixture} -KnownStartedIdentity
 $expected=($mode -in @('normal','already-exited','exit-race'))
 if($r.confirmedOwnedExit -ne $expected){throw ('Wrong confirmation '+$mode)}
 if($mode -eq 'identity-drift' -and $p.Killed){throw 'Killed changed owner'}
 if($mode -eq 'timeout' -and -not $r.error){throw 'Timeout error absent'}
 $results+=[ordered]@{mode=$mode;result=$r;killed=$p.Killed}
}
# Retained identity/handle gates, distinct from fresh lookup drift.
foreach($mode in @('retained-path','retained-start','zero-handle','unproven-exit')){
 $p=Mock 'normal';$start=$p.StartTime.ToString('o');$script:fixture=$p
 if($mode -eq 'retained-path'){$p.Path='wrong'}
 if($mode -eq 'retained-start'){$p.StartTime=$p.StartTime.AddSeconds(1)}
 if($mode -eq 'zero-handle'){$p.Handle=[IntPtr]::Zero}
 if($mode -eq 'unproven-exit'){$p.HasExited=$true}
 $r=Invoke-FactoryOwnedCleanup $p 'fixture' $start 1 {param($id) $script:fixture}
 if($r.confirmedOwnedExit -or $p.Killed -or -not $r.error){throw ('Retained gate failed '+$mode)}
 $results+=[ordered]@{mode=$mode;result=$r;killed=$p.Killed}
}
# Actual production priority helper, with original ErrorRecord & both cleanup/receipt failures.
$primary=$null;try{throw 'simulated capture failure'}catch{$primary=$_}
foreach($mode in @('cleanup-timeout','receipt-write-failure')){
 $p=Mock 'timeout';$script:fixture=$p
 $r=Invoke-FactoryOwnedCleanup $p 'fixture' $p.StartTime.ToString('o') 1 {param($id) $script:fixture} -KnownStartedIdentity
 $errors=if($mode -eq 'receipt-write-failure'){@('outcome receipt: simulated write failure')}else{@()}
 $caught=$null;try{Assert-FactoryCaptureOutcome $primary $r $errors}catch{$caught=$_}
 if($null -eq $caught -or $caught.Exception.Message -ne $primary.Exception.Message){throw ('Original error priority lost '+$mode)}
 $results+=[ordered]@{mode=$mode;originalError=[string]$caught;cleanup=$r;streamErrors=$errors}
}
$failed=$false;try{Assert-FactoryCaptureOutcome $null @{confirmedOwnedExit=$false} @()}catch{$failed=$true}
if(-not $failed){throw 'Cleanup-only failure accepted'}
$results+=[ordered]@{mode='cleanup-only-reject';rejected=$failed}
$script:releaseCalls=0
foreach($case in @(@{acquired=$true;confirmed=$false;expected=$false},@{acquired=$false;confirmed=$true;expected=$false},@{acquired=$true;confirmed=$true;expected=$true})){
 $before=$script:releaseCalls;$value=Invoke-FactoryConfirmedRelease $case.acquired $case.confirmed {$script:releaseCalls++;return $true}
 if($value -ne $case.expected -or ($script:releaseCalls-$before) -ne [int]$case.expected){throw 'Unconfirmed exit released owned lock'}
 $results+=[ordered]@{mode='confirmed-release';acquired=$case.acquired;exitConfirmed=$case.confirmed;released=$value}
}
$results|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
