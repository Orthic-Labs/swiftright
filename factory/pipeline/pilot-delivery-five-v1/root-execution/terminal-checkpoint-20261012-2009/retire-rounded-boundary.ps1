$ErrorActionPreference='Stop'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop lock busy'}
$Source='D:\Claude\swiftright\.factory-work\hosts\rounded-stroke-boundary'
$Destination='D:\Claude\swiftright\.factory-work\retired\rounded-stroke-boundary-20261012-2022'
if(Test-Path -LiteralPath $Destination){throw 'fresh retirement destination required'}
Move-Item -LiteralPath $Source -Destination $Destination
[ordered]@{source=$Source;destination=$Destination;sourceAbsent=(-not(Test-Path -LiteralPath $Source));destinationPresent=(Test-Path -LiteralPath $Destination);deleteActions=0}|ConvertTo-Json
