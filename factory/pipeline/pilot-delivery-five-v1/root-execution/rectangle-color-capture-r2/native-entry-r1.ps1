$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Control='D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r2\control-count1-r1';$Preflight=Join-Path $Control 'root-preflight.json'
if((Get-FileHash -LiteralPath $Preflight).Hash.ToLowerInvariant() -cne '155f516e5a227c1bcdf67116b48f2e1b61605d82ae235bcf5c89014278aac9b6'){throw 'root admission proof drift'}
$P=Get-Content -LiteralPath $Preflight -Raw|ConvertFrom-Json
if($P.status -cne 'preflight-passed' -or $P.nativeActions -ne 0 -or $P.lockActions -ne 0 -or $P.templateHash -cne '38bbc56296ea02cc1ce68bf8c728c83f73704db8edf15b988039e3c4bc5529a3'){throw 'actual source admission required'}
$Template=Join-Path $Control 'config-template.json';if((Get-FileHash -LiteralPath $Template).Hash.ToLowerInvariant() -cne '38bbc56296ea02cc1ce68bf8c728c83f73704db8edf15b988039e3c4bc5529a3'){throw 'actual template drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r2\overlay-count1-r1\coordinator-count1-v3.ps1' -Template $Template -TemplateHash '38bbc56296ea02cc1ce68bf8c728c83f73704db8edf15b988039e3c4bc5529a3'
Get-Content -LiteralPath (Join-Path $Control 'coordinator.json') -Raw
