param([ValidateSet('Launch')][string]$Phase='Launch',[string]$CompileReceiptSha256,[string]$ExeSha256,[string]$SerializerControlSha256)
$ErrorActionPreference='Stop'
if($CompileReceiptSha256 -cne 'f8284f2f9fee5f82411474ecc356e25c189dcdf984f8bfdb86f2563d85f687e3'){throw 'capture admission argument mismatch'}
if($ExeSha256 -cne '76152979c8ae679b3643307ce7608112ddefd50ef60d83d5d7fe868002f36871'){throw 'capture admission argument mismatch'}
if($SerializerControlSha256 -cne '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'){throw 'capture admission argument mismatch'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\circle\build-circle-owned-v2.ps1').Hash.ToLowerInvariant() -cne '3d4b4d4cee16ad0ee974b624d6fb0eee2c2ce77ac82a7ed8d719b09d34c12808'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\circle\package\plan-final-v2.json').Hash.ToLowerInvariant() -cne '23f99cc23c81b2bb49b8bbe60a77123a94b840c8f2a0851073cd981760a5e308'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\circle\final-r2\observation.json').Hash.ToLowerInvariant() -cne 'f8284f2f9fee5f82411474ecc356e25c189dcdf984f8bfdb86f2563d85f687e3'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\circle\package\build-bound-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe').Hash.ToLowerInvariant() -cne '76152979c8ae679b3643307ce7608112ddefd50ef60d83d5d7fe868002f36871'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -cne 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\rectangle\dependencies\serializer-actual-r2\control.json').Hash.ToLowerInvariant() -cne '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'){throw 'capture measured bytes drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\circle\build-circle-owned-v2.ps1' -PlanPath 'D:\Claude\swiftright\.factory-work\hosts\circle\package\plan-final-v2.json' -PlanSha256 '23f99cc23c81b2bb49b8bbe60a77123a94b840c8f2a0851073cd981760a5e308' -Phase final -Attempt 3 -PreflightOnly|Out-Null
@{status='passed';nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json
