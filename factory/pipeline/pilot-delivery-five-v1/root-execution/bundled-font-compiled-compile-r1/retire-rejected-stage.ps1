$ErrorActionPreference='Stop'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
$Source='D:\Claude\swiftright\.factory-work\hosts\bundled-font-live'
$Destination='D:\Claude\swiftright\.factory-work\retired\bundled-font-preflight-rejected-20261012-2027'
if(Test-Path -LiteralPath $Destination){throw 'fresh retirement destination required'}
Move-Item -LiteralPath $Source -Destination $Destination
[ordered]@{source=$Source;destination=$Destination;deleteActions=0}|ConvertTo-Json
