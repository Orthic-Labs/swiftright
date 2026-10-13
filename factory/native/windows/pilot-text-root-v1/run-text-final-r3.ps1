$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if(@(Get-Process swift,swiftc,swift-build,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
& 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\build-text-r3.ps1' -PlanPath 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\package\plan-final-r3.json' -PlanSha256 '0a0bd332d34fc71da63ec59e453a901fd315967fb0556939b73228d68ab16ec3' -Phase final -Attempt 1
Get-Content -Raw 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\final-r1\observation.json'
