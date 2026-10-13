param([ValidateSet('Launch')][string]$Phase='Launch',[string]$CompileReceiptSha256,[string]$ExeSha256,[string]$SerializerControlSha256)
$ErrorActionPreference='Stop'
if($CompileReceiptSha256 -cne '912203faf7d3dbd66c03465c717e6ecc814ccecf2389ab67b659abd84eb90c2b'){throw 'capture admission argument mismatch'}
if($ExeSha256 -cne '4dbdd037dcb8ce2461d90ccacd2f6a853c8a0715c51e2581bcad88f75c303965'){throw 'capture admission argument mismatch'}
if($SerializerControlSha256 -cne '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'){throw 'capture admission argument mismatch'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\build-text-style-r5.ps1').Hash.ToLowerInvariant() -cne '96737f5f0ac6f7ed1cd1655b864f81dd7e7789cc2d7d465be1b0e6d2ed209d68'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\package\plan-final-r5.json').Hash.ToLowerInvariant() -cne '5d5b555ed1fbc52d87393f8d19fe1e7445e039888df90d9c54f7b835163a3e91'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\final-r5\observation.json').Hash.ToLowerInvariant() -cne '912203faf7d3dbd66c03465c717e6ecc814ccecf2389ab67b659abd84eb90c2b'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\package\build-bound-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe').Hash.ToLowerInvariant() -cne '4dbdd037dcb8ce2461d90ccacd2f6a853c8a0715c51e2581bcad88f75c303965'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -cne 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\rectangle\dependencies\serializer-actual-r2\control.json').Hash.ToLowerInvariant() -cne '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'){throw 'capture measured bytes drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\build-text-style-r5.ps1' -PlanPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\package\plan-final-r5.json' -PlanSha256 '5d5b555ed1fbc52d87393f8d19fe1e7445e039888df90d9c54f7b835163a3e91' -Phase final -Attempt 6 -PreflightOnly|Out-Null
@{status='passed';nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json
