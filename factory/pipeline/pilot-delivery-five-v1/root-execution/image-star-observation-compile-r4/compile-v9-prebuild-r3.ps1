$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\image-star-observation'
$builder=Join-Path $stage 'build-owned-pilot-v1.ps1';$plan=Join-Path $stage 'package\plan-prebuild-v4.json'
if((Get-FileHash -LiteralPath $builder).Hash.ToLowerInvariant() -cne 'f4049ca730d8791a61e8a5295982bb3afbf3f42124e15cf35b54be6215585b5b'){throw 'v9 builder drift'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy'}
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
& $builder -PlanPath $plan -PlanSha256 '50796e95331c12822536db5b02862bbb97a450ea679484c1f2079fd136725c04' -Phase prebuild -Attempt 3 -PreflightOnly
& $builder -PlanPath $plan -PlanSha256 '50796e95331c12822536db5b02862bbb97a450ea679484c1f2079fd136725c04' -Phase prebuild -Attempt 3
$mapping=Join-Path $stage 'package\FactorySystemImageAssets.json';$exe=Join-Path $stage 'package\build-bound-r1\scratch\x86_64-unknown-windows-msvc\release\FactoryProbe.exe';$exeDir=Split-Path -Parent $exe;$adjacent=Join-Path $exeDir 'FactorySystemImageAssets.json';$mappingSha='f68691213b2d0454f08230ea898b12d8f61740f44a20340b4966495249296812'
if(-not(Test-Path -LiteralPath $mapping) -or (Get-FileHash -LiteralPath $mapping -Algorithm SHA256).Hash.ToLowerInvariant() -cne $mappingSha){throw 'package-root mapping hash drift'}
if(-not(Test-Path -LiteralPath $exe)){throw 'compiled EXE missing before resource placement'}
if(Test-Path -LiteralPath $adjacent){if((Get-FileHash -LiteralPath $adjacent -Algorithm SHA256).Hash.ToLowerInvariant() -cne $mappingSha){throw 'adjacent mapping collision'}}else{Copy-Item -LiteralPath $mapping -Destination $adjacent -Force}
if((Get-FileHash -LiteralPath $adjacent -Algorithm SHA256).Hash.ToLowerInvariant() -cne $mappingSha){throw 'adjacent mapping hash drift'}
[ordered]@{kind='factory-image-resource-adjacent-proof-v1';sourcePath=$mapping;destinationPath=$adjacent;executablePath=$exe;mappingSha256=('sha256:'+$mappingSha);mappingBytes=(Get-Item -LiteralPath $mapping).Length;adjacentBytes=(Get-Item -LiteralPath $adjacent).Length;sourceBehaviorChanged=$false;providerParityClaim=$false}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $stage 'prebuild-r3\image-resource-adjacent-proof.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $stage 'prebuild-r3\observation.json') -Raw
