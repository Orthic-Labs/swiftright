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
$mta=Join-Path $StageRoot 'producer/dependencies/uia-worker/invoke-worker-mta.ps1';$mtaI=Get-Item -LiteralPath $mta -Force;if($mtaI.Length -le 0){Fail 'MTA invoker missing'}
if([string]$si.uiaWorkerPath -notmatch 'invoke-worker-mta\.ps1$'){Fail 'source inputs not MTA-bound'}
$renderer=Join-Path $StageRoot 'producer/support/final-exit-certificate.ps1';$worker=Join-Path $StageRoot 'producer/dependencies/uia-worker/support/final-exit-certificate.ps1'
if((Get-FileHash $renderer).Hash -ceq (Get-FileHash $worker).Hash){Fail 'renderer helper replaced by worker helper'}
if([string]$si.integrationBindingsRef.path -notmatch 'integration-bindings\.json$'){Fail 'integration binding ref'}
[ordered]@{status='mta-source-closure-pass';nativeActions=0;lockActions=0;compilerActions=0}|ConvertTo-Json -Depth 8)
