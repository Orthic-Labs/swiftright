param([ValidateSet('Launch')][string]$Phase='Launch',[string]$CompileReceiptSha256,[string]$ExeSha256,[string]$SerializerControlSha256)
$ErrorActionPreference='Stop'
if($CompileReceiptSha256 -cne 'bef8851cef48e96889bb46f8e66d85cff7f9f0f8f19e34c65d3d09c38036010b'){throw 'capture admission argument mismatch'}
if($ExeSha256 -cne '33248eaa0369e8d4b5e7dea9e1df7d6d86110ee3f31c8fdc9db61a500d057fe7'){throw 'capture admission argument mismatch'}
if($SerializerControlSha256 -cne '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'){throw 'capture admission argument mismatch'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\build-text-paint-r7.ps1').Hash.ToLowerInvariant() -cne '6a96adbd27539dd034a21b6bb13040e2beb452bacc0096c6dc63f437460fa321'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\package\plan-final-r7.json').Hash.ToLowerInvariant() -cne 'de8660b0c55a717d52171ec476b833881919696f434c3ceba077ba3b77fbc642'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\final-r7\observation.json').Hash.ToLowerInvariant() -cne 'bef8851cef48e96889bb46f8e66d85cff7f9f0f8f19e34c65d3d09c38036010b'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\package\build-bound-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe').Hash.ToLowerInvariant() -cne '33248eaa0369e8d4b5e7dea9e1df7d6d86110ee3f31c8fdc9db61a500d057fe7'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll').Hash.ToLowerInvariant() -cne 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'){throw 'capture measured bytes drift'}
if((Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\hosts\text\dependencies\serializer-actual-r2\control.json').Hash.ToLowerInvariant() -cne '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'){throw 'capture measured bytes drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\build-text-paint-r7.ps1' -PlanPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\package\plan-final-r7.json' -PlanSha256 'de8660b0c55a717d52171ec476b833881919696f434c3ceba077ba3b77fbc642' -Phase final -Attempt 8 -PreflightOnly|Out-Null
@{status='passed';nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json
