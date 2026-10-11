$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\rectangle'
$zip='D:\Claude\swiftright\.factory-work\rectangle-final-r1.zip'
if((Get-FileHash $zip).Hash.ToLowerInvariant() -cne '0773db1e20fb00df8dcde1f840cd50c787e6842e4dc890d9a13401ab64024700'){throw 'final ZIP drift'}
if(Test-Path (Join-Path $root 'package\plan-final-v3.json')){throw 'fresh final plan required'}
$manifest=Join-Path $root 'package\witness.manifest.json'
if((Get-FileHash $manifest).Hash.ToLowerInvariant() -cne 'be67e189aa540a591a7d19453367cfcab03744e660edf674581ba72e339fea15'){throw 'owned prebuild manifest drift'}
Expand-Archive -LiteralPath $zip -DestinationPath $root
Copy-Item -LiteralPath $manifest -Destination (Join-Path $root 'package\witness.manifest.prebuild-r1.json')
Copy-Item -LiteralPath (Join-Path $root 'package\witness.manifest.final-r1.json') -Destination $manifest -Force
$builder=Join-Path $root 'build-owned-v3.ps1'
if((Get-FileHash $builder).Hash.ToLowerInvariant() -cne 'a93e8423250b4016496ecb624c0304f8b4210de7ce1c5b9e27d6905a03214afa'){throw 'builder drift'}
& $builder -PlanPath (Join-Path $root 'package\plan-final-v3.json') -PlanSha256 'a218eecec68ad66e61cc592d345eaad5eba32860859c846acda1f80615149e8a' -Phase final -Attempt 1
