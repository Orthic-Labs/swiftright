# Pure supplemental release verifier for a worker contract failure before worker start.
# Renderer release remains delegated to an already-loaded production release branch.
Set-StrictMode -Version Latest

function Read-FactorySupplementalBounded([string]$Path,[int64]$Limit=2097152){
 if([string]::IsNullOrWhiteSpace($Path)){throw 'Bounded path required'}
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -gt $Limit){throw ('Bounded regular file required: '+$Path)}
 return [IO.File]::ReadAllText($item.FullName)
}
function Get-FactorySupplementalHash([string]$Path,[int64]$Limit=2097152){
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -gt $Limit){throw ('Bounded regular file required: '+$Path)}
 return (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Test-FactorySupplementalHash([string]$Actual,[string]$Expected){
 if($Actual -isnot [string] -or $Expected -isnot [string]){return $false}
 return $Actual.ToLowerInvariant() -ceq ($Expected -replace '^sha256:','').ToLowerInvariant()
}
function Assert-FactorySupplementalNoStartRelease {
 param(
  [Parameter(Mandatory=$true)][string]$CoordinatorPath,
  [Parameter(Mandatory=$true)][string]$MemoryReceiptPath,
  [Parameter(Mandatory=$true)][string]$RendererDirectory,
  [Parameter(Mandatory=$true)][string]$WorkerRoot,
  [Parameter(Mandatory=$true)][string]$WorkerSourceRoot,
  [Parameter(Mandatory=$true)][string]$WorkerInvokerPath,
  [Parameter(Mandatory=$true)][string]$WorkerContractPath,
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$ExpectedInvokerHash,
  [Parameter(Mandatory=$true)][string]$ExpectedWorkerContractHash,
  [Parameter(Mandatory=$true)][string]$DesktopLockPath,
  [Parameter(Mandatory=$true)][scriptblock]$RendererReleaseVerifier,
  [Parameter(Mandatory=$true)][string]$OutputPath
 )
 $coord=Read-FactorySupplementalBounded $CoordinatorPath|ConvertFrom-Json
 $memory=Read-FactorySupplementalBounded $MemoryReceiptPath|ConvertFrom-Json
 if($coord.status -cne 'failed'){throw 'Supplemental release requires failed coordinator'}
 $coordOwner=if($coord.PSObject.Properties.Name -contains 'lockOwner' -and $null -ne $coord.lockOwner -and -not [string]::IsNullOrWhiteSpace([string]$coord.lockOwner)){$coord.lockOwner}else{$coord.owner}
 if($coordOwner -cne $Owner -or $coord.lockAcquired -ne $true -or $coord.lockReleased -ne $false){throw 'Original coordinator lock-held owner proof absent'}
 $parent=$coord.taskParentProof
 if($null -eq $parent -or $parent.kernelWait -ne 0 -or $parent.kernelExitCodeSigned -ne 1 -or $parent.dotNetExited -ne $true -or $parent.dotNetExitCode -ne 1){throw 'Original coordinator parent exit-1 proof absent'}
 $memoryFailureParts=@()
 foreach($field in @('error','reason','message','failure')){if($memory.PSObject.Properties.Name -contains $field -and $memory.$field -is [string]){$memoryFailureParts+=$memory.$field}}
 $memoryFailureText=($memoryFailureParts -join "`n")
 $memoryStatusValid=($memory.status -ceq 'passed') -or (($memory.status -ceq 'rejected') -and $memoryFailureText -match '(?i)(worker-contract\.json).*(cannot find|does not exist|not found|missing)|(cannot find|does not exist|not found|missing).*(worker-contract\.json)')
 if(-not $memoryStatusValid -or $memory.parentPid -ne $parent.pid -or $memory.killOnJobClose -ne $false -or $memory.limitFlags -ne 512 -or $memory.jobMemoryLimitBytes -ne 1073741824 -or $memory.activeProcessCount -ne 1 -or $memory.peakJobMemoryUsedBytes -le 0 -or $memory.peakJobMemoryUsedBytes -gt 1073741824){throw 'Self-only 1GiB memory proof absent or unrelated rejection'}
 $failureParts=@()
 foreach($field in @('error','primaryError')){if($coord.PSObject.Properties.Name -contains $field -and $coord.$field -is [string]){$failureParts+=$coord.$field}}
 if($coord.PSObject.Properties.Name -contains 'taskResult' -and $null -ne $coord.taskResult -and $coord.taskResult.PSObject.Properties.Name -contains 'error' -and $coord.taskResult.error -is [string]){$failureParts+=$coord.taskResult.error}
 $failureText=($failureParts -join "`n")
 if($failureText -notmatch '(?i)worker-contract\.json' -or $failureText -notmatch '(?i)(cannot find|does not exist|not found|missing)'){throw 'Exact missing worker-contract failure absent'}
 $absent=@($WorkerRoot,(Join-Path $WorkerRoot 'worker-launch-attempt.json'),(Join-Path $WorkerRoot 'config.json'),(Join-Path $WorkerRoot 'owned-worker.json'),(Join-Path $WorkerRoot 'final-start.json'))
 foreach($path in $absent){if(Test-Path -LiteralPath $path){throw ('Worker no-start absence failed: '+$path)}}
 $noStartPath=Join-Path $RendererDirectory 'uia-no-start.json'
 if(Test-Path -LiteralPath $noStartPath){$noStart=Read-FactorySupplementalBounded $noStartPath|ConvertFrom-Json;if($noStart.kind -cne 'factory-uia-slot-no-start-v1' -or $noStart.root -cne $WorkerRoot -or $noStart.lockOwner -cne $Owner -or $noStart.processStartReached -ne $false -or $noStart.contractFailureBeforeWorkerStart -ne $true -or $noStart.PSObject.Properties.Name -notcontains 'attempted' -or $noStart.noInvocationConfirmed -ne (-not [bool]$noStart.attempted)){throw 'Worker no-start receipt lineage mismatch'}}
 $invokerText=Read-FactorySupplementalBounded $WorkerInvokerPath
 $contractText=Read-FactorySupplementalBounded $WorkerContractPath
 if(-not(Test-FactorySupplementalHash (Get-FactorySupplementalHash $WorkerInvokerPath) $ExpectedInvokerHash) -or -not(Test-FactorySupplementalHash (Get-FactorySupplementalHash $WorkerContractPath) $ExpectedWorkerContractHash)){throw 'Pinned worker source drift'}
 $contractReadMatch=[regex]::Match($invokerText,'(?m)Get-Content[^\r\n]*worker-contract\.json')
 $contractIndex=$contractReadMatch.Index
 $processIndex=$invokerText.IndexOf('[Diagnostics.Process]::Start',[StringComparison]::Ordinal)
 if(-not $contractReadMatch.Success -or $processIndex -lt 0 -or $contractIndex -ge $processIndex -or $invokerText -notmatch '\$SourceRoot' -or $contractText -notmatch 'sourceBindings'){throw 'Worker contract must be read before Process.Start'}
 $rendererResult=& $RendererReleaseVerifier
 if(@($rendererResult).Count -ne 1 -or $rendererResult -ne $true){throw 'Existing production renderer release proof failed'}
 if(Test-Path -LiteralPath $OutputPath){throw 'Supplemental proof output must be fresh'}
 $lockStream=$null
 try{
  $lockStream=[IO.File]::Open($DesktopLockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  if($lockStream.Length -gt 4096){throw 'Desktop lock bound exceeded'}
  $lockReader=[IO.StreamReader]::new($lockStream,[Text.Encoding]::UTF8,$true,1024,$true)
  try{$lockStream.Position=0;$lockBefore=$lockReader.ReadToEnd().Trim()}finally{$lockReader.Dispose()}
  if($lockBefore -cne $Owner){throw 'Desktop lock owner CAS mismatch'}
  $freeBytes=[Text.Encoding]::UTF8.GetBytes('free');$lockStream.Position=0;$lockStream.SetLength(0);$lockStream.Write($freeBytes,0,$freeBytes.Length);$lockStream.Flush($true)
  $lockReader=[IO.StreamReader]::new($lockStream,[Text.Encoding]::UTF8,$true,1024,$true)
  try{$lockStream.Position=0;$lockAfter=$lockReader.ReadToEnd().Trim()}finally{$lockReader.Dispose()}
  if($lockAfter -cne 'free'){throw 'Desktop lock CAS readback mismatch'}
 }finally{if($null -ne $lockStream){$lockStream.Dispose()}}
 $proof=[ordered]@{kind='factory-uia-supplemental-no-start-release-v1';status='failed-before-worker-start';owner=$Owner;coordinatorPath=$CoordinatorPath;coordinatorStatus=$coord.status;coordinatorOwner=$coordOwner;originalLockAcquired=$coord.lockAcquired;originalLockReleased=$coord.lockReleased;lockPath=$DesktopLockPath;lockBefore=$Owner;lockAfter='free';lockFlushReadback=$true;parentExit=[ordered]@{pid=$parent.pid;kernelWait=$parent.kernelWait;kernelExitCodeSigned=$parent.kernelExitCodeSigned;dotNetExited=$parent.dotNetExited;dotNetExitCode=$parent.dotNetExitCode};memoryReceiptPath=$MemoryReceiptPath;memory=$memory;rendererDirectory=$RendererDirectory;rendererReleaseVerified=$true;workerRoot=$WorkerRoot;workerAbsence=$absent;workerSourceRoot=$WorkerSourceRoot;workerInvokerPath=$WorkerInvokerPath;workerInvokerHash=(Get-FactorySupplementalHash $WorkerInvokerPath);workerContractPath=$WorkerContractPath;workerContractHash=(Get-FactorySupplementalHash $WorkerContractPath);contractReadBeforeProcessStart=$true;failure=$failureText;noStartReceipt=if(Test-Path -LiteralPath $noStartPath){$noStartPath}else{$null};qualification='release-only; no native worker or capture qualification'}
 [IO.File]::WriteAllText($OutputPath,($proof|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
 return $proof
}
