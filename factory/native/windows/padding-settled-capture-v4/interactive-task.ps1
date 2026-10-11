param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference='Stop'
$here=[IO.Path]::GetFullPath($PSScriptRoot)
$configPath=[IO.Path]::GetFullPath($Config)
if(-not $configPath.StartsWith($here+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Config outside coordinator lane'}
$c=Get-Content -Raw $configPath|ConvertFrom-Json
$controlRoot=Join-Path $here $(if($c.count -eq 1){'coordinator-single-r1'}elseif($c.count -eq 20){'coordinator-repeat-r1'}else{throw 'Exact count required'})
if($configPath -cne (Join-Path $controlRoot 'config.json') -or $c.controlRoot -cne $controlRoot){throw 'Exact coordinator config required'}
$status='hold-harness-error';$primaryError=$null
try{
 if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Interactive desktop session required'}
 if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne $c.owner){throw 'Coordinator lock ownership lost'}
 & (Join-Path $here 'dispatch.ps1') -LockOwner $c.owner -CompileReceiptHash $c.compileReceiptHash -ExeHash $c.exeHash -SerializerControlSha256 $c.serializerControlSha256 -Count $c.count -RunRoot $c.runRoot *> (Join-Path $controlRoot 'task.log')
 $status='completed-source-bound-observation'
}catch{$primaryError=$_}
[ordered]@{status=$status;owner=$c.owner;count=$c.count;runRoot=$c.runRoot;compileReceiptHash=$c.compileReceiptHash;exeHash=$c.exeHash;serializerControlSha256=$c.serializerControlSha256;error=if($null -ne $primaryError){[string]$primaryError}else{''};errorId=if($null -ne $primaryError){$primaryError.FullyQualifiedErrorId}else{''};finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $controlRoot 'task-result.json')
if($null -ne $primaryError){throw $primaryError}
