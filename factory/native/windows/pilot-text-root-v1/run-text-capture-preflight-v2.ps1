$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\text-capture-foundation-v2.zip').Hash.ToLowerInvariant() -cne 'da0f08868dfbeb0c0900090828c2d1128e9d288568764fb51ded236de138a403'){throw 'source upload drift'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\text-count1-v2-r1.zip').Hash.ToLowerInvariant() -cne 'd6b3095cd9706a546f5aa1b6e8aca411e6e0632203a11159ac832b0a51a917db'){throw 'source upload drift'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\install-capture-foundation-text-v2.ps1').Hash.ToLowerInvariant() -cne '5d1241dd789b7c8a504918918a43f06219456f8f8bd04c1c75eaba2c5baeeb9c'){throw 'source upload drift'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\install-count1-text-preflight-v2.ps1').Hash.ToLowerInvariant() -cne 'b5dec62162cbfe6974d67e39105d8c37546c385ba14d0faa80c66a4f31e7693c'){throw 'source upload drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\install-capture-foundation-text-v2.ps1'
& 'D:\Claude\swiftright\.factory-work\hosts\text-baseline\install-count1-text-preflight-v2.ps1'
