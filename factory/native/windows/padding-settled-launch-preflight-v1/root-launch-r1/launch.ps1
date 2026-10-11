$ErrorActionPreference='Stop'
$p='D:\Claude\swiftright\.factory-work\hosts\padding-settled\preflight.ps1'
if((Get-FileHash $p).Hash.ToLowerInvariant() -cne 'b54160b5902ced62c51b6f836f27a4ed40991dd8617e89fffc268105f81f6d9f'){throw 'Launch guard drift'}
& $p -Phase Launch -CompileReceiptSha256 '90f50b3fa049d4b21a0c5ad5eca78d8c024b961aa102fbc345767c151e503365' -ExeSha256 '9ed4e7ed376cf2ad20879e99326291dcad31634156934e69d86094b2685fb5a4' -SerializerControlSha256 '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
