$ErrorActionPreference='Stop'
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\rectangle-fixed-capture-foundation-v2.zip').Hash.ToLowerInvariant() -cne 'dbba72a068770890065951590d0c3865342a170f43d77c63b8ac0def1eb30101'){throw 'upload drift'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\rectangle-fixed-count1-r1.zip').Hash.ToLowerInvariant() -cne 'd0b9c29e5327b2006815fe977f7d9691d91779b69564908c549083a9bbea295c'){throw 'upload drift'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\hosts\rectangle\install-capture-foundation-v3.ps1').Hash.ToLowerInvariant() -cne '460677a2c71503db88a849eb510e663749dadabe4f32ef76fa69e051b19ace88'){throw 'upload drift'}
if((Get-FileHash 'D:\Claude\swiftright\.factory-work\hosts\rectangle\install-fixed-count1-preflight-v2-r1.ps1').Hash.ToLowerInvariant() -cne '8c3279f1d19b6b175c1b2eb3d7b43b479c28fb66ab288861cc46c448f8b274f1'){throw 'upload drift'}
& 'D:\Claude\swiftright\.factory-work\hosts\rectangle\install-capture-foundation-v3.ps1'
& 'D:\Claude\swiftright\.factory-work\hosts\rectangle\install-fixed-count1-preflight-v2-r1.ps1'
