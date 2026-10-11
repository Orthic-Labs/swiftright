$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\rectangle'
$zip='D:\Claude\swiftright\.factory-work\rectangle-stage-v3.zip'
if((Get-FileHash $zip).Hash.ToLowerInvariant() -cne '41468b721eaf06254a268f846a0c24fa8478fad879ec0bae0dda52d4066cc99c'){throw 'stage ZIP mismatch'}
foreach($p in @('build-owned-v3.ps1','package\plan-prebuild-v3.json')){if(Test-Path (Join-Path $root $p)){throw 'fresh v3 source required'}}
Expand-Archive -LiteralPath $zip -DestinationPath $root
$builder=Join-Path $root 'build-owned-v3.ps1'
if((Get-FileHash $builder).Hash.ToLowerInvariant() -cne 'a93e8423250b4016496ecb624c0304f8b4210de7ce1c5b9e27d6905a03214afa'){throw 'builder hash mismatch'}
& $builder -PlanPath (Join-Path $root 'package\plan-prebuild-v3.json') -PlanSha256 'a3b379a8248810d9cf14e17c380bf6ebba95ba3b3a9f3e87358fbdd9a7d58327' -Attempt 3
