$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\rectangle'
$builder=Join-Path $root 'build-owned-v2.ps1'
if((Get-FileHash -LiteralPath $builder).Hash.ToLowerInvariant() -cne '5f25b63479f26f8e8bc265a5e6f67c81b9d002be39019b5b286c2c43d17dc244'){throw 'builder drift'}
$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($builder,[ref]$t,[ref]$e);if($e.Count){throw ($e|Out-String)}
& $builder -PlanPath (Join-Path $root 'package\plan-prebuild.json') -PlanSha256 '89b3f012bedd09154b5f78ab7d7cdcbfd0f3b97d46e8d221fafcd9a5aa1671d9' -Attempt 2
