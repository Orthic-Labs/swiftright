[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$IdentityPath,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$IdentitySha256,
 [Parameter(Mandatory)][string]$CoordinatorPath,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$CoordinatorSha256,
 [Parameter(Mandatory)][string]$TaskResultPath,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TaskResultSha256,
 [Parameter(Mandatory)][string]$SourceInputsPath,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$SourceInputsSha256,
 [Parameter(Mandatory)][string[]]$OutcomePaths,
 [Parameter(Mandatory)][string[]]$OutcomeSha256s,
 [Parameter(Mandatory)][string[]]$InventoryPaths,
 [Parameter(Mandatory)][string[]]$InventorySha256s,
 [Parameter(Mandatory)][string]$LockPath,
 [Parameter(Mandatory)][string]$ExpectedOwner,
 [Parameter(Mandatory)][string]$OutputPath,
 [ValidateRange(1,30)][int]$DeadlineSeconds=30
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$JsonLimit=[int64]2097152;$EvidenceLimit=[int64]8388608;$ExeLimit=[int64]33554432;$MemoryLimit=[int64]1073741824;$StreamLimit=[int64]8388608
function Fail([string]$m){throw ('text-count20-r9 cleanup review rejected: '+$m)}
function Require([bool]$ok,[string]$m){if(-not $ok){Fail $m}}
function Full([string]$p){return [IO.Path]::GetFullPath($p)}
function Read-Bounded([string]$p,[int64]$limit=$EvidenceLimit){$i=Get-Item -LiteralPath (Full $p) -Force;Require (-not $i.PSIsContainer -and (($i.Attributes-band[IO.FileAttributes]::ReparsePoint)-eq 0) -and $i.Length -le $limit) ('unsafe input: '+$p);return [IO.File]::ReadAllBytes($i.FullName)}
function Hash-Bounded([string]$p,[int64]$limit=$EvidenceLimit){$bytes=Read-Bounded $p $limit;$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))-replace '-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Read-Json([string]$p,[int64]$limit=$JsonLimit){return ([Text.Encoding]::UTF8.GetString((Read-Bounded $p $limit))).TrimStart([char]0xfeff)|ConvertFrom-Json}
function Normalize-Hash([object]$v){if($null -eq $v){return ''};return ([string]$v).ToLowerInvariant().Replace('sha256:','')}
function Assert-Pin([string]$p,[string]$h,[int64]$limit=$EvidenceLimit){Require ((Hash-Bounded $p $limit)-ceq (Normalize-Hash $h)) ('hash pin mismatch: '+$p)}
function Write-Fresh([string]$p,[object]$v){$full=Full $p;Require (-not(Test-Path -LiteralPath $full)) 'cleanup review receipt must be fresh';$parent=Split-Path -Parent $full;Require (Test-Path -LiteralPath $parent -PathType Container) 'cleanup review output parent missing';$tmp="$full.$([guid]::NewGuid().ToString('N')).tmp";[IO.File]::WriteAllText($tmp,(($v|ConvertTo-Json -Depth 18)+"`r`n"),[Text.Encoding]::UTF8);[IO.File]::Move($tmp,$full)}
function Add-NativeType {
 if('Sr0TextCleanupReviewNativeV3' -as [type]){return}
 Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Sr0TextCleanupReviewNativeV3 {
 [DllImport("kernel32.dll",SetLastError=true,EntryPoint="OpenProcess")] public static extern IntPtr OpenProcess(uint a,bool i,uint p);
 [DllImport("kernel32.dll",SetLastError=true,EntryPoint="QueryFullProcessImageNameW",CharSet=CharSet.Unicode)] public static extern bool QueryFullProcessImageName(IntPtr h,uint f,StringBuilder n,ref uint s);
 [DllImport("kernel32.dll",SetLastError=true,EntryPoint="GetProcessTimes")] public static extern bool GetProcessTimes(IntPtr h,out long c,out long e,out long k,out long u);
 [DllImport("kernel32.dll",SetLastError=true,EntryPoint="WaitForSingleObject")] public static extern uint WaitForSingleObject(IntPtr h,uint m);
 [DllImport("kernel32.dll",SetLastError=true,EntryPoint="GetExitCodeProcess")] public static extern bool GetExitCodeProcess(IntPtr h,out uint c);
 [DllImport("kernel32.dll",SetLastError=true,EntryPoint="TerminateProcess")] public static extern bool TerminateProcess(IntPtr h,uint c);
 [DllImport("kernel32.dll",SetLastError=true,EntryPoint="CloseHandle")] public static extern bool CloseHandle(IntPtr h);
}
'@
}
function Native-Path([IntPtr]$h){$s=New-Object Text.StringBuilder 1024;$n=[uint32]$s.Capacity;Require ([Sr0TextCleanupReviewNativeV3]::QueryFullProcessImageName($h,0,$s,[ref]$n)) 'native path query failed';return $s.ToString()}
function Native-StartUtc([IntPtr]$h){$c=[int64]0;$e=[int64]0;$k=[int64]0;$u=[int64]0;Require ([Sr0TextCleanupReviewNativeV3]::GetProcessTimes($h,[ref]$c,[ref]$e,[ref]$k,[ref]$u)) 'native process time query failed';return [DateTime]::FromFileTimeUtc($c).ToString('o')}
function Test-CurrentAbsence([int]$pid){$h=[Sr0TextCleanupReviewNativeV3]::OpenProcess(0x00120101,$false,[uint32]$pid);if($h -ne [IntPtr]::Zero){[Sr0TextCleanupReviewNativeV3]::CloseHandle($h)|Out-Null;return [ordered]@{openProcessZero=$false;lastError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}};return [ordered]@{openProcessZero=$true;lastError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}}
function Same-Identity([object]$a,[object]$e){return [bool]($a.pid -eq $e.pid -and ([string]$a.path).Equals([string]$e.path,[StringComparison]::OrdinalIgnoreCase) -and [DateTimeOffset]::Parse([string]$a.startUtc).UtcDateTime.Ticks -eq [DateTimeOffset]::Parse([string]$e.startUtc).UtcDateTime.Ticks -and (Normalize-Hash $a.exeSha256) -ceq (Normalize-Hash $e.exeSha256))}
function Read-OriginalAbsence([object]$e){
 if(-not $e.absenceProofPath -or -not $e.absenceProofSha256){return [ordered]@{accepted=$false;action='current-not-present-without-original-proof'}}
 try{$p=Read-Json ([string]$e.absenceProofPath);Assert-Pin ([string]$e.absenceProofPath) ([string]$e.absenceProofSha256);$ok=($p.start.pid -eq $e.pid -and [DateTimeOffset]::Parse([string]$p.start.startedAt).UtcDateTime.Ticks -eq [DateTimeOffset]::Parse([string]$e.startUtc).UtcDateTime.Ticks -and (Normalize-Hash $p.start.exeHash) -ceq (Normalize-Hash $e.exeSha256) -and $p.sample.handlePid -eq $e.pid -and [int]$p.sample.kernelAfter -eq 0 -and [bool]$p.sample.getExitCodeSucceeded -and @($p.rawStreams).Count -ge 2 -and @($p.rawStreams|Where-Object{ -not $_.sealed -or -not $_.destinationClosed -or -not $_.copyCompleted}).Count -eq 0);return [ordered]@{accepted=$ok;action=if($ok){'current-not-present-original-terminal-proof'}else{'current-not-present-proof-invalid'}}}catch{return [ordered]@{accepted=$false;action='current-not-present-proof-read-failed'}}
}
Assert-Pin $IdentityPath $IdentitySha256;Assert-Pin $CoordinatorPath $CoordinatorSha256;Assert-Pin $TaskResultPath $TaskResultSha256;Assert-Pin $SourceInputsPath $SourceInputsSha256
$identity=Read-Json $IdentityPath;$coordinator=Read-Json $CoordinatorPath;$task=Read-Json $TaskResultPath;$inputs=Read-Json $SourceInputsPath
Require (@($identity.identities).Count -eq 2) 'exactly two identities required';Require ([string]$identity.owner -ceq $ExpectedOwner -and [string]$coordinator.owner -ceq $ExpectedOwner -and [string]$task.owner -ceq $ExpectedOwner) 'owner lineage mismatch';Require ([int]$coordinator.count -eq 20 -and [int]$task.count -eq 20) 'count20 lineage missing';Require ((Normalize-Hash $coordinator.sourceInputsHash)-ceq(Normalize-Hash $SourceInputsSha256)) 'coordinator source-input lineage missing';Require ((Normalize-Hash $coordinator.exeHash)-ceq(Normalize-Hash $inputs.exeHash)) 'coordinator executable lineage missing';Require ((Normalize-Hash $identity.exeHash)-ceq(Normalize-Hash $inputs.exeHash)) 'identity executable lineage missing';Require ((Normalize-Hash $identity.sourceInputsHash)-ceq(Normalize-Hash $SourceInputsSha256)) 'identity source-input lineage missing';Require ([int64]$task.memoryReceipt.jobMemoryLimitBytes -eq $MemoryLimit -and [int64]$task.memoryReceipt.peakJobMemoryUsedBytes -le $MemoryLimit) 'memory bound missing';Require ($OutcomePaths.Count -eq 2 -and $OutcomeSha256s.Count -eq 2 -and $InventoryPaths.Count -eq 2 -and $InventorySha256s.Count -eq 2) 'two outcome/inventory joins required'
for($j=0;$j -lt 2;$j++){Assert-Pin $OutcomePaths[$j] $OutcomeSha256s[$j];Assert-Pin $InventoryPaths[$j] $InventorySha256s[$j];$outcome=Read-Json $OutcomePaths[$j];$inventory=Read-Json $InventoryPaths[$j];$expected=$identity.identities[$j];Require ([int]$outcome.ownedIdentity.pid -eq [int]$expected.pid -and ([string]$outcome.ownedIdentity.path).Equals([string]$expected.path,[StringComparison]::OrdinalIgnoreCase) -and [DateTimeOffset]::Parse([string]$outcome.ownedIdentity.startedAt).UtcDateTime.Ticks -eq [DateTimeOffset]::Parse([string]$expected.startUtc).UtcDateTime.Ticks -and (Normalize-Hash $outcome.exeHash)-ceq(Normalize-Hash $inputs.exeHash) -and [string]$outcome.lockOwner -ceq $ExpectedOwner) ('outcome lineage mismatch '+$j);Require ([string]$inventory.lockOwner -ceq $ExpectedOwner) ('inventory owner mismatch '+$j)}
$lockOwner=([Text.Encoding]::UTF8.GetString((Read-Bounded $LockPath 4096))).Trim();Require ($lockOwner -ceq $ExpectedOwner) 'lock owner changed; no cleanup release authority'
Add-NativeType;$watch=[Diagnostics.Stopwatch]::StartNew();$records=@();$handles=@();$failures=@()
try {
 foreach($expected in @($identity.identities)){
  $r=[ordered]@{pid=[int]$expected.pid;expectedPath=[string]$expected.path;expectedStartUtc=[string]$expected.startUtc;expectedExeSha256=(Normalize-Hash $expected.exeSha256);action='none';identityMatch=$false;currentPresence=$null;kernelWait=$null;kernelTerminal=$false;exitCodeRaw=$null;hasExited=$null;streamsSealed=[bool]$expected.streamsSealed}
  if(-not(Get-Process -Id ([int]$expected.pid) -ErrorAction SilentlyContinue)){$nativeAbsence=Test-CurrentAbsence ([int]$expected.pid);$absence=Read-OriginalAbsence $expected;$r.currentPresence='absent-at-cleanup';$r.nativeAbsence=$nativeAbsence;$r.absenceDecision=$absence.action;$r.kernelTerminal=[bool]($absence.accepted -and $nativeAbsence.openProcessZero -and [int]$nativeAbsence.lastError -eq 87);$r.identityMatch=[bool]$r.kernelTerminal;if(-not $r.kernelTerminal){$failures+=('PID '+$expected.pid+' absent without native ERROR_INVALID_PARAMETER 87 plus original terminal proof')};$records+=,[pscustomobject]$r;continue}
  $h=[IntPtr]::Zero
  try{$h=[Sr0TextCleanupReviewNativeV3]::OpenProcess(0x00120101,$false,[uint32]$expected.pid);Require ($h -ne [IntPtr]::Zero) 'OpenProcess failed';$actual=[pscustomobject]@{pid=[int]$expected.pid;path=(Native-Path $h);startUtc=(Native-StartUtc $h);exeSha256=(Hash-Bounded (Native-Path $h) $ExeLimit)};$r.currentPresence='present';$r.actualPath=$actual.path;$r.actualStartUtc=$actual.startUtc;$r.actualExeSha256=$actual.exeSha256;Require (Same-Identity $actual $expected) 'reused PID or path/start/hash mismatch';$r.identityMatch=$true;$p=Get-Process -Id ([int]$expected.pid) -ErrorAction Stop;$r.hasExited=[bool]$p.HasExited;$wait=[Sr0TextCleanupReviewNativeV3]::WaitForSingleObject($h,0);$r.kernelWait=[int64]$wait;Require ($wait -eq 0 -or $wait -eq 258) 'unknown kernel wait; hold';if($wait -eq 258){Require ($watch.Elapsed.TotalSeconds -lt $DeadlineSeconds) 'cleanup deadline before owned termination';Require ([Sr0TextCleanupReviewNativeV3]::TerminateProcess($h,1)) 'owned termination failed';$r.action='terminate-exact-owned-identity';$wait=[Sr0TextCleanupReviewNativeV3]::WaitForSingleObject($h,[uint32][Math]::Max(1,(($DeadlineSeconds-$watch.Elapsed.TotalSeconds)*1000)));$r.kernelWait=[int64]$wait};$r.kernelTerminal=($wait -eq 0);$code=[uint32]0;Require ([Sr0TextCleanupReviewNativeV3]::GetExitCodeProcess($h,[ref]$code)) 'exit code query failed';$r.exitCodeRaw=[uint64]$code;if(-not $r.kernelTerminal){$failures+=('PID '+$expected.pid+' remained nonterminal')} }catch{$r.error=$_.Exception.Message;$failures+=('PID '+$expected.pid+': '+$_.Exception.Message)}finally{if($h -ne [IntPtr]::Zero){$handles+=,$h}}
  $records+=,[pscustomobject]$r
 }
 $status=if($failures.Count -eq 0 -and @($records|Where-Object{-not $_.kernelTerminal}).Count -eq 0){'cleanup-complete-held-qualification'}else{'cleanup-held'};$terminationCount=@($records|Where-Object{$_.action -eq 'terminate-exact-owned-identity'}).Count;$receipt=[ordered]@{kind='text-count20-r9-cleanup-review-v3';status=$status;qualificationClaim=$false;lockAction='none';expectedOwner=$ExpectedOwner;historicalFailurePreserved=$true;identityPath=(Full $IdentityPath);identitySha256=(Normalize-Hash $IdentitySha256);coordinatorPath=(Full $CoordinatorPath);coordinatorSha256=(Normalize-Hash $CoordinatorSha256);taskResultPath=(Full $TaskResultPath);taskResultSha256=(Normalize-Hash $TaskResultSha256);sourceInputsPath=(Full $SourceInputsPath);sourceInputsSha256=(Normalize-Hash $SourceInputsSha256);records=$records;failures=@($failures);memoryLimitBytes=$MemoryLimit;streamLimitBytes=$StreamLimit;deadlineSeconds=$DeadlineSeconds;terminationCount=$terminationCount;policy='exact PID+path+native start ticks+EXE hash; native wait 0/258 only; no lock mutation';checkedAt=[DateTimeOffset]::UtcNow.ToString('o')};Write-Fresh $OutputPath $receipt
} finally {foreach($h in $handles){if($h -ne [IntPtr]::Zero){[Sr0TextCleanupReviewNativeV3]::CloseHandle($h)|Out-Null}}}
if($status -eq 'cleanup-held'){exit 2};exit 0
