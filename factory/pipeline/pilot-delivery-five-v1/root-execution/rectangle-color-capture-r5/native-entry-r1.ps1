$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Control='D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r5\control-count1-r1';$Preflight=Join-Path $Control 'root-preflight.json'
if((Get-FileHash -LiteralPath $Preflight).Hash.ToLowerInvariant() -cne '99f6ae2bf43db7418c41ed986921436e0de4ba95adf66200756b873c71672ba8'){throw 'root admission proof drift'}
$P=Get-Content -LiteralPath $Preflight -Raw|ConvertFrom-Json
if($P.status -cne 'preflight-passed' -or $P.nativeActions -ne 0 -or $P.lockActions -ne 0 -or $P.templateHash -cne '1002b575e85add5378794a7b0c3dcb99d3084fe18a1b9eb437d6553fc631713c'){throw 'actual source admission required'}
$Template=Join-Path $Control 'config-template.json';if((Get-FileHash -LiteralPath $Template).Hash.ToLowerInvariant() -cne '1002b575e85add5378794a7b0c3dcb99d3084fe18a1b9eb437d6553fc631713c'){throw 'actual template drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r5\overlay-count1-r1\coordinator-count1-v3.ps1' -Template $Template -TemplateHash '1002b575e85add5378794a7b0c3dcb99d3084fe18a1b9eb437d6553fc631713c'
Get-Content -LiteralPath (Join-Path $Control 'coordinator.json') -Raw
