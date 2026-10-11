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
# Original exception retains priority regardless of cleanup failure.
$primary='simulated capture failure';$p=Mock 'timeout';$script:fixture=$p
$r=Invoke-FactoryOwnedCleanup $p 'fixture' $p.StartTime.ToString('o') 1 {param($id) $script:fixture} -KnownStartedIdentity
$outcome=[ordered]@{primaryError=$primary;cleanup=$r}
if($outcome.primaryError -ne 'simulated capture failure' -or -not $outcome.cleanup.error){throw 'Capture error lost behind cleanup'}
$results+=[ordered]@{mode='capture-error-plus-cleanup-timeout';result=$outcome}
$results|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
