$ErrorActionPreference='Stop'
$zip='D:\Claude\swiftright\.factory-work\rectangle-stage-r1.zip'
$dest='D:\Claude\swiftright\.factory-work\hosts\rectangle'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'b6f5f1740bee04fa0802e51e01c420896db8d1f7e79f9dd3ba807fc8c15a4783'){throw 'ZIP drift'}
if(Test-Path -LiteralPath $dest){throw 'fresh rectangle stage required'}
Expand-Archive -LiteralPath $zip -DestinationPath $dest
$m=Get-Content -Raw (Join-Path $dest 'stage-manifest.json')|ConvertFrom-Json
foreach($r in $m.files){$p=Join-Path $dest $r.path;if((Get-Item $p).Length -ne $r.bytes -or (Get-FileHash $p).Hash.ToLowerInvariant() -cne $r.sha256){throw 'stage bytes mismatch'}}
$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $dest 'build-owned.ps1'),[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}
& (Join-Path $dest 'build-owned.ps1') -PlanPath (Join-Path $dest 'package\plan-prebuild.json') -PlanSha256 '89b3f012bedd09154b5f78ab7d7cdcbfd0f3b97d46e8d221fafcd9a5aa1671d9' -PreflightOnly
