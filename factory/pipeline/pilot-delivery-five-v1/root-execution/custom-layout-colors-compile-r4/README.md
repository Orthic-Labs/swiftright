# Custom direct-v7 rolling-stage compile packet

Source-only packet for root-owned prebuild. Uses existing rolling stage `D:\Claude\swiftright\.factory-work\hosts\custom-layout-colors`; no fourth host stage.

- package source: `factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v2/direct-original-execution-v7/package`
- package plan SHA256: `sha256:6eae21b6d888c3c7f8abd7e564c62d259eafa45cc7d93ac185ce46da6fea701c`
- compile plan SHA256: `sha256:b12e789843ccd6a31b1c214c4ab6c2b8523418b5110f698395ebe1364d37e241`
- source/witness SHA256: `sha256:afe77cdfbd5c73943aeebe52c515f2149c7951a4e3512f1678cda6625cdb58f7`
- source bindings SHA256: `sha256:3ac6bad134f9a42dca29113fed56c410d5459f506e011df40a5eb802e3df6d52`
- runtime commit: `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`; renderer SHA256: `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`
- execution remains false until root stages package, runs preflight, then compiler.

Existing builder/helper copied unchanged from r3. Historical r3 remains preserved.

Root resume command after staged inputs: `& .\resume-prebuild-v7-r2.ps1`

## Rolling-stage entry

Root retires complete prior stage at `D:\Claude\swiftright\.factory-work\retired\custom-layout-colors-direct-v6-observed-20261013-0120`, then invokes `stage-build-r4-direct-v7.ps1` against fresh `custom-layout-colors`. Entry embeds 10 v7 source rows, pinned runtime receipt/tree, case join, package plan, prebuild plan, builder, & 1 GiB helper. It performs preflight before compiler invocation & reuses `build-bound-r1\scratch`.

- staging entry SHA256: `sha256:465cad4563b8447e0ea70e959615737bcb188a134ca559886edeb9452b8e5d88`
- immutable resume entry: `resume-prebuild-v7-r2.ps1`; SHA256: `sha256:9da65031f3a4853e85af1bb53389844324d981fa3f211524bdb4b39c6eee2558`; validates JSON preflight `status=passed`, `compilerStarted=false`, `nativeActions=0`, `memoryCapBytes=1073741824`, then invokes compile attempt 1
- native product path: `D:\Claude\swiftright\.factory-work\hosts\custom-layout-colors\package\build-bound-r1\scratch\x86_64-unknown-windows-msvc\release\FactoryProbe.exe`
- prior final receipt guard: archived receipt prefix `1e68`; root verifies complete receipt before retirement
