param([Parameter(Mandatory=$true)][string]$HelperPath)
Set-StrictMode -Version Latest
. (Resolve-Path -LiteralPath $HelperPath)
$script:failures=@()
function Assert-Case([string]$Name,[bool]$Condition,[bool]$KillAttempted,[object]$Result){
 if(-not $Condition){$script:failures+="${Name}: expected result condition failed"}
 if([bool]$Result.killAttempted -ne $KillAttempted){$script:failures+="${Name}: killAttempted=$($Result.killAttempted), expected=$KillAttempted"}
}
function New-FakeProcess([bool]$HasExited,[string]$Path,[string]$StartedAt,[int]$FakeProcessId=4242){
 $p=[pscustomobject]@{Handle=[IntPtr]42;Id=$FakeProcessId;Path=$Path;StartTime=([datetime]::Parse($StartedAt).ToLocalTime());HasExited=$HasExited}
 $p|Add-Member ScriptMethod Refresh { }
 return $p
}
function Invoke-Fake([string]$Name,[bool]$HasExited,[int[]]$Waits,[int]$KernelPid=4242,[object]$ExitCode=[pscustomobject]@{succeeded=$true;code=[uint32]1},[string]$Path=$PSCommandPath,[string]$Start='2026-10-12T00:00:00.0000000Z',[string]$ExpectedExeHash='', [bool]$ExpectKill=$false,[string]$ProcessPath='',[string]$ProcessStart=''){
 if([string]::IsNullOrEmpty($ProcessPath)){$ProcessPath=$Path};if([string]::IsNullOrEmpty($ProcessStart)){$ProcessStart=$Start}
 $p=New-FakeProcess $HasExited $ProcessPath $ProcessStart
 $state=[pscustomobject]@{index=0};$killed=$false
 $waiter={param($h,$ms)if($state.index -ge $Waits.Count){return 258};$v=$Waits[$state.index];$state.index++;return $v}.GetNewClosure()
 $pidReader={param($h)return $KernelPid}.GetNewClosure()
 $identityReader={param($h)$dt=[DateTimeOffset]::Parse($ProcessStart).UtcDateTime;return [pscustomobject]@{succeeded=$true;pid=$KernelPid;path=$ProcessPath;startFileTime=$dt.ToFileTimeUtc()}}.GetNewClosure()
 $terminator={param($h,$code)$script:killed=$true;return $true}.GetNewClosure()
 $exitReader={param($h)return $ExitCode}.GetNewClosure()
 if([string]::IsNullOrEmpty($ExpectedExeHash)){$ExpectedExeHash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
 $r=Invoke-FactoryOwnedCleanup $p $Path $Start -ExpectedExeHash $ExpectedExeHash -KnownStartedIdentity -KernelWait $waiter -KernelPid $pidReader -KernelIdentity $identityReader -KernelTerminate $terminator -KernelExitCode $exitReader
 Assert-Case $Name ($r.confirmedOwnedExit -or $r.status -eq 'hold-cleanup') $ExpectKill $r
 return $r
}
# Positive phantom HasExited is diagnostic only: exact retained handle is terminated after identity proof.
$r=Invoke-Fake 'phantom-hasexited' $true @(258,258,0) -ExpectKill $true
if(-not($r.confirmedOwnedExit -and $r.status -eq 'killed-owned-handle-after-phantom-exited')){$script:failures+='phantom-hasexited: retained-handle cleanup not admitted'}
# Natural kernel signal never invokes termination.
$r=Invoke-Fake 'genuine-kernel-zero' $true @(0) -ExpectKill $false
if(-not($r.confirmedOwnedExit -and $r.status -eq 'already-signaled')){$script:failures+='genuine-kernel-zero: natural signal not admitted'}
# Identity and executable lineage failures must hold without termination.
$r=Invoke-Fake 'wrong-pid' $true @(258) -KernelPid 9191 -ExpectKill $false
$r=Invoke-Fake 'wrong-start' $true @(258) -ProcessStart '2026-10-12T00:00:01.0000000Z' -ExpectKill $false
$r=Invoke-Fake 'wrong-path' $true @(258) -ProcessPath (Join-Path (Split-Path $PSCommandPath) 'wrong.exe') -ExpectKill $false
$r=Invoke-Fake 'wrong-exe-hash' $true @(258) -ExpectedExeHash ('0'*64) -ExpectKill $false
$r=Invoke-Fake 'unknown-kernel-wait' $true @(259) -ExpectKill $false
$r=Invoke-Fake 'failed-kernel-exit-query' $true @(0) -ExitCode ([pscustomobject]@{succeeded=$false;code=[uint32]0}) -ExpectKill $false
if($script:failures.Count -gt 0){$script:failures|ForEach-Object{Write-Error $_};throw 'kernel-authority controls failed'}
[pscustomobject]@{status='SOURCE_CONTROLS_PASS';cases=8;nativeWindowActions=0;kernelAuthority='retained-handle'}|ConvertTo-Json -Compress
