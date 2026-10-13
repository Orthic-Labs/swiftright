$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$run='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r12b\run'
$owner='SR0-DISPLAY-SELFJOB-SR0-factory-display-selfjob-v7-root-r12'
$taskName='SR0-factory-display-selfjob-v7-root-r12'
function Read-Pinned([string]$path,[string]$sha){
 $f=Get-Item -LiteralPath $path -Force
 if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $f.Length -gt 2097152 -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $sha){throw 'cleanup receipt pin drift'}
 return Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
}
$launcher=Read-Pinned (Join-Path $run 'launcher-receipt.json') '1fc37b5872c0c39fb7f0760401ba50c4edb21ca926b9401c8da9c31d87e169c7'
$collector=Read-Pinned (Join-Path $run 'collector-receipt.json') 'f6cff6993f65fa697492ddf692c8bcfd1da2c1d1162da2bd73d90d02a60684c4'
$coordinator=Read-Pinned (Join-Path $run 'coordinator-verdict.json') '0325eb454f4819a816938b2482a8fd4617fe371e505cf1e2943f5b32c53a874d'
$outer=Read-Pinned 'D:\Claude\swiftright\.factory-work\root-tools\sr0-r12-observer-r13-native-r1-transport.json' '99d14739fcd1e64b8b8d15450e51cab60c07ab08135710f914e72df31e8bb870'
if($launcher.status -cne 'held' -or $collector.status -cne 'failed' -or $coordinator.status -cne 'held'){throw 'failed evidence must remain held'}
foreach($r in @($launcher,$collector,$coordinator)){if($r.taskName -cne $taskName){throw 'exact task identity'} }
if(-not $launcher.coordinatorHandleAcquired -or -not $launcher.coordinatorTerminal -or -not $launcher.coordinatorExitIdentity -or -not $launcher.collectorHandleAcquired -or -not $launcher.collectorTerminal -or -not $launcher.collectorExitIdentity -or -not $launcher.aggregateDescendantsQuiesced -or $launcher.aggregateActiveAfter -ne 1 -or $launcher.aggregateJobMemoryLimitBytes -ne 1073741824 -or $launcher.aggregateLimitFlags -ne 512 -or $launcher.aggregateMemoryCapExceeded){throw 'original launcher terminal/self-only proof'}
if(-not $collector.parentOriginalHandleRetained -or -not $collector.presentMonHandleAcquired -or -not $collector.presentMonTerminal -or -not $collector.presentMonExitIdentity -or -not $collector.workloadHandleAcquired -or -not $collector.workloadTerminal -or -not $collector.workloadExitIdentity -or -not $collector.activeSelfOnly -or $collector.activeAfter -ne 1 -or -not $collector.presentMonSessionAbsent){throw 'original collector terminal/self-only proof'}
if(-not $coordinator.parentKernelTerminal -or $coordinator.parentExitRaw -ne 1 -or $coordinator.parentExitSigned -ne 1 -or $coordinator.parentExitDotnet -ne 1 -or -not $coordinator.lockOwnerObserved){throw 'original launcher-parent terminal identity'}
if(-not $outer.childHandleAcquired -or -not $outer.childTerminal -or -not $outer.childExitIdentity -or -not $outer.streamsSealed -or -not $outer.selfOnly -or $outer.activeAfter -ne 1 -or -not $outer.cleanupSelfOnly -or $outer.cleanupAfter -ne 1 -or $outer.memoryCapExceeded){throw 'original transport cleanup terminal proof'}
$task=@(Get-ScheduledTask -TaskName $taskName -ErrorAction Stop)
if($task.Count -ne 1 -or [string]$task[0].State -cne 'Ready'){throw 'exact scheduled task must be Ready'}
$lock='D:\Claude\desktop.lock';$item=Get-Item -LiteralPath $lock -Force
if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 256){throw 'lock regular file cap'}
$stream=[IO.File]::Open($lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
 $raw=New-Object byte[] ([int]$stream.Length);$count=$stream.Read($raw,0,$raw.Length)
 if($count -ne $raw.Length -or [Text.Encoding]::UTF8.GetString($raw).Trim() -cne $owner){throw 'exact lock owner changed'}
 $free=[Text.Encoding]::UTF8.GetBytes('free');$stream.Position=0;$stream.SetLength(0);$stream.Write($free,0,$free.Length);$stream.Flush()
}finally{$stream.Dispose()}
[ordered]@{kind='sr0-r12-owner-cleanup-v1';status='owner-released-after-original-terminal-proofs';owner=$owner;taskName=$taskName;taskState='Ready';processActions=0;lockReleased=$true;qualificationClaim=$false;originalFailurePreserved=$true;observerCertificateMissing=$true;proofMode='original launcher collector coordinator & outer retained-kernel terminal receipts';checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8
