[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArchiveRoot,
  [Parameter(Mandatory)][string]$OutputPath,
  [string]$ExpectedOwner = 'SR0-DISPLAY-SELFJOB-SR0-factory-display-selfjob-v7-root-r8'
)
$ErrorActionPreference='Stop'
$MaxJson=2MB;$MaxEvidence=64MB;$ExpectedMemory=[int64]1073741824;$ExpectedFlags=[int64]512
function Reject([string]$m){throw "owner-release evidence rejected: $m"}
function Read-BoundedJson([string]$p){
  $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if(-not $i.PSIsContainer -and (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) -and $i.Length -le $MaxJson){return ([IO.File]::ReadAllText($i.FullName)|ConvertFrom-Json)}
  Reject "unsafe or oversized JSON: $p"
}
function Hash-Bounded([string]$p){
  $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $i.Length -gt $MaxEvidence){Reject "unsafe or oversized evidence: $p"}
  return [ordered]@{bytes=[int64]$i.Length;sha256=(Get-FileHash -LiteralPath $i.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Require([bool]$ok,[string]$why,[System.Collections.Generic.List[string]]$holds){if(-not $ok){[void]$holds.Add($why)}}
$root=[IO.Path]::GetFullPath($ArchiveRoot);$run=Join-Path $root 'run';$control=Join-Path $root 'control';$holds=New-Object 'System.Collections.Generic.List[string]'
$launcher=Read-BoundedJson (Join-Path $run 'launcher-receipt.json');$collector=Read-BoundedJson (Join-Path $run 'collector-receipt.json');$coordinator=Read-BoundedJson (Join-Path $run 'coordinator-verdict.json');$start=Read-BoundedJson (Join-Path $run 'start-receipt.json');$observer=Read-BoundedJson (Join-Path $control 'native-observer-r10c.json');$lockPath=Join-Path $control 'desktop.lock';$lockItem=Get-Item -LiteralPath $lockPath -Force -ErrorAction Stop
if($lockItem.PSIsContainer -or (($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $lockItem.Length -gt 256){Reject 'desktop lock path unsafe or oversized'}
$owner=[IO.File]::ReadAllText($lockItem.FullName).Trim();Require ($owner -ceq $ExpectedOwner) 'desktop owner changed from expected CAS owner' $holds
Require ([bool]$start.parentHandleRetained -and [bool]$start.parentHandleAcquired) 'original collector parent handle was not retained/acquired' $holds
Require ([string]$launcher.kind -eq 'sr0-display-launcher-v7' -or [string]$launcher.kind -eq 'sr0-display-launcher-v8-status') 'launcher receipt kind mismatch' $holds
Require ([string]$launcher.status -eq 'held') 'historical launcher hold status was not preserved' $holds
Require ([bool]$launcher.coordinatorHandleAcquired -and [bool]$launcher.coordinatorTerminal -and [bool]$launcher.coordinatorExitIdentity) 'coordinator original handle terminal identity missing' $holds
Require ([bool]$launcher.collectorHandleAcquired -and [bool]$launcher.collectorTerminal -and [bool]$launcher.collectorExitIdentity) 'collector original handle terminal identity missing' $holds
Require ([bool]$launcher.aggregateDescendantsQuiesced -and [bool]$launcher.aggregateCleanupSelfOnly -and [int64]$launcher.aggregateActiveAfter -eq 1) 'aggregate owned descendants/self-only proof missing' $holds
Require ([int64]$launcher.aggregateJobMemoryLimitBytes -eq $ExpectedMemory -and [int64]$launcher.aggregateLimitFlags -eq $ExpectedFlags -and [bool]$launcher.aggregateMemoryCapExceeded -eq $false) 'aggregate memory proof missing or cap exceeded' $holds
Require ([bool]$collector.parentOriginalHandleRetained -and [bool]$collector.parentOriginalHandleAcquired) 'collector parent original handle proof missing' $holds
Require ([bool]$collector.presentMonHandleAcquired -and [bool]$collector.presentMonTerminal -and [bool]$collector.presentMonExitIdentity) 'PresentMon original handle terminal identity missing' $holds
Require ([bool]$collector.workloadHandleAcquired -and [bool]$collector.workloadTerminal -and [bool]$collector.workloadExitIdentity) 'Workload original handle terminal identity missing' $holds
Require ([bool]$collector.presentMonSessionAbsent -and [int64]$collector.presentMonExitSigned -eq -1 -and [int64]$collector.presentMonStopExit -eq 0) 'owned PresentMon stop/session proof missing' $holds
Require ([bool]$collector.activeSelfOnly -and [int64]$collector.activeAfter -eq 1 -and [int64]$collector.jobMemoryLimitBytes -eq $ExpectedMemory -and [int64]$collector.limitFlagsAfter -eq $ExpectedFlags) 'collector job self-only/memory proof missing' $holds
Require ([bool]$coordinator.parentKernelTerminal -and [int64]$coordinator.parentExitSigned -eq [int64]$coordinator.parentExitDotnet -and [int64]$coordinator.parentExitRaw -eq [int64]$coordinator.parentExitSigned) 'coordinator retained parent kernel/.NET terminal identity missing' $holds
Require ([bool]$observer.scheduleOriginalHandleAcquired -and [bool]$observer.scheduleTerminal -and [bool]$observer.scheduleExitIdentity -and [bool]$observer.scheduleStreamsSealed) 'observer schedule original terminal/stream proof missing' $holds
Require ([bool]$observer.launcherSelfOnly -and [int64]$observer.launcherAggregateActiveAfter -eq 1 -and [bool]$observer.transportSelfOnly -and [bool]$observer.transportCleanupProof) 'observer outer transport self-only cleanup proof missing' $holds
Require ([int64]$observer.transportFinal.LimitBytes -eq $ExpectedMemory -and [int64]$observer.transportFinal.LimitFlags -eq $ExpectedFlags -and [int64]$observer.transportFinal.ActiveCount -eq 1) 'observer transport final memory/active proof missing' $holds
Require ([string]$collector.status -eq 'failed' -and [string]$coordinator.status -eq 'held' -and [string]$observer.status -eq 'held') 'historical failure/hold status was not preserved' $holds
$exportPath=Join-Path $root 'export-manifest.json';$raw=@();if(Test-Path -LiteralPath $exportPath -PathType Leaf){$export=Read-BoundedJson $exportPath;foreach($entry in @($export.files)){if([string]$entry.path -match '(^|[\\/])\.\.?([\\/]|$)'){Reject 'export path traversal'};$p=Join-Path $root ([string]$entry.path);try{$h=Hash-Bounded $p;Require ($h.bytes -eq [int64]$entry.bytes -and $h.sha256 -ceq ([string]$entry.sha256).ToLowerInvariant()) "raw hash/byte mismatch: $($entry.path)" $holds;$raw+=[ordered]@{path=[string]$entry.path;bytes=$h.bytes;sha256=$h.sha256}}catch{[void]$holds.Add($_.Exception.Message)}}}else{[void]$holds.Add('export manifest missing')}
$proof=[ordered]@{kind='sr0-display-native-r10c-owner-release-v1';status=if($holds.Count -eq 0){'eligible-for-owner-cas-review'}else{'held'};releaseEligible=($holds.Count -eq 0);processActions='none';desktopLockAction='compare-and-set only after independent review';expectedOwner=$ExpectedOwner;observedOwner=$owner;originalFailurePreserved=$true;qualificationClaim=$false;streamProofMode='transitive-owned-job-terminal-self-only';rawSealTiming='post-terminal archival hashes; not original child stream-seal certificate';holds=@($holds);rawEvidence=$raw;sourceArchive=$root;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$outDir=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $outDir -PathType Container)){Reject 'output parent missing'};if(Test-Path -LiteralPath $OutputPath){Reject 'output must be fresh'};$tmp="$OutputPath.$PID.$([guid]::NewGuid().ToString('N')).tmp";[IO.File]::WriteAllText($tmp,(($proof|ConvertTo-Json -Depth 12)+"`r`n"),[Text.Encoding]::UTF8);[IO.File]::Move($tmp,$OutputPath);if($proof.releaseEligible){Write-Output 'eligible-for-owner-cas-review'}else{Write-Output 'held';exit 2}
