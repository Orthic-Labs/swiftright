# Prospective supplemental release. It never rewrites coordinator/native receipts.
param(
 [Parameter(Mandatory=$true)][string]$Directory,
 [Parameter(Mandatory=$true)][string]$CoordinatorReceiptPath,
 [Parameter(Mandatory=$true)][string]$TaskResultPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TaskResultHash,
 [Parameter(Mandatory=$true)][string]$ProducerRoot,
 [Parameter(Mandatory=$true)][string]$SourceInputsPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$SourceInputsHash,
 [Parameter(Mandatory=$true)][string]$IssuedMetadataPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$IssuedMetadataHash,
 [Parameter(Mandatory=$true)][string]$IntegrationGuardPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$IntegrationGuardHash,
 [Parameter(Mandatory=$true)][string]$ControlsPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ControlsHash,
 [Parameter(Mandatory=$true)][string]$ControlsReceiptPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ControlsReceiptHash,
 [Parameter(Mandatory=$true)][string]$CompilePath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$CompileHash,
 [Parameter(Mandatory=$true)][string]$Exe,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExeHash,
 [Parameter(Mandatory=$true)][string]$SourceHash,
 [Parameter(Mandatory=$true)][string]$RendererHelperPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$RendererHelperHash,
 [Parameter(Mandatory=$true)][string]$AllOwnedReleasePath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$AllOwnedReleaseHash,
 [Parameter(Mandatory=$true)][string]$FrozenReleasePath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$FrozenReleaseHash,
 [Parameter(Mandatory=$true)][string]$V2HelperPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$V2HelperHash,
 [Parameter(Mandatory=$true)][string]$LockPath,
 [Parameter(Mandatory=$true)][string]$SupplementalPath
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Fail([string]$m){throw ('supplemental-owner-release-v2: '+$m)}
function Read-BoundedBytes([string]$Path,[int64]$MaxBytes=8388608){
 $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $i.Length -gt $MaxBytes){Fail ('unsafe or oversized file '+$Path)}
 return ,([IO.File]::ReadAllBytes($Path))
}
function Read-BoundedJson([string]$Path){return ([Text.Encoding]::UTF8.GetString((Read-BoundedBytes $Path))).TrimStart([char]0xfeff)|ConvertFrom-Json}
function Canon([object]$Value){if($null -eq $Value){return ''};return ([string]$Value).ToLowerInvariant().Replace('sha256:','')}
function Hash-Bounded([string]$Path,[int64]$MaxBytes=67108864){
 $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $i.Length -gt $MaxBytes){Fail ('unsafe or oversized pinned file '+$Path)}
 $sha=[Security.Cryptography.SHA256]::Create();$stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read,1048576,[IO.FileOptions]::SequentialScan)
 try{$buf=New-Object byte[] 1048576;while(($n=$stream.Read($buf,0,$buf.Length)) -gt 0){$sha.TransformBlock($buf,0,$n,$null,0)|Out-Null};$sha.TransformFinalBlock([byte[]]::new(0),0,0)|Out-Null;return ([BitConverter]::ToString($sha.Hash)-replace '-','').ToLowerInvariant()}finally{$stream.Dispose();$sha.Dispose()}
}
function Assert-Pin([string]$Path,[string]$Hash,[int64]$MaxBytes=67108864){if((Hash-Bounded $Path $MaxBytes) -cne (Canon $Hash)){Fail ('pinned hash mismatch '+$Path)}}
function Assert-Path([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){Fail ('required path missing '+$Path)}}
function Assert-Dir([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Container)){Fail ('required directory missing '+$Path)}}
function Assert-FreshSupplement([string]$Path){
 $parent=Split-Path -Parent ([IO.Path]::GetFullPath($Path));if(-not(Test-Path -LiteralPath $parent -PathType Container)){Fail 'supplement parent missing'}
 $pi=Get-Item -LiteralPath $parent -Force;if(($pi.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){Fail 'supplement parent is reparse point'}
 if(Test-Path -LiteralPath $Path){Fail 'supplement path must be fresh'}
}
Assert-Dir $Directory;Assert-Dir $ProducerRoot
Assert-Path $CoordinatorReceiptPath;Assert-Path $TaskResultPath;Assert-Path $SourceInputsPath;Assert-Path $IssuedMetadataPath;Assert-Path $IntegrationGuardPath;Assert-Path $ControlsPath;Assert-Path $ControlsReceiptPath;Assert-Path $CompilePath;Assert-Path $Exe;Assert-Path $RendererHelperPath;Assert-Path $AllOwnedReleasePath;Assert-Path $FrozenReleasePath;Assert-Path $V2HelperPath;Assert-Path $LockPath
$co=Read-BoundedJson $CoordinatorReceiptPath
$taskHashActual=Hash-Bounded $TaskResultPath 8388608;if($taskHashActual -cne (Canon $TaskResultHash)){Fail 'task-result hash mismatch'}
$task=Read-BoundedJson $TaskResultPath
$sourceInputsHashActual=Hash-Bounded $SourceInputsPath 8388608;if($sourceInputsHashActual -cne (Canon $SourceInputsHash)){Fail 'source-inputs hash mismatch'}
$sourceInputs=Read-BoundedJson $SourceInputsPath
$issuedHashActual=Hash-Bounded $IssuedMetadataPath 8388608;if($issuedHashActual -ne (Canon $IssuedMetadataHash)){Fail 'issued metadata hash mismatch'}
$issued=Read-BoundedJson $IssuedMetadataPath
Assert-Pin $IntegrationGuardPath $IntegrationGuardHash 16777216;Assert-Pin $ControlsPath $ControlsHash 16777216;Assert-Pin $ControlsReceiptPath $ControlsReceiptHash 8388608;Assert-Pin $CompilePath $CompileHash 67108864;Assert-Pin $Exe $ExeHash 268435456;Assert-Pin $RendererHelperPath $RendererHelperHash 16777216;Assert-Pin $AllOwnedReleasePath $AllOwnedReleaseHash 16777216;Assert-Pin $FrozenReleasePath $FrozenReleaseHash 16777216;Assert-Pin $V2HelperPath $V2HelperHash 16777216
$controls=Read-BoundedJson $ControlsReceiptPath
if($controls.status -cne 'source-control-pass' -or $controls.nativeWindowActions -ne 0 -or $controls.compilerActions -ne 0 -or $controls.lockActions -ne 0){Fail 'controls receipt is not zero-effect pass'}
if($co.owner -isnot [string] -or [string]::IsNullOrWhiteSpace($co.owner)){Fail 'coordinator owner missing'}
if($task.owner -cne $co.owner){Fail 'task-result owner mismatch'}
if($co.status -notin @('completed-source-bound-observation','failed')){Fail 'unexpected coordinator terminal status'}
if($co.status -ceq 'failed' -and [string]$co.error -notmatch 'All owned worker original handle proofs required'){Fail 'failed coordinator reason is not worker-release proof failure'}
foreach($x in @($co,$task)){
 if($x.issuedMetadataHash -cne $co.issuedMetadataHash -or $x.compileReceiptHash -cne $co.compileReceiptHash -or $x.exeHash -cne $co.exeHash -or $x.runRoot -cne $co.runRoot -or $x.count -ne $co.count){Fail 'receipt lineage mismatch'}
 if($x.issuedMetadataHash -cne $IssuedMetadataHash -or (Canon $x.compileReceiptHash) -ne (Canon $CompileHash) -or (Canon $x.exeHash) -ne (Canon $ExeHash)){Fail 'receipt pin mismatch'}
}
if($co.sourceInputsHash -cne $SourceInputsHash){Fail 'coordinator source-inputs join mismatch'}
if($task.PSObject.Properties.Name -contains 'sourceInputsHash' -and $task.sourceInputsHash -cne $SourceInputsHash){Fail 'task source-inputs join mismatch'}
if($sourceInputs.sourceHash -cne $SourceHash -or (Canon $sourceInputs.compileReceiptHash) -ne (Canon $CompileHash) -or (Canon $sourceInputs.exeHash) -ne (Canon $ExeHash)){Fail 'source-inputs compile/source/exe join mismatch'}
if($sourceInputs.compileRef.path -cne $CompilePath -or (Canon $sourceInputs.compileRef.sha256) -ne (Canon $CompileHash) -or $sourceInputs.exeRef.path -cne $Exe -or (Canon $sourceInputs.exeRef.sha256) -ne (Canon $ExeHash)){Fail 'source-inputs reference join mismatch'}
if($co.issuedMetadataHash -cne $IssuedMetadataHash -or $issued.sourceHash -cne $SourceHash -or (Canon $issued.compile.sha256) -ne (Canon $CompileHash) -or (Canon $issued.exe.sha256) -ne (Canon $ExeHash) -or $issued.compile.path -ne $CompilePath -or $issued.exe.path -ne $Exe){Fail 'issued metadata source/compile/exe join mismatch'}
if($issued.runRoot -ne $co.runRoot -or $issued.expectedCount -ne $co.count){Fail 'issued metadata run/count join mismatch'}
if($issued.runID -isnot [string] -or [string]::IsNullOrWhiteSpace($issued.runID)){Fail 'issued runID missing'}
$parent=$co.taskParentProof;if($null -eq $parent -or $parent.kernelWait -ne 0 -or $parent.dotNetExited -ne $true -or $parent.dotNetExitCode -ne $parent.kernelExitCodeSigned){Fail 'original parent kernel/.NET proof missing'}
if($null -eq $task.memoryReceipt){Fail 'task-result memory receipt missing'}
$memory=$task.memoryReceipt
if($memory.status -notin @('passed','rejected') -or $memory.parentPid -ne $parent.pid -or $memory.runID -cne $issued.runID -or $memory.issuedMetadataHash -cne $IssuedMetadataHash -or $memory.killOnJobClose -ne $false -or $memory.limitFlags -ne 512 -or $memory.jobMemoryLimitBytes -ne 1073741824 -or $memory.activeProcessCount -ne 1 -or $memory.peakJobMemoryUsedBytes -le 0 -or $memory.peakJobMemoryUsedBytes -gt 1073741824){Fail 'memory/self-only proof missing'}
$lockItem=Get-Item -LiteralPath $LockPath -Force;if($lockItem.PSIsContainer -or (($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $lockItem.Length -gt 4096){Fail 'unsafe lock'}
Assert-FreshSupplement $SupplementalPath
. $V2HelperPath
. $IntegrationGuardPath
. $RendererHelperPath
. $AllOwnedReleasePath
. $FrozenReleasePath
Assert-RootTextAllOwnedRelease $Directory $co.owner $CompilePath $CompileHash $Exe $ExeHash $SourceHash $ProducerRoot $sourceInputs
$result=[ordered]@{kind='factory-text-supplemental-owner-release-v2';status='supplemental-released';originalCoordinatorReceipt=$CoordinatorReceiptPath;originalTaskResult=$TaskResultPath;originalTaskResultHash=$TaskResultHash;originalCoordinatorStatus=$co.status;originalCoordinatorError=$co.error;owner=$co.owner;lockPath=$LockPath;issuedMetadataPath=$IssuedMetadataPath;issuedMetadataHash=$IssuedMetadataHash;sourceInputsPath=$SourceInputsPath;sourceInputsHash=$SourceInputsHash;rendererAndWorkerProof='v2 worker helper + frozen renderer helper';parentProof=$parent;memoryProof=$memory;nativeWindowActions=0;compilerActions=0;lockActions=1;at=[DateTimeOffset]::UtcNow.ToString('o')}
$json=$result|ConvertTo-Json -Depth 16
$lock=[IO.File]::Open($LockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
 $reader=[IO.StreamReader]::new($lock,[Text.Encoding]::UTF8,$true,1024,$true);try{$old=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()}
 if($old -cne $co.owner){Fail 'lock owner changed before supplemental CAS'}
 $bytes=[Text.Encoding]::UTF8.GetBytes('free');$lock.Position=0;$lock.SetLength(0);$lock.Write($bytes,0,$bytes.Length);$lock.Flush($true);$lock.Position=0
 $reader=[IO.StreamReader]::new($lock,[Text.Encoding]::UTF8,$true,1024,$true);try{$after=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()}
 if($after -cne 'free'){Fail 'supplemental CAS readback failed'}
}finally{$lock.Dispose()}
$out=[IO.FileStream]::new($SupplementalPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,65536,[IO.FileOptions]::SequentialScan);try{$outBytes=[Text.Encoding]::UTF8.GetBytes($json);$out.Write($outBytes,0,$outBytes.Length);$out.Flush($true)}finally{$out.Dispose()}
$json
