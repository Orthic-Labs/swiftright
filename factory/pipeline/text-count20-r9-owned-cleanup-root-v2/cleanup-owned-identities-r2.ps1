[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$IdentityPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$IdentitySha256,
 [Parameter(Mandatory=$true)][string]$CoordinatorPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$CoordinatorSha256,
 [Parameter(Mandatory=$true)][string]$TaskResultPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TaskResultSha256,
 [Parameter(Mandatory=$true)][string]$SourceInputsPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$SourceInputsSha256,
 [Parameter(Mandatory=$true)][string[]]$OutcomePaths,
 [Parameter(Mandatory=$true)][string[]]$OutcomeSha256s,
 [Parameter(Mandatory=$true)][string[]]$InventoryPaths,
 [Parameter(Mandatory=$true)][string[]]$InventorySha256s,
 [Parameter(Mandatory=$true)][string]$LockPath,
 [Parameter(Mandatory=$true)][string]$ExpectedOwner,
 [Parameter(Mandatory=$true)][string]$OutputPath,
 [int]$DeadlineSeconds=30
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$MaxJson=[int64]2097152;$MaxEvidence=[int64]8388608;$MaxMemory=[int64]1073741824;$MaxStream=[int64]8388608
function Fail([string]$m){throw ('text-count20-r9 cleanup rejected: '+$m)}
function Require([bool]$ok,[string]$m){if(-not $ok){Fail $m}}
function Full([string]$p){return [IO.Path]::GetFullPath($p)}
function Read-Bounded([string]$p,[int64]$limit=$MaxEvidence){$i=Get-Item -LiteralPath (Full $p) -Force;Require (-not $i.PSIsContainer -and (($i.Attributes-band[IO.FileAttributes]::ReparsePoint)-eq 0) -and $i.Length -le $limit) "unsafe input: $p";return ,([IO.File]::ReadAllBytes($i.FullName))}
function Read-Json([string]$p,[int64]$limit=$MaxJson){return ([Text.Encoding]::UTF8.GetString((Read-Bounded $p $limit))).TrimStart([char]0xfeff)|ConvertFrom-Json}
function Hash-Bounded([string]$p,[int64]$limit=$MaxEvidence){$bytes=Read-Bounded $p $limit;$sha=[Security.Cryptography.SHA256]::Create();try{$sha.ComputeHash($bytes)|ForEach-Object{};return ([BitConverter]::ToString($sha.Hash)-replace '-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Assert-Pin([string]$p,[string]$hash,[int64]$limit=$MaxEvidence){Require ((Hash-Bounded $p $limit)-ceq $hash.ToLowerInvariant()) "hash pin mismatch: $p"}
function Add-NativeType {
 if('Sr0TextCleanupNativeV1' -as [type]){return}
 Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class Sr0TextCleanupNativeV1 {
 [DllImport("kernel32.dll", SetLastError=true, EntryPoint="OpenProcess")] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
 [DllImport("kernel32.dll", SetLastError=true, EntryPoint="QueryFullProcessImageNameW", CharSet=CharSet.Unicode)] public static extern bool QueryFullProcessImageName(IntPtr h, uint flags, System.Text.StringBuilder name, ref uint size);
 [DllImport("kernel32.dll", SetLastError=true, EntryPoint="GetProcessTimes")] public static extern bool GetProcessTimes(IntPtr h, out long creation, out long exit, out long kernel, out long user);
 [DllImport("kernel32.dll", SetLastError=true, EntryPoint="WaitForSingleObject")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
 [DllImport("kernel32.dll", SetLastError=true, EntryPoint="GetExitCodeProcess")] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
 [DllImport("kernel32.dll", SetLastError=true, EntryPoint="TerminateProcess")] public static extern bool TerminateProcess(IntPtr h, uint code);
 [DllImport("kernel32.dll", SetLastError=true, EntryPoint="CloseHandle")] public static extern bool CloseHandle(IntPtr h);
}
'@
}
function Get-NativePath([IntPtr]$h){$sb=New-Object Text.StringBuilder 1024;$n=[uint32]$sb.Capacity;Require ([Sr0TextCleanupNativeV1]::QueryFullProcessImageName($h,0,$sb,[ref]$n)) 'native process path query failed';return $sb.ToString()}
function Get-NativeStartUtc([IntPtr]$h){$creation=[int64]0;$exit=[int64]0;$kernel=[int64]0;$user=[int64]0;Require ([Sr0TextCleanupNativeV1]::GetProcessTimes($h,[ref]$creation,[ref]$exit,[ref]$kernel,[ref]$user)) 'native process start query failed';return [DateTime]::FromFileTimeUtc($creation).ToString('o')}
function Open-ExactProcess([object]$expected){
 $p=$null;$h=[IntPtr]::Zero
 try {
  $p=Get-Process -Id ([int]$expected.pid) -ErrorAction Stop
  $h=[Sr0TextCleanupNativeV1]::OpenProcess(0x00120101,$false,[uint32]$expected.pid)
  Require ($h -ne [IntPtr]::Zero) "OpenProcess failed for $($expected.pid)"
  $path=Get-NativePath $h;$start=Get-NativeStartUtc $h;$actualHash=Hash-Bounded $path 33554432
  $actual=[pscustomobject]@{pid=[int]$expected.pid;path=$path;startUtc=$start;exeSha256=$actualHash;hasExited=[bool]$p.HasExited;handle=$h;kernelTerminal=$false;waitResult=$null}
  $same=[bool](([IO.Path]::GetFullPath($path)).Equals([IO.Path]::GetFullPath([string]$expected.path),[StringComparison]::OrdinalIgnoreCase) -and ([DateTimeOffset]::Parse($start).UtcDateTime.Ticks -eq [DateTimeOffset]::Parse([string]$expected.startUtc).UtcDateTime.Ticks) -and $actualHash -ceq ([string]$expected.exeSha256).ToLowerInvariant())
  Require $same 'live identity changed or does not match pinned PID/path/start/hash'
  return $actual
 } catch {if($h -ne [IntPtr]::Zero){[Sr0TextCleanupNativeV1]::CloseHandle($h)|Out-Null};throw}
}
function Write-Fresh([string]$p,[object]$value){$full=Full $p;Require (-not(Test-Path -LiteralPath $full)) 'cleanup receipt must be fresh';$parent=Split-Path -Parent $full;if(-not(Test-Path -LiteralPath $parent)){Fail 'cleanup output parent missing'};$tmp="$full.$PID.$([guid]::NewGuid().ToString('N')).tmp";[IO.File]::WriteAllText($tmp,(($value|ConvertTo-Json -Depth 16)+"`r`n"),[Text.Encoding]::UTF8);[IO.File]::Move($tmp,$full)}
. (Join-Path $PSScriptRoot 'owned-cleanup-policy.ps1')
Require ($DeadlineSeconds -ge 1 -and $DeadlineSeconds -le 30) 'deadline must be 1..30 seconds'
Assert-Pin $IdentityPath $IdentitySha256;Assert-Pin $CoordinatorPath $CoordinatorSha256;Assert-Pin $TaskResultPath $TaskResultSha256;Assert-Pin $SourceInputsPath $SourceInputsSha256
$identity=Read-Json $IdentityPath;$coordinator=Read-Json $CoordinatorPath;$task=Read-Json $TaskResultPath;$inputs=Read-Json $SourceInputsPath
Require (@($identity.identities).Count -eq 2) 'exactly two diagnosed identities required'
Require ([string]$identity.owner -ceq $ExpectedOwner -and [string]$coordinator.owner -ceq $ExpectedOwner -and [string]$task.owner -ceq $ExpectedOwner) 'owner lineage mismatch'
Require ([int]$coordinator.count -eq 20 -and [int]$task.count -eq 20) 'count20 lineage missing'
Require ((Normalize-Hash $coordinator.sourceInputsHash) -ceq (Normalize-Hash $SourceInputsSha256)) 'source-input hash lineage mismatch'
if($task.PSObject.Properties.Name -contains 'sourceInputsHash'){Require ((Normalize-Hash $task.sourceInputsHash) -ceq (Normalize-Hash $SourceInputsSha256)) 'task source-input hash lineage mismatch'}
Require ((Normalize-Hash $coordinator.exeHash) -ceq (Normalize-Hash $inputs.exeHash)) 'coordinator executable lineage mismatch'
Require ((Normalize-Hash $identity.exeHash) -ceq (Normalize-Hash $inputs.exeHash)) 'identity/exe source join missing'
Require ((Normalize-Hash $identity.sourceInputsHash) -ceq (Normalize-Hash $SourceInputsSha256)) 'identity/source-input hash lineage mismatch'
Require ($OutcomePaths.Count -eq 2 -and $OutcomeSha256s.Count -eq 2 -and $InventoryPaths.Count -eq 2 -and $InventorySha256s.Count -eq 2) 'two outcome/inventory joins required'
for($join=0;$join -lt 2;$join++){$outcome=Read-Json $OutcomePaths[$join];Assert-Pin $OutcomePaths[$join] $OutcomeSha256s[$join];$inventory=Read-Json $InventoryPaths[$join];Assert-Pin $InventoryPaths[$join] $InventorySha256s[$join];$expectedJoin=$identity.identities[$join];Require ($outcome.ownedIdentity.pid -eq $expectedJoin.pid -and ([DateTimeOffset]::Parse([string]$outcome.ownedIdentity.startedAt).UtcDateTime.Ticks -eq [DateTimeOffset]::Parse([string]$expectedJoin.startUtc).UtcDateTime.Ticks) -and ([string]$outcome.ownedIdentity.path).Equals([string]$expectedJoin.path,[StringComparison]::OrdinalIgnoreCase) -and (Normalize-Hash $outcome.exeHash) -eq (Normalize-Hash $inputs.exeHash) -and (Normalize-Hash $outcome.sourceHash) -eq (Normalize-Hash $inputs.sourceHash) -and [string]$outcome.lockOwner -ceq $ExpectedOwner) "outcome lineage mismatch $join";Require ([string]$inventory.lockOwner -ceq $ExpectedOwner -and [string]$inventory.kind -ceq 'factory-owned-uia-slot-inventory-v1' -and [bool]$inventory.attempted -and ([string]$inventory.rendererDirectory).Equals([string]$expectedJoin.workerId,[StringComparison]::OrdinalIgnoreCase)) "inventory lineage mismatch $join"}
Require ([int64]$task.memoryReceipt.peakJobMemoryUsedBytes -le $MaxMemory -and [int64]$task.memoryReceipt.jobMemoryLimitBytes -eq $MaxMemory) 'memory proof missing or over cap'
foreach($identityEntry in @($identity.identities)){if($null -ne $identityEntry.streamBytes){Require ([int64]$identityEntry.streamBytes -le $MaxStream) "stream cap exceeded for PID $($identityEntry.pid)"}}
$lockBytes=Read-Bounded $LockPath 4096;$owner=([Text.Encoding]::UTF8.GetString($lockBytes)).Trim();Require ($owner -ceq $ExpectedOwner) 'owner changed; cleanup will not mutate lock'
Add-NativeType;$watch=[Diagnostics.Stopwatch]::StartNew();$handles=New-Object System.Collections.Generic.List[object];$results=New-Object System.Collections.Generic.List[object];$failed=New-Object System.Collections.Generic.List[string]
try {
 foreach($expected in @($identity.identities)) {
  if($watch.Elapsed.TotalSeconds -ge $DeadlineSeconds){$failed.Add("deadline before PID $($expected.pid)");continue}
  $h=[IntPtr]::Zero;$record=[ordered]@{pid=[int]$expected.pid;expectedPath=[string]$expected.path;expectedStartUtc=[string]$expected.startUtc;expectedExeSha256=(Normalize-Hash $expected.exeSha256);action='none';identityMatch=$false;hasExited=$null;kernelTerminal=$false;exitCodeRaw=$null;streamsSealed=([bool]$expected.streamsSealed);memoryBounded=$true}
  if(-not (Get-Process -Id ([int]$expected.pid) -ErrorAction SilentlyContinue)){
   $record.action='absent-at-cleanup';$record.currentAbsenceAuthority=(Get-CurrentAbsenceDecision $false).action;$proofOk=$false
   if($expected.absenceProofPath -and $expected.absenceProofSha256){try{$proof=Read-Json $expected.absenceProofPath;$proofHash=Hash-Bounded $expected.absenceProofPath;$proofOk=($proofHash -ceq (Normalize-Hash $expected.absenceProofSha256) -and $proof.start.pid -eq $expected.pid -and ([DateTimeOffset]::Parse([string]$proof.start.startedAt).UtcDateTime.Ticks -eq [DateTimeOffset]::Parse([string]$expected.startUtc).UtcDateTime.Ticks) -and (Normalize-Hash $proof.start.exeHash) -eq (Normalize-Hash $expected.exeSha256) -and $proof.sample.handlePid -eq $expected.pid -and [int]$proof.sample.kernelAfter -eq 0 -and [bool]$proof.sample.getExitCodeSucceeded -and @($proof.rawStreams).Count -ge 2 -and @($proof.rawStreams|Where-Object{-not $_.sealed -or -not $_.destinationClosed -or -not $_.copyCompleted}).Count -eq 0)}catch{$record.absenceProofError=$_.Exception.Message}}
   $absenceDecision=Get-AbsentCleanupDecision $proofOk;$record.absenceDecision=$absenceDecision.action;if($absenceDecision.accepted){$record.absenceWithOriginalTerminalProof=$true;$record.kernelTerminal=$true;$record.identityMatch=$true}else{$record.currentAbsenceOriginalProof=$false;$failed.Add("PID $($expected.pid) absent without pinned original terminal proof")}
   $results.Add([pscustomobject]$record);continue
  }
  try {$actual=Open-ExactProcess $expected;$h=$actual.handle;$handles.Add([pscustomobject]@{pid=$expected.pid;handle=$h});$wait=[Sr0TextCleanupNativeV1]::WaitForSingleObject($h,0);$record.waitResult=[int64]$wait;$record.kernelTerminal=($wait -eq 0);$actual.kernelTerminal=$record.kernelTerminal;$actual.waitResult=[int64]$wait;$decision=Get-CleanupPolicyDecision $actual $expected;Require $decision.identityMatch 'production identity policy rejected matching handle';$record.policyHasExitedKernelConflict=$decision.hasExitedKernelConflict;$record.actualPath=$actual.path;$record.actualStartUtc=$actual.startUtc;$record.actualExeSha256=$actual.exeSha256;$record.hasExited=$actual.hasExited;$record.identityMatch=$true
   if($record.hasExited -and -not $record.kernelTerminal){$record.conflict='managed HasExited=true did not suppress kernel cleanup'}
   if($decision.terminate -and -not $record.kernelTerminal){Require ($watch.Elapsed.TotalSeconds -lt $DeadlineSeconds) 'cleanup deadline reached before termination';Require ([Sr0TextCleanupNativeV1]::TerminateProcess($h,1)) "TerminateProcess failed for $($expected.pid)";$record.action='terminate-matching-owned-identity';$wait=[Sr0TextCleanupNativeV1]::WaitForSingleObject($h,([uint32][Math]::Max(1,(($DeadlineSeconds-$watch.Elapsed.TotalSeconds)*1000))));$record.kernelTerminal=($wait -eq 0)}
   $code=[uint32]0;Require ([Sr0TextCleanupNativeV1]::GetExitCodeProcess($h,[ref]$code)) "exit code query failed for $($expected.pid)";$record.exitCodeRaw=[uint64]$code
   if(-not $record.kernelTerminal){$failed.Add("PID $($expected.pid) remained nonterminal")}
  } catch {$record.error=$_.Exception.Message;$current=Get-Process -Id ([int]$expected.pid) -ErrorAction SilentlyContinue;if($null -ne $current){$record.currentIdentityStatus='present-but-not-exact-match-held'}else{$record.currentIdentityStatus='not-present-at-cleanup-held'};$failed.Add("PID $($expected.pid): "+$_.Exception.Message)}
  $results.Add([pscustomobject]$record)
 }
 $status=if($failed.Count -eq 0 -and @($results|Where-Object{ -not $_.kernelTerminal}).Count -eq 0){'cleanup-complete-held-qualification'}else{'cleanup-held'}
 $terminationCount=@($results|Where-Object{$_.action -eq 'terminate-matching-owned-identity'}).Count;$receipt=[ordered]@{kind='text-count20-r9-owned-cleanup-v1';status=$status;qualificationClaim=$false;lockAction='none';expectedOwner=$ExpectedOwner;identityPath=(Full $IdentityPath);identitySha256=$IdentitySha256.ToLowerInvariant();coordinatorPath=(Full $CoordinatorPath);coordinatorSha256=$CoordinatorSha256.ToLowerInvariant();taskResultPath=(Full $TaskResultPath);taskResultSha256=$TaskResultSha256.ToLowerInvariant();sourceInputsPath=(Full $SourceInputsPath);sourceInputsSha256=$SourceInputsSha256.ToLowerInvariant();outcomePaths=@($OutcomePaths|ForEach-Object{Full $_});outcomeSha256s=@($OutcomeSha256s|ForEach-Object{$_.ToLowerInvariant()});inventoryPaths=@($InventoryPaths|ForEach-Object{Full $_});inventorySha256s=@($InventorySha256s|ForEach-Object{$_.ToLowerInvariant()});identities=$results;failed=@($failed);deadlineSeconds=$DeadlineSeconds;memoryLimitBytes=$MaxMemory;streamCapBytes=$MaxStream;terminationPolicy='only exact PID+path+UTC start+EXE hash; kernel wait retained until sealed receipt';historicalFailurePreserved=$true;nativeActions=0;terminationActions=$terminationCount;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
 Write-Fresh $OutputPath $receipt
} finally {foreach($item in $handles.ToArray()){if($item.handle -ne [IntPtr]::Zero){[Sr0TextCleanupNativeV1]::CloseHandle($item.handle)|Out-Null}}}
if($status -eq 'cleanup-held'){exit 2};$receipt|ConvertTo-Json -Depth 16
