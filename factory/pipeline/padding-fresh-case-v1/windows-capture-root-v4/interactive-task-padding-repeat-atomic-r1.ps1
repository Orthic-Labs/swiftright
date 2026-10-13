param([Parameter(Mandatory=$true)][string]$Config,[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
$overlayRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$configPath=[IO.Path]::GetFullPath($Config)
$c=Get-Content -Raw $configPath|ConvertFrom-Json
$here=[IO.Path]::GetFullPath([string]$c.producerRoot)
$controlRoot=[IO.Path]::GetFullPath([string]$c.controlRoot)
$runRoot=[IO.Path]::GetFullPath([string]$c.runRoot)
$admissionRoot=[IO.Path]::GetFullPath([string]$c.admissionRoot)
if(-not(Test-Path -LiteralPath $admissionRoot -PathType Container)){throw 'Explicit admission root missing'}
if(-not $configPath.StartsWith($controlRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Config outside fresh coordinator lane'}
if($c.count -ne 20){throw 'Exact Count20 Padding capture required'}
if($configPath -cne (Join-Path $controlRoot 'config.json') -or $c.controlRoot -cne $controlRoot -or $c.runRoot -cne $runRoot -or [string]::IsNullOrWhiteSpace($c.outputRoot) -or [string]::IsNullOrWhiteSpace($c.package) -or [string]::IsNullOrWhiteSpace($c.sourceInputsPath) -or $c.sourceInputsHash -notmatch '^[0-9a-f]{64}$' -or [string]::IsNullOrWhiteSpace($c.count1ProofPath) -or $c.count1ProofHash -notmatch '^[0-9a-f]{64}$'){throw 'Exact Count20 Padding coordinator config required'}

# Prospective overlay: publish each JSON receipt through a fresh same-directory
# file, then one atomic rename. Existing evidence is never opened or replaced.
function Write-FreshAtomicJson {
 param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value)
 $full=[IO.Path]::GetFullPath($Path)
 $parent=[IO.Path]::GetDirectoryName($full)
 if([string]::IsNullOrWhiteSpace($parent) -or -not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Atomic JSON parent missing'}
 if(Test-Path -LiteralPath $full){throw "Atomic JSON destination already exists: $full"}
 $tmp=Join-Path $parent ('.'+[IO.Path]::GetFileName($full)+'.tmp-'+[Guid]::NewGuid().ToString('N'))
 try {
  $json=$Value|ConvertTo-Json -Depth 8
  $bytes=[Text.Encoding]::UTF8.GetBytes($json+[Environment]::NewLine)
  if($bytes.Length -gt 2097152){throw 'Atomic JSON receipt exceeds 2MiB'}
  [IO.File]::WriteAllBytes($tmp,$bytes)
  if(Test-Path -LiteralPath $full){throw "Atomic JSON destination appeared during write: $full"}
 [IO.File]::Move($tmp,$full)
 }
}
$status='hold-harness-error';$primaryError=$null;$job=$null;$memoryReceipt=$null
try{
 if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive desktop session required'}
 if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne $c.owner){throw 'Coordinator lock ownership lost'}
 $issued=Get-Content -Raw ([IO.Path]::GetFullPath([string]$c.issuedMetadataPath))|ConvertFrom-Json
 $runId=[string]$issued.runID
 if([string]::IsNullOrWhiteSpace($runId)){throw 'Issued metadata runID required for memory receipt'}
 Add-Type -Path (Join-Path $overlayRoot 'Sr0OwnedJobProcess-v15.cs')
 $job=[Sr0OwnedJobProcess]::CreateCurrentProcess(1073741824)
 $initial=$job.QueryPeakJobMemory()
 if($initial.LimitFlags -ne [Sr0OwnedJobProcess]::JobMemoryOnlyFlags -or $initial.JobMemoryLimitBytes -ne 1073741824 -or $initial.ActiveProcessCount -ne 1){throw 'Memory job admission proof failed'}
 $taskStart=[ordered]@{kind='factory-padding-interactive-task-start-v1';pid=[Diagnostics.Process]::GetCurrentProcess().Id;path=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName;startedAt=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o');observedAt=[DateTimeOffset]::UtcNow.ToString('o');sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;owner=$c.owner;jobMemoryLimitBytes=$initial.JobMemoryLimitBytes;limitFlags=$initial.LimitFlags;activeProcessCount=$initial.ActiveProcessCount;sourceInputsHash=$c.sourceInputsHash;issuedMetadataHash=$c.issuedMetadataHash;runID=$runId;count=$c.count;status='self-job-admitted'}
 Write-FreshAtomicJson -Path (Join-Path $controlRoot 'task-start.json') -Value $taskStart
 & (Join-Path $overlayRoot 'dispatch-padding-repeat.ps1') -Package $c.package -LockOwner $c.owner -ProducerRoot $c.producerRoot -AdmissionRoot $admissionRoot -ControlRoot $c.controlRoot -OutputRoot $c.outputRoot -IntegrationGuardPath $c.integrationGuardPath -IntegrationGuardHash $c.integrationGuardHash -SourceInputsPath $c.sourceInputsPath -SourceInputsHash $c.sourceInputsHash -CompileReceiptHash $c.compileReceiptHash -ExeHash $c.exeHash -SerializerControlSha256 $c.serializerControlSha256 -Count $c.count -RunRoot $c.runRoot -IssuedMetadataPath $c.issuedMetadataPath -IssuedMetadataHash $c.issuedMetadataHash -Count1ProofPath $c.count1ProofPath -Count1ProofHash $c.count1ProofHash -PreflightOnly:$PreflightOnly *> (Join-Path $controlRoot 'task.log')
 $final=$job.WaitForOnlyCurrent(3000)
 [Sr0OwnedJobProcess]::RequireOnlyCurrent($final)
 $memoryReceipt=[ordered]@{kind='factory-interactive-job-memory-receipt-v1';runID=$runId;issuedMetadataHash=$c.issuedMetadataHash;parentPid=[Diagnostics.Process]::GetCurrentProcess().Id;jobMemoryLimitBytes=$final.JobMemoryLimitBytes;limitFlags=$final.LimitFlags;peakJobMemoryUsedBytes=$final.PeakJobMemoryUsedBytes;activeProcessCount=$final.ActiveProcessCount;status='passed';killOnJobClose=$false}
 $status='completed-source-bound-observation'
}catch{$primaryError=$_;if($null -ne $job){try{$s=$job.QueryPeakJobMemory();$memoryReceipt=[ordered]@{kind='factory-interactive-job-memory-receipt-v1';runID=if($null -ne $runId){$runId}else{''};issuedMetadataHash=$c.issuedMetadataHash;parentPid=[Diagnostics.Process]::GetCurrentProcess().Id;jobMemoryLimitBytes=$s.JobMemoryLimitBytes;limitFlags=$s.LimitFlags;peakJobMemoryUsedBytes=$s.PeakJobMemoryUsedBytes;activeProcessCount=$s.ActiveProcessCount;status='rejected';killOnJobClose=$false;error=[string]$primaryError}}catch{}}}
$nativeDirs=@();if(Test-Path -LiteralPath $c.runRoot){$nativeDirs=@(Get-ChildItem -LiteralPath $c.runRoot -Directory|Where-Object{$_.Name -like 'native-*'})}
$inventories=@($nativeDirs|ForEach-Object{$path=Join-Path $_.FullName 'owned-worker-inventory.json';[ordered]@{directory=$_.FullName;path=$path;sha256=if(Test-Path -LiteralPath $path){(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}else{$null}}})
$result=[ordered]@{issuedMetadataHash=$c.issuedMetadataHash;workerInventories=$inventories;status=$status;owner=$c.owner;count=$c.count;runRoot=$c.runRoot;compileReceiptHash=$c.compileReceiptHash;exeHash=$c.exeHash;serializerControlSha256=$c.serializerControlSha256;memoryReceipt=$memoryReceipt;error=if($null -ne $primaryError){[string]$primaryError}else{''};errorId=if($null -ne $primaryError){$primaryError.FullyQualifiedErrorId}else{''};finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}
Write-FreshAtomicJson -Path (Join-Path $controlRoot 'task-result.json') -Value $result
if($null -ne $job){$job.Dispose();$job=$null}
if($null -ne $primaryError){throw $primaryError}
