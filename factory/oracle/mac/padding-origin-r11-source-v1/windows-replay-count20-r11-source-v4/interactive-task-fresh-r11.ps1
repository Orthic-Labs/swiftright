param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference='Stop'
$overlayRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$c=$null
$configPath=[IO.Path]::GetFullPath($Config)
$c=Get-Content -Raw $configPath|ConvertFrom-Json
$here=[IO.Path]::GetFullPath([string]$c.producerRoot)
$controlRoot=[IO.Path]::GetFullPath([string]$c.controlRoot)
$runRoot=[IO.Path]::GetFullPath([string]$c.runRoot)
if(-not $configPath.StartsWith($controlRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Config outside fresh coordinator lane'}
if($c.count -ne 20){throw 'Exact Count20 repeat required'}
if($configPath -cne (Join-Path $controlRoot 'config.json') -or $c.controlRoot -cne $controlRoot -or $c.runRoot -cne $runRoot -or [string]::IsNullOrWhiteSpace($c.outputRoot)){throw 'Exact Count20 fresh coordinator config required'}
$status='hold-harness-error';$primaryError=$null
if($c.count -ne 20){throw 'Exact Count20 repeat required'}
try{
 if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive desktop session required'}
 if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne $c.owner){throw 'Coordinator lock ownership lost'}
 & (Join-Path $overlayRoot 'dispatch-fresh-r11.ps1') -LockOwner $c.owner -ProducerRoot $c.producerRoot -ControlRoot $c.controlRoot -OutputRoot $c.outputRoot -IntegrationGuardPath $c.integrationGuardPath -IntegrationGuardHash $c.integrationGuardHash -FreshGuardControlsPath $c.freshGuardControlsPath -FreshGuardControlsHash $c.freshGuardControlsHash -CompileReceiptHash $c.compileReceiptHash -ExeHash $c.exeHash -SerializerControlSha256 $c.serializerControlSha256 -Count $c.count -RunRoot $c.runRoot -IssuedMetadataPath $c.issuedMetadataPath -IssuedMetadataHash $c.issuedMetadataHash *> (Join-Path $controlRoot 'task.log')
 $status='completed-source-bound-observation'
}catch{$primaryError=$_}
$nativeDirs=@();if(Test-Path -LiteralPath $c.runRoot){$nativeDirs=@(Get-ChildItem -LiteralPath $c.runRoot -Directory|Where-Object{$_.Name -like 'native-*'})}
$inventories=@($nativeDirs|ForEach-Object{$path=Join-Path $_.FullName 'owned-worker-inventory.json';[ordered]@{directory=$_.FullName;path=$path;sha256=if(Test-Path -LiteralPath $path){(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}else{$null}}})
[ordered]@{issuedMetadataHash=$c.issuedMetadataHash;workerInventories=$inventories;status=$status;owner=$c.owner;count=$c.count;runRoot=$c.runRoot;compileReceiptHash=$c.compileReceiptHash;exeHash=$c.exeHash;serializerControlSha256=$c.serializerControlSha256;error=if($null -ne $primaryError){[string]$primaryError}else{''};errorId=if($null -ne $primaryError){$primaryError.FullyQualifiedErrorId}else{''};finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $controlRoot 'task-result.json')
if($null -ne $primaryError){throw $primaryError}
