$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Control='D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r4\control-count1-r1';$Preflight=Join-Path $Control 'root-preflight.json'
if((Get-FileHash -LiteralPath $Preflight).Hash.ToLowerInvariant() -cne '58fbc32d187ae3dd36077e0c1cbee79bcedf17a2a43d49e46e13945fd5501391'){throw 'root admission proof drift'}
$P=Get-Content -LiteralPath $Preflight -Raw|ConvertFrom-Json
if($P.status -cne 'preflight-passed' -or $P.nativeActions -ne 0 -or $P.lockActions -ne 0 -or $P.templateHash -cne '6ac508d6a1de6225c87973affe6d745418c18300165eb558457cb8af227c5afc'){throw 'actual source admission required'}
$Template=Join-Path $Control 'config-template.json';if((Get-FileHash -LiteralPath $Template).Hash.ToLowerInvariant() -cne '6ac508d6a1de6225c87973affe6d745418c18300165eb558457cb8af227c5afc'){throw 'actual template drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r4\overlay-count1-r1\coordinator-count1-v3.ps1' -Template $Template -TemplateHash '6ac508d6a1de6225c87973affe6d745418c18300165eb558457cb8af227c5afc'
Get-Content -LiteralPath (Join-Path $Control 'coordinator.json') -Raw
