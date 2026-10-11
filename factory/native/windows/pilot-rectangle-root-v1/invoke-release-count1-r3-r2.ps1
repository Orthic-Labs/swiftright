$ErrorActionPreference='Stop'
$f='D:\Claude\swiftright\.factory-work\hosts\rectangle\release-count1-r3-supplement-r1.ps1'
if((Get-Item $f).Length -gt 32768 -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne '497c235e31ed00068995b4afeaf95aaf20cdaaacecec57f69a8d359803fafd69'){throw 'exact release script required'}
& $f
