$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if(@(Get-Process swift,swiftc,swift-build,swift-frontend,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\hosts\circle-close-r1\build-circle-close-diagnostic-v1.ps1').Hash.ToLowerInvariant() -cne '79448e4ba729185a1d791a23c2e4a2b8815579c315e4095018026b3f79b01344'){throw 'build source drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\circle-close-r1\build-circle-close-diagnostic-v1.ps1' -PlanPath 'D:\Claude\swiftright\.factory-work\hosts\circle-close-r1\package\plan-prebuild-v2.json' -PlanSha256 '209772945cb02b062c73cdd2840890ab6c717d75903a3c99f289d3947b1055ca' -Phase prebuild
