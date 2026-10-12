$ErrorActionPreference='Stop'
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\rectangle-fixed-capture-foundation-v2.zip').Hash.ToLowerInvariant() -cne 'dbba72a068770890065951590d0c3865342a170f43d77c63b8ac0def1eb30101'){throw 'upload drift'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\rectangle-fixed-count1-r1.zip').Hash.ToLowerInvariant() -cne 'd0b9c29e5327b2006815fe977f7d9691d91779b69564908c549083a9bbea295c'){throw 'upload drift'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\hosts\rectangle\install-capture-foundation-v2.ps1').Hash.ToLowerInvariant() -cne '40891e380d0c52db58dd843509a047661b4b2f3bec4dc8e127237c5c30b2d3b7'){throw 'upload drift'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\hosts\rectangle\install-fixed-count1-preflight-r1.ps1').Hash.ToLowerInvariant() -cne '6d22185e395386cdb1c7e0e9b7420cb9403e9f91c8ae34612137e8a91fe209be'){throw 'upload drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\rectangle\install-capture-foundation-v2.ps1'
& 'D:\Claude\swiftright\.factory-work\hosts\rectangle\install-fixed-count1-preflight-r1.ps1'
