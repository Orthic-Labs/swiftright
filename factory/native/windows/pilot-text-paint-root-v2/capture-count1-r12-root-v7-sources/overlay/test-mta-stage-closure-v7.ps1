param([Parameter(Mandatory=$true)][string]$StageRoot,[Parameter(Mandatory=$true)][string]$SourceInputsPath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Fail([string]$m){throw ('mta-stage-closure: '+$m)}
if(-not(Test-Path -LiteralPath $StageRoot -PathType Container)){Fail 'stage root missing'}
$m=Get-Content -Raw -LiteralPath (Join-Path $StageRoot 'stage-manifest.json')|ConvertFrom-Json
if($m.files.Count -gt 256){Fail 'file count bound'}
$seen=@{};$total=0
foreach($r in $m.files){if($seen.ContainsKey($r.path)){Fail 'duplicate path'};$seen[$r.path]=$true;$p=Join-Path $StageRoot $r.path;$i=Get-Item -LiteralPath $p -Force;if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0)){Fail ('unsafe row '+$r.path)};if($i.Length -ne $r.bytes -or (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $r.sha256){Fail ('row drift '+$r.path)};$total+=$i.Length;if($i.Length -gt 8388608){Fail ('file bound '+$r.path)}}
if($total -gt 33554432){Fail 'total bound'}
$si=Get-Content -Raw -LiteralPath $SourceInputsPath|ConvertFrom-Json
$waitFiles=@('overlay/coordinator-count1-v3.ps1','overlay/capture-text-single-v3.ps1','overlay/uia-worker-invoke-v2.ps1','producer/dependencies/uia-worker/invoke-worker.ps1','producer/dependencies/uia-worker/invoke-worker-mta.ps1')
foreach($wf in $waitFiles){$wp=Join-Path $StageRoot $wf;$wt=Get-Content -Raw -LiteralPath $wp;if($wt -match 'FactoryProcessWaitV5'){Fail ('stale V5 ABI caller '+$wf)};if($wt -match '\[FactoryProcessWaitV6\]' -and $wt.IndexOf('[FactoryProcessWaitV6]') -lt $wt.IndexOf('cleanup.ps1')){Fail ('V6 type used before cleanup loader '+$wf)}}
$cleanupForType=Join-Path $StageRoot 'producer/support/cleanup.ps1';. $cleanupForType;if(-not ('FactoryProcessWaitV6' -as [type])){Fail 'V6 cleanup type not loaded'}
$mta=Join-Path $StageRoot 'producer/dependencies/uia-worker/invoke-worker-mta.ps1';$mtaI=Get-Item -LiteralPath $mta -Force;if($mtaI.Length -le 0){Fail 'MTA invoker missing'}
if([string]$si.uiaWorkerPath -notmatch 'invoke-worker-mta\.ps1$'){Fail 'source inputs not MTA-bound'}
$renderer=Join-Path $StageRoot 'producer/support/final-exit-certificate.ps1';$worker=Join-Path $StageRoot 'producer/dependencies/uia-worker/support/final-exit-certificate.ps1'
$rendererCleanup=Join-Path $StageRoot 'producer/support/cleanup.ps1';$workerCleanup=Join-Path $StageRoot 'producer/dependencies/uia-worker/support/cleanup.ps1'
if((Get-FileHash $renderer).Hash -ceq (Get-FileHash $worker).Hash){Fail 'renderer final-exit helper replaced by worker final-exit helper'}
if((Get-FileHash -LiteralPath $workerCleanup).Hash.ToLowerInvariant() -cne 'cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13' -or (Get-FileHash -LiteralPath $rendererCleanup).Hash.ToLowerInvariant() -cne 'cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13'){Fail 'root-v3 cleanup helper drift'}
if([string]$si.integrationBindingsRef.path -notmatch 'integration-bindings\.json$'){Fail 'integration binding ref'}
[ordered]@{status='mta-source-closure-pass';nativeActions=0;lockActions=0;compilerActions=0}|ConvertTo-Json -Depth 8
