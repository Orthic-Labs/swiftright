$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$p='D:\Claude\swiftright\.factory-work\root-tools\sr0-observer-r12-r1\observer-source-r12.ps1';$f=Get-Item -LiteralPath $p -Force;if($f.Length -ne 23620 -or (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne 'e87eda8007275d172c4baecc0aa63fcf70c58472fc3f6e7ca21eabd5e58f7b0a'){throw 'observer source drift'}
$p='D:\Claude\swiftright\.factory-work\root-tools\sr0-observer-r12-r1\test-observer-kernel-policy-r12.ps1';$f=Get-Item -LiteralPath $p -Force;if($f.Length -ne 2920 -or (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne '5f5c98b9ea9e41d8972eeb1328a2dbae4d414c59953571ea77419d86965dd85e'){throw 'observer source drift'}
& 'D:\Claude\swiftright\.factory-work\root-tools\sr0-observer-r12-r1\test-observer-kernel-policy-r12.ps1' -ObserverPath 'D:\Claude\swiftright\.factory-work\root-tools\sr0-observer-r12-r1\observer-source-r12.ps1'
if(-not $?){throw 'observer controls failed'}
