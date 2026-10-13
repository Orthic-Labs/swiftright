$ErrorActionPreference='Stop'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'owned compiler/native process busy'}
$Root='D:\Claude\swiftright\.factory-work\hosts'
$rows=@(Get-ChildItem -LiteralPath $Root -Directory|ForEach-Object{
 [ordered]@{name=$_.Name;path=$_.FullName;topFiles=@(Get-ChildItem -LiteralPath $_.FullName -File|Select-Object -ExpandProperty Name);directories=@(Get-ChildItem -LiteralPath $_.FullName -Directory|Select-Object -ExpandProperty Name)}
})
[ordered]@{lock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim();hosts=$rows}|ConvertTo-Json -Depth 5
