param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference='Stop'
$overlayRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$configPath=[IO.Path]::GetFullPath($Config)
$c=Get-Content -Raw $configPath|ConvertFrom-Json
$here=[IO.Path]::GetFullPath([string]$c.producerRoot)
$controlRoot=[IO.Path]::GetFullPath([string]$c.controlRoot)
$runRoot=[IO.Path]::GetFullPath([string]$c.runRoot)
if(-not $configPath.StartsWith($controlRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Config outside fresh coordinator lane'}
if($c.count -ne 20){throw 'Exact Count20 repeat required'}
if($configPath -cne (Join-Path $controlRoot 'config.json') -or $c.controlRoot -cne $controlRoot -or $c.runRoot -cne $runRoot -or [string]::IsNullOrWhiteSpace($c.outputRoot)){throw 'Exact Count20 fresh coordinator config required'}
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
 & (Join-Path $overlayRoot 'dispatch-fresh-r11-v10.ps1') -LockOwner $c.owner -ProducerRoot $c.producerRoot -ControlRoot $c.controlRoot -OutputRoot $c.outputRoot -IntegrationGuardPath $c.integrationGuardPath -IntegrationGuardHash $c.integrationGuardHash -FreshGuardControlsPath $c.freshGuardControlsPath -FreshGuardControlsHash $c.freshGuardControlsHash -CompileReceiptHash $c.compileReceiptHash -ExeHash $c.exeHash -SerializerControlSha256 $c.serializerControlSha256 -Count $c.count -RunRoot $c.runRoot -IssuedMetadataPath $c.issuedMetadataPath -IssuedMetadataHash $c.issuedMetadataHash *> (Join-Path $controlRoot 'task.log')
 $final=$job.WaitForOnlyCurrent(3000)
 [Sr0OwnedJobProcess]::RequireOnlyCurrent($final)
 $memoryReceipt=[ordered]@{kind='factory-interactive-job-memory-receipt-v1';runID=$runId;issuedMetadataHash=$c.issuedMetadataHash;parentPid=[Diagnostics.Process]::GetCurrentProcess().Id;jobMemoryLimitBytes=$final.JobMemoryLimitBytes;limitFlags=$final.LimitFlags;peakJobMemoryUsedBytes=$final.PeakJobMemoryUsedBytes;activeProcessCount=$final.ActiveProcessCount;status='passed';killOnJobClose=$false}
 $status='completed-source-bound-observation'
}catch{$primaryError=$_;if($null -ne $job){try{$s=$job.QueryPeakJobMemory();$memoryReceipt=[ordered]@{kind='factory-interactive-job-memory-receipt-v1';runID=if($null -ne $runId){$runId}else{''};issuedMetadataHash=$c.issuedMetadataHash;parentPid=[Diagnostics.Process]::GetCurrentProcess().Id;jobMemoryLimitBytes=$s.JobMemoryLimitBytes;limitFlags=$s.LimitFlags;peakJobMemoryUsedBytes=$s.PeakJobMemoryUsedBytes;activeProcessCount=$s.ActiveProcessCount;status='rejected';killOnJobClose=$false;error=[string]$primaryError}}catch{}}}
$nativeDirs=@();if(Test-Path -LiteralPath $c.runRoot){$nativeDirs=@(Get-ChildItem -LiteralPath $c.runRoot -Directory|Where-Object{$_.Name -like 'native-*'})}
$inventories=@($nativeDirs|ForEach-Object{$path=Join-Path $_.FullName 'owned-worker-inventory.json';[ordered]@{directory=$_.FullName;path=$path;sha256=if(Test-Path -LiteralPath $path){(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}else{$null}}})
$result=[ordered]@{issuedMetadataHash=$c.issuedMetadataHash;workerInventories=$inventories;status=$status;owner=$c.owner;count=$c.count;runRoot=$c.runRoot;compileReceiptHash=$c.compileReceiptHash;exeHash=$c.exeHash;serializerControlSha256=$c.serializerControlSha256;memoryReceipt=$memoryReceipt;error=if($null -ne $primaryError){[string]$primaryError}else{''};errorId=if($null -ne $primaryError){$primaryError.FullyQualifiedErrorId}else{''};finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$result|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $controlRoot 'task-result.json')
if($null -ne $job){$job.Dispose();$job=$null}
if($null -ne $primaryError){throw $primaryError}
