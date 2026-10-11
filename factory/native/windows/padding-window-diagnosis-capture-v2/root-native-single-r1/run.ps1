$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$here='D:\Claude\swiftright\factory\native\windows\padding-window-diagnosis-capture-v2'
if((Get-FileHash -LiteralPath (Join-Path $here 'coordinator.ps1')).Hash.ToLowerInvariant() -cne '7490b201d000bd3736975bbb1155554e5a9b358cf5972a4335ada53b963c2304'){throw 'Coordinator source drift'}
& (Join-Path $here 'coordinator.ps1') -CompileReceiptHash '74bf90f689d00124abbcfbe56a97b1160fe3117277c7e332490b48be713ca8d7' -ExeHash 'caa9b760f2fc4574b0ca9846610f5b177b50e5180986c930415a442b3d83a369' -SerializerControlSha256 '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba' -Count 1
