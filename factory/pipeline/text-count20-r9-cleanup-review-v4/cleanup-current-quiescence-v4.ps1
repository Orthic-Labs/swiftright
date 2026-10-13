[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$EvidenceRoot,
 [Parameter(Mandatory)][string]$IdentityPath,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$IdentitySha256,
 [Parameter(Mandatory)][string]$CoordinatorPath,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$CoordinatorSha256,
 [Parameter(Mandatory)][string]$TaskResultPath,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TaskResultSha256,
 [Parameter(Mandatory)][string]$SourceInputsPath,
 [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$SourceInputsSha256,
 [Parameter(Mandatory)][string]$LockPath,
 [Parameter(Mandatory)][string]$ExpectedOwner,
 [Parameter(Mandatory)][string]$OutputPath,
 [ValidateRange(1,30)][int]$DeadlineSeconds=30
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$JsonLimit=[int64]2097152;$EvidenceLimit=[int64]8388608;$ExeLimit=[int64]33554432;$MemoryLimit=[int64]1073741824
function Fail([string]$m){throw ('text-count20-r9 current cleanup rejected: '+$m)}
function Require([bool]$ok,[string]$m){if(-not $ok){Fail $m}}
function Full([string]$p){return [IO.Path]::GetFullPath($p)}
function Resolve-Evidence([string]$p){if([IO.Path]::IsPathRooted($p)){return Full $p};return Full (Join-Path (Full $EvidenceRoot) $p)}
function Read-Bounded([string]$p,[int64]$limit=$EvidenceLimit){$i=Get-Item -LiteralPath (Resolve-Evidence $p) -Force;Require (-not $i.PSIsContainer -and (($i.Attributes-band[IO.FileAttributes]::ReparsePoint)-eq 0) -and $i.Length -le $limit) ('unsafe input: '+$p);return [IO.File]::ReadAllBytes($i.FullName)}
function Hash-Bounded([string]$p,[int64]$limit=$EvidenceLimit){$b=Read-Bounded $p $limit;$s=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($s.ComputeHash($b))-replace '-','').ToLowerInvariant()}finally{$s.Dispose()}}
function Read-Json([string]$p,[int64]$limit=$JsonLimit){return ([Text.Encoding]::UTF8.GetString((Read-Bounded $p $limit))).TrimStart([char]0xfeff)|ConvertFrom-Json}
function Normalize-Hash([object]$v){if($null -eq $v){return ''};return ([string]$v).ToLowerInvariant().Replace('sha256:','')}
function Assert-Pin([string]$p,[string]$h,[int64]$limit=$EvidenceLimit){Require ((Hash-Bounded $p $limit)-ceq(Normalize-Hash $h)) ('hash pin mismatch: '+$p)}
function Write-Fresh([string]$p,[object]$v){$full=Full $p;Require (-not(Test-Path -LiteralPath $full)) 'fresh receipt path already exists';$parent=Split-Path -Parent $full;Require (Test-Path -LiteralPath $parent -PathType Container) 'receipt parent missing';$tmp="$full.$([guid]::NewGuid().ToString('N')).tmp";[IO.File]::WriteAllText($tmp,(($v|ConvertTo-Json -Depth 18)+"`r`n"),[Text.Encoding]::UTF8);[IO.File]::Move($tmp,$full)}
function Add-NativeType {
 if('Sr0TextCleanupCurrentV4' -as [type]){return}
 Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Sr0TextCleanupCurrentV4 {
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
function Native-Path([IntPtr]$h){$s=New-Object Text.StringBuilder 1024;$n=[uint32]$s.Capacity;Require ([Sr0TextCleanupCurrentV4]::QueryFullProcessImageName($h,0,$s,[ref]$n)) 'native path query failed';return $s.ToString()}
function Native-StartUtc([IntPtr]$h){$c=[int64]0;$e=[int64]0;$k=[int64]0;$u=[int64]0;Require ([Sr0TextCleanupCurrentV4]::GetProcessTimes($h,[ref]$c,[ref]$e,[ref]$k,[ref]$u)) 'native process time query failed';return [DateTime]::FromFileTimeUtc($c).ToString('o')}
function Same-Identity([object]$actual,[object]$expected){return [bool]($actual.pid -eq $expected.pid -and ([string]$actual.path).Equals([string]$expected.path,[StringComparison]::OrdinalIgnoreCase) -and [DateTimeOffset]::Parse([string]$actual.startUtc).UtcDateTime.Ticks -eq [DateTimeOffset]::Parse([string]$expected.startUtc).UtcDateTime.Ticks -and (Normalize-Hash $actual.exeSha256)-ceq(Normalize-Hash $expected.exeSha256))}
function Current-Absence([int]$ProcessId){$h=[Sr0TextCleanupCurrentV4]::OpenProcess(0x00120101,$false,[uint32]$ProcessId);$err=[Runtime.InteropServices.Marshal]::GetLastWin32Error();if($h -ne [IntPtr]::Zero){[Sr0TextCleanupCurrentV4]::CloseHandle($h)|Out-Null;return [ordered]@{managedAbsent=$false;openProcessZero=$false;lastError=$err}};return [ordered]@{managedAbsent=$true;openProcessZero=$true;lastError=$err}}
function Verify-OriginalProof([object]$entry){
 $p=Read-Json ([string]$entry.proofPath)
 if(([string]$entry.role) -eq 'coordinator-parent'){
  Require ([int]$p.taskParentProof.pid -eq [int]$entry.pid -and [int]$p.taskParentProof.kernelWait -eq 0 -and [int]$p.taskParentProof.kernelExitCodeSigned -eq 1 -and [bool]$p.taskParentProof.dotNetExited) 'coordinator parent terminal proof mismatch'
  $s=Read-Json ([string]$entry.startEvidencePath);Require ([int]$s.pid -eq [int]$entry.pid -and ([string]$s.path).Equals([string]$entry.path,[StringComparison]::OrdinalIgnoreCase) -and [DateTimeOffset]::Parse([string]$s.startedAt).UtcDateTime.Ticks -eq [DateTimeOffset]::Parse([string]$entry.startUtc).UtcDateTime.Ticks) 'coordinator start pin mismatch'
 } else {
  Require ([int]$p.start.pid -eq [int]$entry.pid -and ([string]$p.start.path).Equals([string]$entry.path,[StringComparison]::OrdinalIgnoreCase) -and [DateTimeOffset]::Parse([string]$p.start.startedAt).UtcDateTime.Ticks -eq [DateTimeOffset]::Parse([string]$entry.startUtc).UtcDateTime.Ticks -and [int]$p.sample.handlePid -eq [int]$entry.pid -and [int]$p.sample.kernelAfter -eq 0 -and [bool]$p.sample.getExitCodeSucceeded) 'original terminal identity proof mismatch'
  Require (@($p.rawStreams).Count -ge 2 -and @($p.rawStreams|Where-Object{-not $_.copyCompleted -or -not $_.destinationClosed -or -not $_.sealed -or [string]$_.hashQualification -ne 'sealed-raw'}).Count -eq 0) 'original stream seal proof mismatch'
 }
}
function Exact-CASFree([string]$p,[string]$expected){$s=$null;try{$s=[IO.File]::Open((Full $p),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);Require ($s.Length -le 4096) 'lock exceeds bound';$reader=[IO.StreamReader]::new($s,[Text.Encoding]::UTF8,$true,1024,$true);try{$current=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()};if($current -cne $expected){return $false};$bytes=[Text.Encoding]::UTF8.GetBytes("free`r`n");$s.Position=0;$s.SetLength(0);$s.Write($bytes,0,$bytes.Length);$s.Flush($true);return $true}finally{if($s){$s.Dispose()}}}
Assert-Pin $IdentityPath $IdentitySha256;Assert-Pin $CoordinatorPath $CoordinatorSha256;Assert-Pin $TaskResultPath $TaskResultSha256;Assert-Pin $SourceInputsPath $SourceInputsSha256;$outputFull=Full $OutputPath;Require (-not(Test-Path -LiteralPath $outputFull)) 'fresh receipt path already exists';Require (Test-Path -LiteralPath (Split-Path -Parent $outputFull) -PathType Container) 'receipt parent missing'
$identity=Read-Json $IdentityPath;$coordinator=Read-Json $CoordinatorPath;$task=Read-Json $TaskResultPath;$inputs=Read-Json $SourceInputsPath
Require ([string]$identity.kind -eq 'text-count20-r9-current-quiescence-identities-v4') 'identity manifest kind mismatch';Require (@($identity.identities).Count -eq 5) 'five current owned identities required';$requiredRoles=@('coordinator-parent','renderer-native-01','renderer-native-02','uia-worker-native-01','uia-worker-native-02');Require ((@($identity.identities|ForEach-Object{[string]$_.role}|Sort-Object)-join '|') -ceq (($requiredRoles|Sort-Object)-join '|')) 'parent/renderer/UIA identity roles incomplete';Require ([string]$identity.owner -ceq $ExpectedOwner -and [string]$coordinator.owner -ceq $ExpectedOwner) 'owner mismatch';Require ([int]$coordinator.count -eq 20 -and [int]$task.count -eq 20) 'count20 mismatch';Require ((Normalize-Hash $identity.sourceInputsHash)-ceq(Normalize-Hash $SourceInputsSha256)) 'identity/source hash mismatch';Require ((Normalize-Hash $coordinator.sourceInputsHash)-ceq(Normalize-Hash $SourceInputsSha256)) 'coordinator/source hash mismatch';Require ((Normalize-Hash $identity.exeHash)-ceq(Normalize-Hash $inputs.exeHash)) 'identity/exe hash mismatch';Require ((Normalize-Hash $coordinator.exeHash)-ceq(Normalize-Hash $inputs.exeHash)) 'coordinator/exe hash mismatch';Require ([int64]$task.memoryReceipt.jobMemoryLimitBytes -eq $MemoryLimit -and [int64]$task.memoryReceipt.peakJobMemoryUsedBytes -le $MemoryLimit) 'memory proof exceeds 1 GiB'
foreach($entry in @($identity.identities)){Assert-Pin ([string]$entry.proofPath) ([string]$entry.proofSha256);if($entry.startEvidencePath){Assert-Pin ([string]$entry.startEvidencePath) ([string]$entry.startEvidenceSha256)};foreach($pin in @($entry.pinFiles)){Assert-Pin ([string]$pin.path) ([string]$pin.sha256)};if([bool]$entry.originalTerminalProof){Verify-OriginalProof $entry}};Require (@($identity.workerInventories).Count -eq 2) 'two worker inventory pins required';foreach($inv in @($identity.workerInventories)){Assert-Pin ([string]$inv.path) ([string]$inv.sha256);$iv=Read-Json ([string]$inv.path);Require ([string]$iv.lockOwner -ceq $ExpectedOwner -and [bool]$iv.attempted) ('worker inventory owner/attempt mismatch: '+$inv.path)}
$lockOwner=([Text.Encoding]::UTF8.GetString((Read-Bounded $LockPath 4096))).Trim();Require ($lockOwner -ceq $ExpectedOwner) 'owner changed before CAS'
Add-NativeType;$watch=[Diagnostics.Stopwatch]::StartNew();$records=@();$handles=@();$failures=@()
try {
 foreach($expected in @($identity.identities)){
  $r=[ordered]@{role=[string]$expected.role;pid=[int]$expected.pid;expectedPath=[string]$expected.path;expectedStartUtc=[string]$expected.startUtc;expectedExeSha256=(Normalize-Hash $expected.exeSha256);originalTerminalProof=[bool]$expected.originalTerminalProof;currentPresence=$null;currentQuiescent=$false;identityMatch=$false;kernelWait=$null;kernelTerminal=$false;exitCodeRaw=$null;action='none'}
  $h=[IntPtr]::Zero
  if(-not(Get-Process -Id ([int]$expected.pid) -ErrorAction SilentlyContinue)){$absence=Current-Absence ([int]$expected.pid);$r.currentPresence='absent-at-cleanup';$r.currentAbsence=$absence;$r.currentQuiescent=[bool]($absence.managedAbsent -and $absence.openProcessZero -and [int]$absence.lastError -eq 87);$r.kernelTerminal=$r.currentQuiescent;$r.identityMatch=$r.currentQuiescent;if(-not $r.currentQuiescent){$failures+=('PID '+$expected.pid+' absence lacks native ERROR_INVALID_PARAMETER 87')}}
  else {try{$h=[Sr0TextCleanupCurrentV4]::OpenProcess(0x00120101,$false,[uint32]$expected.pid);Require ($h -ne [IntPtr]::Zero) 'native handle open failed';$actual=[pscustomobject]@{pid=[int]$expected.pid;path=(Native-Path $h);startUtc=(Native-StartUtc $h);exeSha256=(Hash-Bounded (Native-Path $h) $ExeLimit)};$r.currentPresence='present';$r.actualPath=$actual.path;$r.actualStartUtc=$actual.startUtc;$r.actualExeSha256=$actual.exeSha256;Require (Same-Identity $actual $expected) 'reused PID/path/start/hash rejected';$r.identityMatch=$true;$wait=[Sr0TextCleanupCurrentV4]::WaitForSingleObject($h,0);$r.kernelWait=[int64]$wait;Require ($wait -eq 0 -or $wait -eq 258) 'unknown native wait rejected';if($wait -eq 258){Require ($watch.Elapsed.TotalSeconds -lt $DeadlineSeconds) 'deadline before exact owned termination';Require ([Sr0TextCleanupCurrentV4]::TerminateProcess($h,1)) 'exact owned termination failed';$r.action='terminate-exact-owned-identity';$wait=[Sr0TextCleanupCurrentV4]::WaitForSingleObject($h,[uint32][Math]::Max(1,(($DeadlineSeconds-$watch.Elapsed.TotalSeconds)*1000)));$r.kernelWait=[int64]$wait};$r.kernelTerminal=($wait -eq 0);$r.currentQuiescent=$r.kernelTerminal;$code=[uint32]0;Require ([Sr0TextCleanupCurrentV4]::GetExitCodeProcess($h,[ref]$code)) 'native exit query failed';$r.exitCodeRaw=[uint64]$code;if(-not $r.currentQuiescent){$failures+=('PID '+$expected.pid+' remained live')} }catch{$r.error=$_.Exception.Message;$failures+=('PID '+$expected.pid+': '+$_.Exception.Message)}}
  if($h -ne [IntPtr]::Zero){$handles+=,$h};$records+=,[pscustomobject]$r
 }
 $currentQuiescent=($failures.Count -eq 0 -and @($records|Where-Object{-not $_.currentQuiescent}).Count -eq 0);$allAbsent=($currentQuiescent -and @($records|Where-Object{$_.currentPresence -ne 'absent-at-cleanup'}).Count -eq 0);$originalTerminalProof=(@($records|Where-Object{-not $_.originalTerminalProof}).Count -eq 0);$lockReleased=$false;if($currentQuiescent){$lockReleased=Exact-CASFree $LockPath $ExpectedOwner;if(-not $lockReleased){$failures+= 'exact owner lock CAS failed';$currentQuiescent=$false}};$status=if($currentQuiescent -and -not $originalTerminalProof){'cleanup-quiescent-current-absence-qualification-held'}elseif($currentQuiescent){'cleanup-quiescent-original-terminal-qualification-held'}else{'cleanup-held'};$receipt=[ordered]@{kind='text-count20-r9-cleanup-review-v4';status=$status;currentQuiescent=$currentQuiescent;currentAbsence=$allAbsent;originalTerminalProof=$originalTerminalProof;qualificationClaim=$false;lockAction=if($lockReleased){'exact-owner-CAS-to-free'}else{'none'};lockReleased=$lockReleased;expectedOwner=$ExpectedOwner;historicalFailurePreserved=$true;identityManifestPath=(Full $IdentityPath);identityManifestSha256=(Normalize-Hash $IdentitySha256);coordinatorPath=(Resolve-Evidence $CoordinatorPath);coordinatorSha256=(Normalize-Hash $CoordinatorSha256);taskResultPath=(Resolve-Evidence $TaskResultPath);taskResultSha256=(Normalize-Hash $TaskResultSha256);sourceInputsPath=(Resolve-Evidence $SourceInputsPath);sourceInputsSha256=(Normalize-Hash $SourceInputsSha256);records=$records;failures=@($failures);memoryLimitBytes=$MemoryLimit;deadlineSeconds=$DeadlineSeconds;policy='all archived parent/renderer/UIA identities; exact current absence or exact native identity; reused PID never terminated; lock CAS only after currentQuiescent';checkedAt=[DateTimeOffset]::UtcNow.ToString('o')};Write-Fresh $OutputPath $receipt
} finally {foreach($h in $handles){if($h -ne [IntPtr]::Zero){[Sr0TextCleanupCurrentV4]::CloseHandle($h)|Out-Null}}}
if($currentQuiescent){exit 0};exit 2
