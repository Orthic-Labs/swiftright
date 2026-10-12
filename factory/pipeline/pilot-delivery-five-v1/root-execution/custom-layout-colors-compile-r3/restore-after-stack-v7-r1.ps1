$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work'
$stack=Join-Path $root 'hosts\stack-overlay-colors';$retired=Join-Path $root 'retired\stack-overlay-colors-v7-observed-20261012-2150'
$customOld=Join-Path $root 'retired\custom-layout-colors-primary-paired20-20261012-2110';$custom=Join-Path $root 'hosts\custom-layout-colors'
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy'}
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
if(-not(Test-Path -LiteralPath $stack) -or -not(Test-Path -LiteralPath $customOld) -or (Test-Path -LiteralPath $retired) -or (Test-Path -LiteralPath $custom)){throw 'unexpected staging state'}
if((Get-FileHash -LiteralPath (Join-Path $stack 'final-r1\observation.json')).Hash.ToLowerInvariant() -cne 'c47fb668acd65f752c71e4a5a4fcc13db1371eb689c8ca75545b3cac8ef70129'){throw 'archived stack final receipt drift'}
$coord=Get-Content -LiteralPath (Join-Path $stack 'captures\count1-r3\control-count1-r3\coordinator.json') -Raw|ConvertFrom-Json
if($coord.count -ne 1 -or -not $coord.lockReleased -or -not $coord.wholeBatchExitConfirmed -or $coord.error -or @($coord.cleanupErrors).Count){throw 'stack Count1 terminal proof missing'}
Move-Item -LiteralPath $stack -Destination $retired
Move-Item -LiteralPath $customOld -Destination $custom
@{kind='factory-owned-stage-rollover-v1';stackRetired=$retired;customActive=$custom;deleted=$false;activeHosts=@(Get-ChildItem -LiteralPath (Join-Path $root 'hosts') -Directory|Select-Object -ExpandProperty Name)}|ConvertTo-Json -Depth 5
