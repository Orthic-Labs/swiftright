$ErrorActionPreference='Stop'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
$Src='D:\Claude\swiftright\.factory-work\hosts\image-star-observation\package\FactorySystemImageAssets.json';$Dst='D:\Claude\swiftright\.factory-work\hosts\image-star-observation\package\build-bound-r1\scratch\x86_64-unknown-windows-msvc\release\FactorySystemImageAssets.json'
if((Get-Item -LiteralPath $Src).Length -ne 1190 -or (Get-FileHash -LiteralPath $Src).Hash.ToLowerInvariant() -cne 'f68691213b2d0454f08230ea898b12d8f61740f44a20340b4966495249296812'){throw 'mapping source drift'}
if(Test-Path -LiteralPath $Dst){throw 'mapping deployment must be fresh'}
Copy-Item -LiteralPath $Src -Destination $Dst
if((Get-FileHash -LiteralPath $Dst).Hash.ToLowerInvariant() -cne 'f68691213b2d0454f08230ea898b12d8f61740f44a20340b4966495249296812'){throw 'mapping deployment drift'}
[ordered]@{mappingSha256='f68691213b2d0454f08230ea898b12d8f61740f44a20340b4966495249296812';mappingBytes=1190;source=$Src;destination=$Dst;nativeActions=0;compilerActions=0}|ConvertTo-Json
